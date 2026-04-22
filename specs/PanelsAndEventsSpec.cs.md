# Panels and Events CodeSpeak

## Intent

Panels are the core user model. The commander supports one or more panels, with a single active panel, keyboard and mouse events, and MC/FAR-like navigation semantics controlled by Crystal.

## MUST

- Panel count MUST be treated as dynamic within configured bounds.
- Active panel MUST be represented as an index modulo panel count.
- Tab MUST cycle the active panel.
- Arrow keys MUST move cursor within the active panel.
- Bare key bindings SHOULD NOT accidentally shadow modifier-specific command bindings.
- Enter MUST activate the selected row in the active panel.
- Backspace or parent navigation MUST reload the affected panel path and rows.
- Marking entries MUST update Crystal panel state first; file operations consume marked entries later.
- F1-F10 SHOULD map to canonical MC-style command IDs when macOS delivers function key events.
- Mouse row selection MUST become a Crystal-visible event or state update.
- Renderer events MUST be small, explicit, and decoded by Crystal before behavior is chosen.
- Status/footer text SHOULD reflect the selected entry and active panel.

## MUST NOT

- Code MUST NOT assume exactly two panels named left/right.
- Renderer MUST NOT decide filesystem navigation rules.
- A stale event MUST NOT apply to the wrong panel after active panel changes.
- Cursor movement MUST NOT silently change directory contents.
- Mouse selection MUST NOT bypass Crystal state.

## Event Categories

- `Key`: keyboard code and modifiers.
- `Mouse`: coordinates/button/click state where needed.
- `RowSelected`: panel index and row index selected in native UI.
- Future `Command`: normalized command action after key/menu/plugin mapping.
- Future `Automation`: debug/AppleScript/Accessibility command translated into the same command path.

## Canonical Command IDs

- `app.help`
- `app.menu`
- `app.pulldown`
- `app.quit`
- `panel.cursor_up`
- `panel.cursor_down`
- `panel.activate_left`
- `panel.activate_right`
- `panel.activate_selected`
- `panel.go_parent`
- `panel.open_path`
- `file.view`
- `file.view_path`
- `file.edit`
- `file.copy`
- `file.copy_to`
- `file.renmov`
- `file.renmov_to`
- `file.mkdir`
- `file.mkdir_named`
- `file.delete`
- `file.delete_plan`
- `file.mark_toggle`
- `file.mark_clear`
- `file.operation_execute`
- `file.operation_cancel`

## File Operation Planning

- `file.view` MAY perform bounded read-only text preview.
- `file.copy`, `file.renmov`, and `file.delete` MUST plan against marked entries when marks exist.
- If no marks exist, file commands MAY plan against the current selected entry.
- Planning is not execution; destructive commands MUST require a later confirmation/execution layer.
- `file.mkdir_named` MAY execute directly because it creates a new directory and fails when the path already exists.
- `file.copy_to` MAY execute for regular files only and MUST fail when the target path already exists.
- `file.renmov_to` MUST remain plan-only until explicit confirmation and overwrite policy exist.
- `file.delete_plan` MUST remain plan-only until explicit confirmation and deletion policy exist.
- `file.operation_execute` MAY execute pending `Copy` and `Mkdir` operations under their fail-closed policies.
- `file.operation_execute` MUST NOT execute pending `Delete` or `RenameMove` operations until explicit destructive confirmation policy exists.
- A pending operation MAY be stored in Crystal state for confirmation, automation, and debug snapshots.
- Clearing a pending operation MUST NOT mutate files.
- Multi-panel operations SHOULD use the next panel as the default target until an explicit target selection UI exists.

## Pending Operation Keys

- `Esc` SHOULD cancel a pending operation when present.
- `Ctrl+Return` or `Cmd+Return` MAY execute a pending operation after the execution layer exists.
- Until execution is implemented, execute command MUST report non-execution rather than mutating files.
- Modifier-specific bindings SHOULD take precedence over bare-key bindings.

## Invariants

- Crystal panel state is canonical.
- Marked paths are Crystal state, not native table state.
- Native selection is a rendering of Crystal state, not a second source of truth.
- Full panel sync happens on list/path changes.
- Cursor-only sync happens on cursor changes.
- A virtual panel from a plugin still behaves like a panel for focus, cursor, and command dispatch.

## Checks

- Launch with `PANELS=1`, `PANELS=2`, and `PANELS=3` when behavior changes affect panel indexing.
- Verify Tab wraps from last panel to first panel.
- Verify Up/Down clamps at panel bounds.
- Verify mouse selection and keyboard selection agree on the selected row.
- Verify Enter on directory changes path; Enter on regular file does not crash.
- Verify Backspace at root or permission-denied paths does not crash.
