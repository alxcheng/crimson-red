-- tools/luacheck — syntax-check every .lua file of the game without running it.
-- Use ./check_syntax from the repo root. A syntax error makes the game (and both
-- tests) hang at start-up with no message, so run this first when that happens.
function love.load(args)
    local root, bad = args[1], 0
    local p = io.popen('find "' .. root .. '/main-game" "' .. root .. '/tools" -name "*.lua" -not -path "*/moonshine/*"')
    for path in p:lines() do
        local fn, err = loadfile(path)
        if not fn then bad = bad + 1; print("SYNTAX ERROR  " .. tostring(err)) end
    end
    p:close()
    print(bad == 0 and "syntax OK" or (bad .. " file(s) with syntax errors"))
    love.event.quit(bad == 0 and 0 or 1)
end
