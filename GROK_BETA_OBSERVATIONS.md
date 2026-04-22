# Grok Beta Observations

Project: `/Users/sergey/Projects/Crystal/commander`

Date: 2026-04-21

Purpose: collect concrete Grok CLI / ACP / model behavior observed while using Grok as a worker agent for this repository. Do not store secrets, raw tokens, or credential-bearing URLs here.

## Observations

### 2026-04-21: entitlement outage surfaced consistently across transports

- Context: `grok-build` had worked earlier, then stopped responding for both Codex-driven automation and manual iTerm use.
- Affected transports:
  - `grok -p "..." --output-format json`
  - `grok agent -m grok-build stdio` via ACP
  - interactive `grok` TUI
  - interactive `grok` controlled through a pseudo-terminal
- Result: all reached the backend and returned HTTP 403 with `Grok Build is in early access`.
- Auth modes confirmed:
  - cached/OIDC auth from `~/.grok/auth.json`
  - API-key auth when `GROK_CODE_XAI_API_KEY` was explicitly set
- Assessment: local transport and auth loading were not the root cause; access/entitlement appeared to be toggled or unavailable server-side.

### 2026-04-21: access later recovered without local code/auth changes

- Context: later the same day, manual iTerm use of `grok` started completing again.
- ACP smoke with subscription/cached auth also recovered:
  - command shape: `env -u GROK_CODE_XAI_API_KEY -u XAI_API_KEY scripts/grok_acp_delegate.py "Reply exactly SUB_OK"`
  - result: `SUB_OK`, exit code 0.
- Assessment: supports the hypothesis that the earlier 403 was transient server-side entitlement/state, not local credential parsing.

### 2026-04-21: plain stdin pipe does not work for interactive TUI

- Command shape: `printf 'Reply exactly PIPE_OK\n' | grok`
- Result: `Error: Device not configured (os error 6)`.
- Assessment: expected for a TUI requiring a terminal device, but worth documenting because automation must use headless, ACP, or PTY rather than ordinary stdin/stdout pipes.

### 2026-04-21: PTY control of interactive TUI works but is transport-only

- Method: spawn `grok` in a pseudo-terminal, write prompt text, then send carriage return.
- Result: the TUI accepted and submitted the prompt.
- During the entitlement outage, the submitted turn still failed with the same backend 403.
- Assessment: PTY automation is viable as a fallback transport, but it does not bypass backend auth/entitlement state.

### 2026-04-21: ACP can emit very large single-line JSON-RPC messages

- Context: the first non-trivial ACP delegation asked Grok to inspect the Commander project and return an engineering plan.
- Failure in local delegator: Python `asyncio.StreamReader.readline()` raised `LimitOverrunError` because a JSON-RPC line exceeded the default stream buffer limit.
- Local mitigation: `scripts/grok_acp_delegate.py` now passes a larger subprocess stream `limit` and exposes `--stream-limit-mb`.
- Assessment: ACP clients should not assume small line-oriented messages. A robust client needs a larger read buffer or a custom newline reader that handles large JSON-RPC frames.

### 2026-04-21: ACP worker produced useful source-grounded project analysis

- Task: analyze next useful Commander improvement with bounded context.
- Result: Grok used tools to inspect project files and identified:
  - current FFI string pointer lifetime is likely safe because native code copies strings immediately;
  - cursor movement currently rebuilds panel rows and reloads the table unnecessarily;
  - a small `set_panel_cursor` ABI would improve responsiveness.
- Assessment: once access recovered, Grok was useful as a bounded codebase explorer/planner.

### 2026-04-21: ACP worker can implement bounded patches

- Task: implement cursor-only renderer update path with write scope limited to:
  - `src/commander_renderer.h`
  - `src/commander_renderer.mm`
  - `src/renderer.cr`
  - `src/commander.cr`
- Result: Grok reported successful edits in exactly that scope and did not run build/test/git commands.
- Follow-up needed: Codex review of the patch before claiming correctness.

### 2026-04-21: bounded worker respected scope, but AppKit nuance still needed review

- Context: Grok implemented `commander_renderer_set_panel_cursor` as a cursor-only native update.
- Positive behavior: respected the allowed write scope and avoided build/test/git commands as instructed.
- Review finding: cursor-only selection avoided full `reloadData`, but table cell text colors depend on `self.cursor` inside the AppKit cell renderer. Without targeted row reload, old/new selected rows could show stale foreground colors after cursor movement.
- Local mitigation: Codex added targeted `reloadDataForRowIndexes` for old and new cursor rows, preserving the no-full-reload intent.
- Assessment: good worker behavior for bounded code edits; still requires human/Codex review for GUI framework lifecycle details.

### 2026-04-21: ACP review task timed out after tool activity

- Context: a read-only review task asked Grok to inspect the new command layer and recommend next architecture steps.
- Result: Grok emitted many tool updates and then text saying it wanted to verify the build, but the ACP client timed out waiting for further stdout.
- Local issue found: `scripts/grok_acp_delegate.py` preserved a stale `last.transcript.md` from the previous successful run when a later prompt timed out before final completion.
- Local mitigation: transcript is now truncated at prompt start and appended incrementally as message chunks arrive.
- Assessment: Grok/model behavior may include long silent tool phases; local ACP clients need timeout handling that preserves partial current-run context and avoids stale transcript confusion.

### 2026-04-21: Grok reviewer found a real command-dispatch risk

- Context: Grok was asked to review `CommandRegistry`, `Keymap`, and snapshot layers without editing files or running build/test/git commands.
- Positive behavior: returned concise source-grounded feedback and identified that bare key bindings could match modified key presses, creating order-dependent shadowing.
- Local mitigation: Codex changed `Keymap#command_for` so modifier-specific bindings are tried before bare bindings, and bare bindings ignore command modifiers.
- Assessment: useful reviewer behavior for bounded static architecture tasks.

### 2026-04-21: instruction drift toward verification despite read-only/no-build request

- Context: a read-only ACP review task explicitly said not to run build/test/git commands.
- Observed behavior: Grok emitted "Let me verify the build compiles cleanly..." before the task timed out. The transcript did not show a completed build result, but intent drifted toward a disallowed verification action.
- Assessment: for Grok worker tasks, prompts should restate "do not run build/test/git" near the end and wrappers should avoid granting terminal permissions unless execution is intended.

### 2026-04-21: separated read-only review and bounded worker wrappers

- Context: manual ACP calls were easy to vary accidentally in auth, timeout, approval mode, and task expectations.
- Local mitigation: added `scripts/grok_review` for read-only tasks and `scripts/grok_worker` for bounded edit tasks. Both unset API-key env vars to prefer subscription/default auth.
- Assessment: wrapper separation should reduce accidental permission drift and make beta issues easier to reproduce.

## Open questions for xAI / Grok team

- Is the `Grok Build is in early access` 403 expected to appear transiently for beta users who previously had access?
- Can the CLI expose a clearer distinction between invalid credentials, expired subscription/session, and server-side entitlement gating?
- Can ACP documentation mention expected maximum JSON-RPC message sizes or recommend client stream buffer settings?
- Should interactive TUI support non-TTY stdin gracefully, or explicitly document that plain pipes are unsupported?
