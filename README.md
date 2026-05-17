# addonmgr

A control panel for your Ashita addons. One window, two tabs, real loaded-state, dynamic resizing — no more hunting for floating ImGui windows or memorizing every addon's slash command.

Built for [HorizonXI](https://horizonxi.com) on Ashita v4, but works on any Ashita v4 client.

## What it does

Ashita's ImGui ships without docking support, so every addon's UI floats independently. With five or six addons running you end up with a screen full of competing windows. addonmgr is the missing "manager" — a single panel that:

- **Toggles addon windows** by firing each addon's real show/hide slash command
- **Show All / Hide All** mass actions, with per-addon checkbox to exempt addons from the mass toggle (e.g. exempt a heads-up overlay you always want visible)
- **Loads, unloads, and reloads** any installed addon — no typing `/addon load X` over and over
- **Detects loaded state** by parsing `/addon list` output, so the panel reflects reality
- **Auto-resizes** as you switch tabs — never wastes screen space, never clips content

## Install

1. Drop the `addonmgr` folder into your Ashita `addons` directory:
   `Ashita\Game\addons\addonmgr\`
2. Load it: `/addon load addonmgr`
3. Open the panel: `/addonmgr` (or `/amgr`)

## Slash commands

```
/addonmgr            -- toggle the panel
/addonmgr show       -- open the panel
/addonmgr hide       -- close the panel
/addonmgr refresh    -- rescan the addons folder + re-detect loaded state
/addonmgr showall    -- fire show on every managed addon (respects "all" checkbox)
/addonmgr hideall    -- fire hide on every managed addon (respects "all" checkbox)
/addonmgr load X     -- load addon X
/addonmgr unload X   -- unload addon X
/addonmgr reload X   -- reload addon X
```

`/amgr` is an alias for `/addonmgr`.

## The "Windows" tab

Shows a curated list of addons addonmgr knows how to show/hide. Each row has:

- A status indicator (`[on]` / `[off]`) — the last-known visibility, flipped by your button clicks
- The addon label
- An `all` checkbox — uncheck to exempt this addon from Show All / Hide All
- `Show` and `Hide` buttons that fire the addon's real slash command

By default, Prism is exempt from the mass toggle (because it's typically an always-on skill overlay). Change any addon's exemption with the `all` checkbox; the setting is persisted.

### Adding more addons to the Windows tab

The catalog lives near the top of `addonmgr.lua`:

```lua
local MANAGED = {
    { key = 'prism',       label = 'Prism (skill overlay)', cmd = '/prism', show = 'on',   hide = 'off'  },
    { key = 'deathclock',  label = 'Deathclock (respawns)', cmd = '/dc',    show = 'show', hide = 'hide' },
    ...
}
```

Add an entry with the addon's real slash command and its show/hide subcommands. Check the addon's `addon.commands` table and slash-handler code — every addon does this differently (`on`/`off`, `show`/`hide`, `toggle`, etc.).

## The "Load/Unload" tab

Lists every addon folder under `Ashita\Game\addons\`. Each row has `[on]` / `[off]` / `[ ? ]` status and `Load` / `Unload` / `Reload` buttons. Has a text filter at the top.

Loaded state is detected by firing `/addon list` and parsing the chat output (`[Addons] >> name version: ...` lines). Click Refresh to re-detect.

## Why ASCII labels?

The ImGui font bundled with Ashita lacks most Unicode glyphs — your fancy `●` will render as `?`. addonmgr uses ASCII tags (`[on]`, `[off]`, `[ ? ]`) so labels are readable on every install.

## Why not just tabs with each addon's UI inside?

Real docking (host addon UIs inside another addon's tabs) requires the ImGui docking branch. Ashita ships with ImGui master. The honest answer is: not possible without forking every addon to publish a draw callback. addonmgr's approach — own panel, manage other addons via their slash commands — works today.

## License

GPL-3.0. See `LICENSE`.

## Credits

Built by Blake ([TreeFidyDad](https://github.com/TreeFidyDad)) and Watney.
