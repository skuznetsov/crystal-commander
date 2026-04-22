#!/usr/bin/env python3
import argparse
import asyncio
import json
import os
import sys
from pathlib import Path


class GrokACP:
    def __init__(
        self,
        cwd: Path,
        model: str,
        always_approve: bool,
        request_timeout: int,
        prompt_timeout: int,
        stream_limit: int,
    ):
        self.cwd = cwd
        self.model = model
        self.always_approve = always_approve
        self.request_timeout = request_timeout
        self.prompt_timeout = prompt_timeout
        self.stream_limit = stream_limit
        self.proc = None
        self.next_id = 1
        self.session_id = None

    async def start(self):
        args = ["grok", "agent"]
        if self.always_approve:
            args.append("--always-approve")
        if self.model:
            args.extend(["-m", self.model])
        args.append("stdio")
        print(f"[grok-acp] starting: {' '.join(args)}", file=sys.stderr)

        self.proc = await asyncio.create_subprocess_exec(
            *args,
            cwd=str(self.cwd),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            limit=self.stream_limit,
        )

        await self.request(
            "initialize",
            {
                "protocolVersion": "1",
                "clientCapabilities": {
                    "fs": {"readTextFile": False, "writeTextFile": False},
                    "terminal": False,
                },
            },
        )
        result = await self.request("session/new", {"cwd": str(self.cwd), "mcpServers": []})
        self.session_id = result["sessionId"]

    async def stop(self):
        if not self.proc:
            return
        if self.proc.returncode is None:
            self.proc.terminate()
            try:
                await asyncio.wait_for(self.proc.wait(), timeout=3)
            except asyncio.TimeoutError:
                self.proc.kill()

    async def request(self, method: str, params: dict):
        request_id = self.next_id
        self.next_id += 1
        await self.write({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})

        while True:
            msg = await self.read_message(timeout=self.request_timeout)
            if msg.get("id") == request_id:
                if "error" in msg:
                    raise RuntimeError(msg["error"].get("message", json.dumps(msg["error"])))
                return msg.get("result", {})

    async def prompt(self, text: str, ndjson_path: Path, transcript_path: Path) -> int:
        request_id = self.next_id
        self.next_id += 1
        await self.write(
            {
                "jsonrpc": "2.0",
                "id": request_id,
                "method": "session/prompt",
                "params": {
                    "sessionId": self.session_id,
                    "prompt": [{"type": "text", "text": text}],
                },
            }
        )

        transcript = []
        ndjson_path.parent.mkdir(parents=True, exist_ok=True)
        transcript_path.parent.mkdir(parents=True, exist_ok=True)
        transcript_path.write_text("", encoding="utf-8")

        with ndjson_path.open("w", encoding="utf-8") as ndjson:
            while True:
                msg = await self.read_message(timeout=self.prompt_timeout)
                ndjson.write(json.dumps(msg, ensure_ascii=False) + "\n")
                ndjson.flush()

                if msg.get("method") in ("session/update", "x.ai/session/update"):
                    update = msg.get("params", {}).get("update", {})
                    kind = update.get("sessionUpdate")
                    if kind == "agent_message_chunk":
                        chunk = update.get("content", {}).get("text", "")
                        transcript.append(chunk)
                        with transcript_path.open("a", encoding="utf-8") as transcript_file:
                            transcript_file.write(chunk)
                        print(chunk, end="", flush=True)
                    elif kind == "tool_call":
                        tool = update.get("tool") or update.get("name") or update.get("title") or update.get("id") or "tool"
                        print(f"\n[tool] {tool}", flush=True)
                    elif kind == "plan":
                        print(f"\n[plan] {json.dumps(update.get('entries', []), ensure_ascii=False)}", flush=True)
                    continue

                if msg.get("method") == "_x.ai/session_notification":
                    update = msg.get("params", {}).get("update", {})
                    if update.get("sessionUpdate") == "retry_state" and update.get("type") == "failed":
                        message = update.get("message", "Grok request failed")
                        print(f"\n[grok-error] {message}", file=sys.stderr)
                    continue

                if msg.get("id") == request_id:
                    if "error" in msg:
                        message = msg["error"].get("data") or msg["error"].get("message") or json.dumps(msg["error"])
                        transcript_path.write_text("".join(transcript), encoding="utf-8")
                        print(f"\n[grok-error] {message}", file=sys.stderr)
                        return 3
                    transcript_path.write_text("".join(transcript), encoding="utf-8")
                    return 0

    async def write(self, msg: dict):
        assert self.proc and self.proc.stdin
        self.proc.stdin.write((json.dumps(msg) + "\n").encode("utf-8"))
        await self.proc.stdin.drain()

    async def read_message(self, timeout: int):
        assert self.proc and self.proc.stdout
        try:
            line = await asyncio.wait_for(self.proc.stdout.readline(), timeout=timeout)
        except asyncio.TimeoutError as exc:
            raise TimeoutError(f"Grok ACP timed out after {timeout}s waiting for stdout") from exc
        if not line:
            stderr = b""
            if self.proc.stderr:
                stderr = await self.proc.stderr.read()
            raise RuntimeError(f"Grok ACP closed stdout. stderr={stderr.decode(errors='replace')}")
        return json.loads(line)


def task_text(args) -> str:
    if args.task_file:
        task = Path(args.task_file).read_text(encoding="utf-8")
    else:
        task = args.task

    return f"""You are a worker agent in this repository.

Task:
{task}

Working rules:
- Edit files directly when the task asks for implementation.
- Do not commit, push, rebase, or delete unrelated files.
- Keep changes scoped to the task.
- At the end, report changed paths, commands run, and remaining risks.
"""


async def amain() -> int:
    parser = argparse.ArgumentParser(description="Delegate one task to Grok over ACP stdio.")
    parser.add_argument("task", nargs="?", help="Task text. Use --task-file for larger tasks.")
    parser.add_argument("--task-file", help="Read task text from a file.")
    parser.add_argument("--cwd", default=os.getcwd(), help="Repository working directory.")
    parser.add_argument("--model", default="grok-build", help="Grok model id. Default: grok-build.")
    parser.add_argument("--always-approve", action="store_true", help="Let Grok execute tools without permission prompts.")
    parser.add_argument("--out-dir", default=".grok-acp", help="Directory for ACP logs.")
    parser.add_argument("--request-timeout", type=int, default=30, help="Seconds to wait for initialize/session responses.")
    parser.add_argument("--prompt-timeout", type=int, default=120, help="Seconds to wait for each prompt stream message.")
    parser.add_argument("--stream-limit-mb", type=int, default=16, help="ACP stdout/stderr stream buffer limit in MiB.")
    args = parser.parse_args()

    if not args.task and not args.task_file:
        parser.error("provide task text or --task-file")

    cwd = Path(args.cwd).resolve()
    out_dir = cwd / args.out_dir
    client = GrokACP(
        cwd=cwd,
        model=args.model,
        always_approve=args.always_approve,
        request_timeout=args.request_timeout,
        prompt_timeout=args.prompt_timeout,
        stream_limit=args.stream_limit_mb * 1024 * 1024,
    )

    try:
        await client.start()
        return await client.prompt(
            task_text(args),
            ndjson_path=out_dir / "last.ndjson",
            transcript_path=out_dir / "last.transcript.md",
        )
    except TimeoutError as exc:
        print(f"[grok-timeout] {exc}", file=sys.stderr)
        return 124
    finally:
        await client.stop()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(amain()))
