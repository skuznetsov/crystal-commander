# Crystal GUI API CodeSpeak

## Intent

Commander should evolve toward a backend-neutral Crystal UI API compatible with the existing `../crystal_tui` widget/event/layout model. Terminal and native macOS rendering should be backend choices, not separate application architectures.

## MUST

- Crystal MUST own the retained widget tree, layout state, application state, command routing, and event dispatch.
- Backends MUST expose drawing primitives and input events, not product-specific widgets.
- The macOS backend MUST render from backend-neutral draw commands or equivalent primitives.
- The terminal backend SHOULD continue to map the same widget tree to terminal cells.
- Widgets MUST NOT know whether they are rendered by ANSI terminal, AppKit, Quartz, or another future backend.
- Input events MUST normalize keyboard, mouse, scroll, and focus data before application widgets consume them.
- Theme colors MUST be represented as a Crystal palette/style model before they reach a backend.
- The first shared layer MUST be expressible from read-only Commander snapshots so terminal and native backends can reuse the same state projection.

## MUST NOT

- The macOS backend MUST NOT become a parallel AppKit widget implementation for every Crystal widget.
- Commander-specific file panel logic MUST NOT leak into the generic backend API.
- Backend draw code MUST NOT hold Crystal heap pointers after an FFI call.
- Backend APIs MUST NOT require plugins to access AppKit or terminal internals directly.

## API shape

- `App`: owns lifecycle, widget tree, command registry, and backend.
- `Widget`: owns local state, layout constraints, focusability, and event handlers.
- `Backend`: owns windows/surfaces, input polling, drawing, clipping, cursor state, and platform lifecycle.
- `DrawCommand`: backend-neutral primitive such as fill rect, stroke rect, text, line, image, and clip.
- `UIEvent`: backend-neutral key, mouse, scroll, resize, focus, and wakeup events.
- `Theme`: palette and style tokens shared by terminal and GUI backends.
- `Commander::UI::WorkspaceView`: backend-neutral projection of commander state for renderers and future viewers/editors.

## Invariants

- A Commander workspace should be expressible as widgets: menu bar, tab bar, split/panel layout, file panels, status/footer, optional command line.
- The same high-level widget should be usable in terminal and native macOS with backend-specific rendering fidelity.
- Backend primitives may be immediate-mode, but application state remains retained in Crystal.
- Native macOS rendering can use AppKit/Quartz for window/input/drawing host, but not for product logic.
- Snapshot-to-view projection is allowed as an incremental bridge while the retained widget tree is introduced.

## Checks

- A backend-neutral file panel can render rows, selection, headers, and scroll state without file-manager logic in native code.
- A tabbed workspace can switch active workspaces without assuming exactly two panels.
- Theme changes can update colors without recompiling Objective-C++ constants.
- Keyboard and scroll input produce the same command IDs in terminal and macOS backends.
- `Commander::UI.workspace(snapshot)` can describe active panel, selected entry, status text, and command IDs without loading AppKit.
