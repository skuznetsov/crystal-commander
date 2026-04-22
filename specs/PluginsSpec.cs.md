# Plugins CodeSpeak

## Intent

Plugins extend Commander through a safe Crystal-owned command API. Plugins may be implemented in Lua, Crystal, subprocess JSON-RPC, or another runtime later, but they must not bypass Commander state and renderer boundaries.

## MUST

- The first plugin API MUST be a Crystal command registry, even before embedding Lua.
- Plugins MUST register commands through Commander APIs.
- Plugin and user key bindings SHOULD target command IDs rather than duplicating behavior.
- Command aliases MAY exist for compatibility through `register_alias`, but canonical command IDs remain preferred.
- Plugins MUST receive snapshots of panel/file state, not mutable internal objects by default.
- Plugin-triggered UI changes MUST go through Commander command/render APIs.
- Plugin file operations MUST use Commander-mediated operations with confirmation/permission policy.
- Plugin manifests SHOULD declare name, version, commands, hotkeys, permissions, and runtime.
- Plugin manifests SHOULD declare `api_version` and runtime `entrypoint` before runtime loading is implemented.
- Plugin manifests SHOULD be JSON-compatible and loadable without executing plugin code.
- Plugin discovery MUST load metadata before runtime initialization.
- Plugin discovery SHOULD support an explicit plugin root path for development and packaging.
- Plugin command IDs MUST be unique across loaded plugin manifests.
- Plugin key bindings MUST reference declared plugin commands or explicitly imported command IDs later.
- Plugin key binding specs SHOULD use portable names such as `ctrl-l`, `cmd-return`, `f5`, or `space`.
- Unknown plugin key binding specs MUST be reported without executing plugin code.
- Unsupported plugin runtimes MUST be reported before runtime initialization.
- Unsupported plugin permissions MUST be reported before runtime initialization.
- Manifest-declared commands MAY be registered as inert placeholders before runtime loading.
- Lua or any embedded runtime MUST have an explicit safe API surface.

## MUST NOT

- Plugins MUST NOT receive raw AppKit pointers.
- Plugins MUST NOT receive raw Crystal heap pointers that outlive a call.
- Plugins MUST NOT call renderer C ABI directly.
- Plugins MUST NOT perform destructive file operations silently.
- Plugins MUST NOT get network, shell, or full filesystem access by default.
- Plugin runtime failures MUST NOT crash the main app if avoidable.

## Initial API Shape

```lua
commander.command("hello", function(ctx)
  commander.status("Hello from Lua")
end)

commander.key("ctrl-l", "hello")

commander.panel_provider("recent", function(ctx)
  return {
    title = "Recent",
    rows = {
      { name = "README.md", kind = "file", size = 1234 },
    }
  }
end)
```

## Recommended Phases

- Phase 1: Crystal `CommandRegistry` and built-in commands.
- Phase 2: read-only plugin manifest discovery.
- Phase 3: Lua host for simple commands, status messages, and panel snapshots.
- Phase 4: virtual panels and read-only file providers.
- Phase 5: mediated file operations and permission prompts.
- Phase 6: subprocess or WASM plugins for stronger sandboxing.

## Initial Permission Names

- `ui.status`: plugin may show status text through Commander API.
- `panel.read`: plugin may read panel snapshots.
- `panel.virtual`: plugin may provide virtual read-only panels.
- `filesystem.read`: plugin may request mediated file reads.
- `filesystem.write`: plugin may request mediated file writes after confirmation.
- `process.spawn`: plugin may request mediated subprocess execution.
- `network`: plugin may request mediated network access.

## Runtime Interface

- A plugin runtime MUST expose a narrow load/execute interface.
- Runtime `load` MUST NOT receive mutable Commander internals.
- Runtime `execute` MUST receive a `PluginRuntimeRequest` and return a `PluginRuntimeResponse`.
- Runtime requests/responses SHOULD be JSON-serializable to support embedded and subprocess runtimes.
- A runtime stub MAY report "not implemented" while preserving manifest discovery and command registration.
- Runtime dispatch MUST be selected by manifest runtime name.
- Runtime dispatch MUST have access to loaded plugin directory and resolved entrypoint metadata.
- Subprocess runtime MUST remain disabled until command protocol and permissions are explicit.
- Subprocess runtime MUST require an explicit enable gate before spawning external processes.
- Embedded Lua runtime MUST require an explicit enable gate until the safe API surface is implemented.

## Invariants

- Commands are the shared path for keyboard, menu, plugin, AppleScript, and debug control.
- Keymaps bind physical keys/modifiers to command IDs; they are not the owner of command behavior.
- Plugin APIs are versioned contracts.
- Manifest parsing is metadata-only; runtime initialization is a separate step.
- Placeholder plugin commands MUST NOT execute plugin code.
- Runtime entrypoints MUST be resolved relative to the plugin directory, not the process cwd.
- Missing runtime entrypoints MUST be reported before runtime initialization.
- Manifest load errors are plugin-local and MUST NOT prevent the core app from launching.
- Plugin state cannot be the canonical source of panel state unless it is a declared virtual panel provider.
- Disabling a plugin must leave the core commander usable.

## Checks

- A plugin command can update status without touching renderer internals.
- A plugin can read active panel snapshot without mutating it.
- Invalid plugin manifests are reported without executing plugin code.
- Duplicate plugin command IDs are reported before runtime initialization.
- A failing plugin command returns an error status and leaves the app running.
- Destructive plugin operations require explicit Commander mediation.
- Plugin hotkeys do not shadow core navigation unless explicitly configured.
