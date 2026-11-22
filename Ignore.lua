local _, chatNS = ...

local EasyFind = EasyFind
local ns = EasyFind and EasyFind._ns
if not (ns and ns.Utils) or chatNS.tooOld then return end

-- One ignore list for every character. An ignored player's lines are not
-- kept in the chat window on any of them, and each character's own in-game
-- list is kept in step: names here are offered to it, names it holds come
-- here, and a name taken off in one place leaves the others.
local Ignore = {}
chatNS.Ignore = Ignore

local UI = chatNS.UI
local Utils = ns.Utils
local CreateFrame = CreateFrame
local FL = C_FriendList
local next, pairs, type = next, pairs, type
local tremove, tsort = table.remove, table.sort

-- Seconds between two changes sent to the game's list.
local SEND_GAP = 1
-- An empty list this long after login is empty, not late.
local LOGIN_WAIT = 15

local function ChatDB()
    EasyFindChatDB = type(EasyFindChatDB) == "table" and EasyFindChatDB or {}
    return EasyFindChatDB
end

local function Sub(parent, field)
    local t = parent[field]
    if type(t) ~= "table" then
        t = {}
        parent[field] = t
    end
    return t
end

-- ignored[key] = the name as the game gave it. unignored[key]: taken off, so
-- a character still listing it drops it. ignoreSent[char][key]: on that
-- character's list or offered to it once (a full list refuses for good).
local function Lists()
    local db = ChatDB()
    return Sub(db, "ignored"), Sub(db, "unignored"), Sub(db, "ignoreSent")
end

-- "First Surname" and "First-Surname" are one player.
function Ignore:Key(name)
    local plain = UI:GetPlainChatLabel(name)
    if plain == "" then return nil end
    return UI:GetChatConversationKey("player", (plain:gsub(" ", "-")))
end

function Ignore:Has(name)
    local ignored = ChatDB().ignored
    if type(ignored) ~= "table" or not next(ignored) then return false end
    local key = self:Key(name)
    return key ~= nil and ignored[key] ~= nil
end

-- The names, sorted, for the list in settings.
function Ignore:Names()
    local out = {}
    local ignored = Lists()
    for _, name in pairs(ignored) do out[#out + 1] = name end
    tsort(out)
    return out
end

local queue, sending = {}, false
local function SendNext()
    local job = tremove(queue, 1)
    if not job then
        sending = false
        return
    end
    local listed = FL.IsIgnored and FL.IsIgnored(job.name)
    if job.add and not listed then
        FL.AddIgnore(job.name)
    elseif not job.add and listed and FL.DelIgnore then
        FL.DelIgnore(job.name)
    end
    Utils.SafeAfter(SEND_GAP, SendNext)
end

-- One change at a time: a login may hold many.
local function Send(add, name)
    if not (FL and FL.AddIgnore) then return end
    queue[#queue + 1] = { add = add, name = name }
    if sending then return end
    sending = true
    Utils.SafeAfter(0, SendNext)
end

local function Forget(key)
    local ignored, unignored, sent = Lists()
    ignored[key] = nil
    unignored[key] = true
    -- Ignored again later, every character is offered the name anew.
    for _, marks in pairs(sent) do
        if type(marks) == "table" then marks[key] = nil end
    end
end

function Ignore:Add(name)
    local key = self:Key(name)
    if not key then return end
    local ignored, unignored, sent = Lists()
    name = UI:GetPlainChatLabel(name)
    ignored[key] = name
    unignored[key] = nil
    local index = UI:GetChatCharacterIndex()
    if index then Sub(sent, index)[key] = true end
    Send(true, name)
end

function Ignore:Remove(name)
    local key = self:Key(name)
    if not key then return end
    local ignored = Lists()
    local listed = ignored[key]
    Forget(key)
    Send(false, listed or UI:GetPlainChatLabel(name))
end

-- The keys the game's list held at this session's last read; nil before
-- the first. settled: login is far enough behind that an empty list is an
-- empty list, not a late one.
local seen, settled

-- The game's list as it stands.
function Ignore:Sync()
    if not (FL and FL.GetNumIgnores and FL.GetIgnoreName) then return end
    local index = UI:GetChatCharacterIndex()
    if not index then return end
    local ignored, unignored, sent = Lists()
    sent = Sub(sent, index)
    local held, count = {}, FL.GetNumIgnores() or 0
    for i = 1, count do
        local name = FL.GetIgnoreName(i)
        local key = type(name) == "string" and not (issecretvalue and issecretvalue(name)) and self:Key(name)
        if key then held[key] = name end
    end
    if count == 0 and not settled then return end
    if not seen then
        for key, name in pairs(held) do
            if unignored[key] then
                Send(false, name)
            else
                ignored[key] = ignored[key] or name
                sent[key] = true
            end
        end
    else
        -- New since the last read: ignored in the game's own window.
        for key, name in pairs(held) do
            if not seen[key] then
                ignored[key] = ignored[key] or name
                unignored[key] = nil
                sent[key] = true
            end
        end
        -- One name gone: taken off in the game's own window. More at once
        -- is no player's doing, and nothing is taken from it.
        local gone, several
        for key in pairs(seen) do
            if not held[key] then
                several = gone ~= nil
                gone = key
            end
        end
        if gone and not several and ignored[gone] then Forget(gone) end
    end
    seen = held
    for key, name in pairs(ignored) do
        if not sent[key] then
            sent[key] = true
            if not held[key] then Send(true, name) end
        end
    end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        -- The list empties on the way out: not a read.
        self:UnregisterAllEvents()
        return
    end
    Ignore:Sync()
end)

-- Once, at login or a load after it.
function Ignore:Start()
    if self.started or not (FL and FL.GetNumIgnores) then return end
    self.started = true
    Utils.RegisterEventIfValid(watcher, "IGNORELIST_UPDATE")
    watcher:RegisterEvent("PLAYER_LOGOUT")
    Utils.SafeAfter(LOGIN_WAIT, function()
        settled = true
        Ignore:Sync()
    end)
end
