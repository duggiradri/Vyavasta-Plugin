"""The whole loop on this computer, with no model: Vyavastha's server in demo mode, the plugin's own script paired
with it the way a developer pairs it, each hook fed the JSON Claude Code would send, and a teammate's account that
sees the work.

    python3 tests/end_to_end.py --project /path/to/MAS_Stealth --port 8804

The server runs only for this script, on its port, with its data in the project's frontend/e2e/.artifacts folder,
and is stopped at the end. Standard library only. Prints each step and what came back; exits non-zero when a step
doesn't come out as it should.
"""

from __future__ import annotations

import argparse
import base64
import http.cookiejar
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "plugins" / "vyavastha" / "scripts" / "vyavastha.sh"
REMOTE = "https://github.com/northwind/customer-platform.git"


class Browser:
    """A person's browser on the web app: its own cookies, and the header the app's routes ask for."""

    def __init__(self, base: str) -> None:
        self.base = base
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def call(self, method: str, path: str, body: dict | None = None) -> tuple[int, dict | list | None]:
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(f"{self.base}/api/v1{path}", data=data, method=method, headers={
            "X-Vyavastha": "1", **({"Content-Type": "application/json"} if data else {})})
        try:
            with self.opener.open(request, timeout=30) as response:
                text = response.read()
                return response.status, json.loads(text) if text else None
        except urllib.error.HTTPError as failure:
            text = failure.read()
            return failure.code, json.loads(text) if text else None

    def ok(self, method: str, path: str, body: dict | None = None):
        status, answer = self.call(method, path, body)
        if status >= 300:
            raise SystemExit(f"{method} {path} answered {status}: {answer}")
        return answer

    def oauth(self, path: str) -> int:
        """Follow the demo's stand-in for a provider's consent: its callback, without following where it leads."""

        class Stay(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None

        opener = urllib.request.build_opener(Stay(), *[handler for handler in self.opener.handlers
                                                         if isinstance(handler, urllib.request.HTTPCookieProcessor)])
        try:
            with opener.open(f"{self.base}{path}", timeout=30) as response:
                return response.status
        except urllib.error.HTTPError as failure:
            return failure.code


def sign_up(browser: Browser, email: str, name: str) -> None:
    browser.ok("POST", "/auth/link", {"email": email, "name": name})
    inbox = browser.ok("GET", f"/demo/inbox?email={email}")
    token = re.search(r"token=([^&\s]+)", inbox[0]["link"]).group(1)
    browser.ok("POST", "/auth/verify", {"token": token})


def connect(browser: Browser, provider: str) -> str:
    started = browser.ok("POST", "/sources", {"provider": provider, "return_to": "sources"})
    state = re.search(r"state=([^&]+)", started["authorize_url"]).group(1)
    code = "demo." + base64.urlsafe_b64encode(b"{}").decode().rstrip("=")
    assert browser.oauth(f"/api/v1/oauth/{provider}/callback?state={state}&code={code}") == 303
    detail = browser.ok("GET", f"/sources/{started['source_id']}")
    browser.ok("PUT", f"/sources/{started['source_id']}/access", {
        "selected_resource_ids": [row["resource_id"] for row in detail["resources"] if row["selected"]],
        "excluded_resource_ids": [], "history_days": detail["settings"]["history_days"], "action_level": "read",
        "audience": "owner"})
    browser.call("POST", f"/sources/{started['source_id']}/sync")
    return started["source_id"]


def step(title: str) -> None:
    print(f"\n== {title}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--project", type=Path, required=True, help="the Vyavastha project folder (with .venv)")
    parser.add_argument("--port", type=int, default=8804)
    args = parser.parse_args()
    project = args.project.resolve()
    base = f"http://127.0.0.1:{args.port}"
    data = project / "frontend" / "e2e" / ".artifacts" / f"plugin-loop-{args.port}"
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    work = Path(tempfile.mkdtemp(prefix="vyavastha-loop-"))
    home = work / "plugin-home"
    log = (data / "server.log").open("w")
    server = subprocess.Popen(
        [str(project / ".venv" / "bin" / "python"), "-m", "mas_stealth.web_cli", "--demo", "--port", str(args.port)],
        cwd=project, stdout=log, stderr=subprocess.STDOUT,
        env={**os.environ, "PYTHONPATH": "src", "VYAVASTHA_DATA_DIR": str(data), "VYAVASTHA_PUBLIC_ORIGIN": base,
             "VYAVASTHA_DEMO_LATENCY_MS": "0", "VYAVASTHA_CODE_AGENT": "scripted", "PYTHONDONTWRITEBYTECODE": "1"})
    failures: list[str] = []

    def expect(condition: bool, what: str) -> None:
        print(("  ok    " if condition else "  FAIL  ") + what)
        if not condition:
            failures.append(what)

    def plugin(*command: str, stdin: dict | None = None, cwd: Path | None = None) -> str:
        done = subprocess.run(["sh", str(SCRIPT), *command], input=json.dumps(stdin) if stdin else "",
                              capture_output=True, text=True, cwd=cwd or work, timeout=120, env={
                                  "PATH": os.environ["PATH"], "HOME": str(work), "VYAVASTHA_HOME": str(home),
                                  "VYAVASTHA_SERVER": base, "CLAUDE_PROJECT_DIR": str(cwd or work)})
        if done.returncode != 0:
            failures.append(f"{' '.join(command)} exited {done.returncode}: {done.stderr}")
        return done.stdout

    def hook(name: str, event: str, repo: Path, **fields) -> dict:
        stdin = {"session_id": "loop-session", "transcript_path": str(work / "transcript.jsonl"), "cwd": str(repo),
                 "permission_mode": "default", "hook_event_name": event, **fields}
        printed = plugin("hook", name, stdin=stdin, cwd=repo)
        said = json.loads(printed) if printed.strip() else {}
        print(f"  {event} printed: {json.dumps(said, ensure_ascii=False)[:600]}")
        return said

    try:
        for _ in range(120):
            try:
                urllib.request.urlopen(f"{base}/api/v1/meta", timeout=1)
                break
            except OSError:
                time.sleep(0.5)
        else:
            raise SystemExit("the demo server didn't start; see " + str(data / "server.log"))

        step("Two teammates in one workspace, each reading northwind/customer-platform through GitHub")
        sam, ganesh = Browser(base), Browser(base)
        sign_up(sam, "sam@northwind.dev", "Sam Rivera")
        for provider in ("slack", "github"):
            connect(sam, provider)
        sam.ok("POST", "/workspace/invitations", {"email": "ganesh@northwind.dev", "role": "admin"})
        inbox = ganesh.ok("GET", "/demo/inbox?email=ganesh@northwind.dev")
        ganesh.ok("POST", "/auth/verify", {"token": re.search(r"token=([^&\s]+)", inbox[0]["link"]).group(1)})
        ganesh_session = ganesh.ok("GET", "/session")
        expect(ganesh_session["workspace"]["workspace_id"] == sam.ok("GET", "/session")["workspace"]["workspace_id"],
               "Ganesh joined Sam’s workspace")
        # The demo lets only a workspace's owner connect its made-up sources: Sam connected his, and hands the
        # workspace to Ganesh, who then connects a GitHub of his own.
        sam.ok("POST", "/workspace/owner", {"user_id": ganesh_session["user"]["user_id"]})
        connect(ganesh, "github")

        step("Sam pairs the plugin: /vyavastha:sign-in, then approves the code in the web app")
        started = plugin("sign-in")
        print("  " + started.strip().replace("\n", "\n  "))
        code = re.search(r"code ([A-Z]{4}-[A-Z]{4})", started).group(1)
        looked = sam.ok("POST", "/plugin/pairings/lookup", {"code": code})
        print(f"  the web app shows: Connect Claude Code on {looked['machine']}? ({looked['workspace']})")
        sam.ok("POST", "/plugin/pairings/approve", {"code": code, "approve": True})
        status = plugin("status")
        print("  " + status.strip().replace("\n", "\n  "))
        expect("sam@northwind.dev" in status, "the plugin is signed in as Sam")
        credentials = (home / "credentials").read_text()
        expect("token=vyv-tool-" in credentials and oct((home / "credentials").stat().st_mode & 0o777) == "0o600",
               "the token is kept in a file only Sam can read")
        expect("vyv-tool-" not in started + status, "the token was never printed")

        step("Sam’s own clone of the repository")
        repo = work / "customer-platform"
        repo.mkdir()
        for command in (["init", "-q", "--initial-branch=main"], ["remote", "add", "origin", REMOTE]):
            subprocess.run(["git", "-C", str(repo), *command], check=True)
        (repo / "api").mkdir()
        (repo / "api" / "serializers.py").write_text("FIELDS = ['id', 'customer_plan', 'subscription_tier']\n")
        environment = {**os.environ, "GIT_AUTHOR_NAME": "Sam", "GIT_AUTHOR_EMAIL": "sam@northwind.dev",
                       "GIT_COMMITTER_NAME": "Sam", "GIT_COMMITTER_EMAIL": "sam@northwind.dev"}
        subprocess.run(["git", "-C", str(repo), "add", "--all"], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "Initial"], check=True, env=environment)
        subprocess.run(["git", "-C", str(repo), "checkout", "-q", "-b", "drop-customer-plan"], check=True)

        step("SessionStart")
        said = hook("session-start", "SessionStart", repo, source="startup")
        expect("signed in as sam@northwind.dev" in said.get("systemMessage", ""), "the session says it is signed in")

        step("UserPromptSubmit: a request for a change")
        said = hook("prompt", "UserPromptSubmit", repo, prompt="Remove customer_plan from the API response")
        context = said.get("hookSpecificOutput", {}).get("additionalContext", "")
        expect("customer_plan" in context and "’s " in context and "(Slack" in context,
               "Claude is shown what the team’s record says of it, with who said it and where")
        expect("decision" not in said, "the demo checks nothing, so nothing is held")

        step("UserPromptSubmit: a question")
        said = hook("prompt", "UserPromptSubmit", repo, prompt="What does this repository do?")
        expect(said == {}, "a question goes to Claude untouched")

        step("Claude edits a file (PostToolUse), then stops (Stop)")
        (repo / "api" / "serializers.py").write_text("FIELDS = ['id', 'subscription_tier']\n")
        (repo / "api" / "notes.md").write_text("customer_plan is gone from the response.\n")
        hook("edited", "PostToolUse", repo, tool_name="Edit", tool_input={"file_path": "api/serializers.py"})
        hook("stopped", "Stop", repo, stop_hook_active=False)

        step("Ganesh, in the web app, sees Sam’s work in progress")
        seen = ganesh.ok("GET", "/team-work")["teammates"]
        print("  " + json.dumps([{key: row[key] for key in ("status", "said", "request", "repository", "files")}
                                 for row in seen], ensure_ascii=False))
        record = seen[0] if seen else {}
        expect(record.get("status") == "local" and record.get("person", {}).get("name") == "Sam Rivera",
               "Sam’s change is listed as being made on his own computer")
        expect(sorted(entry["path"] for entry in record.get("files", [])) == ["api/notes.md", "api/serializers.py"],
               "with the files git reports, and their line counts")

        step("Sam commits; Claude stops again")
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-am", "Drop customer_plan"], check=True,
                       env=environment)
        subprocess.run(["git", "-C", str(repo), "add", "--all"], check=True)
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "Notes"], check=True, env=environment)
        hook("stopped", "Stop", repo, stop_hook_active=False)
        seen = ganesh.ok("GET", "/team-work")["teammates"]
        expect(bool(seen) and seen[0]["status"] == "committed", "Ganesh sees it committed and not pushed yet")

        step("Sam disconnects the computer in Settings")
        (tool,) = sam.ok("GET", "/plugin/tokens")["tokens"]
        print(f"  Settings lists: Claude Code on {tool['machine']}, {tool['workspace']}")
        sam.ok("DELETE", f"/plugin/tokens/{tool['token_id']}")
        said = hook("prompt", "UserPromptSubmit", repo, prompt="Remove customer_plan from the API response")
        expect("connection has ended" in said.get("systemMessage", "") and not (home / "credentials").exists(),
               "the next request goes on unchecked, and the plugin says it was signed out")
    finally:
        server.terminate()
        try:
            server.wait(timeout=20)
        except subprocess.TimeoutExpired:
            server.kill()
        log.close()
        shutil.rmtree(work, ignore_errors=True)
    print("\n" + ("Every step came out as it should." if not failures else f"{len(failures)} step(s) failed:"))
    for failure in failures:
        print(f"  - {failure}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
