# Vyavastha for Claude Code and Codex

One plugin for two coding tools, laid out as its own private plugin marketplace. With it, Claude Code or Codex on your own computer works with your team’s Vyavastha workspace. What follows says Claude; under Codex it is the same, with Codex in its place:

- **Before Claude changes code**, your request is checked against what your team has said and decided, reading only what you can read in Vyavastha. When something stands in the way, Claude Code holds the request and tells you who said what. To go ahead anyway, send `Plan it anyway`.
- **When you ask about your team**, the question goes to your own assistant in Vyavastha, the one that answers in its web app’s chat, and Claude gives you its answer: what a teammate is working on, what was decided, who said what. Ask as you would there (“See what Priya is doing”, “What did we decide about the free trial?”), or speak to it by name (“Vyavastha, what is new?”). The questions of one session are one chat, which you also find in the web app. Claude can ask Vyavastha by itself too, when its work needs something the team said.
- **After Claude changes files**, and when it stops, git’s own list of changed files is sent to Vyavastha, so teammates who read the same repository see your work in progress before it is on GitHub. Edits you make by hand are included, because the list comes from git.
- **The web app stays the place** for setup, the record, your team and review. You approve this computer there, and you can disconnect it there (Settings, Account, Connected tools).

## Install (for a tester)

You need Claude Code, git, and access to this repository.

1. In Claude Code, add the marketplace:

   ```
   /plugin marketplace add duggiradri/Vyavastha-Plugin
   ```

   For a copy on your disk, give its folder instead: `/plugin marketplace add /path/to/vyavastha-plugin`.

2. Install the plugin:

   ```
   /plugin install vyavastha@vyavastha
   ```

   From a terminal, the same two steps are `claude plugin marketplace add duggiradri/Vyavastha-Plugin` and `claude plugin install vyavastha@vyavastha`.

3. Start a new session (or run `/reload-plugins`), then sign in:

   ```
   /vyavastha:sign-in
   ```

   It shows a code and opens Vyavastha’s Connect page. Sign in there if asked, type the code, check the computer’s name, and press **Connect**. Back in Claude Code, your next request finishes connecting, or run `/vyavastha:status`.

Commands: `/vyavastha:sign-in`, `/vyavastha:sign-out`, `/vyavastha:status`.

Requests are checked, and edits shared, only in a repository whose GitHub remote is one you connected in Vyavastha’s Sources. Questions about your team are answered from any folder.

Which messages are asked in Vyavastha without Claude being asked: one that speaks to Vyavastha by name, one about the team as such (“my team”, “teammates”, “anyone else”), one about what was said or decided or who is doing something, and one that names a teammate. A message that asks for a code change is checked and made on your computer, never asked; a message that only names a teammate beside a file or a function (“Explain what Priya wrote in calc.py”) is Claude’s. For anything these rules miss, Claude is told at the start of each session how to ask Vyavastha itself (`vyavastha.sh ask "<question>"`).

## Install in Codex (for a tester)

You need Codex, git, and access to this repository. The same script runs under both tools; Codex gets its own hooks file (`plugins/vyavastha/hooks/codex.json`) and description (`plugins/vyavastha/.codex-plugin/plugin.json`).

1. From a terminal, add the marketplace:

   ```
   codex plugin marketplace add duggiradri/Vyavastha-Plugin
   ```

2. Install the plugin named Vyavastha from that marketplace in Codex’s plugin list, and restart Codex.

3. Approve the plugin’s hooks once: Codex runs no hook until you have reviewed and trusted it. In the terminal, open `/hooks`; in the desktop app, choose **Review hooks**. Codex asks again after each update of the plugin.

4. Sign in by sending this as a message of its own:

   ```
   vyavastha sign in
   ```

   It shows a code and opens Vyavastha’s Connect page, as in Claude Code. The plugin answers the message itself and Codex’s model never sees it.

Commands, each sent as a message of its own: `vyavastha sign in`, `vyavastha sign out`, `vyavastha status`. They work in Claude Code too.

Under Codex the report of changed files also follows shell commands, because Codex often edits files that way. Codex tasks that run in the cloud don’t run a plugin’s hooks, so nothing is checked there.

Tried in a real Codex session on 16 November 2026: installing, trusting the hooks, signing in and the hooks running. Codex being given an answer from Vyavastha, and Codex asking Vyavastha by itself (its shell may need your approval to reach the network), follow Codex’s documentation and are tested with the input Codex documents.

## What it sends, and what it keeps

- **To the check:** the words of your message, the repository’s GitHub remote (any user name or token in the remote’s address is removed first; none outside a repository), the branch, the tool’s session id, and which tool it is (Claude Code or Codex). Vyavastha keeps nothing of the words of a request it checks.
- **A question about your team:** its words are kept, with the answer, as a chat of your own in Vyavastha, exactly as if you had asked in the web app. You can read on, rename or delete it there. Nobody else sees it.
- **After edits:** the remote, branch, session id, and for each changed file its path, git’s status (added, changed, deleted, renamed) and line counts. **Never what a file holds.**
- **Never:** the conversation transcript, file contents, or environment variables.
- **Back from the server:** facts with their sources (who said what, when and where, and what the check made of them), and the answer to a question, shown to Claude as context. With an answer comes one instruction to Claude: to give it to you as it stands. The plugin makes no model calls of its own on your Claude subscription.
- **On your computer:** the token, in `~/.config/vyavastha/credentials` (or `$XDG_CONFIG_HOME/vyavastha`), readable by you only (`chmod 600`, in a `700` folder). On Windows the file sits in your user profile. A token is never sent to any server but the one that issued it. Short-lived notes for each session live in `~/.config/vyavastha/sessions`, and are removed after a week.

If the server can’t be reached, or you aren’t signed in, Claude works as usual. You get one short note, and nothing is checked or shared.

## Why a shell script

Hooks are plain POSIX `sh` using only `git`, `curl` and `awk`. Claude Code runs a command hook through `sh` on macOS and Linux, and through Git Bash on Windows. The plugin needs git anyway, and on Windows git comes as Git for Windows, which brings Git Bash, curl and awk with it. Claude Code itself installs no Node.js or Python (its native installer is a single binary), so this script assumes neither, and it doesn’t use jq. Without Git for Windows, Claude Code runs hooks in PowerShell and these hooks won’t run. Claude still works then, but nothing is checked or shared.

## Choosing the server

By default the plugin talks to `https://vyavasta.com`. To use another server:

- set `VYAVASTHA_SERVER` in the shell you start Claude Code from, for example `export VYAVASTHA_SERVER=https://vyavastha.example.com`, or
- save one for every session: `sh <plugin folder>/scripts/vyavastha.sh use-server https://vyavastha.example.com` (run `use-server` with no address to go back to the default).

Only `https://` addresses are accepted, apart from `http://localhost` and `http://127.0.0.1` for testing.

## Local testing

To run Vyavastha in demo mode on this Mac and point the plugin at it:

1. Start the server from the Vyavastha project folder (the web app must be built once with `cd frontend && npm run build`):

   ```
   VYAVASTHA_DATA_DIR=/tmp/vyavastha-demo PYTHONPATH=src .venv/bin/python -m mas_stealth.web_cli --demo --port 8804
   ```

2. Open `http://127.0.0.1:8804`, create an account (the demo shows the sign-in email on screen), and connect GitHub and Slack in Sources. The demo repository is `northwind/customer-platform`.

3. Get a clone whose remote names that repository:

   ```
   mkdir customer-platform && cd customer-platform && git init
   git remote add origin https://github.com/northwind/customer-platform.git
   ```

4. Add this folder as a marketplace, install the plugin, and start Claude Code with the server set:

   ```
   claude plugin marketplace add /path/to/vyavastha-plugin
   claude plugin install vyavastha@vyavastha
   VYAVASTHA_SERVER=http://127.0.0.1:8804 claude
   ```

   Then run `/vyavastha:sign-in` and approve the code in the browser. Ask for something like “Remove customer_plan from the API response”. The demo has no model, so it holds nothing, but Claude is shown what the team’s record says about the request. Edit a file and look at the home screen of a teammate’s account (the demo lets only a workspace’s owner connect its sources, so hand the workspace to the teammate in Settings, Workspace before they connect GitHub).

## Tests

```
python3 -m pytest tests -q                                          # the hook script against a fake server
python3 tests/end_to_end.py --project /path/to/MAS_Stealth --port 8804   # the whole loop against a demo server
claude plugin validate . && claude plugin validate plugins/vyavastha
```

`tests/test_hooks.py` runs each test under `sh` and, where it is installed, `dash` (Ubuntu’s `sh`). `tests/end_to_end.py` starts the demo server on its own port with a scratch data folder, pairs the plugin’s script with it as a developer would, feeds each hook the JSON Claude Code sends, checks that a teammate’s account sees the work, and then stops the server.
