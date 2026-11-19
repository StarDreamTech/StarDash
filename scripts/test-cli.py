#!/usr/bin/env python3
"""Exercise the bundled CLI against the real app; restore settings and our own test shortcut."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "build/StarDash.app/Contents/Resources/stardash-cli"


def call(*args, ok=True, env=None):
    result = subprocess.run([str(CLI), *args], capture_output=True, text=True, timeout=15, env=env)
    payload = json.loads(result.stdout)
    assert payload["ok"] is ok, (args, payload, result.stderr)
    assert result.returncode == (0 if ok else 1), (args, result.returncode)
    return payload


def wait_for(predicate, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = call("status")
        if predicate(value):
            return value
        time.sleep(0.3)
    raise AssertionError("StarDash did not reach the expected state")


def main():
    assert call("version")["version"] == "0.3.0"
    before = call("status")
    call("awake", "start", "--minutes", "0", ok=False)
    assert call("status")["running"] == before["running"], "Invalid requests must not launch the app"
    assert call("metrics")["metrics"]["memory"]["total"] > 0
    with tempfile.TemporaryDirectory(prefix="StarDash-CLI-") as directory:
        root = Path(directory)
        link = root / "stardash"
        link.symlink_to(CLI)
        linked = subprocess.run([str(link), "version"], capture_output=True, text=True, timeout=10)
        assert json.loads(linked.stdout)["version"] == "0.3.0", "Symlink entry must resolve to the app binary"
        env = dict(os.environ, CODEX_HOME=str(root / "codex"))
        installed = call("skill", "install", "codex", env=env)
        assert installed["changed"] is True
        assert call("skill", "install", "codex", env=env)["changed"] is False
        target = Path(installed["path"])
        target.write_text("existing user skill", encoding="utf-8")
        call("skill", "install", "codex", ok=False, env=env)
        assert target.read_text() == "existing user skill", "A different skill must not be overwritten"

    settings = call("settings", "get")["settings"]
    command_id = None
    awake_started = False
    try:
        state = call("status")
        call("settings", "set", "compact", str(not settings["compact"]).lower())
        assert call("settings", "get")["settings"]["compact"] is not settings["compact"]
        raw = "printf '%s\\n' \"it's fine\" '中文' '$HOME $(exit 9)'\npwd"
        command = call("commands", "add", "--name", "--json", "--command", raw)["command"]
        command_id = command["id"]
        assert command["name"] == "--json" and command["command"] == raw
        assert any(item["id"] == command_id for item in call("commands", "list")["commands"])
        edited = call("commands", "edit", command_id, "--name", "CLI 验证条目")["command"]
        assert edited["name"] == "CLI 验证条目" and edited["command"] == raw
        with tempfile.TemporaryDirectory(prefix="StarDash-Terminal-") as directory:
            output = Path(directory) / "result.txt"
            expected = "CLI OK 中文 ' $HOME $(exit 9)"
            shell = "printf '%s\\n' " + shlex.quote(expected) + " > " + shlex.quote(str(output))
            call("commands", "edit", command_id, "--command", shell)
            assert call("commands", "run", command_id)["accepted"] is True
            deadline = time.monotonic() + 10
            while not output.exists() and time.monotonic() < deadline:
                time.sleep(0.2)
            assert output.read_text().strip() == expected, "Terminal must execute the exact saved command"
        call("commands", "remove", "00000000-0000-0000-0000-000000000000", ok=False)
        if not state["awake"]["active"]:
            assert call("awake", "start", "--minutes", "1")["active"] is True
            awake_started = True
            call("awake", "start", "--minutes", "1", ok=False)
            assert call("status")["awake"]["active"] is True
            assert call("awake", "stop")["active"] is False
            awake_started = False
        call("startup", "status")
        call("update", "install", ok=False)  # Source builds must not modify a Homebrew installation.
        call("update", "check")
        checked = wait_for(lambda value: value["update"]["state"] != "checking")
        assert checked["update"]["state"] in ("current", "available", "unpublished"), checked["update"]
        assert call("status")["pid"] == state["pid"]
    finally:
        if awake_started:
            call("awake", "stop")
        if command_id:
            call("commands", "remove", command_id)
        call("settings", "set", "compact", str(settings["compact"]).lower())

    # Restart only our newly started app, never interrupt an existing keep-awake task.
    if not before["running"]:
        old = call("status")
        call("restart")
        new = wait_for(lambda value: value.get("running") and value["pid"] != old["pid"])
        assert new["version"] == "0.3.0"
        assert new["settings"] == settings
        assert all(item["id"] != command_id for item in call("commands", "list")["commands"])
        call("quit")
        wait_for(lambda value: not value["running"])
    print("PASS: bundled/symlink CLI, JSON/errors, offline reads, live IPC, settings, shortcuts with real Terminal execution, keep-awake, update checks, skill install/conflict protection and restart/quit")


if __name__ == "__main__":
    main()
