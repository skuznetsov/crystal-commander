# Commander Smoke Plan

Use this when validation is explicitly requested.

## Build

```bash
make clean
make commander
```

Expected:

- build exits 0
- `./commander` exists
- no generated artifacts need committing except intended source/docs/scripts

## Headless automation

```bash
sh scripts/spec_check
sh scripts/commanderctl state
sh scripts/commanderctl commands
sh scripts/commanderctl status
sh scripts/commanderctl plugin-list
sh scripts/commanderctl runtime-list
sh scripts/commanderctl command-json '{"command_id":"panel.open_path","panel_index":0,"argument":"/tmp","dry_run":false}'
sh scripts/commanderctl view README.md
sh scripts/commanderctl mkdir /tmp/commander-smoke-dir 0 --dry-run
sh scripts/commanderctl copy /tmp/commander-smoke-dir 0 --dry-run
sh scripts/commanderctl move /tmp/commander-smoke-dir 0 --dry-run
sh scripts/commanderctl delete 0 --dry-run
```

Expected:

- all commands exit 0 except intentionally invalid cases
- JSON outputs parse
- dry-run commands do not create, copy, move, or delete files
- plugin/runtime lists include example plugin and disabled runtimes

## GUI

```bash
PANELS=3 ./commander
```

Expected:

- native macOS window stays open
- panels render MC/FAR-like rows
- Tab cycles active panel
- Up/Down move cursor without full-table flicker
- Space toggles mark on selected row
- F1-F10 trigger command status placeholders
- Enter opens directories
- Backspace goes to parent
- Ctrl-Q or File/Quit exits

## Accessibility

Inspect AX tree or use an automation tool.

Expected identifiers:

- `commander.mainWindow`
- `commander.root`
- `commander.status`
- `commander.panel.0`
- `commander.panel.0.table`
- `commander.panel.0.path`
- `commander.panel.0.footer`

