# Crystal Native Commander

Native Commander-style file manager written in Crystal, with an AppKit backend through Objective-C++ FFI.

Нативный macOS-вариант консольного "движка" Midnight Commander:
- несколько панелей (окна внутри одного приложения),
- рендерер вынесен в `ObjC++` библиотеку (`src/commander_renderer.mm`),
- управление состоянием панелей и навигацией выполняется в Crystal (`src/commander.cr`, `src/renderer.cr`).

## Что сейчас реализовано

- Рендеринг AppKit-UI и сбор input-событий (`keyboard`/`mouse`) реализованы в `.mm`.
- Файловая модель, навигация, обработка `Enter/Backspace/Tab/Arrow` реализованы в Crystal.
- Built-in команды проходят через Crystal `CommandRegistry` и `Keymap`, чтобы позже подключить plugins/AppleScript/debug automation к тому же command layer.
- Crystal exposes internal read-only snapshot structs for future plugins/debug automation.
- Crystal обновляет UI через набор FFI-команд (`set_panel_path`, `set_panel_rows`, `set_status_text`, `set_active_panel`).

## Архитектура FFI

- `src/commander_renderer.mm` — полноценная native-библиотека рендера (AppKit/ObjC++).
- `src/commander_renderer.h` — C ABI для безопасного вызова из Crystal.
- `src/renderer.cr` — Crystal-обертка над C ABI (create/show/pump/poll/update).
- `src/command_registry.cr` — единый Crystal command layer для keyboard/menu/plugins/automation.
- `src/keymap.cr` — mapping raw key codes/modifiers to command IDs.
- `src/snapshots.cr` — read-only JSON-serializable app/panel/entry snapshots for plugins/debug automation.
- `src/automation_protocol.cr` — JSON command/response structs for future stateful IPC.
- `src/plugin_manifest.cr` — JSON manifest model for future Lua/subprocess plugins.
- `src/plugin_host.cr` — read-only plugin manifest discovery; no plugin code execution yet.
- `src/plugin_runtime.cr` — plugin runtime interface and no-op Lua/subprocess runtime stubs.
- `src/file_operations.cr` — safe file operation planning structs; execution is not implemented yet.
- `src/file_preview.cr` — read-only bounded text preview for `file.view`.
- `src/commander.cr` — пример full control логики из Crystal (без нативного file-control внутри `.mm`).

## Grok Delegation

- `scripts/grok_acp_delegate.py` — минимальный ACP-клиент для выдачи задач Grok.
- `GROK_DELEGATION.md` — workflow: Codex ставит задачу и ревьюит, Grok делает рабочий патч.

Текущая локальная проверка: ACP handshake проходит, но `session/prompt` получает `HTTP 403: Grok Build is in early access`.

> Рендер-слой теперь отделен от логики: `.mm` только рисует и отдает события, Crystal решает поведение.

## CodeSpeak specs

Архитектурные контракты лежат в `specs/*Spec.cs.md`:

- `specs/ArchitectureSpec.cs.md` — Crystal-first архитектура и границы ответственности.
- `specs/RendererAbiSpec.cs.md` — правила C ABI, ownership и renderer-команд.
- `specs/PanelsAndEventsSpec.cs.md` — multi-panel модель, Tab, cursor, mouse/key events.
- `specs/PluginsSpec.cs.md` — будущий plugin API, Lua/runtime границы и permissions.
- `specs/AutomationSpec.cs.md` — AppleScript/Accessibility/debug automation contracts.
- `specs/CrystalGuiApiSpec.cs.md` — будущий backend-neutral Crystal TUI/GUI API.
- `specs/TabsSpec.cs.md` — top-level workspace tabs in addition to multiple panels per tab.

Перед изменениями в чувствительных местах нужно сверять patch с соответствующим spec. Если код и spec расходятся, patch должен либо сохранить intent, либо явно обновить spec.

## C ABI API

- `commander_renderer_create/destroy`
- `commander_renderer_show/pump/stop`
- `commander_renderer_poll_event`
- `commander_renderer_set_active_panel`
- `commander_renderer_set_panel_path`
- `commander_renderer_set_panel_rows`
- `commander_renderer_set_status_text`
- `commander_renderer_get_mouse_position`
- `commander_renderer_set_mouse_visible`

## Запуск на macOS

### Быстрый запуск (рекомендуется)

```bash
cd /Users/sergey/Projects/Crystal/commander
chmod +x run_mac.sh
./run_mac.sh
```

Или вручную:

```bash
cd /Users/sergey/Projects/Crystal/commander
make run
```

### Ручной запуск

```bash
cd /Users/sergey/Projects/Crystal/commander
c++ -ObjC++ -fobjc-arc -c src/commander_renderer.mm -o src/commander_renderer.o
cc -ObjC -fobjc-arc -c src/objc_bridge.c -o src/objc_bridge.o
crystal run src/commander.cr --link-flags "$(pwd)/src/objc_bridge.o $(pwd)/src/commander_renderer.o -framework Foundation -framework AppKit -framework Cocoa -lobjc -lc++"
```

Если хочешь собрать бинарь:

```bash
c++ -ObjC++ -fobjc-arc -c src/commander_renderer.mm -o src/commander_renderer.o
cc -ObjC -fobjc-arc -c src/objc_bridge.c -o src/objc_bridge.o
crystal build src/commander.cr -o commander --link-flags "$(pwd)/src/objc_bridge.o $(pwd)/src/commander_renderer.o -framework Foundation -framework AppKit -framework Cocoa -lobjc -lc++"
./commander
```

Запускай без `timeout` и без форка в фоне — процесс должен жить, пока ты сам не закроешь окно.

Откройте приложение — окно появится как обычное macOS окно.

## Конфигурация

- `PANELS` — количество панелей в одном окне (по умолчанию `3`, диапазон `1..8`).
- `COMMANDER_PLUGIN_PATH` — директория read-only plugin manifests (по умолчанию `plugins`).
- `COMMANDER_DUMP_STATE=1` — вывести read-only JSON snapshot и завершиться без открытия окна.
- `COMMANDER_RUN_COMMAND=<id>` — выполнить command ID в headless mode, вывести JSON snapshot и завершиться.
- `COMMANDER_COMMAND_PANEL=<index>` — panel index для `COMMANDER_RUN_COMMAND` (по умолчанию active panel).
- `COMMANDER_COMMAND_ARG=<text>` — optional single string argument for headless command execution.
- `COMMANDER_AUTOMATION_COMMAND_JSON=<json>` — execute JSON `AutomationCommand`, return JSON `AutomationResponse`.
- `COMMANDER_DRY_RUN=1` — plan mutating headless commands without filesystem changes.
- `COMMANDER_AUTOMATION_SOCKET=<path>` — reserved path for future stateful local IPC; listener is not implemented yet.
- `COMMANDER_ENABLE_LUA_PLUGINS=1` — reserved gate for future embedded Lua plugin execution; runtime still stubbed.
- `COMMANDER_ENABLE_SUBPROCESS_PLUGINS=1` — reserved gate for future subprocess plugin execution; runtime still stubbed.

Read-only state через wrapper:

```bash
sh scripts/commanderctl state
sh scripts/commanderctl commands
sh scripts/commanderctl status
sh scripts/commanderctl plugin-list
sh scripts/commanderctl runtime-list
sh scripts/commanderctl command file.view 0
sh scripts/commanderctl command-json '{"command_id":"panel.open_path","panel_index":0,"argument":"/tmp","dry_run":false}'
sh scripts/commanderctl command-json-file /tmp/commander-command.json
COMMANDER_COMMAND_ARG=/tmp sh scripts/commanderctl command panel.open_path 0
sh scripts/commanderctl open /tmp 0
sh scripts/commanderctl view README.md
sh scripts/commanderctl mkdir /tmp/commander-demo-dir 0
sh scripts/commanderctl mkdir /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl copy /tmp/commander-demo-dir 0
sh scripts/commanderctl copy /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl move /tmp/commander-demo-dir 0 --dry-run
sh scripts/commanderctl delete 0 --dry-run
```

`commanderctl` uses the linked `./commander` binary and builds it through `make commander` if needed, so native AppKit/ObjC++ link flags stay centralized in the Makefile.
Command snapshots include `plugin_id` for manifest-declared plugin placeholders.

CodeSpeak spec shape check:

```bash
sh scripts/spec_check
```

Validation checklist:

```bash
cat scripts/smoke_plan.md
```

Read-only Grok ACP review helper:

```bash
sh scripts/grok_review .grok-acp/some_task.md
```

Bounded Grok ACP worker helper:

```bash
sh scripts/grok_worker .grok-acp/some_patch_task.md
```

## Plugin manifests

Plugin discovery is metadata-only for now. Example:

```json
{
  "id": "example.hello",
  "name": "Example Hello Plugin",
  "version": "0.1.0",
  "api_version": "0.1",
  "runtime": "lua",
  "entrypoint": "main.lua",
  "permissions": [],
  "commands": [
    {"id": "example.hello.status", "title": "Hello Status"}
  ]
}
```

Manifest-declared commands are registered as inert placeholders until the runtime host is implemented.

Runtime request/response structs are JSON-serializable so embedded Lua and future subprocess runtimes can share a protocol:

```json
{
  "command_id": "example.hello.status",
  "plugin_id": "example.hello",
  "entrypoint_path": "/absolute/path/to/plugins/example/main.lua",
  "context": {"active_panel": 0}
}
```
