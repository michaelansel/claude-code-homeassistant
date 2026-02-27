#!/usr/bin/env python3
"""
Mock c3po coordinator for local watcher testing.

Implements the endpoints used by claude-watcher.py:
  POST /agent/api/register
  POST /agent/api/unregister
  POST /agent/api/unregister?keep=true
  GET  /agent/api/wait

Usage:
  python3 tests/mock_coordinator.py [--port 9420] [--trigger-after N]

  --trigger-after N  Send a "received" response after N successful wait polls
                     (default: 3). Use 0 to trigger immediately.

The server prints all received requests to stdout so you can verify
the watcher is sending the right headers.
"""

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

API_TOKEN = "test-token"
MACHINE_NAME = "haos"
PROJECT_NAME = "homeassistant"
EXPECTED_AGENT_ID = f"{MACHINE_NAME}/{PROJECT_NAME}"

# Shared state
state = {
    "registered": False,
    "watching": False,
    "wait_polls": 0,
    "trigger_after": 3,
    "triggered": False,
    "errors": [],
}
state_lock = threading.Lock()


def check_auth(handler) -> bool:
    auth = handler.headers.get("Authorization", "")
    if auth != f"Bearer {API_TOKEN}":
        handler.send_error_json(401, f"Unauthorized: got {auth!r}")
        return False
    return True


def check_machine_header(handler, expected: str) -> bool:
    got = handler.headers.get("X-Machine-Name", "")
    if got != expected:
        msg = f"Wrong X-Machine-Name: expected {expected!r}, got {got!r}"
        with state_lock:
            state["errors"].append(msg)
        handler.send_error_json(400, msg)
        return False
    return True


class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress default access log

    def send_json(self, code: int, data: dict):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_error_json(self, code: int, error: str):
        print(f"  [mock] ERROR {code}: {error}")
        self.send_json(code, {"error": error})

    def read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length) if length else b""

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        self.read_body()

        machine = self.headers.get("X-Machine-Name", "")
        project = self.headers.get("X-Project-Name", "")
        print(f"  [mock] POST {self.path}  X-Machine-Name={machine!r}  X-Project-Name={project!r}", flush=True)

        if not check_auth(self):
            return

        if path == "/agent/api/register":
            # Expect X-Machine-Name=haos, X-Project-Name=homeassistant
            if not check_machine_header(self, MACHINE_NAME):
                return
            if project != PROJECT_NAME:
                msg = f"Wrong X-Project-Name: expected {PROJECT_NAME!r}, got {project!r}"
                with state_lock:
                    state["errors"].append(msg)
                self.send_error_json(400, msg)
                return
            with state_lock:
                state["registered"] = True
                state["watching"] = False
            self.send_json(200, {"id": EXPECTED_AGENT_ID, "status": "registered"})

        elif path == "/agent/api/unregister":
            keep = "keep" in query and query["keep"][0].lower() in ("true", "1")
            # Expect X-Machine-Name=haos/homeassistant (full agent ID)
            if not check_machine_header(self, EXPECTED_AGENT_ID):
                return
            with state_lock:
                if keep:
                    state["watching"] = True
                    state["registered"] = False
                else:
                    state["watching"] = False
                    state["registered"] = False
            action = "kept (watching)" if keep else "removed"
            self.send_json(200, {
                "status": "ok",
                "message": f"Agent '{EXPECTED_AGENT_ID}' {action}",
                "kept": keep,
            })

        else:
            self.send_error_json(404, f"Unknown path: {path}")

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)
        machine = self.headers.get("X-Machine-Name", "")
        print(f"  [mock] GET  {self.path}  X-Machine-Name={machine!r}", flush=True)

        if not check_auth(self):
            return

        if path == "/agent/api/wait":
            # Expect X-Machine-Name=haos/homeassistant
            if not check_machine_header(self, EXPECTED_AGENT_ID):
                return
            timeout = int(query.get("timeout", ["30"])[0])
            with state_lock:
                state["wait_polls"] += 1
                polls = state["wait_polls"]
                trigger_after = state["trigger_after"]
                already_triggered = state["triggered"]
                if polls > trigger_after and not already_triggered:
                    state["triggered"] = True
                    do_trigger = True
                else:
                    do_trigger = False

            if do_trigger:
                print(f"  [mock] Triggering session (poll #{polls})", flush=True)
                self.send_json(200, {"status": "received", "count": 1, "messages": [
                    {"id": "test-msg-1", "from_agent": "test-sender",
                     "message": "test trigger message"}
                ]})
            else:
                # Simulate a short wait then timeout
                wait_secs = min(timeout, 2)
                print(f"  [mock] Timing out after {wait_secs}s (poll #{polls})", flush=True)
                time.sleep(wait_secs)
                self.send_json(200, {"status": "timeout", "count": 0})

        else:
            self.send_error_json(404, f"Unknown path: {path}")


def run(port: int, trigger_after: int):
    with state_lock:
        state["trigger_after"] = trigger_after

    server = HTTPServer(("127.0.0.1", port), MockHandler)
    print(f"[mock] Coordinator listening on http://127.0.0.1:{port}")
    print(f"[mock] Token: {API_TOKEN!r}")
    print(f"[mock] Expected agent: {EXPECTED_AGENT_ID!r}")
    print(f"[mock] Will trigger after {trigger_after} wait poll(s)")
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    with state_lock:
        errs = state["errors"]
    if errs:
        print("\n[mock] ERRORS DETECTED:")
        for e in errs:
            print(f"  ✗ {e}")
        return 1
    else:
        print("\n[mock] No protocol errors detected.")
        return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Mock c3po coordinator")
    parser.add_argument("--port", type=int, default=9420)
    parser.add_argument("--trigger-after", type=int, default=3,
                        help="Send 'received' after this many wait polls")
    args = parser.parse_args()
    exit(run(args.port, args.trigger_after))
