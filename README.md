# Crystal Native Commander

Native Commander-style file manager written in Crystal, with an AppKit backend through Objective-C++ FFI.

Native macOS version of a Midnight Commander-style file manager:
- multiple panels inside one application window,
- rendering is isolated in the `ObjC++` library (`src/commander_renderer.mm`),
- panel state and navigation are controlled from Crystal (`src/commander.cr`, `src/renderer.cr`).

## Current implementation

- AppKit UI rendering and input event collection (`keyboard`/`mouse`) are implemented in `.mm`.
- The file model, navigation, and `Enter/Backspace/Tab/Arrow` handling are implemented in Crystal.
- Built-in commands go through the Crystal `CommandRegistry` and `Keymap`, so plugins, AppleScript, and debug automation can share the same command layer later.
- Crystal exposes internal read-only snapshot structs for future plugins/debug automation.
- Crystal updates the UI through FFI commands (`set_panel_path`, `set_panel_rows`, `set_status_text`, `set_active_panel`).

## FFI architecture

- `src/commander_renderer.mm` — native rendering library (AppKit/ObjC++).
- `src/commander_renderer.h` — C ABI for safe calls from Crystal.
- `src/renderer.cr` — Crystal wrapper over the C ABI (create/show/pump/poll/update).
- `src/command_registry.cr` — shared Crystal command layer for keyboard/menu/plugins/automation.
- `src/keymap.cr` — mapping raw key codes/modifiers to command IDs.
- `src/snapshots.cr` — read-only JSON-serializable app/panel/entry snapshots for plugins/debug automation.
- `src/automation_protocol.cr` — JSON command/response structs for future stateful IPC.
- `src/plugin_manifest.cr` — JSON manifest model for future Lua/subprocess plugins.
- `src/plugin_host.cr` — plugin manifest discovery and command registration.
- `src/plugin_runtime.cr` — plugin runtime interface, Lua subprocess runtime, and disabled subprocess runtime stub.
- `src/sdk.cr` — stable Crystal-facing facade for automation, plugins, VFS, and backend-neutral UI rendering.
- `src/file_operations.cr` — safe file operation planning structs; execution is not implemented yet.
- `src/file_preview.cr` — read-only bounded text preview for `file.view`.
- `src/commander.cr` — example of full control logic from Crystal, without native file-control logic inside `.mm`.

## SDK entrypoint

Crystal callers can import the SDK without launching the AppKit application:

```crystal
require "commander/sdk"
```

See `docs/SDK.md` for automation, plugin, VFS, and backend-neutral UI examples.

The macOS application target uses Objective-C++ object files and framework link flags, so build the app through `make commander` or `./run_mac.sh` rather than `shards build`.

## Grok Delegation

- `scripts/grok_acp_delegate.py` — minimal ACP client for delegating tasks to Grok.
- `GROK_DELEGATION.md` — workflow where Codex assigns and reviews tasks while Grok produces working patches.

Current local observation: ACP handshake works, but `session/prompt` may return `HTTP 403: Grok Build is in early access` depending on account access.

> The rendering layer is isolated from behavior: `.mm` draws and emits events, while Crystal decides application behavior.

## CodeSpeak specs

Architectural contracts live in `specs/*Spec.cs.md`:

- `specs/ArchitectureSpec.cs.md` — Crystal-first architecture and responsibility boundaries.
- `specs/RendererAbiSpec.cs.md` — C ABI, ownership, and renderer command rules.
- `specs/PanelsAndEventsSpec.cs.md` — multi-panel model, Tab switching, cursor handling, mouse/key events.
- `specs/PluginsSpec.cs.md` — plugin API, Lua/runtime boundaries, and permissions.
- `specs/AutomationSpec.cs.md` — AppleScript/Accessibility/debug automation contracts.
- `specs/CrystalGuiApiSpec.cs.md` — future backend-neutral Crystal TUI/GUI API.
- `specs/TabsSpec.cs.md` — top-level workspace tabs in addition to multiple panels per tab.
- `docs/SDK.md` — current SDK facade, examples, and stability rules.

Before changing sensitive areas, compare the patch with the relevant spec. If code and spec diverge, the patch must either preserve the documented intent or explicitly update the spec.

## C ABI API

- `commander_renderer_create/destroy`
- `commander_renderer_show/pump/stop`
- `commander_renderer_poll_event`
- `commander_renderer_set_active_panel`
- `commander_renderer_set_panel_path`
- `commander_renderer_set_panel_rows`
- `commander_renderer_set_status_text`
- `commander_renderer_get_mouse_position`
- `commander_renderer_set_mouse_visible`

## Running on macOS

### Quick start (recommended)

```bash
cd /Users/sergey/Projects/Crystal/commander
chmod +x run_mac.sh
./run_mac.sh
```

Or manually:

```bash
cd /Users/sergey/Projects/Crystal/commander
make run
```

### Manual run

```bash
cd /Users/sergey/Projects/Crystal/commander
c++ -ObjC++ -fobjc-arc -c src/commander_renderer.mm -o src/commander_renderer.o
cc -ObjC -fobjc-arc -c src/objc_bridge.c -o src/objc_bridge.o
crystal run src/commander.cr --link-flags "$(pwd)/src/objc_bridge.o $(pwd)/src/commander_renderer.o -framework Foundation -framework AppKit -framework Cocoa -lobjc -lc++"
```

To build the binary:

```bash
c++ -ObjC++ -fobjc-arc -c src/commander_renderer.mm -o src/commander_renderer.o
cc -ObjC -fobjc-arc -c src/objc_bridge.c -o src/objc_bridge.o
crystal build src/commander.cr -o commander --link-flags "$(pwd)/src/objc_bridge.o $(pwd)/src/commander_renderer.o -framework Foundation -framework AppKit -framework Cocoa -lobjc -lc++"
./commander
```

Run without `timeout` and without background forking. The process should stay alive until the window is closed.

Open the application and the window appears as a normal macOS window.

## Configuration

- `PANELS` — number of panels in one window (default `3`, range `1..8`).
- `COMMANDER_PLUGIN_PATH` — directory with plugin manifests (default `plugins`).
- `COMMANDER_DUMP_STATE=1` — print a read-only JSON snapshot and exit without opening a window.
- `COMMANDER_RUN_COMMAND=<id>` — execute a command ID in headless mode, print a JSON snapshot, and exit.
- `COMMANDER_COMMAND_PANEL=<index>` — panel index for `COMMANDER_RUN_COMMAND` (default: active panel).
- `COMMANDER_COMMAND_ARG=<text>` — optional single string argument for headless command execution.
- `COMMANDER_AUTOMATION_COMMAND_JSON=<json>` — execute JSON `AutomationCommand`, return JSON `AutomationResponse`.
- `COMMANDER_DRY_RUN=1` — plan mutating headless commands without applying filesystem changes.
- `COMMANDER_AUTOMATION_SOCKET=<path>` — reserved path for future stateful local IPC; listener is not implemented yet.
- `COMMANDER_ENABLE_LUA_PLUGINS=1` — enable Lua plugin command execution through an external `lua`, `lua5.4`, or `luajit` binary.
- `COMMANDER_ENABLE_SUBPROCESS_PLUGINS=1` — reserved gate for future subprocess plugin execution; runtime still stubbed.

Read-only state through the wrapper:

```bash
sh scripts/commanderctl state
sh scripts/commanderctl commands
sh scripts/commanderctl status
sh scripts/commanderctl plugin-list
sh scripts/commanderctl runtime-list
sh scripts/commanderctl command file.view 0
sh scripts/commanderctl command-json '{"command_id":"panel.open_path","panel_index":0,"argument":"/tmp","dry_run":false}'
sh scripts/commanderctl command-json-file /tmp/commander-command.json
COMMANDER_COMMAND_ARG=/tmp sh scripts/commanderctl command panel.open_path 0
sh scripts/commanderctl open /tmp 0
sh scripts/commanderctl view README.md
sh scripts/commanderctl mkdir /tmp/commander-demo-dir 0
sh scripts/commanderctl mkdir /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl copy /tmp/commander-demo-dir 0
sh scripts/commanderctl copy /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl move /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl delete 0 --dry-run
```

`commanderctl` uses the linked `./commander` binary and builds it through `make commander` if needed, so native AppKit/ObjC++ link flags stay centralized in the Makefile.
Command snapshots include `plugin_id` for manifest-declared plugin placeholders.

CodeSpeak spec shape check:

```bash
sh scripts/spec_check
```

Validation checklist:

```bash
cat scripts/smoke_plan.md
```

Read-only Grok ACP review helper:

```bash
sh scripts/grok_review .grok-acp/some_task.md
```

Bounded Grok ACP worker helper:

```bash
sh scripts/grok_worker .grok-acp/some_patch_task.md
```

## Plugin manifests

Plugin discovery is metadata-only for now. Example:

```json
{
  "id": "example.hello",
  "name": "Example Hello Plugin",
  "version": "0.1.0",
  "api_version": "0.1",
  "runtime": "lua",
  "entrypoint": "main.lua",
  "permissions": [],
  "commands": [
    {"id": "example.hello.status", "title": "Hello Status"}
  ]
}
```

Manifest-declared commands are registered through the command layer and are executed by their configured runtime when that runtime is enabled.

Runtime request/response structs are JSON-serializable so embedded Lua and future subprocess runtimes can share a protocol:

```json
{
  "command_id": "example.hello.status",
  "plugin_id": "example.hello",
  "entrypoint_path": "/absolute/path/to/plugins/example/main.lua",
  "context": {"active_panel": 0}
}
```

## Lua plugin MVP

Lua plugin execution is disabled by default and must be enabled explicitly:

```bash
COMMANDER_ENABLE_LUA_PLUGINS=1 sh scripts/commanderctl command example.hello.status 0
COMMANDER_ENABLE_LUA_PLUGINS=1 ./commander
```

The runtime looks for `COMMANDER_LUA_BIN`, then `lua`, `lua5.4`, and `luajit` on `PATH`.

Available Lua API:

```lua
commander.command("example.hello.status", function(ctx)
  commander.status("Hello from Lua plugin metadata example")
end)
```

Available MVP context fields:

- `ctx.command_id`
- `ctx.plugin_id`
- `ctx.active_panel`
- `ctx.panel.path`
- `ctx.panel.display_path`
- `ctx.panel.cursor`
- `ctx.panel.entries`
- `ctx.panel.selected_entry`
- `ctx.panel.marked_paths`

Current safety boundaries:

- Lua receives copied snapshot data, not Crystal heap pointers.
- Lua can update status text through `commander.status`.
- Lua cannot directly mutate panels, call AppKit, call renderer C ABI, run shell commands through Commander, or perform mediated file operations yet.
