--[[----------------------------------------------------------------------------
run -- the test runner.

    lua5.1 tests/run.lua              run everything
    lua5.1 tests/run.lua parser       run only files whose name contains "parser"

Discovers tests/test_*.lua, loads each (the file registers its cases with
harness.test), then runs every case with a fresh fake client. Prints a summary
and exits non-zero if anything failed, which is what CI reads.

Stock Lua only -- 5.1 is the target, 5.3 and 5.4 also work.
------------------------------------------------------------------------------]]

local scriptPath = (arg and arg[0]) or "tests/run.lua"
local dir = scriptPath:match("^(.*[/\\])") or "./"

package.path = dir .. "?.lua;" .. package.path
local h = require("harness")

------------------------------------------------------------------------------
-- Discovery
------------------------------------------------------------------------------

local function listTestFiles()
    local names = {}
    local windows = package.config:sub(1, 1) == "\\"
    local cmd = windows
        and ('dir /b "' .. dir:gsub("/", "\\") .. '"')
        or ('ls -1 "' .. dir .. '"')
    local pipe = io.popen(cmd)
    if pipe then
        for entry in pipe:lines() do
            -- A fresh local, never the loop variable: Lua 5.5 makes those const.
            local name = entry:gsub("%s+$", "")
            if name:match("^test_.*%.lua$") then names[#names + 1] = name end
        end
        pipe:close()
    end
    table.sort(names)
    return names
end

local files = listTestFiles()
local filter = arg and arg[1]
if filter then
    local kept = {}
    for _, name in ipairs(files) do
        if name:find(filter, 1, true) then kept[#kept + 1] = name end
    end
    files = kept
end

if #files == 0 then
    print("no test files found in " .. dir .. (filter and (" matching '" .. filter .. "'") or ""))
    os.exit(1)
end

------------------------------------------------------------------------------
-- Load
------------------------------------------------------------------------------

for _, name in ipairs(files) do
    h.currentFile = name
    local chunk, err = loadfile(dir .. name)
    if not chunk then
        print("CANNOT LOAD  " .. name .. ": " .. tostring(err))
        os.exit(1)
    end
    local ok, runErr = pcall(chunk)
    if not ok then
        print("ERROR IN     " .. name .. ": " .. tostring(runErr))
        os.exit(1)
    end
end

------------------------------------------------------------------------------
-- Run
------------------------------------------------------------------------------

local passed, failures = 0, {}
local perFile, order = {}, {}

for _, case in ipairs(h.tests) do
    if perFile[case.file] == nil then
        perFile[case.file] = 0
        order[#order + 1] = case.file
    end

    local env
    local ok, err = pcall(function()
        env = h.newEnv(case.opts)
        case.fn(env, env.ns)
    end)
    if env then env.destroy() end

    if ok then
        passed = passed + 1
        perFile[case.file] = perFile[case.file] + 1
    else
        failures[#failures + 1] = { file = case.file, name = case.name, err = err }
    end
end

for _, file in ipairs(order) do
    local failed = 0
    for _, f in ipairs(failures) do
        if f.file == file then failed = failed + 1 end
    end
    print(string.format("%-28s %3d ok%s", file, perFile[file],
        failed > 0 and ("  " .. failed .. " FAILED") or ""))
end

if #failures > 0 then
    print("")
    for _, f in ipairs(failures) do
        print("FAIL  " .. f.file .. "  --  " .. f.name)
        print("      " .. tostring(f.err))
    end
end

print("")
print(string.format("%d file(s), %d test(s), %d passed, %d failed",
    #files, #h.tests, passed, #failures))

os.exit(#failures == 0 and 0 or 1)
