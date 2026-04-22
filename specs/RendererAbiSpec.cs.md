# Renderer ABI CodeSpeak

## Intent

The renderer ABI is a safe, narrow command/event boundary between Crystal and native AppKit. Crystal sends snapshots or small renderer commands. Objective-C++ copies data it needs after the call returns and emits POD-style events back to Crystal.

## MUST

- Native renderer MUST copy any string/data from Crystal before returning if AppKit may read it later.
- Crystal MUST assume pointers from `String#to_unsafe`, slices, and temporary arrays are valid only for the duration of the FFI call.
- C ABI structs MUST remain plain C-compatible data structures.
- C ABI functions MUST tolerate invalid panel indexes by no-op or safe failure, not crash.
- Renderer event structs MUST remain stable enough for Crystal bindings to decode without Objective-C knowledge.
- Full row replacement MUST be used for path/list changes.
- Cursor-only movement SHOULD use a dedicated renderer command such as `set_panel_cursor`, not full row replacement.
- Native code that touches AppKit MUST run on the correct AppKit/main-thread path.

## MUST NOT

- Native renderer MUST NOT retain raw Crystal heap pointers.
- Crystal MUST NOT pass closures, Crystal objects, or GC-managed object references through the renderer ABI.
- C ABI calls MUST NOT require Objective-C exceptions for normal error handling.
- Cursor movement MUST NOT rebuild row strings or reload the full table when row data has not changed.
- Renderer ABI MUST NOT expose raw `NSView`, `NSTableView`, `NSString`, or other Objective-C pointers to Crystal product logic.

## Commands

- `create/destroy`: allocate and release native renderer state.
- `show/pump/stop/run`: drive AppKit lifecycle.
- `poll_event`: return queued input events to Crystal.
- `set_active_panel`: update visual focus.
- `set_panel_path`: update a panel path label.
- `set_panel_rows`: replace a panel row model.
- `set_panel_cursor`: update selection/cursor only, without row rebuild.
- `set_status_text`: update global status.
- `get_mouse_position/set_mouse_visible`: expose mouse integration where needed.

## Invariants

- `set_panel_rows` replaces the row snapshot and may reload the native table.
- `set_panel_cursor` updates selection only and MUST NOT mutate row data.
- Row flags may carry render-only state such as directory, executable, parent, and marked.
- Events flow native-to-Crystal; behavior decisions flow Crystal-to-native as commands.
- ABI extension is append-only where practical: adding functions is preferred over changing existing struct layout.

## Checks

- Build check: `make`.
- Runtime smoke: launch app, verify window opens, panel rows render, Tab cycles panels.
- Cursor smoke: Up/Down moves selection smoothly without visible full reload flicker.
- Navigation smoke: Enter/Backspace still performs full path/list refresh.
- Adversary check: large directory and empty directory must not crash renderer calls.
