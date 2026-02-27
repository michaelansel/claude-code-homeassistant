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
import urllib.parse
import urllib.request
from datetime import datetime, timezone


def load_credentials(creds_file: str) -> dict:
    with open(creds_file) as f:
        return json.load(f)


def make_request(url: str, method: str = "GET", token: str = None,
                 data: bytes = None, timeout: int = 35,
                 machine_name: str = None) -> tuple[int, dict | None]:
    """Make an HTTP request. Returns (status_code, response_body_or_None)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if machine_name:
        headers["X-Machine-Name"] = machine_name
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


def claim_name(coordinator_url: str, token: str, machine_name: str) -> None:
    """Idempotent cold-start: register then unregister-with-keep to enter watching state."""
    print("[watcher] Claiming agent name (watching state)...", flush=True)

    # Register
    status, body = make_request(
        f"{coordinator_url}/agent/api/register",
        method="POST",
        token=token,
        data=b"{}",
        timeout=15,
        machine_name=machine_name,
    )
    if status not in (200, 201, 409):  # 409 = already registered, that's fine
        print(f"[watcher] Warning: register returned HTTP {status}: {body}", flush=True)
    else:
        print(f"[watcher] Registered (HTTP {status})", flush=True)

    # Unregister with keep=true → transitions to "watching" status
    status, body = make_request(
        f"{coordinator_url}/agent/api/unregister?keep=true",
        method="POST",
        token=token,
        data=b"{}",
        timeout=15,
        machine_name=machine_name,
    )
    if status not in (200, 204):
        print(f"[watcher] Warning: unregister(keep) returned HTTP {status}: {body}", flush=True)
    else:
        print(f"[watcher] Watching state set (HTTP {status})", flush=True)


def wait_for_message(coordinator_url: str, token: str, machine_name: str,
                     poll_timeout: int = 30) -> str:
    """Poll /agent/api/wait. Returns 'received', 'timeout', or 'retry:N'."""
    url = f"{coordinator_url}/agent/api/wait?timeout={poll_timeout}"
    try:
        status, body = make_request(url, token=token, timeout=poll_timeout + 10,
                                    machine_name=machine_name)
        if status == 200 and isinstance(body, dict):
            return body.get("status", "timeout")
        if status == 429:
            retry_after = 5
            if isinstance(body, dict):
                retry_after = int(body.get("retry_after", 5))
            return f"retry:{retry_after}"
        # Other non-200 but no exception
        print(f"[watcher] Unexpected wait response HTTP {status}: {body}", flush=True)
        return "timeout"
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        print(f"[watcher] Network error on wait: {e}", flush=True)
        return "error"


def launch_session(work_dir: str, model_flag: str, session_dir: str,
                   env: dict, max_sessions: int) -> None:
    """Launch a claude session, log output, prune old logs."""
    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    log_path = os.path.join(session_dir, f"session-{ts}.log")

    cmd = ["claude", "--dangerously-skip-permissions"]
    if model_flag:
        cmd += model_flag.split()
    cmd += ["-p", "/c3po auto"]

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

    # Read updated agent ID if available
    if os.path.exists(agent_id_file):
        try:
            with open(agent_id_file) as f:
                agent_id = f.read().strip()
            if agent_id:
                print(f"[watcher] Session agent ID: {agent_id}", flush=True)
            os.unlink(agent_id_file)
        except OSError:
            pass

    # Prune old session logs
    prune_old_sessions(session_dir, max_sessions)


def prune_old_sessions(session_dir: str, max_sessions: int) -> None:
    """Keep only the most recent max_sessions log files."""
    logs = sorted(glob.glob(os.path.join(session_dir, "session-*.log")))
    excess = len(logs) - max_sessions
    if excess > 0:
        for old_log in logs[:excess]:
            try:
                os.unlink(old_log)
                print(f"[watcher] Pruned old session log: {os.path.basename(old_log)}", flush=True)
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser(description="Claude Code c3po watcher")
    parser.add_argument("--work-dir", default="/config", help="Working directory for Claude")
    parser.add_argument("--model-flag", default="", help="Model flag (e.g. '--model opus')")
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

    # Machine name: prefer env var (set by run script), fall back to credentials agent_pattern
    machine_name = os.environ.get("C3PO_MACHINE_NAME", "")
    if not machine_name:
        agent_pattern = creds.get("agent_pattern", "")
        machine_name = agent_pattern.split("/")[0] if agent_pattern else ""
    if not machine_name:
        print("[watcher] Fatal: cannot determine machine name (set C3PO_MACHINE_NAME env var)", flush=True)
        sys.exit(1)

    print(f"[watcher] Coordinator: {coordinator_url}", flush=True)
    print(f"[watcher] Machine name: {machine_name}", flush=True)

    # Build env for Claude sessions (inherit current env + add session-specific vars)
    base_env = os.environ.copy()
    base_env["C3PO_KEEP_REGISTERED"] = "1"

    # Claim watching state
    claim_name(coordinator_url, token, machine_name)

    print("[watcher] Entering poll loop...", flush=True)

    while True:
        result = wait_for_message(coordinator_url, token, machine_name)

        if result == "received":
            print("[watcher] Message received, launching session...", flush=True)
            # Re-register as active before launching session
            make_request(f"{coordinator_url}/agent/api/register",
                         method="POST", token=token, data=b"{}", timeout=10,
                         machine_name=machine_name)
            try:
                launch_session(
                    work_dir=args.work_dir,
                    model_flag=args.model_flag,
                    session_dir=args.session_dir,
                    env=base_env,
                    max_sessions=args.max_sessions,
                )
            except Exception as e:
                print(f"[watcher] Session error: {e}", flush=True)
            # Return to watching state after session
            claim_name(coordinator_url, token, machine_name)

        elif result == "timeout":
            # Normal poll timeout, loop immediately
            pass

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
            # Try to re-enter watching state after network recovery
            try:
                claim_name(coordinator_url, token, machine_name)
            except Exception as e:
                print(f"[watcher] Failed to reclaim watching state: {e}", flush=True)

        else:
            print(f"[watcher] Unknown wait result: {result}, sleeping 5s...", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
