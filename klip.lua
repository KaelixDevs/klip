#!/usr/bin/env lua
-- Klip: text clipboard history for Wayland. Lua 5.1+; no Lua modules.
local VERSION = "1.0.0"
local MAX_ENTRY, MAX_TOTAL, MAX_ITEMS = 1024 * 1024, 16 * 1024 * 1024, 200
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function ok(a) return a == true or a == 0 end
local function run(s) return ok(os.execute(s)) end
local function fail(s) error(s, 0) end
local function need(s) if not run("command -v " .. quote(s) .. " >/dev/null 2>&1") then fail("Missing command: " .. s) end end
local function absolute(p) return p and p:sub(1, 1) == "/" end
local home = os.getenv("HOME")
local base = os.getenv("XDG_DATA_HOME")
if not absolute(base) then base = home and (home .. "/.local/share") end
local dir = os.getenv("KLIP_DIR") or (base and (base .. "/klip"))
local db, lock
local function init()
  if not absolute(dir) then fail("Set HOME, XDG_DATA_HOME or KLIP_DIR to an absolute path.") end
  db, lock = dir .. "/history", dir .. "/write.lock"
  if not run("umask 077; mkdir -p -- " .. quote(dir) .. " && chmod 700 -- " .. quote(dir)) then fail("Cannot create private history directory.") end
end
local function readall(path)
  local f, err, code = io.open(path, "rb")
  if not f then if code == 2 then return nil end; fail(err or ("Cannot read " .. path)) end
  local s = f:read(MAX_TOTAL + 65537); f:close()
  return s or ""
end
-- Length-prefixed records: clipboard contents are data, never executable Lua.
local function load()
  local data = readall(db)
  if not data then return { nextid = 1, entries = {} } end
  local cursor = 1
  local function line()
    local e = data:find("\n", cursor, true)
    if not e then fail("History is damaged; refusing to overwrite it: " .. db) end
    local s = data:sub(cursor, e - 1); cursor = e + 1; return s
  end
  if line() ~= "KLIP1" then fail("Unrecognized history format: " .. db) end
  local n = line()
  if not n:match("^%d+$") or tonumber(n) < 1 or tonumber(n) > 9007199254740000 then fail("Invalid history counter.") end
  local result, seen, total = { nextid = tonumber(n), entries = {} }, {}, 0
  while cursor <= #data do
    local id, stamp, len = line():match("^(%d+) (%d+) (%d+)$")
    id, stamp, len = tonumber(id), tonumber(stamp), tonumber(len)
    if not id or id < 1 or id >= result.nextid or seen[id] or not len or len > MAX_ENTRY or cursor + len - 1 > #data then fail("Invalid history record.") end
    local text = data:sub(cursor, cursor + len - 1); cursor = cursor + len
    total = total + len; seen[id] = true
    result.entries[#result.entries + 1] = { id = id, stamp = stamp, text = text }
    if total > MAX_TOTAL or #result.entries > MAX_ITEMS then fail("History exceeds storage limits.") end
  end
  return result
end
local function save(state)
  local path = dir .. "/history.new"
  local f, err = io.open(path, "wb"); if not f then fail(err) end
  local function put(s) local success, why = f:write(s); if not success then f:close(); fail(why) end end
  put("KLIP1\n" .. string.format("%.0f", state.nextid) .. "\n")
  for _, e in ipairs(state.entries) do put(string.format("%.0f %.0f %d\n", e.id, e.stamp, #e.text)); put(e.text) end
  local success, why = f:close(); if not success then fail(why) end
  if not run("chmod 600 -- " .. quote(path)) then fail("Cannot secure history file.") end
  local renamed, reason = os.rename(path, db); if not renamed then fail(reason) end
end
local function mutate(fn)
  local acquired = false
  for _ = 1, 50 do
    if run("umask 077; mkdir -- " .. quote(lock) .. " 2>/dev/null") then acquired = true; break end
    run("sleep 0.1")
  end
  if not acquired then fail("History is busy. If a writer crashed, stop Klip processes and remove " .. lock .. " with rmdir.") end
  local success, result = pcall(function() local state = load(); fn(state); save(state) end)
  run("rmdir -- " .. quote(lock) .. " 2>/dev/null")
  if not success then fail(result) end
end
local function ingest()
  local state = os.getenv("CLIPBOARD_STATE")
  if state and state ~= "data" then return end
  local text = io.stdin:read(MAX_ENTRY + 1)
  if not text or text == "" then return end
  if #text > MAX_ENTRY then
    while io.stdin:read(65536) do end
    io.stderr:write("klip: skipped text larger than 1 MiB.\n"); return
  end
  mutate(function(s)
    local entry
    for i = #s.entries, 1, -1 do if s.entries[i].text == text then entry = table.remove(s.entries, i) end end
    if not entry then entry = { id = s.nextid, text = text }; s.nextid = s.nextid + 1 end
    entry.stamp = os.time(); table.insert(s.entries, 1, entry)
    local total = 0
    for i = #s.entries, 1, -1 do if i > MAX_ITEMS then table.remove(s.entries, i) end end
    for _, e in ipairs(s.entries) do total = total + #e.text end
    while total > MAX_TOTAL do local e = table.remove(s.entries); total = total - #e.text end
  end)
end
-- Prevent terminal escape/control injection, including bidi formatting controls.
local function preview(s)
  s = s:gsub("[\226][\128][\170-\174]", "?"):gsub("[\226][\129][\166-\169]", "?")
  s = s:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("[%z\1-\31\127]", "?")
  if #s > 100 then
    local n = 100
    while n > 0 and (s:byte(n + 1) or 0) >= 128 and (s:byte(n + 1) or 0) < 192 do n = n - 1 end
    s = s:sub(1, n) .. "…"
  end
  return s
end
local function filtered(entries, query)
  local result = {}; query = (query or ""):lower()
  for _, e in ipairs(entries) do if e.text:lower():find(query, 1, true) then result[#result + 1] = e end end
  return result
end
local function wayland()
  if not os.getenv("WAYLAND_DISPLAY") then fail("Run this inside your Plasma Wayland session (WAYLAND_DISPLAY is missing).") end
end
local function copy(entry)
  wayland(); need("wl-copy")
  local p, err = io.popen("wl-copy --type 'text/plain;charset=utf-8'", "w")
  if not p then fail(err) end
  local success, why = p:write(entry.text)
  local closed = p:close()
  if not success or not ok(closed) then fail(why or "wl-copy failed; check your Wayland session.") end
  io.stdout:write("Copied #", entry.id, ". Switch to your app and press Ctrl+V.\n")
end
local function find(entries, id)
  if not id or not id:match("^%d+$") then fail("Provide an entry ID from 'klip list'.") end
  for _, e in ipairs(entries) do if e.id == tonumber(id) then return e end end
  fail("No entry with ID " .. id)
end
local function menu()
  local page, query = 1, ""
  local snapshot = load().entries
  while true do
    local entries = filtered(snapshot, query)
    local pages = math.max(1, math.ceil(#entries / 12)); page = math.min(page, pages)
    io.write("\nKlip — clipboard history | ", #entries, " entries | page ", page, "/", pages, "\n")
    if query ~= "" then io.write("Search: ", preview(query), "\n") end
    local first = (page - 1) * 12 + 1
    for i = first, math.min(first + 11, #entries) do io.write(string.format("%2d. %s\n", i - first + 1, preview(entries[i].text))) end
    if #entries == 0 then io.write("No matching entries. Run 'klip watch' to collect copied text.\n") end
    io.write("Number + Enter: copy | /text: search | /: reset | n/p: page | r: refresh | q: quit\n> "); io.flush()
    local input = io.read("*l"); if not input or input == "q" then return end
    if input:sub(1, 1) == "/" then query = input:sub(2); page = 1
    elseif input == "n" then page = math.min(pages, page + 1)
    elseif input == "p" then page = math.max(1, page - 1)
    elseif input == "r" then snapshot = load().entries
    elseif input:match("^%d+$") and tonumber(input) >= 1 and tonumber(input) <= 12 and entries[first + tonumber(input) - 1] then
      copy(entries[first + tonumber(input) - 1]); return
    else io.write("Choose a displayed number, /search, n, p, r, or q.\n") end
  end
end
local HELP = [[Klip — Lua clipboard history for Plasma Wayland
Usage: lua klip.lua COMMAND [ARGUMENT]
  watch          Collect copied text continuously (Ctrl+C stops)
  menu           Open searchable numbered menu; selection becomes Ctrl+V clipboard
  list [query]   List entry IDs and safe text previews
  copy ID        Restore an entry to the clipboard
  delete ID      Delete an entry from this history
  clear --yes    Erase this history (does not clear the current clipboard)
  add            Add text from standard input
  path           Print the private history directory
  doctor         Check required commands and session environment
  help           Show this help
  version        Show version
Limits: 200 unique text entries, 1 MiB each, 16 MiB total.
Storage: $XDG_DATA_HOME/klip or ~/.local/share/klip; override with KLIP_DIR.
]]
local function main()
  local cmd = arg[1] or "help"
  if cmd == "help" or cmd == "--help" or cmd == "-h" then io.write(HELP); return end
  if cmd == "version" or cmd == "--version" then print(VERSION); return end
  if cmd == "doctor" then
    for _, name in ipairs({ "wl-copy", "wl-paste", "mkdir", "chmod", "rmdir", "sleep" }) do need(name); print(name .. ": found") end
    wayland(); print("Wayland environment: present"); print("Run 'watch' to verify compositor data-control support."); return
  end
  local valid = {watch=true, menu=true, list=true, copy=true, delete=true, clear=true, add=true, capture=true, path=true}
  if not valid[cmd] then fail("Unknown command: " .. cmd .. ". Run 'klip help'.") end
  init()
  if cmd == "path" then print(dir)
  elseif cmd == "add" or cmd == "capture" then ingest()
  elseif cmd == "watch" then
    wayland(); need("wl-paste")
    local interpreter = (arg[-1] and arg[-1]:sub(1, 1) ~= "-") and arg[-1] or "lua"
    need(interpreter)
    io.stderr:write("Klip is watching copied text. Ctrl+C stops it.\n")
    if not run("wl-paste --type text --watch " .. quote(interpreter) .. " " .. quote(arg[0]) .. " capture") then
      fail("Clipboard watcher stopped with an error. Check wl-paste and Plasma Wayland data-control support.")
    end
  elseif cmd == "menu" then menu()
  elseif cmd == "list" then
    for _, e in ipairs(filtered(load().entries, arg[2])) do print(string.format("%d\t%s", e.id, preview(e.text))) end
  elseif cmd == "copy" then copy(find(load().entries, arg[2]))
  elseif cmd == "delete" then
    mutate(function(s) local e = find(s.entries, arg[2]); for i, item in ipairs(s.entries) do if item.id == e.id then table.remove(s.entries, i); break end end end)
    print("Entry deleted.")
  elseif cmd == "clear" then
    if arg[2] ~= "--yes" then fail("Use 'klip clear --yes' to erase the saved history.") end
    mutate(function(s) s.entries = {} end); print("History cleared.")
  end
end
local success, err = pcall(main)
if not success then io.stderr:write("klip: ", tostring(err), "\n"); os.exit(1) end
