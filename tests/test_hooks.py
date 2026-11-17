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

import pytest

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "vyavastha"
SCRIPT = PLUGIN / "scripts" / "vyavastha.sh"
SHELLS = [shell for shell in ("sh", "dash") if shutil.which(shell)]
TOKEN = "vyv-tool-secret-token-value"
SECRET = "THE-FILE-CONTENTS-NEVER-LEAVE"


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
                path = self.path.removeprefix("/api/v1/plugin")
                fake.requests.append({"method": self.command, "path": path, "headers": dict(self.headers),
                                      "raw": raw, "body": json.loads(raw) if raw else None})
                if path in fake.status:
                    return self._answer(fake.status[path], {"detail": {"code": "x", "message": "Refused."}})
                signed = self.headers.get("Authorization") == f"Bearer {TOKEN}"
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
                                              "repositories": ["acme/api"]})
                if path == "/check":
                    return self._answer(200, fake.check)
                if path == "/ask":
                    # (An answer that is slow is still being made on the first calls for it.)
                    if fake.slow > 0 and len(fake.calls("/ask")) <= fake.slow:
                        return self._answer(200, {"status": "pending", "answer": "", "context": "", "notice":
                                                  "Vyavastha is still working on the answer.", "waiting": "msg_9"})
                    return self._answer(200, fake.asked)
                if path == "/work":
                    state = fake.requests[-1]["body"]["state"]
                    status = {"changing": "local"}.get(state, state)
                    return self._answer(200, {"recorded": True, "work_id": "wrk_1", "changed": True, "status": status})
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

    def run_(*args: str, stdin: dict | None = None, server: str | None = None, cwd: Path | None = None,
             tool: str | None = None):
        env = {"PATH": os.environ["PATH"], "HOME": str(tmp_path), "VYAVASTHA_HOME": str(home),
               "VYAVASTHA_SERVER": server or fake.url, "CLAUDE_PROJECT_DIR": str(cwd or tmp_path)}
        if tool:
            # As Codex's hooks file sets it; Claude Code's sets nothing.
            env["VYAVASTHA_TOOL"] = tool
        started = time.monotonic()
        done = subprocess.run([request.param, str(SCRIPT), *args], input=json.dumps(stdin) if stdin else "",
                              capture_output=True, text=True, env=env, cwd=cwd or tmp_path, timeout=60)
        done.seconds = time.monotonic() - started
        assert done.returncode == 0, done.stderr
        return done

    run_.home = home
    return run_


def output(done) -> dict:
    """What the hook printed, which Claude Code reads as one JSON object."""
    return json.loads(done.stdout) if done.stdout.strip() else {}


def event(name: str, repo: Path, session: str = "session-1", **fields) -> dict:
    """A hook's input as Claude Code sends it, transcript path and all."""
    return {"session_id": session, "transcript_path": "/home/sam/.claude/projects/x/transcript.jsonl",
            "cwd": str(repo), "permission_mode": "default", "hook_event_name": name, **fields}


def signed_in(run, fake: Fake) -> None:
    run.home.mkdir(parents=True, exist_ok=True)
    (run.home / "credentials").write_text(f"server={fake.url}\ntoken={TOKEN}\nemail=sam@acme.test\nworkspace=Acme\n")


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
    assert "This repository, acme/api, is connected" in status.stdout
    credentials = run.home / "credentials"
    assert TOKEN in credentials.read_text()
    assert stat.S_IMODE(credentials.stat().st_mode) == 0o600 and stat.S_IMODE(run.home.stat().st_mode) == 0o700
    assert not (run.home / "pairing").exists()
    # The token goes in a header, and is never written anywhere else.
    assert fake.calls("/me")[-1]["headers"]["Authorization"] == f"Bearer {TOKEN}"


def test_a_pairing_approved_while_away_is_finished_by_the_next_prompt(run, fake, repo):
    run("sign-in", cwd=repo)
    fake.approved = True
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Make the trial 30 days in calc.py"))
    said = output(done)
    assert said["systemMessage"].startswith("Vyavastha: connected as sam@acme.test in Acme.")
    assert fake.calls("/check")


def test_signing_out_ends_the_token_on_the_server_and_forgets_it(run, fake, repo):
    signed_in(run, fake)
    assert "Signed out" in run("sign-out", cwd=repo).stdout
    assert fake.calls("/signout") and not (run.home / "credentials").exists()


def test_a_token_is_never_sent_to_a_server_other_than_the_one_that_gave_it(run, fake, repo, tmp_path):
    signed_in(run, fake)
    other = Fake()
    try:
        run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"), server=other.url)
        assert all("Authorization" not in request["headers"] for request in other.requests)
    finally:
        other.server.shutdown()


def test_a_server_address_that_is_not_https_or_this_computer_is_refused_without_a_call(run, fake, repo):
    done = run("status", server="http://vyavasta.example", cwd=repo)
    assert "isn’t one this plugin uses" in done.stdout and fake.requests == []


# -- the check before Claude changes code ---------------------------------------------------------------------

def test_a_clear_request_reaches_claude_with_the_facts_and_sends_only_what_the_check_needs(run, fake, repo):
    signed_in(run, fake)
    prompt = 'Rename "add" to sum\\plus in calc.py — keep the façade 👍\nand the tests'
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=prompt)))
    assert said["hookSpecificOutput"] == {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": fake.check["context"]}
    assert said["systemMessage"] == fake.check["notice"]
    (sent,) = fake.calls("/check")
    # The request word for word; the repository without its credential; nothing of the transcript or the folder.
    assert sent["body"] == {"request": prompt, "remote": "https://github.com/acme/api.git", "branch": "main",
                            "session": "session-1", "tool": "claude-code"}
    assert b"hunter2" not in sent["raw"] and b"transcript" not in sent["raw"] and str(repo).encode() not in sent["raw"]


def test_a_held_request_is_kept_from_claude_and_plan_it_anyway_sends_it_with_what_stands(run, fake, repo):
    signed_in(run, fake)
    fake.check = {"verdict": "held", "hold": True, "repository": "acme/api",
                  "notice": "On hold: something your team has said stands against this change.\n"
                            "• Priya Raman’s decision: keep it.\nTo go ahead anyway, send “Plan it anyway”.",
                  "context": "Vyavastha checked this request: Priya’s decision stands.",
                  "anyway": {"phrase": "Plan it anyway",
                             "context": "The developer chose to go ahead anyway. Their request: “Remove it”."}}
    held = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Remove it from calc.py")))
    assert held == {"decision": "block", "reason": fake.check["notice"]}
    going = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="plan it anyway.")))
    assert going["hookSpecificOutput"]["additionalContext"] == fake.check["anyway"]["context"]
    assert "going ahead" in going["systemMessage"]
    # Going ahead asked the server nothing, and works once.
    assert len(fake.calls("/check")) == 1
    again = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Plan it anyway"))
    assert len(fake.calls("/check")) == 2 and "decision" in output(again)


def test_a_hold_is_forgotten_once_the_developer_asks_for_something_else(run, fake, repo):
    signed_in(run, fake)
    fake.check = {"verdict": "held", "hold": True, "notice": "On hold.", "context": "x",
                  "anyway": {"phrase": "Plan it anyway", "context": "chose to go on"}}
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Remove it from calc.py"))
    fake.check = {"verdict": "not_a_change", "hold": False, "notice": "", "context": ""}
    assert output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="What does calc.py do?"))) == {}
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Plan it anyway"))
    assert len(fake.calls("/check")) == 3


def test_signed_out_a_prompt_goes_on_unchecked_with_one_note_a_session(run, fake, repo):
    first = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py")))
    assert "not signed in" in first["systemMessage"]
    assert output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"))) == {}
    assert fake.requests == []


def test_a_server_out_of_reach_never_holds_the_developer_up(run, fake, repo):
    signed_in(run, fake)
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        closed = probe.getsockname()[1]
    (run.home / "credentials").write_text(f"server=http://127.0.0.1:{closed}\ntoken={TOKEN}\n")
    first = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"),
                server=f"http://127.0.0.1:{closed}")
    assert "can’t be reached" in output(first)["systemMessage"]
    # Found out of reach a moment ago: the next prompt doesn't even try, and says nothing more.
    second = run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"),
                 server=f"http://127.0.0.1:{closed}")
    assert second.stdout == "" and second.seconds < 2


def test_a_connection_ended_in_settings_signs_this_computer_out(run, fake, repo):
    signed_in(run, fake)
    fake.status["/check"] = 401
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py")))
    assert "connection has ended" in said["systemMessage"] and not (run.home / "credentials").exists()


def test_a_slash_command_is_not_sent_and_a_folder_outside_git_names_no_repository(run, fake, repo, tmp_path):
    signed_in(run, fake)
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="/vyavastha:status"))
    assert fake.calls("/check") == []
    # Outside a repository a question about the team can still be asked, so the words are sent, with no remote;
    # the server says nothing of a folder it has nothing to check in, and nothing is printed.
    fake.check = {"verdict": "not_connected", "hold": False, "notice": "", "context": "", "statements": []}
    outside = tmp_path / "notes"
    outside.mkdir()
    done = run("hook", "prompt", stdin=event("UserPromptSubmit", outside, prompt="Change the notes"), cwd=outside)
    (sent,) = fake.calls("/check")
    assert sent["body"]["remote"] == "" and sent["body"]["branch"] == "" and done.stdout.strip() == ""


# -- questions ---------------------------------------------------------------------------------------------------

QUESTION = {"verdict": "question", "hold": False, "ask": True, "notice": "", "context": "", "statements": []}


def test_a_question_about_the_team_is_asked_in_vyavastha_and_the_answer_is_given_to_the_model(run, fake, repo,
                                                                                            tmp_path):
    signed_in(run, fake)
    fake.check = QUESTION
    asking = 'See what "Priya" is doing'
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=asking)))
    (sent,) = fake.calls("/ask")
    assert sent["body"] == {"question": asking, "remote": "https://github.com/acme/api.git", "branch": "main",
                            "session": "session-1", "tool": "claude-code"}
    # The model is given the answer as the server worded it, non-ASCII and all; the developer is told it was asked.
    assert said["hookSpecificOutput"] == {"hookEventName": "UserPromptSubmit",
                                          "additionalContext": fake.asked["context"]}
    assert said["systemMessage"] == fake.asked["notice"] and "decision" not in said
    # From a folder that is no repository it is asked all the same.
    outside = tmp_path / "notes"
    outside.mkdir()
    again = output(run("hook", "prompt", stdin=event("UserPromptSubmit", outside, prompt=asking), cwd=outside))
    assert again["hookSpecificOutput"]["additionalContext"] == fake.asked["context"]
    assert fake.calls("/ask")[-1]["body"]["remote"] == ""


def test_a_slow_answer_is_waited_for_over_several_short_calls_and_then_given_up_on(run, fake, repo):
    signed_in(run, fake)
    fake.check = QUESTION
    fake.slow = 2
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="What is Priya doing?")))
    assert said["hookSpecificOutput"]["additionalContext"] == fake.asked["context"]
    first, second, third = fake.calls("/ask")
    assert first["body"]["question"] == "What is Priya doing?"
    assert second["body"] == third["body"] == {"waiting": "msg_9", "tool": "claude-code"}
    # One that never comes: the model has the message as it is, and the developer is told where the answer will be.
    fake.requests.clear()
    fake.slow = 99
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="What is Priya doing?")))
    assert said == {"systemMessage": "Vyavastha is still working on the answer."} and len(fake.calls("/ask")) == 6


def test_a_question_with_no_answer_goes_to_the_model_as_it_is_with_a_note(run, fake, repo):
    signed_in(run, fake)
    fake.check = QUESTION
    fake.asked = {"status": "failed", "answer": "", "context": "", "conversation_id": None, "url": None,
                  "notice": "The assistant model couldn’t answer. Your message is saved; try again."}
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="What is Priya doing?")))
    assert said == {"systemMessage": fake.asked["notice"]}
    fake.status["/ask"] = 500
    said = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="What is Priya doing?")))
    assert said == {"systemMessage": "Vyavastha: your question couldn’t be asked just now, so Claude answers by itself."}


def test_the_model_can_ask_vyavastha_itself_in_the_session_the_developer_last_wrote_in(run, fake, repo):
    assert "Not signed in" in run("ask", "What is Priya doing?", cwd=repo).stdout and fake.calls("/ask") == []
    signed_in(run, fake)
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, session="session-7", prompt="Fix the rounding"))
    done = run("ask", "What is Priya doing?", cwd=repo)
    assert done.stdout.startswith(fake.asked["answer"]) and "http://127.0.0.1/c/cnv_1" in done.stdout
    assert TOKEN not in done.stdout
    assert fake.calls("/ask")[-1]["body"] == {"question": "What is Priya doing?", "branch": "main",
                                              "remote": "https://github.com/acme/api.git", "session": "session-7",
                                              "tool": "claude-code"}
    fake.asked = {"status": "pending", "answer": "", "context": "", "notice": "Vyavastha is still working on it."}
    assert run("ask", "And Sam?", cwd=repo).stdout.strip() == "Vyavastha gave no answer: Vyavastha is still working on it."
    assert "Usage" in run("ask", cwd=repo).stdout
    # A session's start tells the model what Vyavastha is for and the command that asks it, by this script's path.
    told = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["hookSpecificOutput"]
    assert told["hookEventName"] == "SessionStart"
    assert f'sh "{SCRIPT}" ask "<the question>"' in told["additionalContext"]
    codex = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))
    assert f'VYAVASTHA_TOOL=codex sh "{SCRIPT}" ask' in codex["hookSpecificOutput"]["additionalContext"]


def test_a_repository_not_connected_is_said_once_a_session(run, fake, repo):
    signed_in(run, fake)
    fake.check = {"verdict": "not_connected", "hold": False, "notice": "Not checked: not connected.", "context": ""}
    assert output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py")))
    assert output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Change calc.py"))) == {}


# -- telling teammates what is changing ------------------------------------------------------------------------

def test_an_edit_reports_gits_own_list_of_changes_with_counts_and_never_what_files_hold(run, fake, repo):
    signed_in(run, fake)
    run("hook", "session-start", stdin=event("SessionStart", repo, source="startup"))
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


def test_when_claude_stops_the_work_is_told_as_committed_pushed_or_set_aside(run, fake, repo, tmp_path):
    signed_in(run, fake)
    upstream = tmp_path / "upstream.git"
    git(tmp_path, "init", "-q", "--bare", str(upstream))
    git(repo, "remote", "add", "mirror", str(upstream))
    git(repo, "push", "-q", "mirror", "main")
    git(repo, "branch", "-q", "--set-upstream-to=mirror/main")
    stop = event("Stop", repo, stop_hook_active=False)
    run("hook", "session-start", stdin=event("SessionStart", repo, source="startup"))
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
    (repo / "calc.py").write_text("changed\n")
    run("hook", "stopped", stdin=event("Stop", repo))
    assert fake.requests == []


# -- at the start of a session --------------------------------------------------------------------------------

def test_a_session_starts_by_saying_where_it_is_signed_in(run, fake, repo):
    assert "not signed in" in output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    signed_in(run, fake)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo)))["systemMessage"]
    assert said.startswith("Vyavastha: signed in as sam@acme.test in Acme.") and TOKEN not in said


# -- under Codex -----------------------------------------------------------------------------------------------------

def test_under_codex_the_script_names_codex_and_says_which_tool_it_is(run, fake, repo):
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))["systemMessage"]
    assert "Send “vyavastha sign in” to connect" in said and "Claude" not in said and "/vyavastha:" not in said
    signed_in(run, fake)
    said = output(run("hook", "session-start", stdin=event("SessionStart", repo), tool="codex"))["systemMessage"]
    assert "before Codex changes code" in said and "Claude" not in said
    run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Make the trial 30 days"), tool="codex")
    (sent,) = fake.calls("/check")
    assert sent["body"]["tool"] == "codex" and sent["headers"]["User-Agent"].startswith("vyavastha-codex/")


@pytest.mark.parametrize("typed", ["vyavastha sign in", "Vyavastha sign-in.", "  VYAVASTHA  SIGN IN  "])
def test_the_commands_sent_as_plain_messages_are_answered_by_the_plugin_and_never_reach_the_model(
        run, fake, repo, typed):
    started = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt=typed), tool="codex"))
    # Held back from the model, with what the command said as the reason the developer sees.
    assert started["decision"] == "block" and "BCDF-GHJK" in started["reason"]
    assert "To connect Codex on" in started["reason"] and "device-secret" not in started["reason"]
    assert fake.calls("/pair")[0]["body"]["tool"] == "codex" and not fake.calls("/check")
    fake.approved = True
    status = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha status"),
                        tool="codex"))
    assert status["decision"] == "block" and "connected as sam@acme.test in Acme" in status["reason"]
    assert "This repository, acme/api, is connected" in status["reason"] and TOKEN not in status["reason"]
    out = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="vyavastha sign out"),
                     tool="codex"))
    assert out["decision"] == "block" and "Signed out" in out["reason"]
    assert fake.calls("/signout") and not (run.home / "credentials").exists() and not fake.calls("/check")


def test_a_request_that_only_mentions_the_commands_is_checked_like_any_other(run, fake, repo):
    signed_in(run, fake)
    said = output(run("hook", "prompt", tool="codex",
                      stdin=event("UserPromptSubmit", repo, prompt="Add a vyavastha sign in button to the page")))
    assert "decision" not in said and fake.calls("/check") and not fake.calls("/pair")


def test_a_held_request_under_codex_is_blocked_in_the_form_codex_reads(run, fake, repo):
    signed_in(run, fake)
    fake.check = {"verdict": "held", "hold": True, "notice": "On hold: Helen decides this.", "context": "c",
                  "statements": [], "anyway": {"phrase": "Plan it anyway", "context": "Go on: c"}}
    held = output(run("hook", "prompt", stdin=event("UserPromptSubmit", repo, prompt="Make the trial 30 days",
                                                   turn_id="turn-1", model="gpt-6-luna"), tool="codex"))
    assert held == {"decision": "block", "reason": "On hold: Helen decides this."}
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
    assert manifest["name"] == claude["name"] == "vyavastha" and manifest["version"] == claude["version"]
    assert f'VERSION="{manifest["version"]}"' in SCRIPT.read_text()
    assert (PLUGIN / manifest["hooks"]).is_file() and (PLUGIN / manifest["skills"] / "vyavastha" / "SKILL.md").is_file()
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
        assert command.rsplit(" ", 1)[1] in {"session-start", "prompt", "edited", "stopped"}
    for skill in ("sign-in", "sign-out", "status"):
        text = (PLUGIN / "skills" / skill / "SKILL.md").read_text()
        assert f'!`sh "${{CLAUDE_PLUGIN_ROOT}}/scripts/vyavastha.sh" {skill}`' in text
        assert "disable-model-invocation: true" in text
