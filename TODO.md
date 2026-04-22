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
- `DrawCommand` enum covers fill, stroke, text, clip, image
- `UIEvent` union covers key, mouse, scroll, resize, focus, wakeup
- `Theme` palette/style tokens shared by both backends
- Check: `make && sh scripts/spec_check` passes
- Check: compile stub that swaps backends; both receive identical DrawCommand streams
- Check: runtime theme switch updates colors in terminal and macOS without restart

Migration phases (see `specs/CrystalGuiApiSpec.cs.md`):

- P0: Snapshot projection (`Commander::UI.workspace(snapshot)`) — current baseline
- P1: DrawCommand + UIEvent abstractions; `Backend` trait with `draw`/`poll_event`
- P2: Retained widget tree (`Widget`, `Label`, `ListView`, `Split`, `TabBar`); file panel as `ListView`
- P3: Theme and style tokens; palette maps to NSColor vs ANSI escapes
- P4: Full workspace as widgets (`MenuBar` | `TabBar` | `WorkspaceSplit` | `StatusBar`); C ABI as one backend impl

## 8. Add top-level workspace tabs

Status: TODO

Risk: CAUTION

Definition of Done:

- Tabs are Crystal-owned workspaces
- Each tab owns its own panel collection and active panel
- Existing `Tab` key still cycles panels inside the active workspace
- Separate commands exist for next/previous/new/close tab
- `tab.set_panel_count` changes only active tab's panel array
- `COMMANDER_DUMP_STATE` includes `workspace.tabs[*]` with per-tab panels and cursors
- Check: `sh scripts/commanderctl command-json tab.new` emits parseable workspace JSON
- Check: create tab A (2 panels), tab B (4 panels); switch verifies independent state

Migration phases (see `specs/TabsSpec.cs.md`):

- P1: Tab model in Crystal, snapshot includes workspace; no renderer tab bar yet
- P2: `set_tab_bar(TabBarState)` renderer command; native tab bar renders titles
- P3: Per-tab panel independence verified by cross-tab state preservation
- P4: Tab rename + optional persistence (future)

## 9. Text viewer/editor and external viewer integration

Status: TODO

Risk: CAUTION

Definition of Done:

- Internal text viewer widget supports scroll, search, line navigation
- Internal editor supports edit, undo/redo, save with dirty flag
- External viewer/editor delegation launches system default or configured app
- Viewer/editor sessions are separate from panel state; `ViewerSession` registry exists
- `file.view` / `file.edit` open internal widgets; `file.view_external` / `file.edit_external` delegate
- Save from internal editor goes through Commander file operation path (confirmation policy respected)
- `ViewerConfig` holds `external_viewer`, `external_editor`, `max_buffer_size`, `tab_width`
- Check: `sh scripts/commanderctl commands` lists viewer/editor command IDs
- Check: open viewer on small file; verify `COMMANDER_DUMP_STATE` includes `viewer_sessions`
- Check: large file (> max_buffer_size) shows "external required" or auto-delegates
- Check: `make && sh scripts/spec_check` passes

Migration phases (see `docs/ViewerEditorSpec.cs.md`):

- P1: Internal text viewer (read-only); `file.view` opens session; snapshot includes sessions
- P2: External viewer delegation; `file.view_external` uses NSWorkspace / $PAGER
- P3: Internal editor (basic); edit, undo/redo, save via mediated file ops
- P4: External editor + completion; `file.edit_external`; optional file-watch refresh (future)

## 10. Virtual File System (SSH/SFTP/S3) integration design

Status: DONE (design only)

Risk: LOW

Definition of Done:

- `docs/specs/VirtualFileSystemSpec.cs.md` created with URI schemes, provider operations, auth rules, caching model, panel navigation, staged plan (Phase 0 first), and credential-free verification matrix
- TODO.md updated with this item
- `sh scripts/spec_check` exits 0 (English prose, required headings in checked specs)
- No changes to src/, spec/, no new dependencies, no network calls, no app launch

Evidence:

- Created docs/specs/VirtualFileSystemSpec.cs.md following CodeSpeak style (Intent/MUST/MUST NOT/Invariants/Checks)
- Defined file/ssh/sftp/s3 URI forms + examples
- Specified exact provider ops (stat/list/read/write/mkdir/delete/rename/copy/open_stream)
- Auth boundary: secrets never in Crystal heap; keychain/agent only
- Offline model: stale cache + VfsError::Offline for mutations
- Panel nav preserves local semantics via URI-based dispatch
- Lua plugins access VFS only through Commander-mediated permission-gated APIs
- Safe first increment = Phase 0 (URI + FileProvider wrapper only)
- Verification: URI roundtrips, mock dispatch, offline simulation, auth grep checks — all runnable without credentials
- Command run: sh scripts/spec_check (passed)

Remaining:

- Actual implementation of Phase 0+ deferred to future work items
- Will require update to specs/ArchitectureSpec.cs.md and PanelsAndEventsSpec.cs.md when code changes begin

## 11. Virtual File System Phase 0 implementation

Status: PARTIAL

Risk: SAFE

Definition of Done:

- `Commander::VirtualFS::VirtualPath` parses and serializes file/ssh/sftp/s3 URIs
- `Commander::VirtualFS::Registry` dispatches all provider operations by URI scheme
- `Commander::VirtualFS::UriResolver` resolves relative, parent, absolute, and home paths across supported schemes
- `Commander::VirtualFS::FileProvider` supports local stat/list/read/write/mkdir/delete/rename/copy without network dependencies
- Existing `Commander::FileOperations.mkdir` and `copy_file` delegate local mutations through `VirtualFS::FileProvider`
- `PanelState.load_path` uses `VirtualFS::FileProvider` for local directory stat/list rows
- `VirtualFS::Registry.default` registers fail-closed ssh/sftp/s3 provider skeletons with no network access
- Lua plugins can inspect manifest-granted VFS schemes through `commander.vfs.allowed_schemes()`
- Panel and entry snapshots expose canonical VFS `uri` fields while retaining legacy `path` fields
- `panel.open_path` accepts `file://` URIs and fail-closed remote URIs without network access
- Lua plugins can declare VFS request intent actions without executing provider I/O
- App snapshots expose pending plugin VFS actions for automation/debug layers
- `vfs.probe_uri` probes URIs through the VFS registry without mutating panels
- `vfs.execute_pending_action` executes the first pending read-only plugin VFS action (`stat`/`list`) through the registry
- `COMMANDER_AUTOMATION_COMMANDS_JSON` runs multiple automation commands in one headless process for stateful smoke tests
- `scripts/commanderctl command-seq-json` and `command-seq-json-file` wrap same-process command arrays
- `VirtualFS::MemoryProvider` simulates supported remote schemes without network or credentials
- Unsupported schemes fail before I/O with typed `VfsError`
- Tests cover registry dispatch, unsupported scheme, binary-safe local read, and local mutation operations
- `crystal spec`, `sh scripts/spec_check`, and `make commander` pass

Evidence:

- Implemented `ErrorCode`, `VfsError`, `VfsException`, `Registry`, and `FileProvider`
- Expanded provider contract to stat/list/read/write/mkdir/delete/rename/copy/open_stream
- Added URI `to_uri` serialization for round-trip checks while keeping `to_s` as display formatting
- Added `UriResolver` for relative, parent, absolute, and home path resolution
- Added mock provider dispatch specs and local file provider specs
- Routed existing local mkdir/copy commands through the VFS file provider
- Routed local panel directory listing through the VFS file provider
- Added fail-closed remote provider skeletons for ssh/sftp/s3
- Added Lua VFS allowed-scheme introspection
- Added canonical VFS URI fields to panel/entry snapshots and Lua panel snapshots
- Added URI-aware `panel.open_path` behavior for local file URIs and fail-closed remote URI probes
- Added Lua VFS request intent actions in `PluginRuntimeResponse`
- Added app snapshot exposure for pending plugin VFS actions
- Added headless VFS probe command for automation/debug use
- Added read-only pending plugin VFS action executor command
- Added headless multi-command automation JSON mode for same-process stateful checks
- Added `VirtualFS::MemoryProvider` for deterministic remote-like tests and offline mutation checks
- Added `commanderctl` wrappers for same-process command arrays
- Validation: `crystal spec` passed with 69 examples; `sh scripts/spec_check` passed; `make clean && make commander` passed; `sh scripts/commanderctl state` returned JSON with `uri` fields; temporary Lua plugin command returned one pending VFS action; `vfs.probe_uri` succeeded for file URI and failed closed for s3 URI; `vfs.execute_pending_action` reports no action when none is pending; multi-command automation executed a Lua-produced local VFS stat action in one process

Remaining:

- PanelState still stores local paths internally instead of `VirtualPath`
- Real SSH/SFTP/S3 providers remain future work behind explicit auth/credential boundaries
- `open_stream` intentionally returns `UnsupportedOperation` until stream ownership is specified
