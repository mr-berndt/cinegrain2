-- cinegrain2-control.lua - live control for the cinegrain2 film grain shader
--
-- A five-zone graphic equalizer over luma (Black / Shadow / Mid / High /
-- White) plus Level, Size and Soft, shown as a one-row overlay on the
-- picture. Values go to the shader through glsl-shader-opts, so nothing is
-- recompiled and every change is instant.
--
-- Keys:
--   Alt+q                 grain on / off
--   Alt+Left / Alt+Right  select a control
--   Alt+Up   / Alt+Down   change the selected control
--   Alt+,    / Alt+.      previous / next preset
--   Alt+d                 test picture: off -> 50 % grey card -> grey staircase
--
-- Options (script-opts/cinegrain2-control.conf, or
-- --script-opts=cinegrain2-control-<name>=<value>):
--   sidecars=yes     store and load per-film / per-series .grain files
--   osd_timeout=8    seconds the overlay stays after the last key press
--
-- The shader is found in glsl-shaders by its file name: anything starting
-- with "cinegrain2" and ending in ".glsl".

local mp      = require 'mp'
local msg     = require 'mp.msg'
local options = require 'mp.options'

local opts = {
    sidecars    = true,
    osd_timeout = 8,
}
options.read_options(opts, "cinegrain2-control")

-- ─── Shader lookup ───────────────────────────────────────────────────────────
-- glsl-shader-opts are scoped by the shader's file name without extension,
-- so the name has to come from whatever the user actually loaded.
local shader_path = nil      -- entry as it stands in glsl-shaders
local shader_name = nil      -- file name without ".glsl"

local function basename(p)
    return (p:match("([^/\\]+)$") or p)
end

local function find_shader()
    for _, s in ipairs(mp.get_property_native("glsl-shaders", {}) or {}) do
        local b = basename(s)
        if b:lower():match("^cinegrain2.*%.glsl$") then
            shader_path = s
            shader_name = b:gsub("%.[Gg][Ll][Ss][Ll]$", "")
            return true
        end
    end
    return false
end

-- ─── Equalizer zones (must match luma_weight() in the shader) ───────────────
-- Black 0.00, Shadow 0.13, Mid 0.30, High 0.60, White 1.00, smoothstep
-- between neighbours. Zone value 0 = flat, -1 = no grain, +3 = four times.

-- ─── Presets ─────────────────────────────────────────────────────────────────
local presets = {
    { name = "flat",      LEVEL = 0.200, GRAIN_SIZE = 0.40, SOFTBLUR = 0.0, B1 =  0.00, B2 =  0.00, B3 =  0.00, B4 =  0.00, B5 =  0.00 },
    { name = "35mm std",  LEVEL = 0.114, GRAIN_SIZE = 0.40, SOFTBLUR = 0.0, B1 = -0.81, B2 = -0.26, B3 =  0.00, B4 = -0.76, B5 = -1.00 },
    { name = "35mm high", LEVEL = 0.075, GRAIN_SIZE = 0.75, SOFTBLUR = 0.0, B1 = -0.90, B2 = -0.59, B3 = -0.04, B4 =  0.00, B5 = -0.95 },
    { name = "16mm std",  LEVEL = 0.102, GRAIN_SIZE = 1.25, SOFTBLUR = 0.0, B1 = -0.78, B2 = -0.34, B3 =  0.00, B4 = -0.58, B5 = -1.00 },
    { name = "16mm low",  LEVEL = 0.106, GRAIN_SIZE = 1.50, SOFTBLUR = 0.0, B1 =  0.00, B2 = -0.01, B3 = -0.12, B4 = -0.82, B5 = -1.00 },
    { name = "Aliens",    LEVEL = 0.240, GRAIN_SIZE = 0.50, SOFTBLUR = 0.8, B1 =  3.00, B2 =  0.90, B3 = -0.15, B4 = -0.45, B5 = -0.95 },
}

-- ─── Menu ────────────────────────────────────────────────────────────────────
local MENU = {
    { key = "LEVEL",      label = "Level",  fmt = "%.3f",  step = 0.01 },
    { key = "GRAIN_SIZE", label = "Size",   fmt = "%.2f",  step = 0.05 },
    { key = "SOFTBLUR",   label = "Soft",   fmt = "%.2f",  step = 0.10 },
    { key = "B1",         label = "Black",  fmt = "%+.2f", step = 0.05 },
    { key = "B2",         label = "Shadow", fmt = "%+.2f", step = 0.05 },
    { key = "B3",         label = "Mid",    fmt = "%+.2f", step = 0.05 },
    { key = "B4",         label = "High",   fmt = "%+.2f", step = 0.05 },
    { key = "B5",         label = "White",  fmt = "%+.2f", step = 0.05 },
}

local limits = {
    LEVEL      = { 0.0, 5.0 },
    GRAIN_SIZE = { 0.0, 3.0 },
    SOFTBLUR   = { 0.0, 10.0 },
    B1 = { -3.0, 3.0 }, B2 = { -3.0, 3.0 }, B3 = { -3.0, 3.0 },
    B4 = { -3.0, 3.0 }, B5 = { -3.0, 3.0 },
}

-- Shader parameter behind each control.
local SHADER_KEY = {
    LEVEL = "LEVEL", GRAIN_SIZE = "GRAIN_SIZE", SOFTBLUR = "SOFTBLUR",
    B1 = "GAIN_1", B2 = "GAIN_2", B3 = "GAIN_3", B4 = "GAIN_4", B5 = "GAIN_5",
}
local CHROMA = "0.1000"

-- ─── State ───────────────────────────────────────────────────────────────────
local params = {}
local preset_index = 1
local preset_name = nil       -- nil = custom
local active_idx = 1
local grain_enabled = true
local demo_state = 0

local function state_file(name)
    return mp.command_native({ "expand-path", "~~/" .. name })
end
local VALUE_FILE  = state_file("cinegrain2-values")
local PRESET_FILE = state_file("cinegrain2-preset")

local function clamp(k, v)
    local l = limits[k]
    return math.max(l[1], math.min(l[2], v))
end

local function load_preset_values(idx)
    local p = presets[idx]
    for _, m in ipairs(MENU) do params[m.key] = p[m.key] end
    preset_index, preset_name = idx, p.name
end

-- ─── Push to the shader ──────────────────────────────────────────────────────
-- Merge into glsl-shader-opts instead of replacing it: other scripts may keep
-- their own shader options there.
local function set_shader_opts(values)
    if not shader_name then return end
    local cur = mp.get_property_native("glsl-shader-opts", {}) or {}
    for k, v in pairs(values) do cur[shader_name .. "/" .. k] = v end
    local out = {}
    for k, v in pairs(cur) do out[#out + 1] = k .. "=" .. v end
    mp.set_property("glsl-shader-opts", table.concat(out, ","))
end

local function push_opts()
    local v = { CHROMA = CHROMA }
    for _, m in ipairs(MENU) do
        v[SHADER_KEY[m.key]] = string.format("%.4f", params[m.key])
    end
    set_shader_opts(v)
end

-- ─── Overlay ─────────────────────────────────────────────────────────────────
-- Every cell is placed on its own, so the columns line up with any font -
-- no monospace font needed.
local overlay = mp.create_osd_overlay("ass-events")
local osd_timer = nil

local function hide_overlay()
    overlay.data = ""; overlay:update()
    if osd_timer then osd_timer:kill(); osd_timer = nil end
end

local function ass_escape(s)
    return (s:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"))
end

local function osd_update()
    local dims = mp.get_property_native("osd-dimensions") or {}
    local w, h = dims.w or 1920, dims.h or 1080
    if w <= 0 or h <= 0 then return end
    overlay.res_x, overlay.res_y = w, h

    local fs  = math.max(16, math.floor(h / 40))
    local x0  = math.floor((dims.ml or 0) + fs * 1.5)
    local y0  = math.floor((dims.mt or 0) + fs * 3)
    local col = math.floor(fs * 4.2)
    local style = "{\\an7\\bord2\\shad0\\3c&H000000&\\fs" .. fs .. "}"
    local yellow, green = "{\\c&H00FFFF&}", "{\\c&H00FF00&}"

    local ev = {}
    local function put(x, y, color, text)
        ev[#ev + 1] = string.format("{\\pos(%d,%d)}%s%s%s", x, y, style, color,
                                    ass_escape(text))
    end

    if not shader_name then
        put(x0, y0, yellow, "cinegrain2: shader not found in glsl-shaders")
    elseif not grain_enabled then
        put(x0, y0, yellow, "cinegrain2: off")
    else
        put(x0, y0, yellow, "cinegrain2 [" .. (preset_name or "custom") .. "]")
        for i, m in ipairs(MENU) do
            local c = (i == active_idx) and green or yellow
            local x = x0 + (i - 1) * col
            put(x, y0 + math.floor(fs * 1.3), c, (i == active_idx and "> " or "") .. m.label)
            put(x, y0 + math.floor(fs * 2.6), c, string.format(m.fmt, params[m.key]))
        end
    end

    overlay.data = table.concat(ev, "\n")
    overlay:update()
    if osd_timer then osd_timer:kill() end
    osd_timer = mp.add_timeout(opts.osd_timeout, hide_overlay)
end

-- ─── Persistence ─────────────────────────────────────────────────────────────
local function save_global()
    local f = io.open(VALUE_FILE, "w")
    if f then
        for _, m in ipairs(MENU) do
            f:write(string.format("%s=%.4f\n", m.key, params[m.key]))
        end
        f:close()
    end
    f = io.open(PRESET_FILE, "w")
    if f then f:write(preset_name and tostring(preset_index) or "custom"); f:close() end
end

-- Read KEY=value lines into params. Returns true if anything was taken.
local function read_values(lines)
    local got = false
    for _, line in ipairs(lines) do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(%-?[%d%.]+)%s*$")
        v = tonumber(v)
        if k and v and limits[k] then params[k] = clamp(k, v); got = true end
    end
    return got
end

local function read_lines(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local t = {}
    for line in f:lines() do t[#t + 1] = line end
    f:close()
    return t
end

-- The values that apply when a file has no sidecar: the last ones set.
local function load_global()
    load_preset_values(1)
    local p = read_lines(PRESET_FILE)
    local idx = p and tonumber(p[1])
    if idx and presets[idx] then load_preset_values(idx) end
    local v = read_lines(VALUE_FILE)
    if v and read_values(v) and not idx then preset_name = nil end
end

-- ─── Sidecars (.grain next to the video) ────────────────────────────────────
--   film:    <file name>.grain
--   series:  "<series> S01.grain" (by hand, per season) or "<series>.grain"
-- Only for local files. A sidecar is only written when the grain was changed
-- while the file was playing, so no .grain files appear next to videos that
-- were merely watched.
local current_path = nil
local changed = false

local function is_local(p)
    return p and p ~= "" and not p:match("^%a[%w+.-]*://")
end

local function split_path(p)
    local dir, file = p:match("^(.*[/\\])([^/\\]*)$")
    return dir or "", file or p
end

local function parse_series(filename)
    local prefix, season = filename:match("^(.-)[ ._%-]+[Ss](%d%d?)[Ee]%d%d?")
    if not prefix or prefix == "" then return nil end
    return prefix:gsub("[%s%-%._]+$", ""), tonumber(season)
end

local function sidecar_candidates(p)
    local dir, file = split_path(p)
    local series, season = parse_series(file)
    if series then
        return { dir .. string.format("%s S%02d.grain", series, season),
                 dir .. series .. ".grain" }, dir .. series .. ".grain"
    end
    local g = p:gsub("%.[%w]+$", "") .. ".grain"
    return { g }, g
end

local function load_sidecar(p)
    local cands = sidecar_candidates(p)
    for _, g in ipairs(cands) do
        local lines = read_lines(g)
        if lines then
            local pname = (lines[1] or ""):match("^preset=(.+)$")
            if pname then
                for i, pr in ipairs(presets) do
                    if pr.name == pname then load_preset_values(i); break end
                end
            elseif read_values(lines) then
                preset_name = nil
            end
            msg.info("sidecar loaded: " .. g)
            return
        end
    end
end

local function write_sidecar(p)
    local _, target = sidecar_candidates(p)
    local f, err = io.open(target, "w")
    if not f then
        msg.warn("could not write sidecar " .. target .. ": " .. tostring(err))
        return
    end
    if preset_name then
        f:write("preset=" .. preset_name .. "\n")
    else
        f:write("custom\n")
        for _, m in ipairs(MENU) do
            f:write(string.format("%s=%.4f\n", m.key, params[m.key]))
        end
    end
    f:close()
    msg.info("sidecar written: " .. target)
end

-- ─── Actions ─────────────────────────────────────────────────────────────────
local function touched()
    changed = true
    save_global()
    push_opts()
    osd_update()
end

local function cycle_preset(dir)
    load_preset_values(((preset_index - 1 + dir) % #presets) + 1)
    touched()
end

local function adjust(dir)
    local m = MENU[active_idx]
    params[m.key] = clamp(m.key, params[m.key] + dir * m.step)
    preset_name = nil
    touched()
end

local function nav(dir)
    active_idx = ((active_idx - 1 + dir) % #MENU) + 1
    osd_update()
end

local function toggle()
    if not shader_name and not find_shader() then osd_update(); return end
    local list = mp.get_property_native("glsl-shaders", {}) or {}
    if grain_enabled then
        local keep = {}
        for _, s in ipairs(list) do
            if s ~= shader_path then keep[#keep + 1] = s end
        end
        mp.set_property_native("glsl-shaders", keep)
        grain_enabled = false
    else
        list[#list + 1] = shader_path
        mp.set_property_native("glsl-shaders", list)
        grain_enabled = true
        push_opts()
    end
    osd_update()
end

local DEMO_VALUES = { "0.0000", "0.5000", "1.0000" }
local DEMO_LABELS = { "test picture off", "grey card 50 %", "grey staircase" }
local function toggle_demo()
    if not shader_name then osd_update(); return end
    demo_state = (demo_state + 1) % 3
    set_shader_opts({ DEMO = DEMO_VALUES[demo_state + 1] })
    mp.osd_message("cinegrain2: " .. DEMO_LABELS[demo_state + 1], 2)
end

-- ─── Events ──────────────────────────────────────────────────────────────────
mp.register_event("file-loaded", function()
    if not shader_name then find_shader() end
    current_path = mp.get_property("path")
    changed = false
    load_global()
    if opts.sidecars and is_local(current_path) then load_sidecar(current_path) end
    push_opts()
end)

local function leave_file()
    if opts.sidecars and changed and is_local(current_path) then
        write_sidecar(current_path)
    end
    changed = false
    current_path = nil
end
mp.register_event("end-file", leave_file)
mp.register_event("shutdown", leave_file)

-- The shader list can change at runtime (other scripts, the console).
mp.observe_property("glsl-shaders", "native", function(_, list)
    if grain_enabled then
        local was = shader_name
        shader_path, shader_name = nil, nil
        if find_shader() and shader_name ~= was then push_opts() end
    end
end)

-- ─── Key bindings ────────────────────────────────────────────────────────────
local rep = { repeatable = true }
mp.add_key_binding("Alt+q", "toggle",      toggle)
mp.add_key_binding("Alt+d", "demo",        toggle_demo)
mp.add_key_binding("Alt+,", "preset-prev", function() cycle_preset(-1) end)
mp.add_key_binding("Alt+.", "preset-next", function() cycle_preset( 1) end)
-- Forced: mpv binds Alt+arrows to video panning by default.
mp.add_forced_key_binding("Alt+LEFT",  "prev", function() nav(-1) end, rep)
mp.add_forced_key_binding("Alt+RIGHT", "next", function() nav( 1) end, rep)
mp.add_forced_key_binding("Alt+UP",    "up",   function() adjust( 1) end, rep)
mp.add_forced_key_binding("Alt+DOWN",  "down", function() adjust(-1) end, rep)

find_shader()
load_global()
