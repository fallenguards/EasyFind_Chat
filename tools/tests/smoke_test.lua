-- Loads the chat's toc files against a stubbed game and EasyFind, then checks
-- what it registered and the paths a stub can drive.
-- Usage: lua smoke_test.lua <addon dir> <toc> <addon name> [noef|old|lockdown|tooold|bn]
-- noef: no EasyFind (nothing loads); old: a store saved before schema 2, over
-- the message cap, a pinned message at its start; lockdown: a whisper whose
-- words the client hides, recorded once the lockdown ends; tooold: an
-- EasyFind older than Guard.lua's (one chat line, nothing else); bn:
-- Battle.net chats saved under a past session's IDs and name tokens, on a
-- login that handed those IDs to other friends.
-- luacheck: ignore 111 112 113 121 122 212
local dir, tocName, addon, mode = arg[1], arg[2], arg[3], arg[4] or "normal"

local Stub
local stubMeta = {}
stubMeta.__index = function(t, k)
    -- No list: ipairs over a stub ends at once.
    if type(k) == "number" then return nil end
    if k == "GetName" then return function() return nil end end
    if k == "GetWidth" or k == "GetHeight" or k == "GetScale" or k == "GetStringWidth" then
        return function() return 1 end
    end
    if k == "IsShown" or k == "IsVisible" or k == "GetChecked" or k == "IsEventRegistered"
        or k == "IsMouseOver" or k == "HasFocus" then
        return function() return false end
    end
    local v = Stub()
    rawset(t, k, v)
    return v
end
stubMeta.__call = function() return Stub() end
stubMeta.__concat = function(a, b)
    return tostring(type(a) == "table" and "" or a) .. tostring(type(b) == "table" and "" or b)
end
for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow" }) do
    stubMeta[op] = function() return 0 end
end
stubMeta.__lt = function() return false end
stubMeta.__le = function() return false end
stubMeta.__len = function() return 0 end
function Stub() return setmetatable({}, stubMeta) end

local frames = {}
local function NewFrame()
    local f = Stub()
    local scripts, events = {}, {}
    rawset(f, "SetScript", function(_, which, fn) scripts[which] = fn end)
    rawset(f, "GetScript", function(_, which) return scripts[which] end)
    rawset(f, "HookScript", function(_, which, fn) scripts[which] = scripts[which] or fn end)
    rawset(f, "RegisterEvent", function(_, e) events[e] = true end)
    rawset(f, "UnregisterEvent", function(_, e) events[e] = nil end)
    rawset(f, "UnregisterAllEvents", function() for e in pairs(events) do events[e] = nil end end)
    rawset(f, "IsEventRegistered", function(_, e) return events[e] == true end)
    f.scripts, f.events = scripts, events
    frames[#frames + 1] = f
    return f
end

local toc = assert(io.open(dir .. "/" .. tocName)):read("a")
local saved = {}
for list in toc:gmatch("## SavedVariables[%w]*:%s*([^\r\n]+)") do
    for name in list:gmatch("[%w_]+") do saved[name] = true end
end

-- The game's own strings are absent here, so the addon's English fallbacks show.
local env = setmetatable({}, { __index = function(t, k)
    local v = rawget(_G, k)
    if v ~= nil or saved[k] or k == "EasyFind" or k:match("^[A-Z][A-Z0-9_]+$") then return v end
    v = Stub()
    rawset(t, k, v)
    return v
end, __newindex = function(t, k, v)
    if saved[k] then rawset(_G, k, v) else rawset(t, k, v) end
end })

-- Any use but issecretvalue throws, as the client's secret values do for us.
local function Refuse() error("used a secret value") end
local SECRET = setmetatable({}, { __eq = Refuse, __index = Refuse, __tostring = Refuse, __concat = Refuse,
                                  __len = Refuse, __lt = Refuse, __le = Refuse })
local lockdown, lines = false, {}
local errors = {}
_G.CreateFrame = NewFrame
_G.GetLocale = function() return "enUS" end
_G.GetTime = function() return 100 end
_G.time, _G.date = os.time, os.date
_G.IsLoggedIn = function() return false end
_G.InCombatLockdown = function() return false end
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
_G.geterrorhandler = function() return function(e) errors[#errors + 1] = tostring(e) end end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.C_Timer = { After = function() end, NewTicker = function() return Stub() end, NewTimer = function() return Stub() end }
_G.C_ChatInfo = {
    InChatMessagingLockdown = function() return lockdown end,
    GetChatLineText = function(id) return lockdown and SECRET or (lines[id] and lines[id].text) end,
    GetChatLineSenderName = function(id) return lockdown and SECRET or (lines[id] and lines[id].name) end,
    GetChatLineSenderGUID = function() return lockdown and SECRET or nil end,
}
_G.unpack = table.unpack

local function Say(s) io.stdout:write(s, "\n") end

local registered, providers, actions = {}, {}, {}
if mode ~= "noef" then
    local API = Stub()
    rawset(API, "RegisterExtension", function(def)
        local rec = registered[def.id] or {}
        for k, v in pairs(def) do rec[k] = v end
        registered[def.id] = rec
        return true
    end)
    rawset(API, "RegisterSearchProvider", function(def) providers[def.key] = def return true end)
    rawset(API, "RegisterAction", function(id, name, fn) actions[id .. "." .. name] = fn return true end)
    rawset(API, "HasAction", function() return false end)
    local Utils = Stub()
    for k, v in pairs({ sfind = string.find, slower = string.lower, tinsert = table.insert, tconcat = table.concat,
                        tremove = table.remove, tsort = table.sort, mmin = math.min, mmax = math.max,
                        ErrorHandler = function(e) errors[#errors + 1] = tostring(e) end,
                        OffOrNil = function(on) if on then return nil end return false end,
                        SafeAfter = function(_, fn) fn() end,
                        RegisterEventIfValid = function(f, e) f:RegisterEvent(e) end }) do
        rawset(Utils, k, v)
    end
    local efns = Stub()
    rawset(efns, "Utils", Utils)
    -- Old: the search switches EasyFind kept while Chat came inside it.
    _G.EasyFind = { API = API, _ns = efns, db = mode == "old" and { chatFindChats = false, chatFindMessages = true } or {} }
end

if mode == "old" then
    local messages = {}
    for i = 1, 450 do messages[i] = { text = "line " .. i, outgoing = false } end
    messages[1].pinned = true
    _G.EasyFindChatDB = { schemaVersion = 0, conversations = {
        byKey = { ["player:bob-realm"] = { key = "player:bob-realm", label = "Bob", kind = "player", messages = messages } },
        order = { "player:bob-realm" } } }
end

local bnFriends = {}
if mode == "bn" then
    local function Token(n) return "|Kq" .. n .. "|k" end
    local function Saved(id, tag, initialLabel, text, at)
        return { key = "bn:" .. id, kind = "bn", label = Token(id), targetID = id, battleTag = tag,
                 initialLabel = initialLabel, lastTime = os.time() - 5000 + at,
                 messages = { { text = text, outgoing = false, senderLabel = "", time = os.time() - 5000 + at } } }
    end
    _G.EasyFindChatDB = { schemaVersion = 2, conversations = {
        byKey = {
            ["bn:42"] = Saved(42, "Ann#1111", Token(42), "hi from Ann", 100),
            ["bn:43"] = Saved(43, "Bob#2222", "Bobchar", "hi from Bob", 200),
            ["bn:7"] = Saved(7, "Ann#1111", nil, "older Ann", 50),
            ["bn:9"] = Saved(9, nil, nil, "no tag", 60),
            ["bn:44"] = Saved(44, "Gone#3333", nil, "left the list", 70),
        },
        order = { "bn:43", "bn:42", "bn:44", "bn:9", "bn:7" } } }
    -- This login: Bob holds 42, Ann 43, a new friend 9; Gone is off the list.
    bnFriends = {
        { bnetAccountID = 43, accountName = Token(43), battleTag = "Ann#1111", gameAccountInfo = {} },
        { bnetAccountID = 42, accountName = Token(42), battleTag = "Bob#2222", gameAccountInfo = { characterName = "Bobchar" } },
        { bnetAccountID = 9, accountName = Token(9), battleTag = "Cy#4444", gameAccountInfo = {} },
    }
    _G.C_BattleNet = {
        GetNumFriends = function() return #bnFriends end,
        GetFriendAccountInfo = function(i) return bnFriends[i] end,
        GetAccountInfoByID = function(id)
            for _, friend in ipairs(bnFriends) do
                if friend.bnetAccountID == id then return friend end
            end
        end,
    }
end

local said = {}
if mode == "tooold" then
    _G.C_AddOns = { GetAddOnMetadata = function(name, field)
        if name == "EasyFind" and field == "Version" then return "3.4.4" end
        if field == "Title" then return "EasyFind [Chat]" end
    end }
    _G.print = function(s) said[#said + 1] = s end
end

local ns = {}
local count = 0
for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua$") and not line:match("^#") then
        local chunk, err = loadfile(dir .. "/" .. line:gsub("\\", "/"), "t", env)
        if not chunk then Say("LOAD " .. err) os.exit(1) end
        local ok, runErr = pcall(chunk, addon, ns)
        if not ok then Say("RUN " .. line .. ": " .. tostring(runErr)) os.exit(1) end
        count = count + 1
    end
end
Say("loaded " .. count .. " files (" .. mode .. ")")

local failed = false
local function Check(ok, what)
    Say((ok and "PASS " or "FAIL ") .. what)
    if not ok then failed = true end
end

if mode == "noef" then
    Check(registered.chat == nil and ns.UI == nil, "nothing loads without EasyFind")
    os.exit(failed and 1 or 0)
end

if mode == "tooold" then
    for i = 1, #frames do
        local f = frames[i]
        if f.scripts.OnEvent and f.events.PLAYER_LOGIN then f.scripts.OnEvent(f, "PLAYER_LOGIN") end
    end
    Check(next(registered) == nil and next(providers) == nil and next(actions) == nil,
        "nothing registers with an EasyFind too old")
    local set = {}
    for k in pairs(ns) do
        if k ~= "tooOld" and k ~= "EMOTE_SHEET" then set[#set + 1] = tostring(k) end
    end
    Check(#set == 0, "every code file stops at its first lines" .. (#set > 0 and (": " .. table.concat(set, ", ")) or ""))
    Check(#said == 1 and said[1]:find("EasyFind [Chat]", 1, true) and said[1]:find("4.0.0", 1, true) ~= nil,
        "one chat line at login naming the EasyFind it needs: " .. tostring(said[1]))
    for _, e in ipairs(errors) do Check(false, "error: " .. e) end
    os.exit(failed and 1 or 0)
end

local ext = registered.chat
Check(ext ~= nil and ext.icon == "Interface\\AddOns\\EasyFind_Chat\\textures\\chat-icon" and type(ext.open) == "function",
    "the chat registers its own tile: its icon and its window")
local provider = providers.chat
Check(provider ~= nil and provider.extension == "chat" and type(provider.rows) == "function"
    and provider.options ~= nil and #provider.options == 2, "its search rows, with their two switches")
Check(type(actions["chat.compose"]) == "function" and type(actions["chat.conversations"]) == "function",
    "compose and conversations for EasyFind's send menu")
Check(ext ~= nil and type(ext.settings) == "function" and type(ext.settingsRows) == "function",
    "the chat extension, with its settings page and rows")
local views = ns.Views
local bottom = views and views:BottomEntry({ "channel:#2" })
Check(bottom ~= nil and bottom.folder == views.GAME and bottom.members[1] == views.ALL
    and bottom.members[2] == "channel:#2" and bottom.members[3] == views.SYSTEM,
    "the game chats as one group at the list's foot: All, the channels, System")
-- Every edit box drops its focus on an outside click (the client keeps it
-- focused and it eats every key), after its own focus scripts; or says why
-- not with "-- keeps focus:". The third report of this (2026-10-30).
local boxes, unwatched = 0, {}
for line in toc:gmatch("[^\r\n]+") do
    if line:match("%.lua$") and not line:match("^#") then
        local src = assert(io.open(dir .. "/" .. line:gsub("\\", "/"))):read("a"):gsub("\r\n", "\n")
        local srcLines = {}
        for l in (src .. "\n"):gmatch("(.-)\n") do srcLines[#srcLines + 1] = l end
        for i = 1, #srcLines do
            if srcLines[i]:find('CreateFrame%("EditBox"') and not srcLines[i]:find("^%s*%-%-") then
                boxes = boxes + 1
                local keeps = srcLines[i]:find("%-%- keeps focus:") or (srcLines[i - 1] or ""):find("%-%- keeps focus:")
                local var = srcLines[i]:match("^%s*local%s+([%w_%.%[%]]+)%s*=") or srcLines[i]:match("^%s*([%w_%.%[%]]+)%s*=")
                local esc = var and var:gsub("%p", "%%%0")
                local released, late
                for j = i + 1, #srcLines do
                    if esc and srcLines[j]:find("ReleaseFocusOnOutsideClick%(" .. esc .. "%)") then released = j end
                    if esc and srcLines[j]:find(esc .. ':SetScript%("OnEditFocus') then late = j end
                end
                if not keeps and (not released or (late and late > released)) then
                    unwatched[#unwatched + 1] = line .. ":" .. i .. " " .. tostring(var)
                end
            end
        end
    end
end
Check(boxes >= 8 and #unwatched == 0, "every edit box drops its focus on an outside click"
    .. (#unwatched > 0 and (": " .. table.concat(unwatched, ", ")) or ""))
local chatSrc = assert(io.open(dir .. "/Chat.lua")):read("a")
local fillAt = chatSrc:find("function UI:FillChatFolderFlyout", 1, true) or 0
Check(chatSrc:find("foot.folderID == flyout.fid then owner = foot end", fillAt, true) ~= nil,
    "the foot row's click opens its members: the flyout finds it as its owner")
Check(chatSrc:find('self.hovering = true\n        UI:RepaintChatListRow(self)', 1, true) ~= nil
    and chatSrc:find('self.hovering = false\n        UI:RepaintChatListRow(self)', 1, true) ~= nil,
    "a list row lights under the cursor and goes plain when it leaves")
Check(chatSrc:find('HookScript("OnScrollRangeChanged", function() UI:UpdateChatNewestButton(view) end)', 1, true) ~= nil
    and chatSrc:find("self:UpdateChatNewestButton(view, range - scrollTo)", 1, true) ~= nil,
    "the newest button reads the layout's own distance, and again once the range settles")
if ext then
    local ok, rows = pcall(ext.settingsRows)
    Check(ok and type(rows) == "table" and #rows > 10, "its settings rows build")
    for _, r in ipairs(ok and rows or {}) do
        local c = r.control
        local okGet, value = pcall(c.get)
        if not okGet then Check(false, "row " .. r.name .. " reads: " .. tostring(value)) end
        if c.kind == "check" and okGet and type(value) ~= "boolean" then
            Check(false, "row " .. r.name .. " reads a boolean, not " .. tostring(value))
        end
    end
    local kit = setmetatable({}, { __index = function() return function() return Stub() end end })
    local okPage, err = pcall(ext.settings, Stub(), kit)
    Check(okPage, "the settings page builds" .. (okPage and "" or (": " .. tostring(err))))
end

for i = 1, #frames do
    local f = frames[i]
    if f.scripts.OnEvent and f.events.PLAYER_LOGIN then
        local ok, err = pcall(f.scripts.OnEvent, f, "PLAYER_LOGIN")
        if not ok then Check(false, "PLAYER_LOGIN: " .. tostring(err)) end
    end
end

local UI = ns.UI
if mode == "normal" then
    -- The button counts the chats the list shows: this character's (a
    -- muted room its mentions only), every character's under that pick.
    local badge
    rawset(EasyFind.API, "SetBadge", function(_, n) badge = n end)
    rawset(EasyFind._ns, "PlayerName", function() return "Me" end)
    rawset(EasyFind._ns, "CurrentCharacterKey", function() return "Me-Realm" end)
    local store = UI:GetChatConversationStore()
    store.chars = { "Me-Realm", "Alt-Realm" }
    store.byKey["player:bob-realm"] = { unread = 3, chars = { [1] = true }, messages = { {} } }
    store.byKey["player:ann-realm"] = { unread = 5, chars = { [2] = true }, messages = { {} } }
    store.byKey["channel:#general"] = { unread = 100, mentions = 2, chars = { [1] = true, [2] = true }, messages = { {} } }
    store.byKey["channel:party"] = { unread = 4, chars = { [1] = true, [2] = true }, messages = { {} } }
    store.order = { "player:bob-realm", "player:ann-realm", "channel:#general", "channel:party" }
    -- Only whispers start unmuted: the party's four stay off the button.
    UI:UpdateChatUnreadBadge()
    Check(badge == 5, "the badge counts this character's whispers, a muted chat's mentions only: " .. tostring(badge))
    UI._chatComposer.charView = "all"
    UI:UpdateChatUnreadBadge()
    Check(badge == 10, "every character's under that pick: " .. tostring(badge))
    UI._chatComposer.charView = nil
    Check(UI:IsChatConversationMuted("channel:party") and UI:IsChatConversationMuted("channel:guild")
        and UI:IsChatConversationMuted("channel:#general") and not UI:IsChatConversationMuted("player:bob-realm")
        and not UI:IsChatConversationMuted("bn:ann#1111"), "group, guild and public chats start muted, whispers do not")
    store.byKey["channel:party"].mentions = 1
    UI:UpdateChatUnreadBadge()
    Check(badge == 6, "a party message naming you counts through the mute: " .. tostring(badge))
    store.byKey["channel:party"].mentions = nil
    store.byKey["channel:party"].muted = false
    UI:UpdateChatUnreadBadge()
    Check(badge == 9, "a chat unmuted from its menu counts whole: " .. tostring(badge))
    store.byKey["channel:party"].muted = nil
    _G.EasyFindChatDB.muteGroups = false
    UI:UpdateChatUnreadBadge()
    Check(badge == 9 and not UI:IsChatConversationMuted("channel:guild") and UI:IsChatConversationMuted("channel:#general"),
        "the group setting off: party and guild count again, public rooms stay muted: " .. tostring(badge))
    _G.EasyFindChatDB.muteGroups = nil
    local muteRow
    for _, r in ipairs(ext.settingsRows()) do
        if r.name == "Mute group and guild chat" then muteRow = r end
    end
    Check(muteRow ~= nil and muteRow.control.get() == true, "its switch is on the settings page, on by default")
end
if mode == "old" then
    local db = _G.EasyFindChatDB
    Check(db.findChats == false and db.findMessages == true, "the search switches carried over from EasyFind's save")
    local messages = db.conversations.byKey["player:bob-realm"].messages
    Check(db.schemaVersion == ns.Store.SCHEMA_VERSION, "the old store migrates to schema " .. tostring(db.schemaVersion))
    Check(#messages == 401, "trimmed to the cap with the pinned message kept: " .. #messages)
    Check(messages[1].pinned == true and messages[2].text == "line 51", "the pinned message stays first")
end

if mode == "bn" then
    local store = UI:GetChatConversationStore()
    local annKey, bobKey, goneKey = "bn:ann#1111", "bn:bob#2222", "bn:gone#3333"
    local ann, bob, gone = store.byKey[annKey], store.byKey[bobKey], store.byKey[goneKey]
    Check(ann ~= nil and bob ~= nil and gone ~= nil and store.byKey["bn:42"] == nil and store.byKey["bn:43"] == nil
        and store.byKey["bn:7"] == nil and store.byKey["bn:44"] == nil, "saved Battle.net chats are kept under their BattleTags")
    Check(ann ~= nil and #ann.messages == 2 and ann.messages[1].text == "older Ann",
        "one friend's two saved chats are one chat")
    local past, leaked
    for key, convo in pairs(store.byKey) do
        if key:find("^bn:past:") then past = key end
        if convo.targetID or tostring(convo.label):find("|K", 1, true)
            or tostring(convo.initialLabel or ""):find("|K", 1, true) then leaked = key end
    end
    Check(leaked == nil, "no saved chat keeps a session's ID or name token" .. (leaked and (": " .. leaked) or ""))
    Check(past ~= nil and store.byKey["bn:9"] == nil, "a saved chat with no BattleTag is set apart from this login's IDs")
    Check(ann ~= nil and UI:GetChatConversationDisplayLabel(ann, annKey) == "|Kq43|k"
        and bob ~= nil and UI:GetChatConversationDisplayLabel(bob, bobKey) == "|Kq42|k",
        "each chat shows its friend's name token of this login")
    Check(ann ~= nil and UI:GetChatConversationPlainLabel(ann, annKey) == "Ann"
        and UI:GetChatMessageSenderLabel(ann, ann.messages[1], annKey) == "Ann",
        "its plain name, and a saved line's sender, are the BattleTag's name")
    Check(gone ~= nil and UI:GetChatConversationDisplayLabel(gone, goneKey) == "Gone",
        "a friend off the list shows the BattleTag's name")
    Check(ann ~= nil and UI:GetChatBNAccountID(ann, annKey) == 43 and bob ~= nil and UI:GetChatBNAccountID(bob, bobKey) == 42,
        "a reply goes to the friend's ID of this login")
    Check(gone ~= nil and UI:GetChatBNAccountID(gone, goneKey) == nil and past ~= nil
        and UI:GetChatBNAccountID(store.byKey[past], past) == nil,
        "a friend off the list, or a past login's chat with no BattleTag, has no one to send to")
    -- ID 42 was Ann's when her chat was saved; Bob holds it now.
    UI:HandleChatMessageEvent("CHAT_MSG_BN_WHISPER", "new from Bob", "|Kq42|k", "", "", "", "", 0, 0, "", 0, 1, nil, 42)
    Check(bob ~= nil and #bob.messages == 2 and bob.messages[2].text == "new from Bob" and ann ~= nil and #ann.messages == 2,
        "a whisper lands in its sender's chat, whoever held the ID before")
    Check(bob ~= nil and bob.messages[2] ~= nil and bob.messages[2].senderLabel == "Bob" and bob.label == "Bob"
        and bob.targetID == nil, "its sender and the chat's name are saved as plain text, no ID")
    UI:HandleChatMessageEvent("CHAT_MSG_BN_WHISPER", "hello from Cy", "|Kq9|k", "", "", "", "", 0, 0, "", 0, 2, nil, 9)
    Check(store.byKey["bn:cy#4444"] ~= nil and past ~= nil and #store.byKey[past].messages == 1,
        "a new friend on a past chat's ID gets a chat of their own")
    -- The friend list moves under the index: read again by BattleTag.
    table.insert(bnFriends, 1, { bnetAccountID = 50, accountName = "|Kq50|k", battleTag = "New#5555", gameAccountInfo = {} })
    Check(ann ~= nil and UI:GetChatBNAccountID(ann, annKey) == 43, "the friend is found after the list's order moved")
    -- A whisper with no readable BattleTag: this login only.
    bnFriends[#bnFriends + 1] = { bnetAccountID = 77, accountName = "|Kq77|k", battleTag = "", gameAccountInfo = {} }
    UI:HandleChatMessageEvent("CHAT_MSG_BN_WHISPER", "no tag yet", "|Kq77|k", "", "", "", "", 0, 0, "", 0, 3, nil, 77)
    local live = store.byKey["bn:session:77"]
    Check(live ~= nil and UI:GetChatBNAccountID(live, "bn:session:77") == 77 and live.targetID == nil,
        "a chat with no BattleTag answers to its ID for this login, nothing saved")
    Check(live ~= nil and UI:GetCanonicalChatConversationKey("bn:session:77", live) == "bn:session:77",
        "and keeps its key while the login lasts")
    UI._chatComposer.bnSessionIDs["bn:session:77"] = nil
    Check(live ~= nil and UI:GetCanonicalChatConversationKey("bn:session:77", live):find("^bn:past:") ~= nil,
        "the next login sets it apart")
    -- Every send reads the ID from the friend list, never a chat's saved field or its key.
    Check(chatSrc:find("convo.targetID or", 1, true) == nil and chatSrc:find('key:match("^bn:', 1, true) == nil
        and chatSrc:find("presenceID = id, text = sendLine", 1, true) ~= nil,
        "the reply path sends to GetChatBNAccountID's answer only")
end

if mode == "lockdown" then
    lockdown = true
    lines[7] = { text = "hello from the fight", name = "Bob-Realm" }
    local ok, err = pcall(UI.HandleChatMessageEvent, UI, "CHAT_MSG_WHISPER", SECRET, SECRET, "", "", SECRET,
        "", 0, 0, "", 0, 7, SECRET, SECRET)
    Check(ok, "a hidden whisper does not error" .. (ok and "" or (": " .. tostring(err))))
    local store = UI:GetChatConversationStore()
    Check(store.byKey["player:bob-realm"] == nil, "nothing recorded while hidden")
    lockdown = false
    for i = 1, #frames do
        local f = frames[i]
        if f.events.ADDON_RESTRICTION_STATE_CHANGED and f.scripts.OnEvent then
            f.scripts.OnEvent(f, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
        end
    end
    local convo = store.byKey["player:bob-realm"]
    local msg = convo and convo.messages and convo.messages[#convo.messages]
    Check(msg ~= nil and msg.text == "hello from the fight" and msg.outgoing == false,
        "recorded once the lockdown ends")
end

for _, e in ipairs(errors) do Check(false, "error: " .. e) end
os.exit(failed and 1 or 0)
