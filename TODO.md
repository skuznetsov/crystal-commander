# Commander TODO

## 1. Verify current integration

Status: PARTIAL

Risk: SAFE

Definition of Done:

- `make clean`
- `make commander`
- `sh scripts/spec_check`
- `sh scripts/commanderctl state`
- `sh scripts/commanderctl commands`
- `sh scripts/commanderctl plugin-list`
- `sh scripts/commanderctl runtime-list`

Expected:

- build exits 0
- headless JSON commands parse
- no AppKit window opens for headless modes
- plugin manifest metadata appears
- runtimes show disabled unless gates are set

Evidence:

- `make clean && make commander` passed after compile fixes.
- `sh scripts/spec_check` passed.
- `sh scripts/commanderctl state` emitted parseable JSON.
- `sh scripts/commanderctl commands/status/plugin-list/runtime-list` passed.
- `sh scripts/commanderctl command-json ...`, `view`, and dry-run mkdir/copy/move/delete emitted parseable JSON.

Remaining:

- GUI smoke from `scripts/smoke_plan.md` not run yet.

## 2. Fix compile/runtime issues from verification

Status: TODO

Risk: SAFE

Definition of Done:

- all commands from TODO item 1 pass
- update `LANDMARKS.md` trust levels if verification succeeds

## 3. Add stateful automation IPC

Status: TODO

Risk: CAUTION

Definition of Done:

- `COMMANDER_AUTOMATION_SOCKET=<path> ./commander` creates a local-only IPC listener
- listener accepts one JSON `AutomationCommand` per request
- response is JSON `AutomationResponse`
- disabled by default
- no destructive commands without explicit command policy

## 4. Implement minimal embedded Lua API

Status: TODO

Risk: CAUTION

Definition of Done:

- gated behind `COMMANDER_ENABLE_LUA_PLUGINS=1`
- Lua can register/execute a status-only command
- Lua receives snapshots, not mutable Commander internals
- no raw AppKit/C ABI access from Lua

## 5. Promote file operation UI

Status: TODO

Risk: CAUTION

Definition of Done:

- copy/mkdir visible through GUI status and command flow
- delete/renmov remain plan-only until confirmation UI exists
- pending operations visible in snapshots

## 6. Package as macOS app bundle

Status: TODO

Risk: CAUTION

Definition of Done:

- app bundle has stable identity
- File/Quit works
- Accessibility identifiers visible in AX tree
- AppleScript `.sdef` design can start from existing command IDs

## 7. Design backend-neutral Crystal TUI/GUI API

Status: TODO

Risk: CAUTION

Definition of Done:

- Extract a small backend-neutral draw/event/style API compatible with `../crystal_tui`
- Keep Commander state/widgets in Crystal
- Keep AppKit as a backend host for windows/input/drawing only
- Support terminal and macOS backends from the same widget model

## 8. Add top-level workspace tabs

Status: TODO

Risk: CAUTION

Definition of Done:

- Tabs are Crystal-owned workspaces
- Each tab owns its own panel collection and active panel
- Existing `Tab` key still cycles panels inside the active workspace
- Separate commands exist for next/previous/new/close tab
