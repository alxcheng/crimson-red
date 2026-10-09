-- tools/recolor — make a recoloured copy of a sprite folder by shifting ONE
-- colour (e.g. the Knight's blue clothes) and leaving every other pixel alone.
--
-- Use ./recolor from the repo root (it runs this with LÖVE):
--
--   ./recolor report <srcDir>
--       Prints which hues the sprites contain, so you can see what to target.
--
--   ./recolor shift <srcDir> <dstDir> <fromHue> <toHue> [tolerance] [satScale] [valScale]
--       Copies every .png of srcDir to dstDir. Pixels whose hue is within
--       `tolerance` degrees (default 30) of fromHue are moved to toHue; their
--       shading (how light/dark and how vivid each pixel is) is kept, so folds
--       and highlights survive. satScale / valScale (default 1) make the new
--       colour more/less vivid or lighter/darker (use satScale 0 for grey/white).
--
-- Hues are degrees on the colour wheel:
--   0 red, 30 orange, 60 yellow, 120 green, 180 cyan, 240 blue, 280 purple, 320 pink.
-- Grey / near-black / near-white pixels (skin shadows, steel, outlines) have no
-- real hue and are never touched (saturation < MIN_SAT or value < MIN_VAL).
--
-- Paths are relative to the repo root. Example (what made the Paladin):
--   ./recolor shift main-game/assets/characters/Knight main-game/assets/characters/Paladin 215 50

local MIN_SAT, MIN_VAL = 0.18, 0.12

local function rgb2hsv(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h * 60
    end
    return h, (mx > 0) and d / mx or 0, mx
end

local function hsv2rgb(h, s, v)
    local c = v * s
    local hp = (h % 360) / 60
    local x = c * (1 - math.abs(hp % 2 - 1))
    local r, g, b = 0, 0, 0
    if hp < 1 then r, g = c, x elseif hp < 2 then r, g = x, c
    elseif hp < 3 then g, b = c, x elseif hp < 4 then g, b = x, c
    elseif hp < 5 then r, b = x, c else r, b = c, x end
    local m = v - c
    return r + m, g + m, b + m
end

local function hueDistance(a, b)
    local d = math.abs(a - b) % 360
    return (d > 180) and 360 - d or d
end

-- Plain file access (LÖVE's own filesystem cannot reach the project folders).
local function readImage(path)
    local f = assert(io.open(path, "rb"), "cannot read " .. path)
    local bytes = f:read("*a"); f:close()
    return love.image.newImageData(love.filesystem.newFileData(bytes, path))
end

local function writeImage(img, path)
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(img:encode("png"):getString()); f:close()
end

local function listPngs(dir)
    local out = {}
    local p = io.popen('ls "' .. dir .. '"')
    for name in p:lines() do
        if name:lower():match("%.png$") then out[#out + 1] = name end
    end
    p:close()
    return out
end

local function report(src)
    local buckets, total = {}, 0
    for _, name in ipairs(listPngs(src)) do
        readImage(src .. "/" .. name):mapPixel(function(_, _, r, g, b, a)
            if a > 0.5 then
                local h, s, v = rgb2hsv(r, g, b)
                if s >= MIN_SAT and v >= MIN_VAL then
                    local k = math.floor(h / 10) * 10
                    buckets[k] = (buckets[k] or 0) + 1
                    total = total + 1
                end
            end
            return r, g, b, a
        end)
    end
    print(("Coloured pixels in %s by hue (10-degree steps):"):format(src))
    for k = 0, 350, 10 do
        local n = buckets[k] or 0
        if n / math.max(1, total) >= 0.005 then
            print(("  %3d-%3d  %5.1f%%  %s"):format(k, k + 10, 100 * n / total, string.rep("#", math.floor(60 * n / total + 0.5))))
        end
    end
end

local function shift(src, dst, fromHue, toHue, tol, satScale, valScale)
    os.execute('mkdir -p "' .. dst .. '"')
    local changed, files = 0, 0
    for _, name in ipairs(listPngs(src)) do
        local img = readImage(src .. "/" .. name)
        img:mapPixel(function(_, _, r, g, b, a)
            if a > 0 then
                local h, s, v = rgb2hsv(r, g, b)
                if s >= MIN_SAT and v >= MIN_VAL and hueDistance(h, fromHue) <= tol then
                    -- Keep the pixel's own offset from the source hue so gradients survive.
                    local nr, ng, nb = hsv2rgb(toHue + (h - fromHue), math.min(1, s * satScale), math.min(1, v * valScale))
                    changed = changed + 1
                    return nr, ng, nb, a
                end
            end
            return r, g, b, a
        end)
        writeImage(img, dst .. "/" .. name)
        files = files + 1
    end
    print(("wrote %d files to %s (%d pixels recoloured: hue %g -> %g, tolerance %g)"):format(files, dst, changed, fromHue, toHue, tol))
end

function love.load(args)
    local root = args[1]            -- the wrapper passes the repo root first
    local function path(p) return (p:sub(1, 1) == "/") and p or (root .. "/" .. p) end
    local cmd = args[2]
    local ok, err = pcall(function()
        if cmd == "report" and args[3] then
            report(path(args[3]))
        elseif cmd == "shift" and args[6] then
            shift(path(args[3]), path(args[4]), tonumber(args[5]), tonumber(args[6]),
                  tonumber(args[7]) or 30, tonumber(args[8]) or 1, tonumber(args[9]) or 1)
        else
            print("usage: ./recolor report <srcDir>")
            print("       ./recolor shift <srcDir> <dstDir> <fromHue> <toHue> [tolerance] [satScale] [valScale]")
        end
    end)
    if not ok then print("recolor: " .. tostring(err)) end
    love.event.quit(ok and 0 or 1)
end
