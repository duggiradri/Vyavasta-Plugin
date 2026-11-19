# Vyavastha for Claude Code and Codex

One plugin for two coding tools, laid out as its own private plugin marketplace. With it, Claude Code or Codex on your own computer works with your team’s Vyavastha workspace. What follows says Claude; under Codex it is the same, with Codex in its place.

The plugin is **off in every project** until you send `vyavastha on` there. Off, it does nothing and sends nothing; only its own commands are answered. On:

- **Before Claude changes code**, your request is checked against what your team has said and decided, reading only what you can read in Vyavastha. When something stands in the way, the request is held and you are told who said what. To go ahead anyway, send `Plan it anyway`.
- **When you ask about your team**, the question goes to your own assistant in Vyavastha, the one that answers in its web app’s chat, and Claude gives you its answer. Ask as you would there (“See what Priya is doing”), or speak to it by name (“Vyavastha, what is new?”). The questions of one session are one chat, which you also find in the web app.
- **Summaries for your teammates come from the session itself.** With summaries on (they are on once you turn the project on), your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavastha, a chat of your own. A reply can quote code or what a file holds. Nothing else of the conversation is kept. Vyavastha sums the chat up in a sentence or two and files it under a category, exactly as it does for its web app’s chats, and you choose there which categories teammates see. Send `vyavastha summaries off` to stop.
- **Every message gets one line** from Vyavastha saying what was sent, what was not and why, whether it was kept for your summary, and what came of it, for example: `Vyavastha · sent: your message and 2 changed files’ names. Not sent: what the files hold (code sharing is off). Kept in this session’s chat for your summary. · Checked against your team’s record: nothing stands against this change.`
- **After Claude changes files**, and when it stops, your changed files’ names (git’s own list) are sent, so teammates who read the same repository see your work in progress before it is on GitHub.
- **With code sharing on** (off until you turn it on, per project), your uncommitted changes themselves are sent too, so Vyavastha’s check reads the real change. Teammates who can already see this work see a short summary of what the change does, written by Vyavastha, never the code. If something the team has said stands against the change, Claude is stopped once and you are asked: send `continue` to go on, or `stop` to leave the change where it is.
- **Teammates’ agents.** Each person has an agent that teammates can ask about their work. You can ask a teammate’s agent a question, which it answers only from what you can both already see, and the teammate sees what you asked. Your own agent answers your teammates the same way, and you see everything they asked. At the start of a session you are told what teammates asked of you while you were away.

The web app stays the place for setup, the record, your team and review. You approve this computer there, and you can disconnect it there (Settings, Account, Connected tools).

## Install in Claude Code (for a tester)

You need Claude Code, git, and access to this repository.

1. Add the marketplace and install the plugin:

   ```
   /plugin marketplace add duggiradri/Vyavastha-Plugin
   /plugin install vyavastha@vyavastha
   ```

   For a copy on your disk, give its folder instead: `/plugin marketplace add /path/to/vyavastha-plugin`. From a terminal, the same two steps are `claude plugin marketplace add duggiradri/Vyavastha-Plugin` and `claude plugin install vyavastha@vyavastha`.

2. Start a new session (or run `/reload-plugins`) in your project, and send:

   ```
   vyavastha on
   ```

   If you aren’t signed in yet, Vyavastha’s Connect page opens in your browser and the answer shows a code. Sign in there if asked, type the code, check the computer’s name, and press **Connect**. Your next message finishes connecting.

## Install in Codex (for a tester)

You need Codex, git, and access to this repository. The same script runs under both tools; Codex gets its own hooks file (`plugins/vyavastha/hooks/codex.json`) and description (`plugins/vyavastha/.codex-plugin/plugin.json`).

1. From a terminal, add the marketplace: `codex plugin marketplace add duggiradri/Vyavastha-Plugin`.
2. Install the plugin named Vyavastha from that marketplace in Codex’s plugin list, and restart Codex.
3. Approve the plugin’s hooks once: Codex runs no hook until you have reviewed and trusted it. In the terminal, open `/hooks`; in the desktop app, choose **Review hooks**. Codex asks again after each update of the plugin.
4. In your project, send `vyavastha on` as a message of its own, and sign in as above.

Codex has no plugin slash commands, so every command is a message. Under Codex the report of changed files also follows shell commands, because Codex often edits files that way. Codex tasks that run in the cloud don’t run a plugin’s hooks, so nothing is checked there. Codex runs the commands its own model starts in a closed-off space that can’t write the plugin’s settings folder or reach the internet. When that keeps a command from Vyavastha, the plugin says so; send the same thing as a message instead (a question as a message that starts with “Vyavastha,”), because messages aren’t closed off.

## Commands

Each is sent as a message of its own, in either tool; case and a trailing full stop don’t matter. The plugin answers it and the model never sees it. In Claude Code most are also slash commands (`/vyavastha:on`, `/vyavastha:status`, …); `ask`, `assign`, `reply`, `start`, `done` and `decline` are typed only, because a slash command never passes your words to a shell.

Start here
- `vyavastha on` / `vyavastha off`: use Vyavastha in this project, or stop. Off keeps your code-sharing and summaries choices.
- `vyavastha status`: whether you’re signed in, and whether this project, code sharing and summaries are on.
- `vyavastha check`: tests that git, curl and awk are there, that the settings folder can be written, the server address, that the server answers, sign-in, that this folder is a repository on GitHub that Vyavastha reads for you, that the project, code sharing and summaries are on, and the plugin’s version. Each line says “ok” or the problem and how to fix it.
- `vyavastha sign in` / `vyavastha sign out`: connect or disconnect this computer.
- `vyavastha help`: the commands.

See what is shared
- `vyavastha settings`: each setting with its value and how to change it.
- `vyavastha share code on` / `vyavastha share code off`: code sharing for this project. Off also deletes what Vyavastha kept of your code.
- `vyavastha summaries on` / `vyavastha summaries off`: summaries for this project: whether your messages and Claude’s replies are kept in this session’s chat and summed up for teammates. On from the moment you turn the project on. A project turned on with an earlier version says so once, on the first line of a session or message, and that first message isn’t kept.
- `vyavastha shared`: everything sent from this session, as Vyavastha recorded it, oldest first.
- `vyavastha chat` / `vyavastha chat open`: this session’s chat in Vyavastha, as a link or opened.
- `vyavastha upload`: opens this session’s chat so you can drop in a file; your next question in this session carries it. A pasted image never reaches Vyavastha by itself: with code sharing on, the same page opens once by itself; with it off, the message’s line says once to send `vyavastha upload`.

Teammates
- `vyavastha inbox`: what teammates asked of you and have not seen yet, numbered.
- `vyavastha ask <name>: <question>`: asks a teammate’s agent, which answers only from what you can both already see. The colon may be a comma, or left out when the name is one word.
- `vyavastha assign <name>: <task>`: gives a teammate a task (owners and administrators only).
- `vyavastha reply <number>: <words>`: answers an item of your last inbox listing.
- `vyavastha start <number>`: accepts a task, and gives its words to Claude as your request, checked as any request is. `vyavastha done <number>` and `vyavastha decline <number>` close it.

Every message to or from another person’s agent opens with a header line, such as `── To Priya Raman’s agent · from Sam Rivera · 18 November 2026, 10:42 · through Vyavastha ──`, and the answer with `── From Priya Raman’s agent · 18 November 2026, 10:43 · answered only from what you can both already see ──`.

## What it sends, and what it keeps

From a project that is off: nothing, ever.

From a project that is on:

- **With each message:** its words, the repository’s GitHub remote (any user name or token in the address is removed first; none outside a repository), the branch, the tool’s session id, which tool it is, and whether summaries are on. A question about your team carries the same.
- **With summaries on** (per project, on from the moment you turn the project on): your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavastha. It is a chat of your own that only you read, in the web app. A held request is kept too. A reply can quote code or what a file holds. Only the first 4,000 characters of a reply are sent, with bytes that aren’t valid text dropped. A reply is sent only after a message kept in the same turn, and is added to that message alone. Nothing else of the conversation is kept: not Claude’s other steps, the commands it ran or the files it read, and not the earlier conversation. Vyavastha then sums the chat up in one or two sentences about the work, never the material itself, and files it under a category: the repository, an initiative, Miscellaneous or Personal. On your Summaries page in the web app you choose which categories teammates see (Personal stays hidden until you turn it on). The summaries appear on that page, on the Team page and in answers about what you are working on. Deleting the chat in the web app deletes its summary with it.
- **Never kept:** the plugin’s own commands (`vyavastha …`, which are never sent at all), a started task’s words, and these answers to the plugin’s own questions: `Plan it anyway`, `continue`, `continue anyway`, `go on` and `stop` (case, spacing and a closing full stop, exclamation or question mark don’t matter).
- **With summaries off:** nothing you write in this project, and none of Claude’s replies, is kept or summed up for teammates. No reply is sent, and `vyavastha shared` shows that a request was checked, never its words. A question about your team is still answered by Vyavastha’s assistant. It stays in your chat there, where you can delete it.
- **A question about your team:** its words and the answer are a chat of your own in Vyavastha, exactly as if you had asked in the web app. Nobody else sees it. It is summed up for teammates only with summaries on.
- **With each message and after edits:** your changed files’ names: for each, its path, git’s status (added, changed, deleted, renamed) and line counts (none for a new file that looks like a key, is machine-written or is over 1 MB, which isn’t read at all). Without code sharing, these reports **never carry what a file holds.**
- **With code sharing on, also:** one unified diff of your working tree against your GitHub copy (where your branch last matched its upstream, else origin’s default branch, else your last commit): your edits, new files git doesn’t ignore, deleted and renamed files, and commits not yet pushed. It is sent with each message, and after edits when it changed since it was last sent. Vyavastha’s check reads it; teammates who can already see this work see a short summary of what the change does, never the code. What is sent is chosen file by file from git’s own list, by each file’s exact name, and a file the plugin can’t vouch for is left out rather than sent. Never sent, each named in the list of what was left out with its reason:
  - files git ignores (they are never even listed);
  - files that look like keys or credentials, in any letter case and in any folder, even when committed, and a file renamed from or to such a name: `.env` and `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, `credentials` and `credentials.*`, `secrets.*`, `*.secret`, `.npmrc`, `.pypirc`, `.netrc`, `*.tfvars`, `*.tfstate*`, `auth.json`, `service-account*.json`;
  - machine-written files: lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `uv.lock`, `go.sum` and the like), `*.min.js`, `*.min.css`, `*.map`, generated protocol files, and anything under `node_modules/`, `dist/`, `build/`, `out/`, `target/`, `vendor/`, `.next/`, `coverage/` or `__pycache__/`;
  - files that aren’t text, symbolic links (whatever they point to; a link to a key file is counted as one), files that changed type, and a new file whose name holds a line break;
  - files that would take the whole past 5,000 lines of changes (the server may set another limit), and a new file over 1 MB, which isn’t read at all; later, smaller files may still fit. A line longer than 2,000 characters is cut, and bytes that aren’t valid text are dropped.
  - a submodule is sent only as the commit it is at, never its files.

  Vyavastha keeps only the latest changes of each session, until the work ends and for 7 days at most. `vyavastha share code off` deletes what was kept. Turning code sharing off in the web app turns it off here too, and the next line says so. Signing out and in again keeps your choice, and the new connection is told it with your next message.
- **Never:** the conversation transcript (only your messages and Claude’s last reply of each turn, with summaries on), Claude’s other steps, environment variables, or anything from a project that is off.
- **Back from the server:** facts with their sources (who said what, when and where, and what the check made of them), and the answer to a question, shown to Claude as context. The plugin makes no model calls of its own on your Claude subscription.
- **On your computer:** the token, in `~/.config/vyavastha/credentials` (or `$XDG_CONFIG_HOME/vyavastha`, or `$VYAVASTHA_HOME`), readable by you only (`chmod 600`, in a `700` folder); both tools share it. A token is never sent to any server but the one that issued it. Which projects are on, and whether code sharing and summaries are on for each and whether you were told what summaries do, are kept in `projects/` in the same folder, and short-lived notes for each session in `sessions/`, removed after a week.

If you aren’t signed in, the server can’t be reached, or it isn’t working, Claude works as usual and the message’s line says what happened in one plain sentence. A slow check gives up after about a minute and Claude goes on; sending a reply at the end of a turn gives up after 4 seconds, and isn’t tried when the server was just found out of reach; a slow answer to a question is left in your chat in Vyavastha. The plugin never writes git’s own index or takes its lock, so your git commands and Claude’s never collide with it, and in a project that is off it doesn’t even read your messages.

## Why a shell script

Hooks are plain POSIX `sh` using only `git`, `curl` and `awk`. Claude Code runs a command hook through `sh` on macOS and Linux, and through Git Bash on Windows. The plugin needs git anyway, and on Windows git comes as Git for Windows, which brings Git Bash, curl and awk with it. Claude Code itself installs no Node.js or Python, so this script assumes neither, and it doesn’t use jq. Without Git for Windows, Claude Code runs hooks in PowerShell and these hooks won’t run. Claude still works then, but nothing is checked or shared.

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

   Then send `vyavastha on` and approve the code in the browser. Ask for something like “Remove customer_plan from the API response”. The demo has no model, so it holds nothing, but Claude is shown what the team’s record says about the request.

## Tests

```
python3 -m pytest tests -q                                          # the hook script against a fake server
python3 tests/end_to_end.py --project /path/to/MAS_Stealth --port 8804   # the whole loop against a demo server
claude plugin validate . && claude plugin validate plugins/vyavastha
```

`tests/test_hooks.py` runs each test under `sh` and, where it is installed, `dash` (Ubuntu’s `sh`). `tests/end_to_end.py` starts the demo server on its own port with a scratch data folder, pairs the plugin’s script with it as a developer would, feeds each hook the JSON Claude Code sends, checks that a teammate’s account sees the work, and then stops the server.
