# Commander Landmarks

## LM-1: Crystal-first architecture

Crystal owns file-manager behavior, panel state, commands, plugin decisions, and automation state. Objective-C++ owns AppKit rendering and event capture only.

Evidence: `specs/ArchitectureSpec.cs.md`, `src/commander.cr`, `src/commander_renderer.mm`.

Trust: `{F:0.8,G:0.8,R:0.8}` build and headless smoke passed; GUI smoke still pending.

## LM-2: Renderer C ABI boundary

Crystal talks to AppKit through `src/commander_renderer.h` and `src/renderer.cr`. Native code must copy Crystal strings before retaining data.

Evidence: `specs/RendererAbiSpec.cs.md`, `src/renderer.cr`, `src/commander_renderer.h`.

Trust: `{F:0.8,G:0.8,R:0.8}` build passed; GUI renderer behavior still pending manual smoke.

## LM-3: Commands are the shared mutation path

Keyboard, future menus, plugins, AppleScript, and debug automation converge on command IDs via `CommandRegistry` and `Keymap`.

Evidence: `src/command_registry.cr`, `src/keymap.cr`, `specs/PluginsSpec.cs.md`, `specs/AutomationSpec.cs.md`.

Trust: `{F:0.8,G:0.8,R:0.8}` build and headless command listing passed.

## LM-4: Headless automation uses snapshots

`COMMANDER_DUMP_STATE`, `COMMANDER_RUN_COMMAND`, and `COMMANDER_AUTOMATION_COMMAND_JSON` return JSON snapshots/responses without creating AppKit windows.

Evidence: `src/snapshots.cr`, `src/automation_protocol.cr`, `src/commander.cr`, `scripts/commanderctl`.

Trust: `{F:0.8,G:0.8,R:0.8}` headless state/command JSON smoke passed.

## LM-5: Plugins are metadata-only until runtime gates open

Plugin manifests are discovered and validated without executing plugin code. Lua/subprocess runtimes are stubs behind explicit enable gates.

Evidence: `src/plugin_manifest.cr`, `src/plugin_host.cr`, `src/plugin_runtime.cr`, `plugins/example/plugin.json`.

Trust: `{F:0.8,G:0.8,R:0.8}` build passed and plugin/runtime list smoke passed.

## LM-6: Destructive file operations remain plan-only

Delete and rename/move are pending-operation plans only. Copy and mkdir may execute under fail-closed policies; dry-run exists for headless mutation planning.

Evidence: `src/file_operations.cr`, `src/commander.cr`, `specs/PanelsAndEventsSpec.cs.md`.

Trust: `{F:0.8,G:0.7,R:0.8}` build passed and dry-run headless operation smoke passed.

## LM-7: Grok is useful but must be bounded

Grok ACP works on subscription/default auth and can perform useful source-grounded review/patches, but needs wrapper-enforced scope and timeout hygiene.

Evidence: `scripts/grok_acp_delegate.py`, `scripts/grok_review`, `scripts/grok_worker`, `GROK_BETA_OBSERVATIONS.md`.

Trust: `{F:0.8,G:0.7,R:0.8}` verified through ACP smoke and worker/review runs.

## LM-8: VirtualFS Phase 0 foundation exists

VirtualFS has a typed URI, URI resolver, provider, registry, and local file provider foundation. Existing local mkdir/copy file operations and local panel directory listing now delegate through the local VFS provider. `MemoryProvider` can simulate supported remote schemes and offline mutation failures without network or credentials. `PanelState` stores a canonical `VirtualPath` location, panel/entry snapshots expose canonical `uri` fields while retaining legacy `path`, and entries store stable URIs. `panel.open_path` accepts `file://` URIs and returns fail-closed typed statuses for remote URI probes. `vfs.probe_uri` lets automation/debug layers probe registry behavior without mutating panels. Lua plugins can parse permitted VFS URIs, inspect permitted schemes, read snapshot URIs, and return VFS request intent actions for Crystal to mediate. `plugins/vfs_probe` is the repo-local example for this Lua VFS intent flow. App snapshots expose those pending plugin actions for automation/debug layers. `vfs.execute_pending_action` can execute the first pending read-only `stat`/`list` action through the registry. `COMMANDER_AUTOMATION_COMMANDS_JSON` and `commanderctl command-seq-json*` support same-process headless command sequences for stateful smoke tests. `scripts/vfs_smoke` verifies the no-GUI VFS/Lua automation path. SSH/SFTP/S3 have fail-closed provider skeletons, but real remote provider implementations are not connected yet.

Evidence: `src/virtual_fs.cr`, `spec/virtual_fs_spec.cr`, `docs/specs/VirtualFileSystemSpec.cs.md`.

Trust: `{F:0.8,G:0.7,R:0.8}` `crystal spec` passed with 69 examples, `sh scripts/spec_check` passed, `make clean && make commander` passed, `sh scripts/commanderctl state` returned JSON with `uri` fields, the repo-local Lua VFS probe plugin returned one pending VFS action, `vfs.probe_uri` succeeded for file URI while failing closed for s3 URI, `vfs.execute_pending_action` reports no action when none is pending, multi-command automation executed a Lua-produced local VFS stat action in one process, and `scripts/vfs_smoke` passed.

## LM-9: Tabs are Crystal-owned workspace state

Commander has a Crystal-owned tab model with independent panel arrays, per-tab active panel state, tab rename support, per-tab panel count changes, and native renderer tab-bar sync for title, active state, and panel count. Tab click events are not wired yet, and native renderer panel layout still matches the launch-time renderer panel count.

Evidence: `src/commander.cr`, `src/snapshots.cr`, `specs/TabsSpec.cs.md`.

Trust: `{F:0.8,G:0.6,R:0.8}` `crystal spec` passed with 73 examples, `sh scripts/spec_check` passed, `make commander` passed, `scripts/tabs_smoke` passed, `scripts/vfs_smoke` passed, native renderer tab-bar C ABI compiled, and tabs smoke preserved different panel URIs across two tabs, verified rename, verified close, verified per-tab panel count independence, and verified the last-tab guard.

## LM-10: Backend-neutral UI draw frame exists

Commander has a Crystal-owned UI API with backend-neutral events, draw commands, draw frames, theme tokens, a backend contract, a recording backend for no-GUI verification, a terminal-grid backend for deterministic cell rendering, a retained widget tree, and a snapshot-to-widget workspace renderer. File panels are represented through a generic `ListView` widget, with Commander-specific state staying in Crystal snapshots. The current AppKit renderer still consumes the older C ABI state directly; this landmark proves the Crystal-side draw stream can be generated deterministically before native renderer migration.

Evidence: `src/ui_api.cr`, `spec/ui_api_spec.cr`, `specs/CrystalGuiApiSpec.cs.md`.

Trust: `{F:0.8,G:0.6,R:0.8}` `crystal spec` passed with 73 examples, `sh scripts/spec_check` passed, `make commander` passed, `scripts/tabs_smoke` passed, `scripts/vfs_smoke` passed, and UI specs verified two backend stubs receive identical draw command streams, a retained workspace widget tree with tabs, split panels, list rows, selection styles, and terminal-grid rendering of the same `DrawFrame`.

## LM-11: Commander SDK facade exists

Commander has a stable source-level SDK facade at `src/sdk.cr`, a shard-style entrypoint at `src/commander/sdk.cr` for `require "commander/sdk"`, and an SDK-only shard target at `src/commander/sdk_info.cr`. The macOS executable build remains Makefile-owned because it needs Objective-C++ object files and AppKit/Cocoa link flags. The SDK exposes automation command helpers, command registry construction, metadata-only plugin host construction, VFS URI/default-registry helpers, workspace projection, backend-neutral workspace rendering, recording backend construction, and terminal-grid backend construction without importing `CommanderApp` or opening AppKit.

Evidence: `src/sdk.cr`, `src/commander/sdk.cr`, `src/commander/sdk_info.cr`, `spec/sdk_spec.cr`, `docs/SDK.md`, `shard.yml`.

Trust: `{F:0.8,G:0.6,R:0.8}` `shards build` passed for the SDK-only target, `crystal spec` passed with 77 examples, `sh scripts/spec_check` passed, `make commander` passed, `scripts/tabs_smoke` passed, `scripts/vfs_smoke` passed, and SDK specs verified automation, VFS, plugin registry, UI rendering helpers, and both repository-local plus shard-style SDK import paths.

## LM-12: Stateful automation IPC skeleton is live

Commander has a local Unix socket automation server that accepts one newline-delimited JSON `AutomationCommand` per client and delegates valid allowed commands to the same in-process automation executor as headless JSON paths. `commanderctl` can send socket commands through `ipc-command-json` and `ipc-command-json-file`. Malformed JSON returns a structured error envelope. Socket startup refuses to overwrite existing filesystem paths. Mutating IPC command IDs are denied unless the request explicitly sets `dry_run=true`.

Evidence: `src/automation_protocol.cr`, `src/automation_server.cr`, `spec/automation_protocol_spec.cr`, `spec/automation_server_spec.cr`, `scripts/commanderctl`, `scripts/ipc_smoke`, `specs/AutomationSpec.cs.md`.

Trust: `{F:0.8,G:0.6,R:0.8}` `crystal spec` passed with 84 examples, `sh scripts/spec_check` passed, `shards build` passed, `make commander` passed, `scripts/tabs_smoke` passed, `scripts/vfs_smoke` passed, `scripts/ipc_smoke` passed, and automation specs covered valid IPC, malformed JSON, existing-path safety, mutating command denial, and dry-run mutating command allowance.
