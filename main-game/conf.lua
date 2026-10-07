function love.conf(t)
    t.identity        = "crimson-red"
    t.title           = "Crimson Red"
    t.version         = "11.4"
    t.window.title    = "Crimson Red"
    t.window.width    = 800
    t.window.height   = 450
    t.window.resizable = true
    t.window.minwidth  = 400
    t.window.minheight = 225
    -- Headless mode (agent background smoke tests): run offscreen so NO window
    -- ever pops on the Director's screen. Audio module stays on (offscreen
    -- LÖVE creates a silent dummy device). Visible default is untouched —
    -- none of these lines apply unless CR_HEADLESS=1 is set.
    if os.getenv("CR_HEADLESS") == "1" then
        t.window.offscreen = true
        t.modules.audio = true        -- keep audio module (dummy device, silent)
    end
end
