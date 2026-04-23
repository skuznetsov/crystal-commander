# Viewer and Editor Integration CodeSpeak

## Intent

Commander panels should support viewing and editing file contents through an integrated text viewer/editor widget and external viewer/editor delegation. The viewer/editor layer must be backend-neutral and compatible with the `../crystal_tui` widget model while remaining decoupled from file-manager core logic.

## MUST

- A `Viewer` widget MUST render text content from a file path or in-memory buffer with scroll, search, and line navigation.
- An `Editor` widget MUST support in-place editing with undo/redo, save, and dirty-state tracking.
- External viewer/editor commands MUST delegate to system defaults or user-configured executables without embedding file content in Commander memory.
- Viewer/editor sessions MUST be scoped to a panel or a floating overlay; closing the session returns focus to the originating panel.
- Viewer MUST support read-only mode for binary-incompatible files with hex fallback or "cannot display" message.
- Editor save MUST go through Commander-mediated file operations (permission checks, optional confirmation).
- Theme and key bindings for viewer/editor MUST reuse the shared `Theme` and `Keymap` from the Crystal GUI API.

## MUST NOT

- Viewer/editor MUST NOT bypass Crystal command routing; all save/edit operations emit `Command` IDs.
- External delegation MUST NOT block the main UI thread; launch should be async with optional completion callback.
- Viewer/editor state MUST NOT be stored in `PanelState`; a separate `ViewerSession` registry is required.
- Native renderer code MUST NOT implement text layout or syntax highlighting; Crystal widgets own that.

## State Structs

```crystal
enum ViewerMode
  Text
  Hex
  Image # future
end

struct ViewerSession
  id : String
  panel_id : String? # originating panel, nil for floating
  path : String
  mode : ViewerMode
  scroll_offset : Int32
  cursor_line : Int32
  cursor_col : Int32
  search_term : String?
  dirty : Bool # for editor sessions
end

struct EditorSession
  id : String
  viewer_id : String # 1:1 with viewer backing buffer
  undo_stack : Array(EditorDelta)
  redo_stack : Array(EditorDelta)
  last_save : Time?
end

struct ViewerConfig
  external_viewer : String? # e.g., "open", "/usr/bin/less"
  external_editor : String? # e.g., "code", "/usr/local/bin/vim"
  max_buffer_size : Int64 # 10MB default; larger files require external
  tab_width : Int32
  show_line_numbers : Bool
  word_wrap : Bool
end
```

## Migration Phases

### P1 — Internal Text Viewer (read-only)
- Add `Viewer` widget bound to a UTF-8 text buffer or file path.
- Commands: `file.view` opens viewer for selected file in active panel.
- Viewer supports: Up/Down/PgUp/PgDn/Home/End, `/` search, `n`/`N` next/prev match, `q` close.
- Snapshot includes `viewer_sessions` array for headless inspection.
- Current partial implementation exposes read-only `ViewerSessionSnapshot` metadata and `viewer.close`/`viewer.scroll`/`viewer.search` command IDs; renderer widget integration remains future work.
- Current partial implementation exposes `ViewerConfigSnapshot` with external viewer/editor, max buffer size, tab width, line-number, and word-wrap fields.
- Check: `COMMANDER_RUN_COMMAND file.view --path README.md` opens viewer; `COMMANDER_DUMP_STATE` shows session.

### P2 — External Viewer Delegation
- `file.view_external` or `file.view_with <app>` launches system default or specified app.
- On macOS: uses `NSWorkspace.shared.open(URL)`.
- Terminal backend: uses `$PAGER` or `xdg-open`/`open`.
- Commander remains responsive; no content buffering for external viewer.
- Check: `sh scripts/commanderctl command-json file.view_external` returns `{launched:true, pid:?}` or error.

### P3 — Internal Editor (basic)
- `Editor` widget extends `Viewer` with insert/delete, dirty flag, save.
- Commands: `file.edit` opens editor; `editor.save`, `editor.save_as`, `editor.close`.
- Undo/redo via simple delta stack (insert range, delete range).
- Save uses Commander file operation path (may prompt for confirmation if policy set).
- Check: edit a small text file, modify, save; verify file contents updated on disk and panel refreshes.

### P4 — External Editor + Completion
- `file.edit_external` launches external editor (respecting `$EDITOR` or config).
- Optional: watch file for changes and refresh panel on external save (future, behind flag).
- Check: configure `external_editor: "code"`; verify `file.edit_external` launches VS Code.

## Commands (Concrete)

- `file.view [path]` → open internal viewer for path or selected entry.
- `file.view_external [path] [app]` → delegate to system or specified external viewer.
- `file.edit [path]` → open internal editor (or external if `prefer_external_editor=true`).
- `file.edit_external [path] [app]` → delegate to external editor.
- `viewer.scroll <lines>` → programmatic scroll within active viewer.
- `viewer.search <term>` → set search term and highlight matches.
- `viewer.close` → close active viewer/editor session.
- `editor.save` → save current editor buffer (may prompt).
- `editor.save_as <path>` → save to new path.
- `editor.undo` / `editor.redo` → stack operations.
- `config.viewer.set <key> <value>` → update `ViewerConfig` (headless or runtime).

## Key Bindings (defaults, overridable)

- `file.view`: `F3`
- `file.edit`: `F4`
- `viewer.close`: `q`, `Escape`
- `editor.save`: `ctrl-s`, `cmd-s`
- `editor.close`: `ctrl-w`, `cmd-w`

## Checks

- Opening a viewer does not mutate the originating panel's cursor or marked set.
- Closing a viewer restores focus to the originating panel if still present.
- External viewer launch does not block UI; Commander accepts input while external app runs.
- Internal editor save goes through file operation confirmation policy when enabled.
- `make && sh scripts/spec_check` passes.
- `sh scripts/commanderctl commands` lists new viewer/editor command IDs.
- Large file (> max_buffer_size) triggers "external required" message or auto-delegation.

## Invariants

- Viewer/editor widgets are generic; they do not know about file panels or commander-specific state.
- All mutations from editor save flow through `file_operations.cr` or equivalent mediated path.
- Viewer sessions are ephemeral unless pinned; closing the last viewer for a panel returns to normal panel view.
- Theme and keymap consistency: viewer uses the same `Theme` tokens and `Keymap` resolution as panels.
