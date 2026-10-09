function love.conf(t)
    t.window = false
    t.modules.window, t.modules.graphics, t.modules.audio, t.modules.sound = false, false, false, false
end
