# Standalone hosted DUI bridge

`hxx_dui.lua` loads the existing hosted React UI from:

`https://themiga.github.io/erp_adminmenu/`

It is intended for an authorized client-side runtime that exposes the standard FiveM DUI/NUI functions confirmed by the capability scanner.

## Controls

- `F5`: open/close the DUI
- `ESC`: close while open
- `F6`: unload and destroy the DUI
- `/hxxdui`: toggle
- `/hxxduiunload`: unload

## What it does

- creates a DUI for the GitHub Pages frontend
- creates a runtime texture from the DUI handle
- renders the hosted UI with `DrawSprite`
- forwards mouse movement, clicks and wheel input
- sends `bridgeReady` and `setVisible` messages to React
- registers callbacks for `close`, `unload`, `getPlayerInfo` and `getVehicleInfo`
- releases focus and destroys the DUI on unload/resource stop

## External DUI callback note

Lua -> React is handled directly with `SendDuiMessage` and is reliable when the DUI is available.

React -> Lua uses the FiveM NUI callback endpoint format `https://<resourceName>/<event>`. Because the page is hosted on GitHub Pages rather than under the resource's normal NUI origin, behavior can depend on the CEF/runtime's callback and CORS handling. The React transport helper therefore:

- stores the temporary resource name received in `bridgeReady`
- uses timeouts
- catches HTTP/CORS errors
- does not leave rejected promises unhandled
- keeps browser development mode working with harmless mocks

If the runtime blocks cross-origin NUI callbacks from an external DUI page, rendering and Lua -> React messages still work; React -> Lua actions will return a controlled `{ ok: false, error: ... }` response until a supported callback transport is available.

## No manifest required inside this file

Do not prepend `fx_version`, `game`, `ui_page` or other manifest directives to `hxx_dui.lua`. It is plain client-side Lua.
