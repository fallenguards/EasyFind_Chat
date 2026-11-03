-- Every EasyFind name the chat calls or indexes (ns.X, ns.X.Y, a local
-- alias's functions, EasyFind.API.X) is defined in the EasyFind given: CI
-- hands it the oldest release Guard.lua names. A name used only behind a
-- check (X and, X or, if X then, not X) may be missing.
-- Usage: lua core_names.lua <addon dir> <toc> <easyfind dir>
local dir, tocName, efDir = arg[1], arg[2], arg[3]

local function Read(path)
    local f = assert(io.open(path, "rb"), path)
    local s = f:read("a")
    f:close()
    return s
end

local function Strip(s)
    s = s:gsub("%-%-%[(=*)%[.-%]%1%]", "")
    return (s:gsub("%-%-[^\n]*", ""))
end

local function Esc(s) return (s:gsub("%p", "%%%0")) end
local USED = "%s*[%(%.:%[\"{]"

local function Defined(text, ref)
    local e = Esc(ref)
    return text:find("function%s+" .. e .. "%s*%(") or text:find(e .. "%s*=[^=]") ~= nil
end

local function Guarded(text, ref)
    local e = Esc(ref)
    return text:find(e .. "%s+and%f[%W]") or text:find(e .. "%s+or%f[%W]")
        or text:find("if%s+" .. e .. "%s+then") or text:find("not%s+" .. e .. "%f[^%w_.:]") ~= nil
end

-- What the chat uses, keyed "ns.X", "ns.X.Y" or "API.X".
local uses = {}
local function Note(text, ref, own)
    own = own or ref
    if not Defined(text, own) and not Guarded(text, own) then uses[ref] = true end
end
local files = {}
for line in Read(dir .. "/" .. tocName):gmatch("[^\r\n]+") do
    local file = line:match("^([%w_/]+%.lua)")
    if file and not file:find("^Locales/") and file ~= "Guard.lua" then files[#files + 1] = Strip(Read(dir .. "/" .. file)) end
end
local all = table.concat(files, "\n")
for _, text in ipairs(files) do
    for x in text:gmatch("%f[%w_]ns%.([%a_][%w_]*)" .. USED) do
        if not Defined(all, "ns." .. x) then Note(text, "ns." .. x) end
    end
    for x, y in text:gmatch("%f[%w_]ns%.([%a_][%w_]*)[.:]([%a_][%w_]*)" .. USED) do
        if not Defined(all, "ns." .. x .. "." .. y) then Note(text, "ns." .. x .. "." .. y) end
    end
    for alias, x in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*ns%.([%a_][%w_]*)%s*\n") do
        if not Guarded(text, alias) then
            for y in text:gmatch("%f[%w_]" .. Esc(alias) .. "[.:]([%a_][%w_]*)%s*%(") do
                if not Defined(all, alias .. "." .. y) then Note(text, "ns." .. x .. "." .. y, alias .. "." .. y) end
            end
        end
    end
    for x in text:gmatch("EasyFind%.API%.([%a_][%w_]*)%s*%(") do Note(text, "API." .. x, "EasyFind.API." .. x) end
end

-- EasyFind's own code: a top name as ns.X, a field on any of its tables.
local efParts = {}
local list = assert(io.popen('cd "' .. efDir .. '" && find . -name "*.lua" -not -path "./tests/*" -not -path "./dev/*"'))
for path in list:lines() do efParts[#efParts + 1] = Strip(Read(efDir .. "/" .. path)) end
list:close()
local ef = table.concat(efParts, "\n")

local function Has(ref)
    local api = ref:match("^API%.(.+)$")
    if api then return Defined(ef, "API." .. api) end
    local x, y = ref:match("^ns%.([%w_]+)%.([%w_]+)$")
    if not x then return Defined(ef, ref) end
    local e = Esc(y)
    return ef:find("function%s+[%w_.]+[.:]" .. e .. "%s*%(") or ef:find("[%w_%]]%." .. e .. "%s*=[^=]")
        or ef:find("[{,]%s*" .. e .. "%s*=[^=]") or ef:find("%[\"" .. e .. "\"%]%s*=") ~= nil
end

local missing = {}
for ref in pairs(uses) do
    if not Has(ref) then missing[#missing + 1] = ref end
end
table.sort(missing)
if #missing > 0 then
    io.stdout:write("not in " .. efDir .. ": " .. table.concat(missing, ", ") .. "\n")
    os.exit(1)
end
io.stdout:write("every EasyFind name the chat calls is in " .. efDir .. "\n")
