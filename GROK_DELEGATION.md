# Grok Delegation Workflow

This repo can delegate implementation tasks to Grok over ACP while Codex keeps the
architect/reviewer role.

## Roles

- Codex: breaks work into bounded tasks, reviews diffs, runs verification.
- Grok: implements the assigned task in the working tree.
- Crystal/macOS app: remains the source of truth; do not commit from Grok.

## Run A Delegated Task

```bash
cd /Users/sergey/Projects/Crystal/commander
scripts/grok_acp_delegate.py "Implement <task> and report changed files"
```

The delegate uses `grok-build` explicitly:

```bash
grok agent -m grok-build stdio
```

For larger tasks:

```bash
scripts/grok_acp_delegate.py --task-file /tmp/grok-task.md
```

If you want Grok to run tools without permission prompts:

```bash
scripts/grok_acp_delegate.py --always-approve --task-file /tmp/grok-task.md
```

For diagnostics with shorter waits:

```bash
scripts/grok_acp_delegate.py --request-timeout 10 --prompt-timeout 20 "Reply exactly ACP_OK"
```

## Outputs

- `.grok-acp/last.ndjson`: raw ACP stream.
- `.grok-acp/last.transcript.md`: assistant text transcript.

Exit codes:

- `0`: Grok completed the turn.
- `3`: Grok returned an ACP/backend error.
- `124`: local ACP timeout.

## Current Local Finding

ACP stdio starts correctly with `grok-build`:

- `initialize` succeeds.
- `session/new` succeeds.
- `session/prompt` reaches Grok.

The current blocker is the backend response:

```text
HTTP 403: Grok Build is in early access.
Request URL: https://cli-chat-proxy.grok.com/v1/responses
```

The same error appears in headless mode with `grok -p`, so this is not specific to
the local ACP client.
