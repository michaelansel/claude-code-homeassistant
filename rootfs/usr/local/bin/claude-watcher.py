#!/usr/bin/env python3
"""
Claude Code watcher — keeps the agent registered as "watching" in c3po
and launches Claude sessions when messages arrive.
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone


def load_credentials(creds_file: str) -> dict:
    with open(creds_file) as f:
        return json.load(f)


def make_request(url: str, method: str = "GET", token: str = None,
                 data: bytes = None, timeout: int = 35,
                 extra_headers: dict = None) -> tuple[int, dict | None]:
    """Make an HTTP request. Returns (status_code, response_body_or_None)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if extra_headers:
        headers.update(extra_headers)
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
            try:
                return resp.status, json.loads(body)
            except json.JSONDecodeError:
                return resp.status, None
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body)
        except json.JSONDecodeError:
            return e.code, None


def register_agent(coordinator_url: str, token: str,
                   machine_name: str, project_name: str) -> str | None:
    """Register the agent. Returns the assigned agent ID (e.g. 'haos/homeassistant')."""
    status, body = make_request(
        f"{coordinator_url}/agent/api/register",
        method="POST",
        token=token,
        data=b"{}",
        timeout=15,
        extra_headers={
            "X-Machine-Name": machine_name,
            "X-Project-Name": project_name,
        },
    )
    if status in (200, 201):
        agent_id = body.get("id") if isinstance(body, dict) else None
        print(f"[watcher] Registered as '{agent_id}' (HTTP {status})", flush=True)
        return agent_id
    if status == 409:
        # Already registered — agent_id is still machine/project
        agent_id = f"{machine_name}/{project_name}"
        print(f"[watcher] Already registered as '{agent_id}' (HTTP 409)", flush=True)
        return agent_id
    print(f"[watcher] Register failed HTTP {status}: {body}", flush=True)
    return None


def enter_watching_state(coordinator_url: str, token: str, agent_id: str) -> bool:
    """Unregister with keep=true to enter watching state. Uses full assigned agent ID."""
    status, body = make_request(
        f"{coordinator_url}/agent/api/unregister?keep=true",
        method="POST",
        token=token,
        data=b"{}",
        timeout=15,
        extra_headers={"X-Machine-Name": agent_id},
    )
    if status in (200, 204):
        print(f"[watcher] Watching state set for '{agent_id}' (HTTP {status})", flush=True)
        return True
    print(f"[watcher] unregister(keep) failed HTTP {status}: {body}", flush=True)
    return False


def claim_watching_state(coordinator_url: str, token: str,
                         machine_name: str, project_name: str) -> str | None:
    """Register then immediately enter watching state. Returns assigned agent ID."""
    print("[watcher] Claiming watching state...", flush=True)
    agent_id = register_agent(coordinator_url, token, machine_name, project_name)
    if agent_id is None:
        return None
    enter_watching_state(coordinator_url, token, agent_id)
    return agent_id


def wait_for_message(coordinator_url: str, token: str, agent_id: str,
                     poll_timeout: int = 30) -> tuple:
    """Poll /agent/api/wait. Returns (status, messages) where status is
    'received', 'timeout', 'retry:N', or 'error', and messages is a list."""
    url = f"{coordinator_url}/agent/api/wait?timeout={poll_timeout}"
    try:
        status, body = make_request(url, token=token, timeout=poll_timeout + 10,
                                    extra_headers={"X-Machine-Name": agent_id})
        if status == 200 and isinstance(body, dict):
            s = body.get("status", "timeout")
            messages = body.get("messages", []) if s == "received" else []
            return s, messages
        if status == 429:
            retry_after = 5
            if isinstance(body, dict):
                retry_after = int(body.get("retry_after", 5))
            return f"retry:{retry_after}", []
        print(f"[watcher] Unexpected wait response HTTP {status}: {body}", flush=True)
        return "timeout", []
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        print(f"[watcher] Network error on wait: {e}", flush=True)
        return "error", []


DEFAULT_PROMPT = (
    "Process the c3po message(s) above. Reply using the c3po MCP reply tool "
    "with the message_id. When done, exit."
)


def format_messages_for_prompt(messages: list) -> str:
    """Format c3po messages as context for Claude's prompt."""
    if not messages:
        return ""
    lines = ["You have received the following c3po message(s):", ""]
    for msg in messages:
        from_agent = msg.get("from_agent", "unknown")
        content = msg.get("message", msg.get("content", ""))
        msg_id = msg.get("id", msg.get("message_id", ""))
        lines.append(f"From: {from_agent}")
        if msg_id:
            lines.append(f"Message-ID: {msg_id}")
        lines.append(f"Message: {content}")
        lines.append("")
    return "\n".join(lines)


def launch_session(work_dir: str, model_flag: str, prompt: str, session_dir: str,
                   env: dict, max_sessions: int, messages: list | None = None) -> None:
    """Launch a claude session, log output, prune old logs."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = os.path.join(session_dir, f"session-{ts}.log")

    # Build the full prompt: message context + task instructions
    base_prompt = prompt or DEFAULT_PROMPT
    if messages:
        msg_context = format_messages_for_prompt(messages)
        full_prompt = f"{msg_context}\n{base_prompt}"
    else:
        full_prompt = base_prompt

    cmd = ["claude", "--dangerously-skip-permissions"]
    if model_flag:
        cmd += model_flag.split()
    cmd += ["-p", full_prompt]

    print(f"[watcher] Launching session → {log_path}", flush=True)

    agent_id_file = "/run/claude-agent-id"
    session_env = {**env, "C3PO_AGENT_ID_FILE": agent_id_file}

    os.makedirs(session_dir, exist_ok=True)

    with open(log_path, "w") as log_f:
        log_f.write(f"# Session started {ts}\n# Command: {' '.join(cmd)}\n\n")
        log_f.flush()

        proc = subprocess.Popen(
            cmd,
            cwd=work_dir,
            env=session_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        for line in proc.stdout:
            sys.stdout.write(f"[session] {line}")
            sys.stdout.flush()
            log_f.write(line)
            log_f.flush()

        proc.wait()
        rc = proc.returncode
        log_f.write(f"\n# Session ended with exit code {rc}\n")

    print(f"[watcher] Session exited with code {rc}", flush=True)

    # Clean up agent ID file if present
    if os.path.exists(agent_id_file):
        try:
            os.unlink(agent_id_file)
        except OSError:
            pass

    prune_old_sessions(session_dir, max_sessions)


def prune_old_sessions(session_dir: str, max_sessions: int) -> None:
    """Keep only the most recent max_sessions log files."""
    logs = sorted(glob.glob(os.path.join(session_dir, "session-*.log")))
    excess = len(logs) - max_sessions
    if excess > 0:
        for old_log in logs[:excess]:
            try:
                os.unlink(old_log)
                print(f"[watcher] Pruned: {os.path.basename(old_log)}", flush=True)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description="Claude Code c3po watcher")
    parser.add_argument("--work-dir", default="/config", help="Working directory for Claude")
    parser.add_argument("--model-flag", default="", help="Model flag (e.g. '--model opus')")
    parser.add_argument("--prompt", default="", help="Prompt for Claude sessions (default: check c3po inbox and handle messages)")
    parser.add_argument("--session-dir", default="/data/sessions", help="Session log directory")
    parser.add_argument("--max-sessions", type=int, default=50, help="Max session logs to keep")
    parser.add_argument("--creds-file", default="/root/.claude/c3po-credentials.json",
                        help="Path to c3po credentials JSON")
    args = parser.parse_args()

    # Load credentials
    print(f"[watcher] Loading credentials from {args.creds_file}", flush=True)
    try:
        creds = load_credentials(args.creds_file)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[watcher] Fatal: cannot load credentials: {e}", flush=True)
        sys.exit(1)

    coordinator_url = creds.get("coordinator_url", "").rstrip("/")
    token = creds.get("api_token", "")
    if not coordinator_url or not token:
        print("[watcher] Fatal: credentials missing coordinator_url or api_token", flush=True)
        sys.exit(1)

    # Machine and project name come from env vars set by the run script
    machine_name = os.environ.get("C3PO_MACHINE_NAME", "").strip()
    project_name = os.environ.get("C3PO_PROJECT_NAME", "").strip()
    if not machine_name:
        print("[watcher] Fatal: C3PO_MACHINE_NAME env var not set", flush=True)
        sys.exit(1)
    if not project_name:
        print("[watcher] Fatal: C3PO_PROJECT_NAME env var not set", flush=True)
        sys.exit(1)

    print(f"[watcher] Coordinator: {coordinator_url}", flush=True)
    print(f"[watcher] Agent identity: {machine_name}/{project_name}", flush=True)

    # Build env for Claude sessions
    base_env = os.environ.copy()
    base_env["C3PO_KEEP_REGISTERED"] = "1"

    # Claim watching state and get assigned agent ID
    agent_id = claim_watching_state(coordinator_url, token, machine_name, project_name)
    if agent_id is None:
        print("[watcher] Fatal: failed to claim watching state", flush=True)
        sys.exit(1)

    print(f"[watcher] Entering poll loop (agent_id={agent_id})...", flush=True)

    while True:
        result, messages = wait_for_message(coordinator_url, token, agent_id)

        if result == "received":
            if messages:
                print(f"[watcher] {len(messages)} message(s) received, launching session...", flush=True)
            else:
                print("[watcher] Notified (no message content), launching session...", flush=True)
            # Re-register as active before launching
            agent_id = register_agent(coordinator_url, token, machine_name, project_name) or agent_id
            try:
                launch_session(
                    work_dir=args.work_dir,
                    model_flag=args.model_flag,
                    prompt=args.prompt,
                    session_dir=args.session_dir,
                    env=base_env,
                    max_sessions=args.max_sessions,
                    messages=messages,
                )
            except Exception as e:
                print(f"[watcher] Session error: {e}", flush=True)
            # Return to watching state
            agent_id = claim_watching_state(coordinator_url, token, machine_name, project_name) or agent_id

        elif result == "timeout":
            pass  # Normal poll timeout, loop immediately

        elif result.startswith("retry:"):
            try:
                delay = int(result.split(":")[1])
            except (IndexError, ValueError):
                delay = 5
            print(f"[watcher] Rate limited, sleeping {delay}s...", flush=True)
            time.sleep(delay)

        elif result == "error":
            print("[watcher] Network error, sleeping 10s before retry...", flush=True)
            time.sleep(10)
            try:
                agent_id = claim_watching_state(coordinator_url, token, machine_name, project_name) or agent_id
            except Exception as e:
                print(f"[watcher] Failed to reclaim watching state: {e}", flush=True)

        else:
            print(f"[watcher] Unknown wait result: {result!r}, sleeping 5s...", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
