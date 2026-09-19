local script = arg[1] or "klip.lua"
local lua = arg[-1] or "lua"
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function ok(s) local a = os.execute(s); return a == true or a == 0 end
local function write(path, s) local f = assert(io.open(path, "wb")); assert(f:write(s)); assert(f:close()) end
local function read(path) local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s end
local root = os.tmpname(); os.remove(root)
assert(ok("mkdir -p " .. q(root .. "/bin")))
local env = "KLIP_DIR=" .. q(root .. "/data") .. " WAYLAND_DISPLAY=klip-test CLIPBOARD_STATE=data PATH=" .. q(root .. "/bin:" .. os.getenv("PATH")) .. " KLIP_TEST_ROOT=" .. q(root)
write(root .. "/bin/wl-copy", [[#!/usr/bin/env lua
assert(arg[1] == '--type' and arg[2] == 'text/plain;charset=utf-8')
if os.getenv('KLIP_TEST_FAIL') == '1' then os.exit(1) end
local f = assert(io.open(os.getenv('KLIP_TEST_ROOT') .. '/clipboard', 'wb'))
f:write(io.read('*a')); f:close()
]])
write(root .. "/bin/wl-paste", [[#!/usr/bin/env lua
assert(arg[1] == '--type' and arg[2] == 'text' and arg[3] == '--watch')
local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local r = os.getenv('KLIP_TEST_ROOT')
local f = assert(io.open(r .. '/event', 'wb')); f:write('watch event\n'); f:close()
local a = os.execute(q(arg[4]) .. ' ' .. q(arg[5]) .. ' ' .. q(arg[6]) .. ' < ' .. q(r .. '/event'))
if not (a == true or a == 0) then os.exit(1) end
]])
assert(ok("chmod +x " .. q(root .. "/bin/wl-copy") .. " " .. q(root .. "/bin/wl-paste")))
local count = 0
local function command(args, input, extra, expected)
  write(root .. "/input", input or "")
  local success = ok(env .. " " .. (extra or "") .. " " .. q(lua) .. " " .. q(script) .. " " .. args .. " < " .. q(root .. "/input") .. " > " .. q(root .. "/out") .. " 2> " .. q(root .. "/err"))
  assert(success == (expected ~= false), read(root .. "/err")); count = count + 1
  return read(root .. "/out")
end
local success, err = pcall(function()
  assert(command("list") == "")
  local tricky = "quote ' \" $(touch /nope) `echo bad`\nline two\t\27[31m\0end\n"
  command("add", tricky)
  local listing = command("list"); assert(listing:find("1\t", 1, true)); assert(not listing:find("\27", 1, true))
  command("copy 1"); assert(read(root .. "/clipboard") == tricky)
  command("add", "second")
  command("add", tricky)
  listing = command("list"); assert(listing:sub(1, 2) == "1\t"); assert(not listing:find("3\t", 1, true))
  command("menu", "/second\n1\n"); assert(read(root .. "/clipboard") == "second")
  command("capture", "secret", "CLIPBOARD_STATE=sensitive")
  assert(command("list secret") == "")
  command("capture", "ignored", "CLIPBOARD_STATE=nil")
  command("add", string.rep("x", 1024 * 1024 + 1))
  assert(command("list xxxx") == "")
  command("copy 2", "", "KLIP_TEST_FAIL=1", false)
  command("watch"); assert(command("list 'watch event'"):find("watch event", 1, true))
  command("delete 2"); command("copy 2", "", nil, false)
  command("clear", "", nil, false)
  command("clear --yes"); assert(command("list") == "")
  
  local records = {"KLIP1\n201\n"}
  for i = 200, 1, -1 do local s = "entry " .. i; records[#records + 1] = i .. " 1 " .. #s .. "\n" .. s end
  write(root .. "/data/history", table.concat(records))
  command("add", "newest")
  listing = command("list"); assert(listing:sub(1, 4) == "201\t"); assert(not listing:find("\n1\t", 1, true))
  command("menu", "n\n1\n"); assert(read(root .. "/clipboard") == "entry 189")
  
  write(root .. "/data/history", "broken")
  command("add", "keep old file", nil, false); assert(read(root .. "/data/history") == "broken")
  
  os.remove(root .. "/data/history")
  local jobs = {}
  for i = 1, 8 do
    write(root .. "/job" .. i, "parallel " .. i)
    jobs[#jobs + 1] = env .. " " .. q(lua) .. " " .. q(script) .. " add < " .. q(root .. "/job" .. i) .. " &"
  end
  assert(ok(table.concat(jobs, "\n") .. "\nwait"))
  listing = command("list"); local _, lines = listing:gsub("\n", ""); assert(lines == 8)
end)
assert(ok("rm -rf -- " .. q(root)))
if not success then error(err, 0) end
print("PASS: " .. count .. " CLI checks, including exact round trips, menu selection, watcher dispatch, retention, corrupt storage and concurrent writers.")
