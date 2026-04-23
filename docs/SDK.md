# Commander SDK

The SDK is the stable Crystal-facing facade for automation, plugins, VFS access, and backend-neutral UI rendering.

The shard-style entrypoint is:

```crystal
require "commander/sdk"
```

Inside this repository, tests may also use:

```crystal
require "./src/sdk"
```

The facade keeps callers away from internal file layout and avoids importing `CommanderApp` or opening an AppKit window.

## Surfaces

### Automation

Use automation commands when an external controller, AppleScript bridge, Accessibility smoke, or plugin wants to invoke Commander behavior through the same command path as keyboard/menu handling.

```crystal
command = Commander::SDK.command("panel.open_path", panel_index: 0, argument: "/tmp")
sequence = Commander::SDK.parse_command_sequence_json(%([{"command_id":"tab.new"}]))
```

Automation uses `Commander::AutomationCommand` and `Commander::AutomationResponse`. Commands must route through `CommandRegistry`; automation must not implement file-manager behavior separately.

### Command registry

```crystal
registry = Commander::SDK.command_registry
registry.register("example.status", "Example") { |ctx| }
```

Plugins, future AppleScript handlers, and debug tooling should converge on command IDs.

### Plugin manifests

```crystal
host = Commander::SDK.plugin_host("plugins")
host.load_manifests
```

Manifest loading is metadata-only. Runtime execution remains gated, and unsupported runtimes or permissions should be reported without executing plugin code.

### VirtualFS

```crystal
path = Commander::SDK.parse_vfs_uri("sftp://example.com/home/user")
registry = Commander::SDK.default_vfs_registry
```

The default registry supports local file operations and fail-closed SSH/SFTP/S3 skeletons. Real remote providers are future work and must preserve credential boundaries.

Lua plugins should use Commander-mediated VFS intent APIs rather than direct provider I/O.

### UI

```crystal
view = Commander::SDK.workspace(snapshot)
frame = Commander::SDK.render_workspace(snapshot, Commander::UI::Rect.new(0, 0, 120, 40))
backend = Commander::SDK.terminal_grid_backend(120, 40)
backend.draw(frame)
```

The UI surface is backend-neutral:

- `DrawCommand`
- `DrawFrame`
- `UIEvent`
- `Theme`
- `Backend`
- retained widgets such as `ListView`, `Split`, `TabBar`, and `WorkspaceWidget`

AppKit and terminal backends should consume draw/event primitives. They must not own Commander product logic.

## Current limitations

- The SDK has a shard-style source entrypoint, but no release/package workflow yet.
- The AppKit renderer still consumes specialized C ABI calls for panels/status/tab bar instead of rendering the full `DrawFrame`.
- `TerminalGridBackend` is deterministic test infrastructure, not an interactive TTY backend.
- SSH/SFTP/S3 providers are fail-closed skeletons.
- Lua plugin APIs are intentionally narrow and require `COMMANDER_ENABLE_LUA_PLUGINS=1`.

## Stability rule

Prefer adding stable methods to `Commander::SDK` over exposing more internal files. If an API needs to change, update this document, the relevant CodeSpeak spec, and SDK specs in the same commit.
