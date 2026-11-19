"""The plugin's hook script, run as Claude Code runs it, against a fake Vyavastha server.

Each test feeds the script the JSON Claude Code sends a hook on stdin, in a real git repository, with its home
folder and server set by environment, and reads what it prints and what it sent. Run with:

    python3 -m pytest tests -q

Every test runs under each POSIX shell this machine has of sh and dash (Ubuntu's sh is dash).
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import stat
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import pytest

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "vyavastha"
SCRIPT = PLUGIN / "scripts" / "vyavastha.sh"
SHELLS = [shell for shell in ("sh", "dash") if shutil.which(shell)]
TOKEN = "vyv-tool-secret-token-value"
SECRET = "THE-FILE-CONTENTS-NEVER-LEAVE"
# What the server answers when code sharing is turned on or off, as it words it.
SHARING_ON = ("Code sharing is on for acme/api. Teammates never see your code, only a short summary of the work. "
              "What was sent is deleted when the work ends, and after 7 days at most.")
SHARING_OFF = "Code sharing is off for acme/api. Nothing more of your code is sent, and what was kept of it has been deleted."
COMMANDS = ["on", "off", "status", "check", "settings", "help", "sign-in", "sign-out", "share-code-on",
            "share-code-off", "summaries-on", "summaries-off", "shared", "chat", "upload", "inbox"]


class Fake:
    """A Vyavastha server: answers the plugin's calls from what a test sets, and keeps every request."""

    def __init__(self) -> None:
        self.requests: list[dict] = []
        self.check = {"verdict": "clear", "hold": False, "notice": "Checked: nothing stands against this change.",
                      "context": "Vyavastha checked this request: nothing stands against it.", "statements": []}
        self.asked = {"status": "answered", "answer": "Priya is changing calc.py — “the export stays”.",
                      "context": "Vyavastha’s assistant answered this message from the team’s record:\n\nPriya is "
                                 "changing calc.py — “the export stays”.\n\nGive the developer this answer in full.",
                      "notice": "Answered from your team’s record by Vyavastha.", "conversation_id": "cnv_1",
                      "url": "http://127.0.0.1/c/cnv_1"}
        self.slow = 0
        self.approved = False
        self.status: dict[str, int] = {}
        # What the newer routes answer.
        self.latest = "0.4.0"
        self.minimum = "0.3.0"
        self.sharing: set[str] = set()
        self.extra: dict[str, dict] = {}
        self.shared = {"items": [], "chat_url": None, "sharing": False,
                       "kept": "Vyavastha keeps this list for 30 days."}
        self.inbox: list[dict] = []
        self.tell = {"status": "answered", "to": {"name": "Priya Raman"}, "from": {"name": "Sam Rivera"},
                     "at_said": "18 Nov, 10:42", "text": "", "answer": "Priya is moving the export to v2.",
                     "answer_at_said": "18 Nov, 10:43", "notice": "Priya sees what you asked and this answer.",
                     "url": "http://127.0.0.1/?agent-chat=usr_p", "waiting": None, "people": []}
        self.tell_slow = 0
        # Seconds a route takes to answer.
        self.delay: dict[str, float] = {}
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args) -> None:
                pass

            def _answer(self, status: int, body: dict) -> None:
                data = json.dumps(body).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def _handle(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                parts = urlsplit(self.path.removeprefix("/api/v1/plugin"))
                path = parts.path
                body = json.loads(raw) if raw else None
                fake.requests.append({"method": self.command, "path": path, "query": parse_qs(parts.query),
                                      "headers": dict(self.headers), "raw": raw, "body": body})
                if path in fake.delay:
                    time.sleep(fake.delay[path])
                if path in fake.status:
                    return self._answer(fake.status[path], {"detail": {"code": "x", "message": "Refused."}})
                signed = self.headers.get("Authorization") == f"Bearer {TOKEN}"
                if path == "/hello":
                    return self._answer(200, {"ok": True, "latest": fake.latest, "minimum": fake.minimum})
                if path == "/pair":
                    return self._answer(201, {"device_code": "device-secret", "user_code": "BCDF-GHJK",
                                              "verification_url": "http://127.0.0.1/connect", "expires_in": 600,
                                              "interval": 3})
                if path == "/token":
                    if not fake.approved:
                        return self._answer(202, {"status": "pending"})
                    return self._answer(200, {"token": TOKEN, "email": "sam@acme.test", "workspace": "Acme",
                                              "machine": "laptop"})
                if not signed:
                    return self._answer(401, {"detail": {"code": "signed_out", "message": "Ended."}})
                if path == "/me":
                    return self._answer(200, {"email": "sam@acme.test", "machine": "laptop",
                                              "workspace": {"workspace_id": "w", "name": "Acme"},
                                              "repositories": ["acme/api"],
                                              "plugin": {"latest": fake.latest, "minimum": fake.minimum},
                                              "limits": {"change_lines": 5000, "change_bytes": 600000},
                                              "sharing": sorted(fake.sharing), "admin": False})
                if path == "/sharing":
                    (fake.sharing.add if body["on"] else fake.sharing.discard)("acme/api")
                    return self._answer(200, {"on": body["on"], "repository": "acme/api",
                                              "notice": SHARING_ON if body["on"] else SHARING_OFF})
                if path in ("/check", "/work"):
                    answer = dict(fake.check) if path == "/check" else {}
                    if path == "/check":
                        # The words are kept for the summary when asked, unless the message goes on as a question.
                        answer["kept"] = bool(body.get("keep")) and answer.get("ask") is not True
                        if answer["kept"]:
                            # Each kept message has its own id, named by the check that kept it.
                            answer["kept_id"] = f"msg_{len(fake.calls('/check'))}"
                    if path == "/work":
                        state = body["state"]
                        answer = {"recorded": True, "work_id": "wrk_1", "changed": True,
                                  "status": {"changing": "local"}.get(state, state)}
                    if "change" in body:
                        answer["sharing"] = "on" if "acme/api" in fake.sharing else "off"
                    answer.update(fake.extra.get(path, {}))
                    return self._answer(200, answer)
                if path == "/ask":
                    # (An answer that is slow is still being made on the first calls for it.)
                    if fake.slow > 0 and len(fake.calls("/ask")) <= fake.slow:
                        return self._answer(200, {"status": "pending", "answer": "", "context": "", "notice":
                                                  "Vyavastha is still working on the answer.", "waiting": "msg_9"})
                    return self._answer(200, fake.asked)
                if path == "/turn":
                    return self._answer(200, {"kept": bool(body["keep"]), "url": "http://127.0.0.1/c/cnv_7"})
                if path == "/conflict":
                    return self._answer(200, {"ok": True})
                if path == "/chat":
                    if "/chat" in fake.extra:
                        return self._answer(200, fake.extra["/chat"])
                    return self._answer(200, {"url": "http://127.0.0.1/c/cnv_7",
                                              "upload_url": "http://127.0.0.1/c/cnv_7?attach=1",
                                              "conversation_id": "cnv_7"})
                if path == "/shared":
                    return self._answer(200, fake.shared)
                if path == "/inbox":
                    return self._answer(200, {"items": fake.inbox, "count": len(fake.inbox)})
                if path == "/tell":
                    if fake.tell_slow > 0 and len(fake.calls("/tell")) <= fake.tell_slow:
                        return self._answer(200, {**fake.tell, "status": "pending", "answer": "",
                                                  "waiting": "pmsg_4"})
                    return self._answer(200, {**fake.tell, "text": fake.tell["text"] or body["text"]})
                if path == "/task":
                    return self._answer(200, {"ok": True, "text": "Move the export to the v2 format.",
                                              "from": {"name": "Helen Ortiz"}, "state": body["state"]})
                if path == "/signout":
                    return self._answer(200, {"ok": True})
                return self._answer(404, {"detail": {"code": "not_found", "message": "No."}})

            do_GET = do_POST = _handle

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def calls(self, path: str) -> list[dict]:
        return [request for request in self.requests if request["path"] == path]


@pytest.fixture()
def fake():
    server = Fake()
    yield server
    server.server.shutdown()


def git(folder: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(folder), *args], check=True, capture_output=True, text=True,
                          env={**os.environ, "GIT_AUTHOR_NAME": "Sam", "GIT_AUTHOR_EMAIL": "sam@acme.test",
                               "GIT_COMMITTER_NAME": "Sam", "GIT_COMMITTER_EMAIL": "sam@acme.test"}).stdout


@pytest.fixture()
def repo(tmp_path: Path) -> Path:
    folder = tmp_path / "api"
    folder.mkdir()
    git(folder, "init", "-q", "--initial-branch=main")
    (folder / "calc.py").write_text("def add(a, b):\n    return a + b\n")
    (folder / "old.py").write_text("x = 1\n")
    (folder / "gone.py").write_text("y = 2\n")
    git(folder, "add", "--all")
    git(folder, "commit", "-q", "-m", "Initial")
    # A remote URL that carries a credential, as some do: it must never leave the computer.
    git(folder, "remote", "add", "origin", "https://sam:ghp_hunter2@github.com/acme/api.git")
    return folder


@pytest.fixture(params=SHELLS)
def run(request, tmp_path: Path, fake: Fake):
    """Runs the script under one shell, as Claude Code does: ``run("hook", "prompt", stdin={...})``."""
    home = tmp_path / "home"
    opened = tmp_path / "opened.txt"
    browser = tmp_path / "browser.sh"
    # Pages the script opens are written down instead of opened.
    browser.write_text(f'#!/bin/sh\nprintf "%s\\n" "$1" >> "{opened}"\n')
    browser.chmod(0o755)

    def run_(*args: str, stdin: dict | None = None, server: str | None = None, cwd: Path | None = None,
             tool: str | None = None, extra: dict | None = None, raw: bytes | None = None):
        env = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), "VYAVASTHA_HOME": str(home),
               "VYAVASTHA_SERVER": server or fake.url, "CLAUDE_PROJECT_DIR": str(cwd or tmp_path),
               "VYAVASTHA_BROWSER": str(browser), **(extra or {})}
        if tool:
            # As Codex's hooks file sets it; Claude Code's sets nothing.
            env["VYAVASTHA_TOOL"] = tool
        started = time.monotonic()
        if raw is not None:
            # Bytes as they are, which may not be UTF-8: what is printed must still be.
            done = subprocess.run([request.param, str(SCRIPT), *args], input=raw, capture_output=True, env=env,
                                  cwd=cwd or tmp_path, timeout=60)
            done.stdout, done.stderr = done.stdout.decode("utf-8"), done.stderr.decode("utf-8")
        else:
            done = subprocess.run([request.param, str(SCRIPT), *args], input=json.dumps(stdin) if stdin else "",
                                  capture_output=True, text=True, env=env, cwd=cwd or tmp_path, timeout=60)
        done.seconds = time.monotonic() - started
        assert done.returncode == 0, done.stderr
        # Nothing the script runs ever writes to its error output.
        assert done.stderr == "", done.stderr
        return done

    run_.home = home
    run_.opened = lambda: opened.read_text().split() if opened.exists() else []
    return run_


def output(done) -> dict:
    """What the hook printed, which Claude Code reads as one JSON object."""
    return json.loads(done.stdout) if done.stdout.strip() else {}


def event(name: str, repo: Path, session: str = "session-1", **fields) -> dict:
    """A hook's input as Claude Code sends it, transcript path and all."""
    return {"session_id": session, "transcript_path": "/home/sam/.claude/projects/x/transcript.jsonl",
            "cwd": str(repo), "permission_mode": "default", "hook_event_name": name, **fields}


def prompt(run, repo: Path, text: str, session: str = "session-1", **kwargs) -> dict:
    return output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, session=session, prompt=text),
                      cwd=kwargs.pop("cwd", repo), **kwargs))


def signed_in(run, fake: Fake) -> None:
    run.home.mkdir(parents=True, exist_ok=True)
    (run.home / "credentials").write_text(f"server={fake.url}\ntoken={TOKEN}\nemail=sam@acme.test\nworkspace=Acme\n")


def switched_on(run, fake: Fake, folder: Path) -> None:
    """The developer sends “vyavastha on” in a project, as they must before the plugin does anything there."""
    run("on", cwd=folder)
    fake.requests.clear()
    # A sign-in it started is left as if it ran out, so each test starts from a plain state.
    (run.home / "pairing").unlink(missing_ok=True)
    opened = run.home.parent / "opened.txt"
    if opened.exists():
        opened.unlink()


def sharing_on(run, fake: Fake, folder: Path) -> None:
    run("share-code", "on", cwd=folder)
    fake.requests.clear()


# -- on and off ------------------------------------------------------------------------------------------------------

def test_off_by_default_every_hook_does_nothing_and_the_first_session_says_so_once_on_this_computer(run, fake, repo):
    signed_in(run, fake)
    first = output(run("hook", "session-start", stdin=event("SessionStart", repo)))
    assert first == {"systemMessage": "Vyavastha is installed and off in this project. Send “vyavastha on” to use "
                                      "it here."}
    assert output(run("hook", "session-start", stdin=event("SessionStart", repo, session="s2"))) == {}
    (repo / "calc.py").write_text("changed\n")
    for name, kind in (("prompt", "UserPromptSubmit"), ("edited", "PostToolUse"), ("stopped", "Stop"),
                       ("edit-check", "PostToolUse")):
        done = run("hook", name, stdin=event(kind, repo, prompt="Change calc.py", tool_name="Edit"))
        assert done.stdout == ""
    assert fake.requests == []


def test_on_while_signed_in_says_who_what_is_read_and_that_sharing_is_off(run, fake, repo):
    signed_in(run, fake)
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Vyavastha on.")))
    assert said["decision"] == "block" and said["hookSpecificOutput"]["suppressOriginalPrompt"] is True
    reason = said["reason"]
    assert reason.startswith(f"Vyavastha is on for api ({repo}).")
    assert "Signed in as sam@acme.test in Acme." in reason
    assert "Vyavastha reads acme/api for you" in reason
    assert "Code sharing is off" in reason and "“vyavastha share code on”" in reason
    assert "“vyavastha help”" in reason and not fake.calls("/check")
    # From now on, messages here are checked.
    prompt(run, repo, "Change calc.py")
    assert fake.calls("/check")
    off = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha off")))
    assert off["reason"].startswith("Vyavastha is off for api")
    fake.requests.clear()
    assert prompt(run, repo, "Change calc.py") == {} and fake.requests == []


def test_on_while_signed_out_starts_signing_in_in_the_same_answer(run, fake, repo):
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on")))
    assert "enter the code BCDF-GHJK" in said["reason"] and "device-secret" not in said["reason"]
    assert run.opened() == ["http://127.0.0.1/connect"]
    fake.approved = True
    status = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha status")))
    assert "connected as sam@acme.test" in status["reason"] and "Vyavastha is on in this project" in status["reason"]


def test_commands_are_answered_while_the_plugin_is_off(run, fake, repo):
    signed_in(run, fake)
    for typed in ("vyavastha status", "vyavastha help", "vyavastha settings"):
        said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=typed)))
        assert said["decision"] == "block" and said["reason"]
    assert "Vyavastha is off in this project" in output(run("hook", "prompt", stdin=event(
        "UserPromptSubmit", repo, prompt="vyavastha status")))["reason"]
    assert not fake.calls("/check")


# -- signing in ---------------------------------------------------------------------------------------------------

def test_signing_in_shows_the_code_and_address_then_finishes_once_approved_and_keeps_the_token_to_its_owner(
        run, fake, repo):
    started = run("sign-in", cwd=repo)
    assert "BCDF-GHJK" in started.stdout and "http://127.0.0.1/connect" in started.stdout
    assert "device-secret" not in started.stdout
    assert fake.calls("/pair")[0]["body"]["machine"]
    # Not approved yet: status says it waits.
    assert "Waiting for you to approve" in run("status", cwd=repo).stdout
    fake.approved = True
    status = run("status", cwd=repo)
    assert "connected as sam@acme.test in Acme" in status.stdout and TOKEN not in status.stdout
    assert "Vyavastha reads acme/api for you: requests here are checked, and teammates see which files you’re " \
           "changing." in status.stdout
    credentials = run.home / "credentials"
    assert TOKEN in credentials.read_text()
    assert stat.S_IMODE(credentials.stat().st_mode) == 0o600 and stat.S_IMODE(run.home.stat().st_mode) == 0o700
    assert not (run.home / "pairing").exists()
    # The token goes in a header, and is never written anywhere else.
    assert fake.calls("/me")[-1]["headers"]["Authorization"] == f"Bearer {TOKEN}"


def test_the_first_message_while_signed_out_opens_sign_in_by_itself_once_a_session(run, fake, repo):
    switched_on(run, fake, repo)
    fake.requests.clear()
    first = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert first.startswith("Vyavastha · nothing sent (you aren’t signed in) · The sign-in page is open")
    assert first.endswith("Once you approve, your next message finishes connecting.")
    assert "enter the code BCDF-GHJK" in first and run.opened() == ["http://127.0.0.1/connect"]
    second = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert "Enter the code BCDF-GHJK" in second and run.opened() == ["http://127.0.0.1/connect"]
    assert len(fake.calls("/pair")) == 1 and not fake.calls("/check")
    # Approved in the browser: the next message finishes connecting and is checked, and says so.
    fake.approved = True
    said = prompt(run, repo, "Make the trial 30 days in calc.py")["systemMessage"]
    assert "Connected as sam@acme.test in Acme." in said and fake.calls("/check")


def test_signing_out_ends_the_token_on_the_server_and_forgets_it(run, fake, repo):
    signed_in(run, fake)
    assert "Signed out" in run("sign-out", cwd=repo).stdout
    assert fake.calls("/signout") and not (run.home / "credentials").exists()


def test_a_token_is_never_sent_to_a_server_other_than_the_one_that_gave_it(run, fake, repo, tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    other = Fake()
    try:
        run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"), server=other.url)
        assert other.requests and all("Authorization" not in request["headers"] for request in other.requests)
    finally:
        other.server.shutdown()


def test_a_server_address_that_is_not_https_or_this_computer_is_refused_without_a_call(run, fake, repo):
    done = run("status", server="http://vyavasta.example", cwd=repo)
    assert "isn’t one this plugin uses" in done.stdout and fake.requests == []


# -- the check before Claude changes code ---------------------------------------------------------------------

def test_a_clear_request_reaches_claude_with_the_facts_and_sends_only_what_the_check_needs(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    text = 'Rename "add" to sum\\plus in calc.py — keep the façade 👍\nand the tests'
    said = prompt(run, repo, text)
    assert said["hookSpecificOutput"] == {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": fake.check["context"]}
    assert said["systemMessage"] == "Vyavastha · sent: your message. Kept in this session’s chat for your summary. · " + fake.check["notice"]
    (sent,) = fake.calls("/check")
    # The request word for word; the repository without its credential; nothing of the transcript or the folder.
    assert sent["body"] == {"request": text, "remote": "https://github.com/acme/api.git", "branch": "main",
                            "session": "session-1", "tool": "claude-code", "keep": True}
    assert b"hunter2" not in sent["raw"] and b"transcript" not in sent["raw"] and str(repo).encode() not in sent["raw"]


def test_a_held_request_is_kept_from_claude_and_plan_it_anyway_sends_it_with_what_stands(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = {"verdict": "held", "hold": True, "repository": "acme/api",
                  "notice": "On hold: something your team has said stands against this change.\n"
                            "• Priya Raman’s decision: keep it.\nTo go ahead anyway, send “Plan it anyway”.",
                  "context": "Vyavastha checked this request: Priya’s decision stands.",
                  "anyway": {"phrase": "Plan it anyway",
                             "context": "The developer chose to go ahead anyway. Their request: “Remove it”."}}
    held = prompt(run, repo, "Remove it from calc.py")
    assert held["decision"] == "block" and held["reason"] == fake.check["notice"]
    assert held["systemMessage"].startswith("Vyavastha · sent: your message. Kept in this session’s chat for your summary. · On hold")
    going = prompt(run, repo, "plan it anyway.")
    assert going["hookSpecificOutput"]["additionalContext"] == fake.check["anyway"]["context"]
    assert "going ahead" in going["systemMessage"]
    # Going ahead asked the server nothing, and works once.
    assert len(fake.calls("/check")) == 1
    again = prompt(run, repo, "Plan it anyway")
    assert len(fake.calls("/check")) == 2 and "decision" in again
    # The phrase is the plugin's own: checked when nothing waits for it, never kept for the summary.
    assert fake.calls("/check")[-1]["body"]["keep"] is False
    assert "Not kept for your summary." in again["systemMessage"]


def test_a_hold_is_forgotten_once_the_developer_asks_for_something_else(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = {"verdict": "held", "hold": True, "notice": "On hold.", "context": "x",
                  "anyway": {"phrase": "Plan it anyway", "context": "chose to go on"}}
    prompt(run, repo, "Remove it from calc.py")
    fake.check = {"verdict": "not_a_change", "hold": False, "notice": "", "context": ""}
    said = prompt(run, repo, "What does calc.py do?")
    assert said == {"systemMessage": "Vyavastha · sent: your message. Kept in this session’s chat for your summary. · It isn’t a request for a change "
                                     "or a question about your team, so nothing was checked."}
    prompt(run, repo, "Plan it anyway")
    assert len(fake.calls("/check")) == 3


def test_a_server_out_of_reach_never_holds_the_developer_up(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        closed = probe.getsockname()[1]
    (run.home / "credentials").write_text(f"server=http://127.0.0.1:{closed}\ntoken={TOKEN}\n")
    first = prompt(run, repo, "Change calc.py", server=f"http://127.0.0.1:{closed}")
    assert first["systemMessage"] == ("Vyavastha · nothing sent (Vyavastha’s server can’t be reached) · Claude works "
                                      "as usual, and Vyavastha is tried again in a minute.")
    # Found out of reach a moment ago: the next prompt doesn't even try, and says the same quickly.
    second = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"),
                 server=f"http://127.0.0.1:{closed}", cwd=repo)
    assert output(second)["systemMessage"] == first["systemMessage"] and second.seconds < 2


def test_a_server_that_fails_or_is_busy_is_said_in_one_plain_line(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.status["/check"] = 429
    assert "too many requests" in prompt(run, repo, "Change calc.py")["systemMessage"]
    fake.status["/check"] = 503
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert "isn’t working right now" in said and "503" not in said
    (run.home / "offline").unlink()


def test_a_connection_ended_in_settings_signs_this_computer_out(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.status["/check"] = 401
    said = prompt(run, repo, "Change calc.py")
    assert "connection to Vyavastha has ended" in said["systemMessage"] and not (run.home / "credentials").exists()


def test_a_slash_command_is_not_sent_and_a_folder_outside_git_names_no_repository(run, fake, repo, tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "/vyavastha:status")
    assert fake.calls("/check") == []
    # Outside a repository a question about the team can still be asked, so the words are sent, with no remote.
    fake.check = {"verdict": "not_connected", "hold": False, "notice": "", "context": "", "statements": []}
    outside = tmp_path / "notes"
    outside.mkdir()
    switched_on(run, fake, outside)
    said = prompt(run, outside, "Change the notes", cwd=outside)
    (sent,) = fake.calls("/check")
    assert sent["body"]["remote"] == "" and sent["body"]["branch"] == ""
    assert said["systemMessage"].endswith("This folder isn’t a git repository, so nothing was checked. Questions "
                                          "about your team are still answered here.")


def test_a_repository_with_no_github_copy_and_one_not_read_each_say_so(run, fake, tmp_path):
    signed_in(run, fake)
    local = tmp_path / "local"
    local.mkdir()
    git(local, "init", "-q")
    switched_on(run, fake, local)
    fake.check = {"verdict": "not_connected", "hold": False, "notice": "", "context": ""}
    assert "has no copy on GitHub" in prompt(run, local, "Change it", cwd=local)["systemMessage"]
    git(local, "remote", "add", "origin", "https://github.com/acme/other.git")
    fake.check = {"verdict": "not_connected", "hold": False, "context": "",
                  "notice": "Not checked: Vyavastha doesn’t read acme/other for you, so nothing was checked or shared."}
    said = prompt(run, local, "Change it", cwd=local)["systemMessage"]
    assert said == "Vyavastha · sent: your message. Kept in this session’s chat for your summary. · " + fake.check["notice"]


# -- questions ---------------------------------------------------------------------------------------------------

QUESTION = {"verdict": "question", "hold": False, "ask": True, "notice": "", "context": "", "statements": []}


def test_a_question_about_the_team_is_asked_in_vyavastha_and_the_answer_is_given_to_the_model(run, fake, repo,
                                                                                            tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = QUESTION
    asking = 'See what "Priya" is doing'
    said = prompt(run, repo, asking)
    (sent,) = fake.calls("/ask")
    assert sent["body"] == {"question": asking, "remote": "https://github.com/acme/api.git", "branch": "main",
                            "session": "session-1", "tool": "claude-code", "keep": True}
    # The model is given the answer as the server worded it, non-ASCII and all; the developer is told it was asked.
    assert said["hookSpecificOutput"] == {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": fake.asked["context"]}
    assert said["systemMessage"] == "Vyavastha · sent: your question. · " + fake.asked["notice"]
    assert "decision" not in said
    # From a folder that is no repository it is asked all the same.
    outside = tmp_path / "notes"
    outside.mkdir()
    switched_on(run, fake, outside)
    again = prompt(run, outside, asking, cwd=outside)
    assert again["hookSpecificOutput"]["additionalContext"] == fake.asked["context"]
    assert fake.calls("/ask")[-1]["body"]["remote"] == ""


def test_a_slow_answer_is_waited_for_over_several_short_calls_and_then_given_up_on(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = QUESTION
    fake.slow = 2
    said = prompt(run, repo, "What is Priya doing?")
    assert said["hookSpecificOutput"]["additionalContext"] == fake.asked["context"]
    first, second, third = fake.calls("/ask")
    assert first["body"]["question"] == "What is Priya doing?"
    assert second["body"] == third["body"] == {"waiting": "msg_9", "tool": "claude-code"}
    # One that never comes: the model has the message as it is, and the developer is told where the answer will be.
    fake.requests.clear()
    fake.slow = 99
    said = prompt(run, repo, "What is Priya doing?")
    assert said == {"systemMessage": "Vyavastha · sent: your question. · Vyavastha is still working on the answer."}
    assert len(fake.calls("/ask")) == 6


def test_a_question_with_no_answer_goes_to_the_model_as_it_is_with_a_note(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = QUESTION
    fake.asked = {"status": "failed", "answer": "", "context": "", "conversation_id": None, "url": None,
                  "notice": "The assistant model couldn’t answer. Your message is saved; try again."}
    said = prompt(run, repo, "What is Priya doing?")
    assert said == {"systemMessage": "Vyavastha · sent: your question. · " + fake.asked["notice"]}
    fake.status["/ask"] = 500
    said = prompt(run, repo, "What is Priya doing?")
    assert said == {"systemMessage": "Vyavastha · sent: your question. · Your question couldn’t be asked just now, "
                                     "so Claude answers by itself."}


def test_the_model_can_ask_vyavastha_itself_in_the_session_the_developer_last_wrote_in(run, fake, repo):
    assert "Not signed in" in run("ask", "What is Priya doing?", cwd=repo).stdout and fake.calls("/ask") == []
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Fix the rounding", session="session-7")
    done = run("ask", "What is Priya doing?", cwd=repo)
    assert done.stdout.startswith(fake.asked["answer"]) and "http://127.0.0.1/c/cnv_1" in done.stdout
    assert TOKEN not in done.stdout
    assert fake.calls("/ask")[-1]["body"] == {"question": "What is Priya doing?", "branch": "main",
                                              "remote": "https://github.com/acme/api.git", "session": "session-7",
                                              "tool": "claude-code", "keep": True}
    fake.asked = {"status": "pending", "answer": "", "context": "", "notice": "Vyavastha is still working on it."}
    assert run("ask", "And Sam?", cwd=repo).stdout.strip() == "Vyavastha gave no answer: Vyavastha is still working on it."
    assert "Usage" in run("ask", cwd=repo).stdout
    # A session's start tells the model what Vyavastha is for and the command that asks it, by this script's path.
    told = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["hookSpecificOutput"]
    assert told["hookEventName"] == "SessionStart"
    assert f'sh "{SCRIPT}" ask "<the question>"' in told["additionalContext"]
    codex = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))
    assert f'VYAVASTHA_TOOL=codex sh "{SCRIPT}" ask' in codex["hookSpecificOutput"]["additionalContext"]
    assert "message that starts with “Vyavastha,”" in codex["hookSpecificOutput"]["additionalContext"]


def test_under_codex_a_sandboxed_ask_says_how_to_ask_instead_and_never_prints_a_shell_error(run, fake, repo,
                                                                                           tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    # Codex's sandbox: the settings folder can't be written, and the network can't be reached.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        closed = probe.getsockname()[1]
    (run.home / "credentials").write_text(f"server=http://127.0.0.1:{closed}\ntoken={TOKEN}\n")
    done = run("ask", "What is Priya doing?", cwd=repo, tool="codex", server=f"http://127.0.0.1:{closed}")
    assert done.stdout.strip() == ("Codex kept this command from reaching Vyavastha. The developer can ask the same "
                                   "thing by sending a message that starts with “Vyavastha,”.")
    run.home.chmod(0o500)
    try:
        done = run("ask", "What is Priya doing?", cwd=repo, tool="codex")
        assert done.stdout.strip().startswith("Codex kept this command from reaching Vyavastha.")
        assert "Operation not permitted" not in done.stdout + done.stderr
    finally:
        run.home.chmod(0o700)


# -- the one line for every message ------------------------------------------------------------------------------

def test_with_sharing_off_the_line_names_the_changed_files_and_asks_about_sharing_once(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text(f"# {SECRET}\n")
    (repo / "new.py").write_text("z = 3\n")
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert said.startswith("Vyavastha · sent: your message and 2 changed files’ names. Not sent: what the files hold "
                           "(code sharing is off). Kept in this session’s chat for your summary. · Checked: nothing stands against this change.")
    # The one question about code sharing says what turning it on does, in a sentence.
    assert said.endswith(" Send “vyavastha share code on” to also send your uncommitted changes for the check; "
                         "teammates see only a summary, and key, ignored, machine-written and non-text files never go "
                         "(asked once).")
    (check,) = fake.calls("/check")
    assert "change" not in check["body"] and SECRET.encode() not in check["raw"]
    (work,) = fake.calls("/work")
    assert SECRET.encode() not in work["raw"] and "change" not in work["body"]
    # Asked once only.
    again = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert "asked once" not in again
    # One changed file is said in the singular.
    git(repo, "checkout", "-q", "--", "calc.py")
    assert "sent: your message and 1 changed file’s name." in prompt(run, repo, "Change calc.py")["systemMessage"]


def test_turning_code_sharing_on_says_what_is_sent_and_never_sent_and_tells_the_server(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha share code on")))
    # What Vyavastha does with the changes is the server's own notice, printed as it came; what never leaves this
    # computer is the plugin's own list, since the plugin decides it.
    never = ("Never sent from this computer: files git ignores, key and password files (such as .env or .pem), "
             "machine-written files such as lock files and build output, and files that aren’t text.")
    assert said["reason"].splitlines() == [SHARING_ON, never,
                                           "Send “vyavastha share code off” to stop it and delete what was kept."]
    assert fake.calls("/sharing")[0]["body"] == {"remote": "https://github.com/acme/api.git", "on": True}
    off = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha share-code off")))
    assert off["reason"].splitlines() == [SHARING_OFF, "Send “vyavastha share code on” to turn it on again."]
    assert fake.calls("/sharing")[-1]["body"]["on"] is False
    # Signed out, the plugin says itself what Vyavastha does with the changes: teammates see a summary only.
    (run.home / "credentials").unlink()
    said = run("share-code", "on", cwd=repo).stdout.splitlines()
    assert said[0] == ("Code sharing is on for acme/api: your uncommitted changes (up to 5,000 lines) now go to "
                       "Vyavastha with each message and after each edit, and Vyavastha’s check reads them.")
    assert said[1].startswith("Teammates who can already see this work see a short summary of what the change does, "
                              "never the code.") and "7 days" in said[1] and said[2] == never


def test_with_sharing_on_the_check_carries_one_diff_of_the_working_tree_against_github(run, fake, repo, tmp_path):
    signed_in(run, fake)
    upstream = tmp_path / "upstream.git"
    git(tmp_path, "init", "-q", "--bare", str(upstream))
    git(repo, "remote", "add", "mirror", str(upstream))
    git(repo, "push", "-q", "mirror", "main")
    git(repo, "branch", "-q", "--set-upstream-to=mirror/main")
    pushed = git(repo, "rev-parse", "HEAD").strip()
    # A commit not pushed yet, an edit, a new file, a deleted file and a rename.
    (repo / "committed.py").write_text("print('committed, not pushed')\n")
    git(repo, "add", "committed.py")
    git(repo, "commit", "-q", "-m", "Local")
    (repo / "calc.py").write_text("def add(a, b):\n    return a + b + 0\n")
    (repo / "new file \"q\".py").write_text("brand = 'new'\n")
    (repo / "gone.py").unlink()
    git(repo, "mv", "old.py", "renamed.py")
    (repo / ".gitignore").write_text("ignored.txt\n")
    (repo / "ignored.txt").write_text(f"{SECRET}\n")
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    (check,) = fake.calls("/check")
    change = check["body"]["change"]
    assert change["base"] == pushed and change["complete"] is True and change["left_out"] == []
    diff = change["diff"]
    assert "+    return a + b + 0" in diff and "committed, not pushed" in diff
    # (git writes a name with quotes in it quoted, as its own diffs do.)
    assert "brand = 'new'" in diff and '+++ "b/new file \\"q\\".py"' in diff
    assert "deleted file" in diff and "-y = 2" in diff
    assert "rename from old.py" in diff and "rename to renamed.py" in diff
    # An ignored file is never even listed (only the .gitignore that names it is a change).
    assert SECRET not in diff and "b/ignored.txt" not in diff
    assert change["files"] == 6 and change["lines"] >= 5
    assert said.startswith("Vyavastha · sent: your message and your uncommitted changes (6 files,")
    assert "Not sent" not in said
    # The developer's own index is untouched: the new file is still untracked.
    assert "?? " in git(repo, "status", "--porcelain")
    # The same changes are not sent again with the report that follows; changed again, they are.
    assert "change" not in fake.calls("/work")[0]["body"]
    run("hook", "stopped", stdin=event("Stop", repo))
    assert "change" not in fake.calls("/work")[-1]["body"]
    (repo / "calc.py").write_text("def add(a, b):\n    return b + a\n")
    run("hook", "stopped", stdin=event("Stop", repo))
    assert "return b + a" in fake.calls("/work")[-1]["body"]["change"]["diff"]


def test_keys_machine_written_and_binary_files_are_left_out_by_name_with_their_reasons(run, fake, repo):
    signed_in(run, fake)
    (repo / ".env").write_text("A=1\n")
    git(repo, "add", ".env")
    git(repo, "commit", "-q", "-m", "A tracked key file, as happens")
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / ".env").write_text(f"A={SECRET}\n")
    (repo / "deploy.pem").write_text(f"{SECRET}\n")
    (repo / "config").mkdir()
    (repo / "config" / "credentials.json").write_text(f"{SECRET}\n")
    (repo / "package-lock.json").write_text("{}\n")
    (repo / "node_modules" / "x").mkdir(parents=True)
    (repo / "node_modules" / "x" / "index.js").write_text(f"{SECRET}\n")
    (repo / "app.min.js").write_text("a()\n")
    (repo / "logo.png").write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00" + bytes(range(256)))
    (repo / "calc.py").write_text("def add(a, b):\n    return 2\n")
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    change = fake.calls("/check")[0]["body"]["change"]
    assert SECRET not in json.dumps(change)
    reasons = {entry["path"]: entry["why"] for entry in change["left_out"]}
    assert reasons == {".env": "secret", "deploy.pem": "secret", "config/credentials.json": "secret",
                       "package-lock.json": "generated", "node_modules/x/index.js": "generated",
                       "app.min.js": "generated", "logo.png": "binary"}
    assert change["files"] == 1 and change["complete"] is True
    assert ("Not sent: 3 files that look like keys or passwords, 3 machine-written files, such as lock files or "
            "build output, 1 file that isn’t text.") in said


def test_the_limit_leaves_out_files_that_would_pass_it_and_cuts_long_lines_and_strange_bytes(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / "a_big.py").write_text("".join(f"line {n}\n" for n in range(4990)))
    (repo / "b_huge.py").write_text("".join(f"x {n}\n" for n in range(100)))
    (repo / "c_small.py").write_text("small = 1\n" + "w" * 5000 + "\n")
    (repo / "d_latin1.py").write_bytes(b"name = 'caf\xe9'\n")
    said = prompt(run, repo, "Change it")["systemMessage"]
    change = fake.calls("/check")[0]["body"]["change"]
    assert change["complete"] is False and change["left_out"] == [{"path": "b_huge.py", "why": "limit"}]
    assert "line 4989" in change["diff"] and "small = 1" in change["diff"] and "x 99" not in change["diff"]
    assert max(len(line) for line in change["diff"].split("\n")) <= 2000
    assert "name = 'caf" in change["diff"]
    assert "1 file past the limit of 5,000 lines" in said


def test_a_file_name_with_spaces_and_quotes_is_sent_as_it_is(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / 'my "odd" file.py').write_text("odd = True\n")
    prompt(run, repo, "Change it")
    change = fake.calls("/check")[0]["body"]["change"]
    assert '+++ "b/my \\"odd\\" file.py"' in change["diff"] and "odd = True" in change["diff"]


def test_sharing_turned_off_in_the_web_app_turns_it_off_here_and_says_so(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    fake.sharing.clear()
    (repo / "calc.py").write_text("changed = True\n")
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert "code sharing was turned off for this repository in Vyavastha’s web app" in said
    assert "Code sharing: off" in run("settings", cwd=repo).stdout


# -- a conflict found in the real change ------------------------------------------------------------------------

CONFLICT = {"id": "cfl_1", "notice": "Something your team has said stands against the change being made.\n"
                                     "• Priya Raman’s decision: the export stays.",
            "context": "Priya decided the export stays (Slack, 3 Nov)."}


def test_a_conflict_stops_the_next_edit_once_and_continue_tells_the_server_and_goes_on(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text("changed = True\n")
    fake.extra["/work"] = {"conflict": CONFLICT}
    run("hook", "edited", stdin=event("PostToolUse", repo, tool_name="Edit"))
    stopped = output(run("hook", "edit-check", stdin=event("PostToolUse", repo, tool_name="Edit")))
    assert stopped["continue"] is False and stopped["stopReason"].startswith(CONFLICT["notice"])
    assert stopped["stopReason"].endswith("Send “continue” to go on, or “stop” to leave the change where it is.")
    # Once only, and the stop hook doesn't say it again.
    assert run("hook", "edit-check", stdin=event("PostToolUse", repo, tool_name="Edit")).stdout == ""
    assert run("hook", "stopped", stdin=event("Stop", repo)).stdout == ""
    fake.requests.clear()
    going = prompt(run, repo, "Continue")
    assert fake.calls("/conflict")[0]["body"] == {"session": "session-1", "remote": "https://github.com/acme/api.git",
                                                  "id": "cfl_1", "decision": "continue"}
    assert CONFLICT["context"] in going["hookSpecificOutput"]["additionalContext"]
    assert "chose to continue" in going["hookSpecificOutput"]["additionalContext"] and not fake.calls("/check")
    # Decided: the same conflict coming back is not told again.
    run("hook", "edited", stdin=event("PostToolUse", repo, tool_name="Edit"))
    assert run("hook", "edit-check", stdin=event("PostToolUse", repo)).stdout == ""


def test_a_conflict_told_when_the_tool_stops_and_stop_asks_to_make_no_more_edits(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text("changed = True\n")
    fake.extra["/work"] = {"conflict": CONFLICT}
    told = output(run("hook", "stopped", stdin=event("Stop", repo)))
    assert told["systemMessage"].startswith(CONFLICT["notice"])
    stopping = prompt(run, repo, "stop")
    assert fake.calls("/conflict")[-1]["body"]["decision"] == "stop"
    assert "Make no more edits" in stopping["hookSpecificOutput"]["additionalContext"]


def test_any_other_message_after_a_conflict_marks_it_seen_and_gives_the_model_its_facts(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text("changed = True\n")
    fake.extra["/work"] = {"conflict": CONFLICT}
    run("hook", "stopped", stdin=event("Stop", repo))
    fake.extra.clear()
    said = prompt(run, repo, "Add a test for calc.py")
    assert fake.calls("/conflict")[-1]["body"]["decision"] == "seen"
    assert said["hookSpecificOutput"]["additionalContext"].startswith(CONFLICT["context"])
    assert fake.calls("/check")


def test_a_conflict_that_comes_with_a_check_pauses_the_message_until_the_developer_chooses(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.extra["/check"] = {"conflict": CONFLICT}
    paused = prompt(run, repo, "Remove the export")
    assert paused["decision"] == "block" and paused["reason"].startswith(CONFLICT["notice"])
    fake.extra.clear()
    going = prompt(run, repo, "continue")
    assert "Their request, sent before they were asked: Remove the export" in \
        going["hookSpecificOutput"]["additionalContext"]


# -- upload, chat, shared, settings, status, check, help --------------------------------------------------------

def test_upload_opens_the_sessions_chat_to_drop_a_file_and_chat_gives_its_link(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py", session="session-3")
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, session="session-3",
                                                     prompt="vyavastha upload")))["reason"]
    assert "drop the file there" in said and "next question in this session" in said
    assert run.opened() == ["http://127.0.0.1/c/cnv_7?attach=1"]
    assert fake.calls("/chat")[0]["body"] == {"session": "session-3", "remote": "https://github.com/acme/api.git",
                                              "branch": "main", "tool": "claude-code"}
    chat = run("chat", cwd=repo).stdout
    assert "http://127.0.0.1/c/cnv_7" in chat and fake.calls("/chat")[-1]["body"]["session"] == "session-3"
    assert len(run.opened()) == 1
    run("chat", "open", cwd=repo)
    assert run.opened()[-1] == "http://127.0.0.1/c/cnv_7"


def test_an_image_in_the_message_opens_the_chat_with_sharing_on_and_asks_once_with_it_off(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    said = prompt(run, repo, "[Image #1] Make the button look like this")["systemMessage"]
    # With code sharing off, the way to give Vyavastha the image is the upload page, not sharing code.
    assert said.endswith(" Your image stays in Claude Code. To give it to Vyavastha, send “vyavastha upload” and drop "
                         "it on the page that opens.") and run.opened() == []
    assert "share code on" not in said
    sharing_on(run, fake, repo)
    said = prompt(run, repo, "[Image #2] And this one")["systemMessage"]
    assert "this session’s chat is open in your browser" in said
    assert run.opened() == ["http://127.0.0.1/c/cnv_7?attach=1"]


def test_shared_lists_what_this_session_sent_oldest_first_with_what_is_kept(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    assert "Nothing has been sent" in run("shared", cwd=repo).stdout
    prompt(run, repo, "Change calc.py", session="session-5")
    fake.shared = {"items": [
        {"at": "2026-11-18T10:45:00Z", "at_said": "18 Nov, 10:45", "kind": "change",
         "said": "Your uncommitted changes to 2 files."},
        {"at": "2026-11-18T10:42:00Z", "at_said": "18 Nov, 10:42", "kind": "request",
         "said": "A request of 14 words was checked; nothing stood against it. Its words were not kept."}],
        "chat_url": "http://127.0.0.1/c/cnv_7", "sharing": True, "kept": "Vyavastha keeps this list for 30 days."}
    listed = run("shared", cwd=repo).stdout.splitlines()
    assert listed == ["Sent to Vyavastha from this session, oldest first:",
                      "- 18 Nov, 10:42: A request of 14 words was checked; nothing stood against it. Its words were "
                      "not kept.",
                      "- 18 Nov, 10:45: Your uncommitted changes to 2 files.",
                      "Vyavastha keeps this list for 30 days.", "This session’s chat: http://127.0.0.1/c/cnv_7"]
    assert fake.calls("/shared")[-1]["query"] == {"session": ["session-5"],
                                                  "remote": ["https://github.com/acme/api.git"]}


def test_settings_and_status_show_the_project_and_sharing_and_how_to_change_them(run, fake, repo):
    signed_in(run, fake)
    settings = run("settings", cwd=repo).stdout
    assert "- This project: off. Send “vyavastha on” to turn it on." in settings
    assert "- Code sharing: off. Send “vyavastha share code on” to turn it on." in settings
    assert "- Signed in as: sam@acme.test in Acme." in settings and f"- Server: {fake.url}." in settings
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    settings = run("settings", cwd=repo).stdout
    assert "- This project: on." in settings and "- Code sharing: on." in settings
    status = run("status", cwd=repo).stdout
    assert "Vyavastha is on in this project (api)." in status and "Code sharing is on for this project." in status


def test_check_tests_each_part_and_says_how_to_fix_what_is_wrong(run, fake, repo, tmp_path):
    lines = run("check", cwd=repo).stdout.splitlines()
    assert lines[0] == "ok: git, curl and awk are installed."
    assert any(line.startswith("ok: the settings folder") for line in lines)
    assert "ok: Vyavastha’s server answers." in lines
    assert any(line.startswith("Problem: not signed in.") for line in lines)
    assert "ok: this folder is the repository acme/api on GitHub." in lines
    assert any(line.startswith("Problem: Vyavastha is off in this project.") for line in lines)
    assert "ok: this plugin (0.4.0) is the latest." in lines
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.latest = "0.5.0"
    lines = run("check", cwd=repo).stdout.splitlines()
    assert "ok: signed in as sam@acme.test in Acme." in lines and "ok: Vyavastha reads acme/api for you." in lines
    assert "ok: Vyavastha is on in this project." in lines
    assert any(line.startswith("Problem: this plugin is 0.4.0 and 0.5.0 is out.") for line in lines)
    fake.minimum = "0.4.1"
    assert any("must be updated" in line for line in run("check", cwd=repo).stdout.splitlines())
    outside = tmp_path / "plain"
    outside.mkdir()
    assert any("isn’t a git repository" in line for line in run("check", cwd=outside).stdout.splitlines())
    lines = run("check", cwd=repo, server="http://127.0.0.1:9").stdout.splitlines()
    assert any(line.startswith("Problem: Vyavastha’s server can’t be reached.") for line in lines)


def test_help_lists_the_commands_in_three_groups(run, fake, repo):
    text = run("help", cwd=repo).stdout
    for group in ("Start here", "See what is shared", "Teammates"):
        assert f"\n{group}\n" in text
    assert "“vyavastha ask <name>: <question>”" in text and "/vyavastha:on" in text
    assert "/vyavastha:" not in run("help", cwd=repo, tool="codex").stdout


# -- teammates ------------------------------------------------------------------------------------------------------

INBOX = [{"n": 1, "message_id": "pm_1", "from": {"name": "Priya Raman"}, "kind": "message",
          "text": "Are you changing the export?", "answer": "Sam is changing calc.py.", "at": "x",
          "at_said": "18 Nov, 09:12", "task": None},
         {"n": 2, "message_id": "pm_2", "from": {"name": "Helen Ortiz"}, "kind": "task",
          "text": "Move the export to the v2 format.", "answer": None, "at": "y", "at_said": "18 Nov, 09:30",
          "task": {"state": "open"}}]


def test_a_session_starts_with_what_teammates_asked_while_away_each_under_its_header(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.inbox = INBOX
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert said.startswith("Vyavastha: signed in as sam@acme.test in Acme.") and TOKEN not in said
    assert "\n\nWhile you were away:\n── From Priya Raman · 18 Nov, 09:12 · asked your agent ──\n" \
           "1. Are you changing the export?\nYour agent answered: Sam is changing calc.py." in said
    assert "── From Helen Ortiz · 18 Nov, 09:30 · assigned you a task ──\n2. Move the export to the v2 format." in said
    assert "“vyavastha reply <number>: <your words>”" in said and "“vyavastha start <number>”" in said
    assert fake.calls("/inbox")[0]["query"] == {"told": ["1"]}


def test_a_session_starts_by_saying_where_it_is_signed_in(run, fake, repo):
    switched_on(run, fake, repo)
    assert "not signed in" in output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    signed_in(run, fake)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert said == ("Vyavastha: signed in as sam@acme.test in Acme. Requests are checked against your team’s record "
                    "before Claude changes code, and questions about your team are answered from it.")


def test_ask_a_teammates_agent_prints_both_headers_the_answer_and_who_sees_it(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                     prompt="vyavastha ask Priya Raman: what is the export’s plan?")))
    assert said["decision"] == "block" and not fake.calls("/check")
    assert fake.calls("/tell")[0]["body"] == {"to": "Priya Raman", "text": "what is the export’s plan?",
                                              "kind": "message", "session": "session-1",
                                              "remote": "https://github.com/acme/api.git", "branch": "main",
                                              "tool": "claude-code"}
    assert said["reason"].splitlines() == [
        "── To Priya Raman’s agent · from Sam Rivera · 18 Nov, 10:42 · through Vyavastha ──",
        "what is the export’s plan?", "",
        "── From Priya Raman’s agent · 18 Nov, 10:43 · answered only from what you can both already see ──",
        "Priya is moving the export to v2.", "",
        "Priya sees what you asked and this answer.",
        "Your conversation with Priya Raman in Vyavastha: http://127.0.0.1/?agent-chat=usr_p"]
    # A notice that ends with the link already: the link is printed once.
    fake.tell = {**fake.tell, "notice": "Priya sees it, in your thread with her: http://127.0.0.1/?agent-chat=usr_p"}
    said = run("tell", "Priya", "and the import?", cwd=repo).stdout
    assert said.count("http://127.0.0.1/?agent-chat=usr_p") == 1
    # A one-word name needs no colon; a comma does as well.
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha ask priya are you around?"))
    assert fake.calls("/tell")[-1]["body"]["to"] == "priya"
    assert fake.calls("/tell")[-1]["body"]["text"] == "are you around?"
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Vyavastha ask Priya, is it done?"))
    assert fake.calls("/tell")[-1]["body"]["text"] == "is it done?"


def test_a_slow_teammate_answer_is_waited_for_and_an_unknown_name_lists_the_team(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.tell_slow = 1
    said = run("tell", "Priya", "what is the plan?", cwd=repo).stdout
    first, second = fake.calls("/tell")
    assert second["body"]["waiting"] == "pmsg_4" and "Priya is moving the export to v2." in said
    fake.tell = {**fake.tell, "status": "unknown_person", "people": ["Priya Raman", "Helen Ortiz"]}
    said = run("tell", "Bob", "hi", cwd=repo).stdout
    assert said.strip() == "Vyavastha doesn’t know a teammate called “Bob”. Your teammates: Priya Raman, Helen Ortiz."


def test_assign_sends_a_task_and_a_refusal_is_one_sentence(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.tell = {**fake.tell, "status": "sent", "answer": "", "notice": "Priya will see the task next time."}
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                     prompt="vyavastha assign Priya: update the export")))["reason"]
    assert fake.calls("/tell")[-1]["body"]["kind"] == "task"
    assert said.startswith("── To Priya Raman · from Sam Rivera · 18 Nov, 10:42 · through Vyavastha ──\n"
                           "update the export")
    fake.tell = {**fake.tell, "status": "refused", "notice": "Only owners and administrators can assign tasks."}
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                     prompt="vyavastha assign Priya: update the export")))["reason"]
    assert said == "Only owners and administrators can assign tasks."


def test_inbox_reply_start_done_and_decline_act_on_the_numbered_items(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    assert "Nothing new" in run("inbox", cwd=repo).stdout
    fake.inbox = INBOX
    listed = run("inbox", cwd=repo).stdout
    assert "1. Are you changing the export?" in listed and fake.calls("/inbox")[-1]["query"] == {}
    fake.tell = {**fake.tell, "status": "sent", "to": {"name": "Priya Raman"}, "answer": "", "notice": ""}
    replied = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                        prompt="vyavastha reply 1: yes, calc.py only")))["reason"]
    assert fake.calls("/tell")[-1]["body"]["reply_to"] == "pm_1"
    assert fake.calls("/tell")[-1]["body"]["to"] == "Priya Raman" and replied.startswith("── To Priya Raman ·")
    assert "isn’t a task" in output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                                      prompt="vyavastha done 1")))["reason"]
    assert "no item 9" in output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo,
                                                                   prompt="vyavastha decline 9")))["reason"]
    # Starting a task lets its words through to the model as the request, checked as any request is.
    started = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha start 2")))
    assert fake.calls("/task")[-1]["body"] == {"message_id": "pm_2", "state": "accepted"}
    assert "decision" not in started
    assert fake.calls("/check")[-1]["body"]["request"] == "Move the export to the v2 format."
    assert started["systemMessage"].startswith("Vyavastha · sent: the task’s words. Not kept for your summary. · "
                                               "Started the task Helen Ortiz assigned you; Helen Ortiz will see that "
                                               "you started it.")
    # A started task's words come from the plugin's own command: never kept for the summary.
    assert fake.calls("/check")[-1]["body"]["keep"] is False
    assert "Move the export to the v2 format." in started["hookSpecificOutput"]["additionalContext"]
    done = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha done 2")))["reason"]
    assert done == "Marked done. Helen Ortiz will see it." and fake.calls("/task")[-1]["body"]["state"] == "done"
    assert "won’t take it on" in run("decline", "2", cwd=repo).stdout


# -- telling teammates what is changing ------------------------------------------------------------------------

def test_an_edit_reports_gits_own_list_of_changes_with_counts_and_never_what_files_hold(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    run("hook", "session-start", stdin=event("SessionStart", repo, source="startup"))
    fake.requests.clear()
    (repo / "calc.py").write_text(f"def add(a, b):\n    # {SECRET}\n    return a + b\n\n\ndef sub(a, b):\n    return a - b\n")
    (repo / "new file \"q\".py").write_text(f"{SECRET}\nline two\nline three\n")
    (repo / "gone.py").unlink()
    git(repo, "mv", "old.py", "renamed.py")
    run("hook", "edited", stdin=event("PostToolUse", repo, tool_name="Edit",
                                      tool_input={"file_path": str(repo / "calc.py"), "new_string": SECRET}))
    (sent,) = fake.calls("/work")
    assert SECRET.encode() not in sent["raw"] and b"hunter2" not in sent["raw"]
    body = sent["body"]
    assert body["state"] == "changing" and body["branch"] == "main" and body["remote"] == "https://github.com/acme/api.git"
    files = {entry["path"]: entry for entry in body["files"]}
    assert files["calc.py"] == {"path": "calc.py", "status": "changed", "additions": 5, "deletions": 0}
    assert files['new file "q".py'] == {"path": 'new file "q".py', "status": "added", "additions": 3, "deletions": 0}
    assert files["gone.py"]["status"] == "deleted" and files["gone.py"]["deletions"] == 1
    assert files["renamed.py"]["status"] == "renamed" and "old.py" not in files
    # Edits a moment later wait for the next report; Claude stopping always reports.
    run("hook", "edited", stdin=event("PostToolUse", repo, tool_name="Write"))
    assert len(fake.calls("/work")) == 1
    run("hook", "stopped", stdin=event("Stop", repo, stop_hook_active=False))
    assert len(fake.calls("/work")) == 2


def test_a_long_edit_input_is_read_quickly(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text("changed\n")
    long = "x" * 400_000
    done = run("hook", "edited", stdin=event("PostToolUse", repo, tool_name="Write",
                                             tool_input={"file_path": "calc.py", "content": long}))
    assert fake.calls("/work") and done.seconds < 5


def test_when_claude_stops_the_work_is_told_as_committed_pushed_or_set_aside(run, fake, repo, tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    upstream = tmp_path / "upstream.git"
    git(tmp_path, "init", "-q", "--bare", str(upstream))
    git(repo, "remote", "add", "mirror", str(upstream))
    git(repo, "push", "-q", "mirror", "main")
    git(repo, "branch", "-q", "--set-upstream-to=mirror/main")
    stop = event("Stop", repo, stop_hook_active=False)
    run("hook", "session-start", stdin=event("SessionStart", repo, source="startup"))
    fake.requests.clear()
    # Nothing changed and nothing open: nothing is sent.
    run("hook", "stopped", stdin=stop)
    assert fake.calls("/work") == []
    (repo / "calc.py").write_text("changed\n")
    run("hook", "stopped", stdin=stop)
    git(repo, "commit", "-q", "-am", "Change")
    run("hook", "stopped", stdin=stop)
    git(repo, "push", "-q", "mirror", "main")
    run("hook", "stopped", stdin=stop)
    assert [call["body"]["state"] for call in fake.calls("/work")] == ["changing", "committed", "pushed"]
    # Pushed, the session's record is done: a clean tree tells nothing more.
    run("hook", "stopped", stdin=stop)
    assert len(fake.calls("/work")) == 3
    # A new session that changes a file and then puts it back as it was: set aside.
    other = event("Stop", repo, session="session-2", stop_hook_active=False)
    run("hook", "session-start", stdin=event("SessionStart", repo, session="session-2", source="startup"))
    (repo / "calc.py").write_text("changed again\n")
    run("hook", "stopped", stdin=other)
    git(repo, "checkout", "-q", "--", "calc.py")
    run("hook", "stopped", stdin=other)
    assert [call["body"]["state"] for call in fake.calls("/work")][-2:] == ["changing", "abandoned"]


def test_signed_out_nothing_is_reported(run, fake, repo):
    switched_on(run, fake, repo)
    (repo / "calc.py").write_text("changed\n")
    run("hook", "stopped", stdin=event("Stop", repo))
    assert fake.requests == []


# -- under Codex -----------------------------------------------------------------------------------------------------

def test_under_codex_the_script_names_codex_and_says_which_tool_it_is(run, fake, repo):
    switched_on(run, fake, repo)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))["systemMessage"]
    assert "“vyavastha sign in”" in said and "Claude" not in said and "/vyavastha:" not in said
    signed_in(run, fake)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))["systemMessage"]
    assert "before Codex changes code" in said and "Claude" not in said
    fake.requests.clear()
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Make the trial 30 days"), tool="codex")
    (sent,) = fake.calls("/check")
    assert sent["body"]["tool"] == "codex" and sent["headers"]["User-Agent"] == "vyavastha-codex/0.4.0"


@pytest.mark.parametrize("typed", ["vyavastha sign in", "Vyavastha sign-in.", "  VYAVASTHA  SIGN IN  "])
def test_the_commands_sent_as_plain_messages_are_answered_by_the_plugin_and_never_reach_the_model(
        run, fake, repo, typed):
    started = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=typed), tool="codex"))
    # Held back from the model, with what the command said as the reason the developer sees; Codex is given only
    # the fields it reads.
    assert set(started) == {"decision", "reason"} and started["decision"] == "block"
    assert "BCDF-GHJK" in started["reason"]
    assert "To connect Codex on" in started["reason"] and "device-secret" not in started["reason"]
    assert fake.calls("/pair")[0]["body"]["tool"] == "codex" and not fake.calls("/check")
    fake.approved = True
    status = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha status"),
                        tool="codex"))
    assert status["decision"] == "block" and "connected as sam@acme.test in Acme" in status["reason"]
    assert "Vyavastha reads acme/api for you" in status["reason"] and TOKEN not in status["reason"]
    out = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha sign out"),
                     tool="codex"))
    assert out["decision"] == "block" and "Signed out" in out["reason"]
    assert fake.calls("/signout") and not (run.home / "credentials").exists() and not fake.calls("/check")


def test_a_request_that_only_mentions_the_commands_is_checked_like_any_other(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    said = output(run("hook", "prompt", tool="codex",
                      stdin=event("UserPromptSubmit", repo, prompt="Add a vyavastha sign in button to the page")))
    assert "decision" not in said and fake.calls("/check") and not fake.calls("/pair")


def test_a_held_request_under_codex_is_blocked_in_the_form_codex_reads(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = {"verdict": "held", "hold": True, "notice": "On hold: Helen decides this.", "context": "c",
                  "statements": [], "anyway": {"phrase": "Plan it anyway", "context": "Go on: c"}}
    held = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Make the trial 30 days",
                                                   turn_id="turn-1", model="gpt-6-luna"), tool="codex"))
    assert held["decision"] == "block" and held["reason"] == "On hold: Helen decides this."
    anyway = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Plan it anyway"),
                        tool="codex"))
    assert anyway["hookSpecificOutput"] == {"hookEventName": "UserPromptSubmit", "additionalContext": "Go on: c"}
    assert "Codex was shown your request" in anyway["systemMessage"]


def test_codexs_hooks_file_and_listing_point_at_this_script_and_folder():
    hooks = json.loads((PLUGIN / "hooks" / "codex.json").read_text())["hooks"]
    assert set(hooks) == {"SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"}
    for groups in hooks.values():
        for group in groups:
            for hook in group["hooks"]:
                assert hook["type"] == "command"
                assert hook["command"].startswith('VYAVASTHA_TOOL=codex sh "${PLUGIN_ROOT}/scripts/vyavastha.sh" hook ')
                assert hook["command"].rsplit(" ", 1)[1] in {"session-start", "prompt", "edited", "stopped"}
    # Only the report after an edit may run in the background: a check that runs there could hold nothing.
    assert [hook.get("async", False) for hook in hooks["UserPromptSubmit"][0]["hooks"]] == [False]
    manifest = json.loads((PLUGIN / ".codex-plugin" / "plugin.json").read_text())
    claude = json.loads((PLUGIN / ".claude-plugin" / "plugin.json").read_text())
    assert manifest["name"] == claude["name"] == "vyavastha" and manifest["version"] == claude["version"] == "0.4.0"
    assert f'VERSION="{manifest["version"]}"' in SCRIPT.read_text()
    assert (PLUGIN / manifest["hooks"]).is_file() and (PLUGIN / manifest["skills"] / "vyavastha" / "SKILL.md").is_file()
    codex_skill = (PLUGIN / manifest["skills"] / "vyavastha" / "SKILL.md").read_text()
    for phrase in ("vyavastha on", "vyavastha share code on", "vyavastha shared", "vyavastha check",
                   "vyavastha ask <name>: <question>"):
        assert phrase in codex_skill
    root = PLUGIN.parents[1]
    (entry,) = json.loads((root / ".agents" / "plugins" / "marketplace.json").read_text())["plugins"]
    assert (root / entry["source"]["path"]).resolve() == PLUGIN and set(entry["policy"]) == {"installation",
                                                                                           "authentication"}


# -- the plugin itself -------------------------------------------------------------------------------------------

def test_every_hook_runs_this_script_with_a_command_it_knows():
    hooks = json.loads((PLUGIN / "hooks" / "hooks.json").read_text())["hooks"]
    commands = [hook["command"] for groups in hooks.values() for group in groups for hook in group["hooks"]]
    assert set(hooks) == {"SessionStart", "UserPromptSubmit", "PostToolUse", "Stop"}
    for command in commands:
        assert command.startswith('sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavastha.sh" hook ')
        assert command.rsplit(" ", 1)[1] in {"session-start", "prompt", "edited", "stopped", "edit-check"}
    # The check after an edit is the one that can stop the tool, so it runs in the foreground, quickly.
    (check,) = [hook for group in hooks["PostToolUse"] for hook in group["hooks"] if hook["command"].endswith("edit-check")]
    assert not check.get("async") and check["timeout"] <= 10
    for skill in COMMANDS:
        text = (PLUGIN / "skills" / skill / "SKILL.md").read_text()
        words = skill.replace("share-code-", "share-code ").replace("summaries-", "summaries ")
        assert f'!`sh "${{CLAUDE_PLUGIN_ROOT}}/scripts/vyavastha.sh" {words} || true`' in text
        assert "disable-model-invocation: true" in text and "allowed-tools: Bash(sh:*)" in text
        # A skill never takes words of its own: nothing typed is put on a shell line.
        assert "$ARGUMENTS" not in text


def test_the_check_after_an_edit_costs_almost_nothing_when_no_conflict_waits(run, fake, repo):
    switched_on(run, fake, repo)
    done = run("hook", "edit-check", stdin=event("PostToolUse", repo, tool_input={"content": "x" * 400_000}))
    assert done.stdout == "" and done.seconds < 1 and fake.requests == []


# -- review fixes: what can never be sent, the developer's index, cost, and the words people read ------------------

KEY = "-----BEGIN PRIVATE KEY----- KEY-CONTENTS-NEVER-LEAVE"


def test_a_file_that_turns_into_a_link_never_lets_a_key_file_after_it_through(run, fake, repo):
    """git lists a file that became a link once and diffs it twice; nothing is matched by its place in a list."""
    signed_in(run, fake)
    (repo / "a_link").write_text("plain\n")
    (repo / "m").mkdir()
    (repo / "m" / ".env").write_text("K=old\n")
    (repo / "z.py").write_text("z = 1\n")
    git(repo, "add", "--all")
    git(repo, "commit", "-q", "-m", "Tracked")
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / "a_link").unlink()
    (repo / "a_link").symlink_to("z.py")
    (repo / "m" / ".env").write_text(f"K={KEY}\n")
    (repo / "z.py").write_text("z = 2\n")
    said = prompt(run, repo, "Change z.py")["systemMessage"]
    (check,) = fake.calls("/check")
    assert KEY.encode() not in check["raw"]
    change = check["body"]["change"]
    assert {entry["path"]: entry["why"] for entry in change["left_out"]} == {"a_link": "binary", "m/.env": "secret"}
    assert "+z = 2" in change["diff"] and "a_link" not in change["diff"] and change["files"] == 1
    assert "1 file that looks like a key or password" in said


def test_no_key_file_reaches_the_sent_change_by_any_path(run, fake, repo, tmp_path):
    """Links tracked and new, inside and outside the project, renames onto and from key names, key files in
    sub-folders and in capitals, and a key file inside a submodule: none of their contents is ever sent."""
    signed_in(run, fake)
    outside = tmp_path / "home-keys"
    outside.mkdir()
    (outside / "id_rsa").write_text(f"{KEY}\n")
    (repo / "notes.txt").write_text("notes\n")
    (repo / "settings.cfg").write_text(f"token = {KEY}\n")
    (repo / "pointer").symlink_to("notes.txt")
    sub = tmp_path / "sub"
    sub.mkdir()
    git(sub, "init", "-q", "--initial-branch=main")
    (sub / "readme.md").write_text("sub\n")
    git(sub, "add", "--all")
    git(sub, "commit", "-q", "-m", "Sub")
    git(repo, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(sub), "vendored")
    git(repo, "add", "--all")
    git(repo, "commit", "-q", "-m", "Tracked")
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    # A tracked link pointed at a key file outside the project; new links to key files inside and outside it.
    (repo / "pointer").unlink()
    (repo / "pointer").symlink_to(outside / "id_rsa")
    (repo / "config").mkdir()
    (repo / "config" / ".ENV").write_text(f"A={KEY}\n")
    (repo / "keys").mkdir()
    (repo / "keys" / "ID_RSA.PEM").write_text(f"{KEY}\n")
    (repo / "harmless.txt").symlink_to("config/.ENV")
    (repo / "elsewhere").symlink_to(outside / "id_rsa")
    # A key file renamed to a plain name, and a plain file holding a key renamed to a key name.
    (repo / "service-account.json").write_text(f"{KEY}\n")
    git(repo, "add", "service-account.json")
    git(repo, "commit", "-q", "-m", "Oops")
    git(repo, "mv", "service-account.json", "plain.json")
    git(repo, "mv", "settings.cfg", "deploy.key")
    (repo / "vendored" / ".env").write_text(f"S={KEY}\n")
    (repo / "vendored" / "readme.md").write_text("sub changed\n")
    (repo / "notes.txt").write_text("notes, changed\n")
    prompt(run, repo, "Change notes.txt")
    (check,) = fake.calls("/check")
    assert KEY.encode() not in check["raw"] and str(outside).encode() not in check["raw"]
    change = check["body"]["change"]
    reasons = {entry["path"]: entry["why"] for entry in change["left_out"]}
    assert reasons["config/.ENV"] == reasons["keys/ID_RSA.PEM"] == reasons["deploy.key"] == "secret"
    # A link is never sent, whatever it points to; one that points at a key file says so.
    assert reasons["pointer"] == reasons["elsewhere"] == reasons["harmless.txt"] == "secret"
    assert "+notes, changed" in change["diff"]
    # The renamed key file: its old name was enough to leave it out, under whatever name it has now.
    assert reasons["plain.json"] == "secret" and "plain.json" not in change["diff"]
    # The submodule is told only as the commit it is at.
    assert "vendored/.env" not in change["diff"]
    (work,) = fake.calls("/work")
    assert KEY.encode() not in work["raw"]


def test_the_developers_index_is_never_written_or_locked_by_any_hook(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    index = repo / ".git" / "index"
    (repo / "calc.py").write_text("def add(a, b):\n    return a + b\n")  # the same text, a newer time
    (repo / "new.py").write_text("n = 1\n")
    os.utime(index, (time.time() - 100, time.time() - 100))

    def seal() -> tuple[bytes, int]:
        return index.read_bytes(), index.stat().st_mtime_ns

    for sharing in ("off", "on"):
        if sharing == "on":
            sharing_on(run, fake, repo)
        before = seal()
        for name, kind in (("session-start", "SessionStart"), ("prompt", "UserPromptSubmit"),
                           ("edited", "PostToolUse"), ("stopped", "Stop"), ("edit-check", "PostToolUse")):
            run("hook", name, stdin=event(kind, repo, prompt="Change calc.py", tool_name="Edit"))
            assert seal() == before, f"{name} with code sharing {sharing} wrote the index"
            assert not (repo / ".git" / "index.lock").exists()
        (run.home / "sessions" / "session-1" / "reported").unlink(missing_ok=True)


def test_a_message_in_a_project_that_is_off_costs_almost_nothing_however_long(run, fake, repo):
    signed_in(run, fake)
    pasted = "\n".join(f'log line {n}: "quoted" \\ path\tvalue' for n in range(20000))
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=pasted), cwd=repo)
    assert done.stdout == "" and fake.requests == []
    print(f"\n[timing] off project, {len(pasted):,} characters: {done.seconds:.3f} s")
    assert done.seconds < 1
    # In a project that is on, the same message is read in time in proportion to its length.
    switched_on(run, fake, repo)
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=pasted), cwd=repo)
    print(f"[timing] on project, {len(pasted):,} characters: {done.seconds:.3f} s")
    assert fake.calls("/check")[0]["body"]["request"] == pasted and done.seconds < 10


def test_a_large_new_file_is_never_read_and_is_left_out_as_past_the_limit(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    with open(repo / "recording.mov", "wb") as big:
        big.truncate(200_000_000)
    (repo / "calc.py").write_text("changed = True\n")
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"), cwd=repo)
    print(f"\n[timing] 200 MB new file, code sharing off: {done.seconds:.3f} s")
    files = {entry["path"]: entry for entry in fake.calls("/work")[0]["body"]["files"]}
    assert files["recording.mov"]["additions"] == 0 and done.seconds < 3
    sharing_on(run, fake, repo)
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"), cwd=repo)
    print(f"[timing] 200 MB new file, code sharing on: {done.seconds:.3f} s")
    change = fake.calls("/check")[0]["body"]["change"]
    assert {"path": "recording.mov", "why": "limit"} in change["left_out"] and change["complete"] is False
    assert done.seconds < 3


def test_signing_out_and_back_in_keeps_code_sharing_on_and_tells_the_new_connection(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / "calc.py").write_text("changed = True\n")
    prompt(run, repo, "Change calc.py")
    run("sign-out", cwd=repo)
    # The server forgets what a connection ended with.
    fake.sharing.clear()
    signed_in(run, fake)
    fake.requests.clear()
    said = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert fake.calls("/sharing")[0]["body"]["on"] is True
    assert "turned off" not in said and "your uncommitted changes" in said
    assert "Code sharing: on" in run("settings", cwd=repo).stdout
    # The same at a session's start, after the connection ended by itself.
    fake.status["/check"] = 401
    prompt(run, repo, "Change calc.py")
    del fake.status["/check"]
    fake.sharing.clear()
    signed_in(run, fake)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert "turned off" not in said and "Code sharing: on" in run("settings", cwd=repo).stdout


def test_a_remote_named_in_other_letter_case_is_the_same_repository(run, fake, repo):
    signed_in(run, fake)
    git(repo, "remote", "set-url", "origin", "git@github.com:ACME/API.git")
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on")))["reason"]
    assert "Vyavastha reads ACME/API for you" in said
    sharing_on(run, fake, repo)
    started = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert "turned off" not in started and "Code sharing: on" in run("settings", cwd=repo).stdout
    assert "ok: Vyavastha reads ACME/API for you." in run("check", cwd=repo).stdout
    assert "Vyavastha reads ACME/API for you" in run("status", cwd=repo).stdout


def test_file_names_that_are_not_utf8_or_hold_a_line_break_still_make_valid_reports(run, fake, repo):
    signed_in(run, fake)
    # A tracked file whose name is in Latin-1, gone from the working tree (made through git, as some file systems
    # refuse such a name).
    blob = git(repo, "hash-object", "-w", "calc.py").strip()
    subprocess.run([b"git", b"-C", bytes(repo), b"update-index", b"--add", b"--cacheinfo",
                    b"100644," + blob.encode() + b",caf\xe9.txt"], check=True)
    git(repo, "commit", "-q", "-m", "Latin-1 name")
    switched_on(run, fake, repo)
    sharing_on(run, fake, repo)
    (repo / "new\nline.py").write_text("x = 1\n")
    (repo / "calc.py").write_text("changed = True\n")
    prompt(run, repo, "Change calc.py")
    # The fake server parses every body as JSON: both arrived.
    (check,) = fake.calls("/check")
    (work,) = fake.calls("/work")
    assert any(entry["path"].startswith("caf") for entry in work["body"]["files"])
    # The new file with a line break in its name is left out, and said so, rather than silently missing.
    assert {"path": "new\nline.py", "why": "binary"} in check["body"]["change"]["left_out"]
    assert check["body"]["change"]["left_out"]


def test_only_web_addresses_are_ever_opened(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    # A page named by an answer that is a program, a file, another site's plain-http address or holds shell words.
    for page in ("/System/Applications/Calculator.app", "-a Calculator", "file:///etc/passwd",
                 "http://evil.example/x", "https://x.test/$(id)"):
        fake.extra["/chat"] = {"url": page, "upload_url": page, "conversation_id": "cnv_7"}
        run("upload", cwd=repo)
    assert run.opened() == []
    del fake.extra["/chat"]
    run("upload", cwd=repo)
    assert run.opened() == ["http://127.0.0.1/c/cnv_7?attach=1"]


def test_a_lone_half_of_a_character_pair_from_the_server_still_prints_valid_text(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = {**fake.check, "notice": "a \ud800 b \U0001F600 c"}
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"), cwd=repo)
    said = json.loads(done.stdout)["systemMessage"]
    assert said.endswith("a � b \U0001F600 c")


def test_a_check_that_brings_a_conflict_says_paused_and_a_hold_says_which_kind(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.extra["/check"] = {"conflict": CONFLICT}
    paused = prompt(run, repo, "Remove the export")
    assert paused["systemMessage"].endswith("Paused: something your team has said stands against the changes already "
                                            "made on your computer. Your message waits until you answer.")
    assert "nothing stands against" not in paused["systemMessage"]
    fake.extra.clear()
    prompt(run, repo, "stop")
    fake.check = {"verdict": "held", "hold": True, "notice": "On hold: something your team has said stands against "
                  "this change, so it wasn’t sent to Claude.\n• Priya: keep it.", "context": "c",
                  "anyway": {"phrase": "Plan it anyway", "context": "go"}}
    held = prompt(run, repo, "Remove it")
    assert held["systemMessage"].endswith("· On hold; see below.")
    fake.check = {**fake.check, "verdict": "unclear"}
    held = prompt(run, repo, "Remove it")
    assert held["systemMessage"].endswith("· On hold: what your team has said doesn’t settle this request; see below.")


def test_vyavastha_on_while_signed_out_opens_sign_in_once_and_says_what_finishes_it(run, fake, repo):
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on")))["reason"]
    assert "Once you approve, your next message finishes connecting." in said
    assert run.opened() == ["http://127.0.0.1/connect"]
    nxt = prompt(run, repo, "Change calc.py")["systemMessage"]
    assert run.opened() == ["http://127.0.0.1/connect"] and "Enter the code BCDF-GHJK" in nxt


def test_a_session_start_says_connected_once_and_what_a_folder_not_read_does(run, fake, repo, tmp_path):
    switched_on(run, fake, repo)
    run("sign-in", cwd=repo)
    fake.approved = True
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert said.startswith("Vyavastha: connected as sam@acme.test in Acme. Requests are checked")
    assert said.count("onnected as") == 1
    git(repo, "remote", "set-url", "origin", "https://github.com/acme/web.git")
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo, session="s2")))["systemMessage"]
    assert said == ("Vyavastha: signed in as sam@acme.test in Acme. Vyavastha doesn’t read acme/web for you, so "
                    "requests here aren’t checked; questions about your team are still answered.")


def test_signing_out_says_nothing_is_sent_and_help_names_the_typed_only_commands(run, fake, repo):
    signed_in(run, fake)
    assert run("sign-out", cwd=repo).stdout.strip() == ("Signed out of Vyavastha on this computer. Requests are no "
                                                        "longer checked, and nothing is sent from this computer.")
    text = run("help", cwd=repo).stdout
    assert "ask, assign, reply, start, done and decline are typed only" in text
    assert "It answers only from what you can both already see" in text


def test_a_slow_teammate_answer_is_said_once(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.tell_slow = 99
    fake.tell = {**fake.tell, "notice": "Priya’s agent is still working on the answer. It will be in Vyavastha when "
                                        "it is done: http://127.0.0.1/?agent-chat=usr_p"}
    said = run("tell", "Priya", "what is the plan?", cwd=repo).stdout
    assert "is still answering" not in said and said.count("still working") == 1
    assert said.count("http://127.0.0.1/?agent-chat=usr_p") == 1


# -- summaries: the session's own messages and replies, kept for the developer's summary ----------------------------

KEPT = "Kept in this session’s chat for your summary."


def stop(run, repo: Path, session: str = "session-1", tool: str | None = None, **fields):
    """The Stop hook, as both tools run it at the end of a turn, with what the turn's input carries."""
    return run("hook", "stopped", stdin=event("Stop", repo, session=session, stop_hook_active=False, **fields),
               cwd=repo, tool=tool)


def test_vyavastha_on_says_in_one_sentence_that_summaries_keep_messages_and_replies_and_how_to_stop(run, fake, repo):
    signed_in(run, fake)
    reason = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on")))["reason"]
    assert ("Summaries are on: your messages here and Claude Code’s replies, as written, are kept in a chat of your "
            "own in Vyavastha and summed up for teammates under categories you control there. A reply can quote code "
            "or what a file holds. Nothing else of the conversation is kept: not Claude Code’s other steps, the "
            "commands it ran or the files it read. Send “vyavastha summaries off” to stop.") in reason.splitlines()
    # Nothing it says claims that what files hold never leaves the computer: a reply can quote it.
    assert "not what they hold" not in reason and "never what" not in reason
    codex = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on"),
                       tool="codex"))["reason"]
    assert "Codex’s replies, as written, are kept" in codex and "/vyavastha:" not in codex and "Claude" not in codex


def test_with_summaries_on_the_message_is_kept_and_the_reply_goes_to_its_chat_when_the_tool_stops(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    # A project turned on keeps no setting of its own for summaries: they are on, as for one turned on before the
    # setting existed.
    assert not list(run.home.glob("projects/*/summaries"))
    said = prompt(run, repo, "Change calc.py")
    assert fake.calls("/check")[0]["body"]["keep"] is True
    assert said["systemMessage"].startswith(f"Vyavastha · sent: your message. {KEPT} · ")
    reply = 'Renamed "add" to sum\\plus in calc.py — façade kept 👍\n\n\tand the tests pass.\r\n'
    done = stop(run, repo, last_assistant_message=reply)
    assert done.stdout == ""
    (turn,) = fake.calls("/turn")
    assert turn["body"] == {"session": "session-1", "remote": "https://github.com/acme/api.git", "branch": "main",
                            "tool": "claude-code", "keep": True, "message_id": "msg_1", "reply": reply}
    assert b"hunter2" not in turn["raw"] and b"transcript" not in turn["raw"]
    # Once for each kept message: a turn that follows none sends nothing.
    stop(run, repo, last_assistant_message="More.")
    assert len(fake.calls("/turn")) == 1


@pytest.mark.parametrize("reply, kept", [
    ("a" * 5000, "a" * 4000),
    ("a" * 3999 + "👍" + "b" * 10, "a" * 3999 + "👍"),
    ("a" * 4000 + "👍", "a" * 4000),
    ("é" * 3998 + "\n\n" + "é" * 5, "é" * 3998 + "\n\n"),
    ("line\n" * 1000, "line\n" * 800),
    ('"\\' * 3000, '"\\' * 2000),
])
def test_a_long_reply_is_cut_to_4000_characters_never_inside_a_character(run, fake, repo, reply, kept):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py")
    stop(run, repo, last_assistant_message=reply)
    assert fake.calls("/turn")[0]["body"]["reply"] == kept


def test_a_very_long_reply_with_many_escapes_is_cut_quickly(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py")
    reply = ('He said "yes" \\ and 👍 é\n' * 60_000)
    done = stop(run, repo, last_assistant_message=reply)
    assert done.stdout == "" and done.seconds < 5
    assert fake.calls("/turn")[0]["body"]["reply"] == reply[:4000]


def test_a_reply_with_bytes_that_are_not_utf8_is_sent_as_valid_text_without_them(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py")
    stdin = json.dumps(event("Stop", repo, stop_hook_active=False, last_assistant_message="Done BAD here — ok 👍"),
                       ensure_ascii=False).encode().replace(b"BAD", b"\xff\xfe\xc3")
    done = run("hook", "stopped", raw=stdin, cwd=repo)
    assert done.stdout == ""
    assert fake.calls("/turn")[0]["body"]["reply"] == "Done  here — ok 👍"


@pytest.mark.parametrize("tool", [None, "codex"])
def test_a_null_or_missing_reply_is_sent_empty(run, fake, repo, tool):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py", tool=tool)
    stop(run, repo, tool=tool, last_assistant_message=None)
    prompt(run, repo, "Change calc.py", tool=tool)
    stop(run, repo, tool=tool)
    assert [call["body"]["reply"] for call in fake.calls("/turn")] == ["", ""]
    assert fake.calls("/turn")[0]["body"]["tool"] == ("codex" if tool else "claude-code")


def test_with_summaries_off_nothing_is_kept_and_no_reply_is_sent(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    off = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Vyavastha summaries off.")))
    assert off["decision"] == "block" and off["hookSpecificOutput"]["suppressOriginalPrompt"] is True
    assert off["reason"].startswith("Summaries are off for api: from now on nothing you write in this project, and "
                                    "none of Claude Code’s replies, is kept or summed up for teammates. A question "
                                    "about your team is still answered by Vyavastha’s assistant. It stays in your "
                                    "chat there, where you can delete it.")
    assert "“vyavastha summaries on”" in off["reason"] and not fake.calls("/check")
    said = prompt(run, repo, "Change calc.py")
    assert fake.calls("/check")[0]["body"]["keep"] is False
    assert said["systemMessage"].startswith("Vyavastha · sent: your message. Not kept, because summaries are off. · ")
    stop(run, repo, last_assistant_message="Done.")
    assert not fake.calls("/turn")
    # Turned off between the message and the end of its turn: the reply is not sent either.
    on = run("summaries", "on", cwd=repo).stdout
    assert on.startswith("Summaries are on for api: your messages here and Claude Code’s replies, as written, are "
                         "kept in this session’s chat in Vyavastha, which only you read")
    assert ("A reply can quote code or what a file holds. Nothing else of the conversation is kept: not Claude "
            "Code’s other steps, the commands it ran or the files it read.") in on.splitlines()
    prompt(run, repo, "Change calc.py")
    run("summaries", "off", cwd=repo)
    stop(run, repo, last_assistant_message="Done.")
    assert not fake.calls("/turn")


def test_the_plugins_own_commands_and_answers_to_its_questions_are_never_kept(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    for typed in ("vyavastha status", "vyavastha summaries on", "vyavastha help"):
        prompt(run, repo, typed)
    assert not fake.calls("/check")
    for words in ("continue", "Stop.", "Plan it anyway"):
        said = prompt(run, repo, words)
        assert fake.calls("/check")[-1]["body"]["keep"] is False
        assert "Not kept for your summary." in said["systemMessage"]
    stop(run, repo, last_assistant_message="Done.")
    assert not fake.calls("/turn")
    # A question goes on to the assistant, whose chat already holds it: the reply is not added again.
    fake.check = dict(QUESTION)
    said = prompt(run, repo, "What is Priya working on?")
    assert fake.calls("/check")[-1]["body"]["keep"] is True and fake.calls("/ask")
    assert "kept" not in said["systemMessage"].lower()
    stop(run, repo, last_assistant_message="Priya is moving the export.")
    assert not fake.calls("/turn")


def test_a_project_that_is_off_sends_no_message_and_no_reply(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    run("off", cwd=repo)
    fake.requests.clear()
    assert prompt(run, repo, "Change calc.py") == {}
    assert stop(run, repo, last_assistant_message="Done.").stdout == "" and fake.requests == []
    # A message kept before the project was turned off: its reply is not sent while it is off.
    run("on", cwd=repo)
    prompt(run, repo, "Change calc.py")
    run("off", cwd=repo)
    fake.requests.clear()
    stop(run, repo, last_assistant_message="Done.")
    assert fake.requests == []


def test_the_stop_hook_stays_quiet_and_quick_when_the_reply_cannot_be_sent(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    for status in (500, 404, 401):
        signed_in(run, fake)
        (run.home / "offline").unlink(missing_ok=True)
        prompt(run, repo, "Change calc.py")
        fake.status["/turn"] = status
        done = stop(run, repo, last_assistant_message="Done.")
        assert done.stdout == "" and done.seconds < 5
    del fake.status["/turn"]
    signed_in(run, fake)
    (run.home / "offline").unlink(missing_ok=True)
    prompt(run, repo, "Change calc.py")
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        closed = probe.getsockname()[1]
    (run.home / "credentials").write_text(f"server=http://127.0.0.1:{closed}\ntoken={TOKEN}\n")
    done = run("hook", "stopped", stdin=event("Stop", repo, last_assistant_message="Done."), cwd=repo,
               server=f"http://127.0.0.1:{closed}")
    assert done.stdout == "" and done.seconds < 5
    # Signed out: nothing is sent and nothing is said.
    (run.home / "credentials").unlink()
    (run.home / "offline").unlink(missing_ok=True)
    fake.requests.clear()
    assert stop(run, repo, last_assistant_message="Done.").stdout == "" and fake.requests == []


def test_settings_status_check_and_help_list_summaries(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    assert "- Summaries: on. Send “vyavastha summaries off” to turn them off." in run("settings", cwd=repo).stdout
    assert "Summaries are on for this project." in run("status", cwd=repo).stdout
    assert any(line.startswith("ok: summaries are on") for line in run("check", cwd=repo).stdout.splitlines())
    run("summaries", "off", cwd=repo)
    assert "- Summaries: off. Send “vyavastha summaries on” to turn them on." in run("settings", cwd=repo).stdout
    assert "Summaries are off for this project." in run("status", cwd=repo).stdout
    assert any(line.startswith("ok: summaries are off") for line in run("check", cwd=repo).stdout.splitlines())
    for tool in (None, "codex"):
        assert "“vyavastha summaries on” / “vyavastha summaries off”" in run("help", cwd=repo, tool=tool).stdout
    # Off and on again keeps the choice, as it keeps the code-sharing choice.
    run("off", cwd=repo)
    run("on", cwd=repo)
    assert "- Summaries: off." in run("settings", cwd=repo).stdout


def test_the_summaries_commands_are_skills_in_claude_code_and_phrases_in_codex():
    for name, words in (("summaries-on", "summaries on"), ("summaries-off", "summaries off")):
        text = (PLUGIN / "skills" / name / "SKILL.md").read_text()
        head = text.split("---")[1]
        assert "description: " in head and "disable-model-invocation: true" in head
        assert f'!`sh "${{CLAUDE_PLUGIN_ROOT}}/scripts/vyavastha.sh" {words} || true`' in text
    codex_skill = (PLUGIN / "codex" / "skills" / "vyavastha" / "SKILL.md").read_text()
    assert "`vyavastha summaries on` / `vyavastha summaries off`" in codex_skill and "/vyavastha:" not in codex_skill


def test_with_summaries_off_a_question_is_still_asked_but_never_summed_up(run, fake, repo, tmp_path):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    fake.check = dict(QUESTION)
    prompt(run, repo, "What is Priya working on?")
    run("ask", "And Sam?", cwd=repo)
    assert [call["body"]["keep"] for call in fake.calls("/ask")] == [True, True]
    run("summaries", "off", cwd=repo)
    fake.requests.clear()
    said = prompt(run, repo, "What is Priya working on?")
    assert said["hookSpecificOutput"]["additionalContext"] == fake.asked["context"]
    run("ask", "And Sam?", cwd=repo)
    assert [call["body"]["keep"] for call in fake.calls("/ask")] == [False, False]
    # What “summaries off” is said to mean names the question that is still answered.
    for told in (run("settings", cwd=repo).stdout, run("check", cwd=repo).stdout,
                 output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha on")))["reason"]):
        if "Summaries are off:" in told or "summaries are off, so" in told:
            assert ("nothing you write in this project, and none of Claude Code’s replies, is kept or summed up for "
                    "teammates. A question about your team is still answered by Vyavastha’s assistant.") in told
    # The model's own question from a folder where the plugin is off is never summed up either.
    outside = tmp_path / "elsewhere"
    outside.mkdir()
    run("summaries", "on", cwd=repo)
    fake.requests.clear()
    run("ask", "What is Priya doing?", cwd=outside)
    assert fake.calls("/ask")[-1]["body"]["keep"] is False


def test_a_turn_that_never_ended_never_files_a_later_reply_under_its_message(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    # A kept message whose turn never came to its end, then one of the plugin's commands, then a turn's end.
    prompt(run, repo, "Change calc.py")
    prompt(run, repo, "vyavastha status")
    stop(run, repo, last_assistant_message="The status, as Claude saw it.")
    assert not fake.calls("/turn")
    # The same with a check that was refused in between.
    prompt(run, repo, "Change calc.py")
    fake.status["/check"] = 429
    prompt(run, repo, "Change old.py")
    del fake.status["/check"]
    stop(run, repo, last_assistant_message="Changed old.py.")
    assert not fake.calls("/turn")
    # And with a new session in between.
    prompt(run, repo, "Change calc.py")
    run("hook", "session-start", stdin=event("SessionStart", repo, source="resume"), cwd=repo)
    stop(run, repo, last_assistant_message="Resumed.")
    assert not fake.calls("/turn")
    # A later turn's reply goes to its own message, named by the id the check gave it.
    prompt(run, repo, "Change gone.py")
    kept_id = f"msg_{len(fake.calls('/check'))}"
    stop(run, repo, last_assistant_message="Changed gone.py.")
    (turn,) = fake.calls("/turn")
    assert turn["body"]["message_id"] == kept_id and turn["body"]["reply"] == "Changed gone.py."
    # A server that names no kept message: the reply is sent without an id, and the server pairs it as before.
    fake.extra["/check"] = {"kept_id": None}
    prompt(run, repo, "Change calc.py")
    stop(run, repo, last_assistant_message="Done.")
    assert "message_id" not in fake.calls("/turn")[-1]["body"]


@pytest.mark.parametrize("words", ["Plan it anyway", "plan  it ANYWAY!", "continue", "Continue anyway?",
                                   "go on", "Go\ton.", "stop", "  STOP !"])
def test_the_phrases_never_kept_are_matched_whatever_their_case_spacing_or_closing_mark(run, fake, repo, words):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    said = prompt(run, repo, words)
    assert fake.calls("/check")[-1]["body"]["keep"] is False
    assert "Not kept for your summary." in said["systemMessage"]


def test_the_script_and_the_readme_list_the_same_phrases_never_kept():
    script = SCRIPT.read_text()
    case = script.split("never_kept() {", 1)[1].split("esac", 1)[0]
    in_script = [part.strip().strip('"') for part in case.split("case \"$1\" in", 1)[1].split(")", 1)[0].split("|")]
    readme = (PLUGIN.parents[1] / "README.md").read_text()
    line = next(line for line in readme.splitlines() if line.startswith("- **Never kept:**"))
    listed = line.split("questions:", 1)[1].split("(", 1)[0]
    in_readme = [phrase.lower() for phrase in __import__("re").findall(r"`([^`]+)`", listed)]
    assert in_script == in_readme == ["plan it anyway", "continue", "continue anyway", "go on", "stop"]


def test_the_end_of_a_turn_waits_at_most_four_seconds_for_the_reply_to_be_taken(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py")
    fake.delay["/turn"] = 12
    done = stop(run, repo, last_assistant_message="Done.")
    assert done.stdout == "" and done.seconds < 6.5
    assert len(fake.calls("/turn")) == 1


def test_no_reply_is_sent_when_the_report_just_before_found_the_server_out_of_reach(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    prompt(run, repo, "Change calc.py")
    (repo / "calc.py").write_text("changed\n")
    # A report that takes too long: the turn's end is not held up a second time.
    fake.delay["/work"] = 12
    done = stop(run, repo, last_assistant_message="Done.")
    assert done.stdout == "" and done.seconds < 10.5
    assert fake.calls("/work") and not fake.calls("/turn")
    # A report the server failed: the same.
    del fake.delay["/work"]
    (run.home / "offline").unlink(missing_ok=True)
    prompt(run, repo, "Change calc.py")
    fake.status["/work"] = 503
    stop(run, repo, last_assistant_message="Done.")
    assert not fake.calls("/turn")


def test_a_project_turned_on_before_summaries_is_told_once_and_that_first_message_is_not_kept(run, fake, repo):
    signed_in(run, fake)
    switched_on(run, fake, repo)
    # “vyavastha on” in this version told it, and marks the project so.
    assert list(run.home.glob("projects/*/summaries-told"))
    first = prompt(run, repo, "Change calc.py")
    assert fake.calls("/check")[-1]["body"]["keep"] is True and "Summaries are on in this project" not in str(first)
    # A project turned on by an earlier version has no such mark: its first message's line tells, and that message
    # is not kept, nor its question summed up.
    for told in run.home.glob("projects/*/summaries-told"):
        told.unlink()
    fake.check = dict(QUESTION)
    said = prompt(run, repo, "What is Priya working on?")
    assert fake.calls("/ask")[-1]["body"]["keep"] is False and fake.calls("/check")[-1]["body"]["keep"] is False
    assert said["systemMessage"].endswith(
        " Summaries are on in this project: from your next message, your messages here and Claude Code’s replies, as "
        "written, are kept in a chat of your own in Vyavastha and summed up for teammates, until you send “vyavastha "
        "summaries off”.")
    fake.check = {"verdict": "clear", "hold": False, "notice": "Checked.", "context": "c", "statements": []}
    again = prompt(run, repo, "Change calc.py")
    assert fake.calls("/check")[-1]["body"]["keep"] is True and "Summaries are on in this project" not in str(again)
    # A session start tells it when it comes first; the message after it is kept.
    for told in run.home.glob("projects/*/summaries-told"):
        told.unlink()
    started = output(run("hook", "session-start", stdin=event("SessionStart", repo, session="s2"), cwd=repo))
    assert "Summaries are on in this project: from your next message" in started["systemMessage"]
    prompt(run, repo, "Change calc.py", session="s2")
    assert fake.calls("/check")[-1]["body"]["keep"] is True
    # With summaries off there is nothing to tell.
    for told in run.home.glob("projects/*/summaries-told"):
        told.unlink()
    (next(run.home.glob("projects/*")) / "summaries").write_text("off\n")
    said = prompt(run, repo, "Change calc.py", session="s3")
    assert "Summaries are on in this project" not in said["systemMessage"]
