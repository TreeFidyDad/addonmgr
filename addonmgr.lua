addon.name      = 'addonmgr'
addon.author    = 'Blake & Watney'
addon.version   = '0.2.4'
addon.desc      = 'Addon Manager — toggle, load, unload, and reload Ashita addons from a single ImGui panel.'
addon.commands  = { '/addonmgr', '/amgr' }

require('common')
local chat     = require('chat')
local settings = require('settings')
local imgui    = require('imgui')

----------------------------------------------------------------
-- Config
----------------------------------------------------------------
local default_config = T{
    visible = false,
    -- Addons that should be SKIPPED by Show All / Hide All / showall /
    -- hideall. Defaults Prism to excluded since it's the always-on skill
    -- overlay — a "hide everything" hotkey shouldn't kill it.
    exclude_from_all = T{ prism = true },
}
local config = settings.load(default_config)
local function save() settings.save() end

settings.register('settings', 'settings_update', function(s)
    if s ~= nil then config = s end
    save()
end)

----------------------------------------------------------------
-- Managed-addons catalog
----------------------------------------------------------------
-- Hand-curated list of addons we know how to show/hide. Anything not
-- listed here only gets load/unload/reload (see the second tab) — we
-- can't toggle visibility without knowing the slash command. Add more
-- entries as new addons learn show/hide.
local MANAGED = {
    { key = 'prism',       label = 'Prism (skill overlay)', cmd = '/prism', show = 'on',   hide = 'off'  },
    { key = 'deathclock',  label = 'Deathclock (respawns)', cmd = '/dc',    show = 'show', hide = 'hide' },
    { key = 'huntpartner', label = 'Hunt Partner',          cmd = '/hp',    show = 'show', hide = 'hide' },
    { key = 'rdmpartner',  label = 'rdmpartner (RDM spells)', cmd = '/rdmp', show = 'show', hide = 'hide' },
    { key = 'wayfinder',   label = 'wayfinder',             cmd = '/wf',    show = 'show', hide = 'hide' },
}

-- Per-session visibility guess. Starts at the saved value, flips on
-- button click. Not authoritative (user can run the slash command
-- outside our UI) but good enough to render an indicator.
local managed_visible = {}
for _, m in ipairs(MANAGED) do managed_visible[m.key] = true end

----------------------------------------------------------------
-- Helpers
----------------------------------------------------------------
local function say(msg)
    print(chat.header(addon.name) .. chat.message(msg))
end

local function queue_command(cmd)
    AshitaCore:GetChatManager():QueueCommand(1, cmd)
end

----------------------------------------------------------------
-- Addon discovery
----------------------------------------------------------------
-- Ashita resolves addons by looking for "<name>/<name>.lua" under
-- the Ashita install's addons/ directory.
local function get_addons_root()
    local install = AshitaCore and AshitaCore:GetInstallPath() or ''
    if install ~= '' then
        return install .. 'addons\\'
    end
    return 'addons\\'
end

-- Check a file exists by trying to open it for read. Lua has no native
-- "does this path exist" primitive but io.open returns nil for missing.
local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function list_available_addons()
    local root = get_addons_root()
    local out  = T{}
    -- /b = bare names, /ad = directories only. Quotes guard against spaces.
    local cmd = 'dir /b /ad "' .. root .. '" 2>nul'
    local p = io.popen(cmd, 'r')
    if not p then return out end
    for line in p:lines() do
        local name = line:gsub('[\r\n]+$', '')
        if name ~= '' and file_exists(root .. name .. '\\' .. name .. '.lua') then
            out:append(name)
        end
    end
    p:close()
    table.sort(out)
    return out
end

----------------------------------------------------------------
-- State tracking (per-session, best-effort)
----------------------------------------------------------------
local STATE_UNKNOWN  = 0
local STATE_LOADED   = 1
local STATE_UNLOADED = 2

local addon_state = T{}
local available   = T{}
local filter_text = { '' }

-- When we fire `/addon list`, Ashita prints loaded addon names to chat.
-- We enter a brief "scan window" during which sniff_chat() will flip any
-- line containing a known addon name to LOADED. Anything not seen during
-- the window stays UNLOADED.
local scan_until = 0
local SCAN_DURATION = 3  -- seconds

local function refresh_list()
    available = list_available_addons()
    -- Default state UNKNOWN. We'll populate via /addon list parsing
    -- below; anything not seen in a scan window stays unknown rather
    -- than being falsely marked unloaded.
    for _, n in ipairs(available) do
        if addon_state[n] == nil then
            addon_state[n] = STATE_UNKNOWN
        end
    end
    addon_state['addonmgr'] = STATE_LOADED
end

local function rescan_loaded()
    -- Ashita's /addon list prints lines like:
    --   [Addons]    >> huntpartner version: 0.8.8 - by: ...
    -- These DO reach text_in (verified). sniff_chat parses them and
    -- flips state to LOADED. We reset all-knowns to UNLOADED first so
    -- anything we previously saw but isn't in the new listing flips
    -- back. UNKNOWNs stay unknown until they appear at least once.
    for k, v in pairs(addon_state) do
        if v == STATE_LOADED then addon_state[k] = STATE_UNLOADED end
    end
    addon_state['addonmgr'] = STATE_LOADED
    queue_command('/addon list')
end

local function state_label(s)
    if s == STATE_LOADED   then return 'loaded'   end
    if s == STATE_UNLOADED then return 'unloaded' end
    return '?'
end

local function state_color(s)
    if s == STATE_LOADED   then return { 0.50, 0.95, 0.55, 1.0 } end
    if s == STATE_UNLOADED then return { 0.85, 0.45, 0.45, 1.0 } end
    return { 0.65, 0.65, 0.70, 1.0 }
end

----------------------------------------------------------------
-- Actions
----------------------------------------------------------------
local function do_load(name)
    queue_command('/addon load ' .. name)
    addon_state[name] = STATE_LOADED
end

local function do_unload(name)
    queue_command('/addon unload ' .. name)
    addon_state[name] = STATE_UNLOADED
end

local function do_reload(name)
    queue_command('/addon reload ' .. name)
    addon_state[name] = STATE_LOADED
end

----------------------------------------------------------------
-- UI
----------------------------------------------------------------
local visible_ref = { false }

local function do_show(m)
    queue_command(m.cmd .. ' ' .. m.show)
    managed_visible[m.key] = true
end

local function do_hide(m)
    queue_command(m.cmd .. ' ' .. m.hide)
    managed_visible[m.key] = false
end

local function draw_windows_tab()
    imgui.TextDisabled('Toggle the windows of addons you control.')
    imgui.Spacing()

    if imgui.Button('Show All##amgr_showall') then
        for _, m in ipairs(MANAGED) do
            if not config.exclude_from_all[m.key] then do_show(m) end
        end
    end
    imgui.SameLine()
    if imgui.Button('Hide All##amgr_hideall') then
        for _, m in ipairs(MANAGED) do
            if not config.exclude_from_all[m.key] then do_hide(m) end
        end
    end
    imgui.SameLine()
    imgui.TextDisabled('  (uncheck "all" to exempt an addon)')

    imgui.Separator()

    for _, m in ipairs(MANAGED) do
        local vis = managed_visible[m.key]
        if vis then
            imgui.TextColored({ 0.50, 0.95, 0.55, 1.0 }, '[on] ')
        else
            imgui.TextColored({ 0.55, 0.55, 0.60, 1.0 }, '[off]')
        end
        imgui.SameLine()
        imgui.Text(m.label)

        -- "all" checkbox: include this addon in Show All / Hide All.
        -- Persisted in config so the exemption survives reloads.
        imgui.SameLine(230)
        local include_ref = { not config.exclude_from_all[m.key] }
        if imgui.Checkbox('all##amgr_all_' .. m.key, include_ref) then
            if include_ref[1] then
                config.exclude_from_all[m.key] = nil
            else
                config.exclude_from_all[m.key] = true
            end
            save()
        end

        imgui.SameLine(290)
        if imgui.SmallButton('Show##amgr_s_' .. m.key) then do_show(m) end
        imgui.SameLine()
        if imgui.SmallButton('Hide##amgr_h_' .. m.key) then do_hide(m) end
    end
end

local function draw_loader_tab()
    imgui.PushItemWidth(-90)
    imgui.InputText('##amgr_filter', filter_text, 64)
    imgui.PopItemWidth()
    imgui.SameLine()
    if imgui.Button('Refresh##amgr_refresh') then
        refresh_list()
        rescan_loaded()
    end

    imgui.Separator()

    local needle = (filter_text[1] or ''):lower()

    for _, name in ipairs(available) do
        if needle == '' or name:lower():find(needle, 1, true) then
            local s = addon_state[name] or STATE_UNKNOWN
            local tag, color
            if s == STATE_LOADED then
                tag, color = '[on] ', { 0.50, 0.95, 0.55, 1.0 }
            elseif s == STATE_UNLOADED then
                tag, color = '[off]', { 0.85, 0.45, 0.45, 1.0 }
            else
                tag, color = '[ ? ]', { 0.65, 0.65, 0.70, 1.0 }
            end
            imgui.TextColored(color, tag)
            imgui.SameLine()
            imgui.Text(name)

            imgui.SameLine(220)
            if imgui.SmallButton('Load##amgr_l_' .. name)   then do_load(name)   end
            imgui.SameLine()
            if imgui.SmallButton('Unload##amgr_u_' .. name) then do_unload(name) end
            imgui.SameLine()
            if imgui.SmallButton('Reload##amgr_r_' .. name) then do_reload(name) end
        end
    end

    imgui.Separator()
    imgui.TextDisabled(('%d addons found'):format(#available))
end

local function draw()
    if not config.visible then return end
    visible_ref[1] = config.visible

    -- AlwaysAutoResize (64) so the window shrink-wraps the active tab.
    -- Cap min/max so a 50-addon load list can't fill the screen, and a
    -- 5-row Windows tab doesn't render as a postage stamp.
    imgui.SetNextWindowSizeConstraints({ 380, 120 }, { 520, 680 })
    if imgui.Begin('Addon Manager##addonmgr', visible_ref, 64) then
        if visible_ref[1] ~= config.visible then
            config.visible = visible_ref[1]; save()
        end

        if imgui.BeginTabBar('##amgr_tabs') then
            if imgui.BeginTabItem('Windows') then
                draw_windows_tab()
                imgui.EndTabItem()
            end
            if imgui.BeginTabItem('Load/Unload') then
                draw_loader_tab()
                imgui.EndTabItem()
            end
            imgui.EndTabBar()
        end
    end
    imgui.End()

    if visible_ref[1] ~= config.visible then
        config.visible = visible_ref[1]; save()
    end
end

----------------------------------------------------------------
-- Chat sniffing: catch addon load/unload echoes and /addon list output.
----------------------------------------------------------------
local function sniff_chat(message)
    local plain = message:gsub('\30.', ''):gsub('\31.', '')

    -- `/addon list` output: "[Addons]    >> NAME version: V - by: ..."
    -- The name field is whatever folder-name the addon was loaded by,
    -- which may differ in case from our folder enumeration (e.g.
    -- "HXUI", "LuAshitacast", "Timers"). Lowercase both sides.
    local nm = plain:match("%[Addons%]%s*>>%s*([%w_%-]+)%s+version:")
    if nm then
        addon_state[nm:lower()] = STATE_LOADED
        return
    end

    -- Per-action echoes from /addon load/unload, just in case Ashita
    -- emits them in chat. Harmless if it doesn't.
    local m = plain:match("[Aa]ddon%s+'?([%w_%-]+)'?%s+loaded")
    if m then addon_state[m:lower()] = STATE_LOADED; return end
    m = plain:match("[Aa]ddon%s+'?([%w_%-]+)'?%s+unloaded")
    if m then addon_state[m:lower()] = STATE_UNLOADED; return end
end

----------------------------------------------------------------
-- Event wiring
----------------------------------------------------------------
ashita.events.register('load', 'amgr_load', function()
    refresh_list()
    rescan_loaded()
end)

ashita.events.register('d3d_present', 'amgr_present', function()
    draw()
end)

ashita.events.register('text_in', 'amgr_text_in', function(e)
    if e and e.message then
        sniff_chat(e.message)
    end
end)

ashita.events.register('command', 'amgr_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/addonmgr' and cmd ~= '/amgr' then return end
    e.blocked = true

    local sub = args[2] and args[2]:lower() or 'toggle'
    if sub == 'toggle' or sub == 'show' or sub == 'hide' then
        if sub == 'show' then
            config.visible = true
        elseif sub == 'hide' then
            config.visible = false
        else
            config.visible = not config.visible
        end
        save()
        say('window ' .. (config.visible and 'OPEN' or 'closed'))
    elseif sub == 'refresh' then
        refresh_list()
        rescan_loaded()
        say(('refresh: %d addons found, rescanning loaded state...'):format(#available))
    elseif sub == 'hideall' then
        local n = 0
        for _, m in ipairs(MANAGED) do
            if not config.exclude_from_all[m.key] then do_hide(m); n = n + 1 end
        end
        say(('hide all: fired hide on %d addons'):format(n))
    elseif sub == 'showall' then
        local n = 0
        for _, m in ipairs(MANAGED) do
            if not config.exclude_from_all[m.key] then do_show(m); n = n + 1 end
        end
        say(('show all: fired show on %d addons'):format(n))
    elseif sub == 'load' and args[3] then
        do_load(args[3]:lower())
    elseif sub == 'unload' and args[3] then
        do_unload(args[3]:lower())
    elseif sub == 'reload' and args[3] then
        do_reload(args[3]:lower())
    else
        say('usage:')
        say('  /addonmgr               -- toggle the panel')
        say('  /addonmgr show|hide     -- explicit')
        say('  /addonmgr hideall       -- hide all managed addon windows')
        say('  /addonmgr showall       -- show all managed addon windows')
        say('  /addonmgr refresh       -- rescan the addons folder')
        say('  /addonmgr load <name>   -- proxy /addon load')
        say('  /addonmgr unload <name> -- proxy /addon unload')
        say('  /addonmgr reload <name> -- proxy /addon reload')
    end
end)
