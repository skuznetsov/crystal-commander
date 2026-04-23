# Automation CodeSpeak

## Intent

Automation makes Commander observable and controllable for debugging, smoke tests, AppleScript, Accessibility, and agent workflows. Automation must reuse the same Crystal command/state model as keyboard, menu, and plugin paths.

## MUST

- Automation commands MUST route through Commander command IDs where practical.
- Debug state MUST be derived from Crystal canonical state, not scraped from native UI when Crystal already knows the answer.
- Status text MUST be canonical Crystal state and mirrored to renderer when a window exists.
- Debug snapshots SHOULD include command metadata so automation can discover valid command IDs.
- Command metadata SHOULD identify plugin-provided commands when applicable.
- Debug snapshots SHOULD include plugin manifest metadata without executing plugin code.
- Plugin snapshots MAY include resolved entrypoint paths for debugging; paths are metadata only and do not imply execution.
- Debug snapshots SHOULD include registered plugin runtime names.
- Debug snapshots SHOULD include whether plugin runtimes are enabled.
- Debug snapshots SHOULD include pending file-operation plans for confirmation/debugging.
- Debug snapshots MAY include bounded read-only file preview state.
- AppKit views SHOULD have stable accessibility identifiers for external inspection.
- AppleScript support SHOULD be added after the app has a stable bundle identity and command model.
- A future `commanderctl` or debug IPC MUST avoid exposing secrets or arbitrary filesystem mutation by default.
- Automation APIs MUST distinguish read-only state queries from mutating commands.
- Stateful IPC MUST be disabled unless an explicit socket path/config is provided.

## MUST NOT

- Automation MUST NOT become a second behavior implementation.
- AppleScript/Accessibility handlers MUST NOT directly mutate AppKit internals in ways Crystal does not observe.
- Debug APIs MUST NOT silently perform destructive file operations.
- Accessibility identifiers MUST NOT encode private paths, secrets, or transient user data.

## Identifier Scheme

- Main window: `commander.mainWindow`
- Root content: `commander.root`
- Top menu bar: `commander.topBar`
- Command/status bar: `commander.commandBar`
- Status label: `commander.status`
- Function-key bar: `commander.keyBar`
- Panel root: `commander.panel.N`
- Panel header: `commander.panel.N.header`
- Panel path label: `commander.panel.N.path`
- Panel table: `commander.panel.N.table`
- Panel footer/hint: `commander.panel.N.footer`

## Recommended Phases

- Phase 1: stable AppKit accessibility identifiers.
- Phase 2: Crystal debug snapshot structs and JSON serialization.
- Phase 3: local read-only state/command/status/plugin/runtime dump (`COMMANDER_DUMP_STATE=1`, `scripts/commanderctl state`, `scripts/commanderctl commands`, `scripts/commanderctl status`, `scripts/commanderctl plugin-list`, `scripts/commanderctl runtime-list`).
- Phase 4: JSON automation command/response structs.
- Phase 5: stateful local IPC for read-only state/status requests and `commanderctl command <id>` against a running app.
- Phase 6: `.app` bundle plus AppleScript `.sdef` mapped onto the same command/state API.

## JSON Protocol Draft

Structured request envelope:

```json
{
  "kind": "snapshot"
}
```

Single command:

```json
{
  "command_id": "panel.open_path",
  "panel_index": 0,
  "argument": "/tmp",
  "dry_run": false
}
```

Same-process command sequence:

```json
[
  {"command_id": "plugin.command", "panel_index": 0},
  {"command_id": "vfs.execute_pending_action", "panel_index": 0}
]
```

Responses include `ok`, `status_text`, and a full `AppSnapshot`.

## Invariants

- Keyboard, plugins, AppleScript, and debug IPC converge on command IDs.
- Accessibility is an observation surface first, not the canonical state store.
- Debug state must remain deterministic enough for agent smoke tests.
- Headless command execution must return a JSON snapshot that includes resulting status text.
- Headless command execution MAY pass one string argument through `CommandContext`, but non-headless calls MUST pass arguments explicitly.
- Headless JSON automation command execution MUST use `AutomationCommand` and return `AutomationResponse`.
- Headless JSON automation command sequence execution MUST use `Array(AutomationCommand)` and preserve state between commands in the same process.
- Omitted optional automation command fields MUST default to `panel_index=0`, `argument=nil`, and `dry_run=false`.
- Stateful IPC SHOULD accept structured `AutomationRequest` envelopes for read-only `snapshot`/`status` requests and command requests.
- Stateful IPC SHOULD preserve compatibility with legacy raw `AutomationCommand` JSON requests.
- Malformed or schema-invalid JSON automation commands MUST return structured error responses rather than raw stack traces.
- Automation responses SHOULD set `ok=false` when command dispatch fails.
- Headless state/command modes MUST NOT create AppKit windows or require renderer lifecycle.
- Headless mutating commands SHOULD support dry-run planning through `COMMANDER_DRY_RUN=1`.
- One-shot headless commands do not preserve pending operation state across processes; pending execution needs a stateful app session, IPC, or direct command form.
- Stateful IPC handlers MUST call the same in-process automation command executor used by headless/test paths.
- Stateful IPC MUST reject mutating command IDs unless the request explicitly sets `dry_run=true`.
- Snapshot structs are read-only transfer objects, not mutable panel state.
- Command snapshots expose metadata only; execution still goes through `CommandRegistry`.

## Checks

- Launch app and inspect AX tree for stable `commander.*` identifiers.
- Verify Tab/cursor/navigation still update Crystal state and visible UI.
- Verify an automation state query does not require screen scraping.
- Verify read-only state dump exits without opening a window.
- Verify `scripts/commanderctl state` is read-only and emits JSON.
- Verify `scripts/commanderctl commands` is read-only and lists command IDs.
- Verify `scripts/commanderctl status` is read-only and prints current status text.
- Verify `scripts/commanderctl plugin-list` is read-only and lists plugin metadata.
- Verify `scripts/commanderctl runtime-list` is read-only and lists runtime enable state.
- Verify `scripts/commanderctl command <id>` routes through `CommandRegistry` and emits JSON.
- Verify `scripts/commanderctl command-json JSON` routes through `AutomationCommand`.
- Verify `scripts/commanderctl command-json-file FILE` routes through `AutomationCommand`.
- Verify `scripts/commanderctl command-seq-json JSON_ARRAY` routes through `Array(AutomationCommand)`.
- Verify `scripts/commanderctl command-seq-json-file FILE` routes through `Array(AutomationCommand)`.
- Verify `scripts/commanderctl ipc-command-json SOCKET JSON` sends one newline-delimited automation command to a running socket.
- Verify `scripts/commanderctl ipc-command-json-file SOCKET FILE` sends one newline-delimited automation command loaded from a file.
- Verify `scripts/commanderctl ipc-state SOCKET` sends a read-only snapshot request to a running socket.
- Verify `scripts/commanderctl ipc-status SOCKET` sends a read-only status request to a running socket.
- Verify `COMMANDER_AUTOMATION_COMMANDS_JSON` executes an array of commands in one process and preserves pending state between them.
- Verify `AutomationServer` accepts one newline-delimited JSON `AutomationCommand` per local Unix socket client.
- Verify `AutomationServer` accepts structured `AutomationRequest` envelopes.
- Verify malformed IPC JSON returns a structured error envelope.
- Verify IPC socket startup refuses to overwrite an existing filesystem path.
- Verify mutating IPC commands are rejected unless `dry_run=true`.
- Verify `scripts/commanderctl open PATH PANEL` routes to `panel.open_path`.
- Verify `scripts/commanderctl view PATH` routes to read-only `file.view_path`.
- Verify `scripts/commanderctl mkdir PATH PANEL` fails if the path already exists.
- Verify `scripts/commanderctl copy TARGET_DIR PANEL` copies only regular files and does not overwrite existing targets.
- Verify `scripts/commanderctl mkdir/copy ... --dry-run` reports a plan without filesystem mutation.
- Verify `scripts/commanderctl move TARGET_DIR PANEL --dry-run` reports a plan without filesystem mutation.
- Verify `scripts/commanderctl delete PANEL --dry-run` reports a plan without filesystem mutation.
- Verify pending operation execution only mutates files for allowed fail-closed operation kinds.
- Automation wrappers SHOULD reuse the linked app binary or Makefile targets rather than duplicating native link flags.
- Verify mutating automation uses the same command path as keyboard input.
