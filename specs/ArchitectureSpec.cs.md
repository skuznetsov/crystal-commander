# Architecture CodeSpeak

## Intent

Commander is a Crystal-first native macOS file commander. Crystal owns product logic and state. Objective-C++ owns AppKit object lifetimes, rendering, and platform event capture through a narrow C ABI.

## MUST

- Crystal MUST own file-manager behavior: navigation, command dispatch, panel state, file operations, plugin decisions, and automation/debug state.
- Objective-C++ MUST own AppKit objects, native view lifetimes, and UI event capture.
- The C ABI MUST remain the only production boundary between Crystal core and AppKit renderer.
- Renderer calls MUST express UI state changes or renderer commands, not business decisions.
- Input from AppKit MUST be converted into plain events consumed by Crystal.
- Architecture-sensitive changes MUST either preserve this contract or update this spec in the same change.

## MUST NOT

- Objective-C++ MUST NOT become the file-manager controller.
- Objective-C++ MUST NOT directly implement copy, move, delete, rename, plugin, or file-selection business rules.
- Crystal MUST NOT retain AppKit or Objective-C object pointers as durable state.
- Plugins MUST NOT bypass Commander APIs to mutate renderer/AppKit internals.
- Automation/debug APIs MUST NOT become hidden product logic paths.

## Boundaries

- `src/commander.cr`: application loop, panel state, command handling, file navigation.
- `src/renderer.cr`: Crystal wrapper over the C ABI.
- `src/commander_renderer.h`: stable C ABI exposed to Crystal.
- `src/commander_renderer.mm`: AppKit renderer and event queue.
- Future plugin host: command registration and safe access to snapshots/actions.
- Future automation layer: state/query/control surface for debugging and scripting.

## Invariants

- Crystal can run the commander decision loop without knowing AppKit implementation details.
- The renderer can be replaced without rewriting commander business logic.
- More than two panels are first-class; logic MUST NOT assume exactly left/right.
- Tab cycles active panel modulo panel count.
- The UI may look MC/FAR/NC-like, but the state model is multi-panel.

## Checks

- Before renderer changes, inspect `specs/RendererAbiSpec.cs.md`.
- Before key/mouse/event changes, inspect `specs/PanelsAndEventsSpec.cs.md`.
- Before plugin changes, inspect `specs/PluginsSpec.cs.md`.
- For non-trivial changes, record whether the patch preserves or updates the relevant CodeSpeak contract.
