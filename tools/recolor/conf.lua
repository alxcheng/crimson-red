-- No window, no audio: this is a command-line tool that only touches image files.
function love.conf(t)
    t.window = false
    t.modules.window, t.modules.graphics, t.modules.audio, t.modules.sound = false, false, false, false
    t.modules.joystick, t.modules.physics, t.modules.video, t.modules.touch = false, false, false, false
end
