# Codex Task — standalone DUI bridge for hosted FiveM UI

## Goal

Adapt this fork so the existing React/Material UI frontend can be used from a **single client-side Lua script** executed by an authorized server-side feature that creates a temporary client runtime similar to a FiveM resource.

Do **not** redesign or replace the UI. Keep the existing React + Material UI frontend and current look as the base.

Hosted frontend:

`https://themiga.github.io/erp_adminmenu/`

## Confirmed runtime capabilities

The client runtime exposes these globals/functions:

- `CreateDui`
- `GetDuiHandle`
- `SetDuiUrl`
- `DestroyDui`
- `SendDuiMessage`
- `SendDuiMouseMove`
- `SendDuiMouseDown`
- `SendDuiMouseUp`
- `SendDuiMouseWheel`
- `CreateRuntimeTxd`
- `CreateRuntimeTextureFromDuiHandle`
- `CreateRuntimeTexture`
- `DrawSprite`
- `SetNuiFocus`
- `SetNuiFocusKeepInput`
- `SetNuiZindex`
- `SendNUIMessage`
- `RegisterNUICallback`
- `RegisterNuiCallbackType`
- `CreateThread`
- `Wait`
- `RegisterCommand`
- `RegisterKeyMapping`
- `GetCurrentResourceName`
- `GetInvokingResource`
- `GetResourceState`
- `GetNumResources`
- `GetResourceByFindIndex`
- `LoadResourceFile`
- `Citizen.InvokeNative`
- `json`
- `msgpack`

`GetCurrentResourceName()` returns a random temporary resource-like name per execution.

Not available/preloaded:

- `ox_lib`
- `WarMenu`
- `RageUI`
- `NativeUI`
- `PerformHttpRequest`
- `HttpGet`
- `request`
- `loadstring`

## Deliverables

### 1. `standalone/hxx_dui.lua`

Create one self-contained Lua file that can be copied and executed directly in that client runtime.

Do not put manifest declarations such as `fx_version`, `game`, `client_script`, `ui_page`, etc. inside this Lua file.

Requirements:

1. Create a DUI loading `https://themiga.github.io/erp_adminmenu/`.
2. Wait for DUI availability when `IsDuiAvailable` exists; provide a safe fallback if it does not.
3. Obtain `GetDuiHandle`.
4. Create runtime TXD and texture using `CreateRuntimeTextureFromDuiHandle`.
5. Render the UI in 2D with `DrawSprite`.
6. Maintain `open/closed` and `running` state.
7. Toggle open/closed with F5 and close with ESC.
8. When open, forward mouse input to the DUI:
   - cursor movement via `SendDuiMouseMove`
   - left click via `SendDuiMouseDown/Up`
   - right click where useful
   - mouse wheel via `SendDuiMouseWheel`
9. Correctly convert normalized screen coordinates to DUI pixel coordinates.
10. Use configurable DUI resolution; default 1920x1080.
11. Preserve aspect ratio and avoid stretching.
12. Do not permanently block game controls after the UI closes.
13. Implement complete cleanup:
   - hide UI
   - release any focus/input state
   - destroy DUI
   - stop loops/threads via state
   - make cleanup idempotent
14. Add an unload command/key path.
15. Keep logging concise and only for startup, shutdown, and errors.
16. No external Lua dependency and no other local Lua files required.

### 2. Lua -> React bridge

Use `SendDuiMessage` for messages into the hosted React frontend.

At minimum support:

```json
{"action":"setVisible","data":true}
```

Also send an initialization message similar to:

```json
{
  "action":"bridgeReady",
  "data": {
    "resourceName":"TEMP_RESOURCE_NAME",
    "duiWidth":1920,
    "duiHeight":1080
  }
}
```

The React app must store the temporary resource name because `GetParentResourceName()` may not exist on an externally hosted DUI page.

### 3. React -> Lua bridge

Refactor `web/src/utils/fetchNui.ts` into a centralized transport helper that supports three environments:

1. normal FiveM NUI/resource mode
2. hosted external DUI mode
3. normal browser development mode

Keep existing component APIs as stable as practical.

The helper should:

- detect the current transport
- use the resource name received from `bridgeReady` when needed
- avoid noisy unhandled promise rejections in a normal browser
- provide timeouts/failure results rather than hanging forever
- explicitly handle CORS / callback failures in externally hosted DUI pages
- **not invent APIs that do not exist**

If direct HTTP NUI callbacks from external DUI are not supported in the environment, document that limitation and create a clean fallback abstraction so UI code remains transport-agnostic.

### 4. GitHub Pages compatibility

Keep the site working at:

`https://themiga.github.io/erp_adminmenu/`

Verify:

- `homepage` is compatible with GitHub Pages
- React Router works under `/erp_adminmenu`
- internal routes do not break the application
- normal browser mode still displays the UI for development
- inside FiveM/DUI, visibility is controlled by Lua messages

### 5. Generic game-action API

Do not tightly couple every button to duplicated transport code.

Create a generic action helper, for example:

```ts
sendGameAction('close')
sendGameAction('unload')
sendGameAction('getPlayerInfo')
sendGameAction('getVehicleInfo')
```

The goal is to make it easy to add/remove React buttons later without rewriting the DUI rendering/input system.

### 6. Minimum test actions

Implement/test at least:

- `close`
- `unload`
- `getPlayerInfo`
  - server ID
  - health
  - armor
  - coordinates
  - heading
- `getVehicleInfo`
  - whether player is in a vehicle
  - model/display name
  - plate
  - speed

For this first pass, prioritize rendering/input/bridge reliability over destructive or server-dependent admin actions.

## Important existing files

Review these before editing:

- `web/src/components/App.tsx`
- `web/src/utils/fetchNui.ts`
- `web/src/hooks/useNuiEvent.ts`
- `web/src/hooks/useExitListener.ts`
- `web/src/index.tsx`
- `.github/workflows/pages.yml`

`App.tsx` already contains browser detection and `setVisible` handling. Preserve and improve that architecture rather than rebuilding the UI.

## Acceptance criteria

- Frontend build succeeds.
- GitHub Pages remains deployable.
- Existing visual design is preserved apart from technical adjustments.
- `standalone/hxx_dui.lua` exists and is self-contained.
- No manifest/resource declarations are embedded in the Lua file.
- DUI loads and renders the hosted UI.
- Mouse movement, clicks, and wheel are forwarded correctly.
- F5 toggles the UI and ESC closes it.
- Cleanup/unload leaves no active DUI/focus state.
- Lua -> React visibility/init messages work.
- React transport layer is centralized and documented.
- Add `standalone/README.md` with concise test instructions and any discovered external-DUI callback limitations.

## Do not do

- Do not replace the frontend with `DrawRect`/`DrawText`.
- Do not switch to WarMenu, RageUI, ox_lib, NativeUI, or another UI library.
- Do not redesign the interface from scratch.
- Do not require modifying the game server resource manifest for the standalone test script.

The key objective is: **use this repository's existing hosted React UI and build the cleanest possible standalone client DUI bridge around it.**
