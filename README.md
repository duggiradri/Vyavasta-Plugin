<p align="center"><img src="plugins/vyavasta/assets/logo.png" alt="" width="96" height="96"></p>

# Vyavasta for Claude Code and Codex

One plugin for two coding tools, laid out as its own plugin marketplace. With it, Claude Code or Codex on your own computer works with your team’s Vyavasta workspace. What follows says Claude; under Codex it is the same, with Codex in its place.

The plugin is **off in every project** until you send `vyavasta on` there. Off, it sends nothing; only its own commands are answered, and a question about using it is explained to Claude. On:

- **Before Claude changes code**, your request is checked against what your team has said and decided, reading only what you can read in Vyavasta. When something stands in the way, the request is held and you are told who said what. To go ahead anyway, send `Plan it anyway`.
- **When you ask about your team**, the question goes to your own assistant in Vyavasta, the one that answers in its web app’s chat, and Claude gives you its answer. Ask as you would there (“See what Priya is doing”), or speak to it by name (“Vyavasta, what is new?”). The questions of one session are one chat, which you also find in the web app.
- **Summaries for your teammates come from the session itself.** With summaries on (they are on once you turn the project on), your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavasta, a chat of your own. A reply can quote code or what a file holds. Nothing else of the conversation is kept. Vyavasta sums the chat up in a sentence or two and files it under a category, exactly as it does for its web app’s chats, and you choose there which categories teammates see. Send `vyavasta summaries off` to stop.
- **Every message gets one line** from Vyavasta saying what was sent, what was not and why, whether it was kept for your summary, and what came of it, for example: `Vyavasta · sent: your message and 2 changed files’ names. Not sent: what the files hold (code sharing is off). Kept in this session’s chat for your summary. · Checked against your team’s record: nothing stands against this change.`
- **After Claude changes files**, and when it stops, your changed files’ names (git’s own list) are sent, so teammates who read the same repository see your work in progress before it is on GitHub.
- **With code sharing on** (off until you turn it on, per project), your uncommitted changes themselves are sent too, so Vyavasta’s check reads the real change. Teammates who can already see this work see a short summary of what the change does, written by Vyavasta, never the code. If something the team has said stands against the change, Claude is stopped once and you are asked: send `continue` to go on, or `stop` to leave the change where it is.
- **Teammates’ agents.** Each person has an agent that teammates can ask about their work. You can ask a teammate’s agent a question, which it answers only from what you can both already see, and the teammate sees what you asked. Your own agent answers your teammates the same way, and you see everything they asked. At the start of a session you are told what teammates asked of you while you were away.

The web app stays the place for setup, the record, your team and review. You approve this computer there, and you can disconnect it there (the Coding tools page).

## The first time you use it

- **Sign-in opens by itself.** In the first session after you install the plugin, if this computer isn’t signed in yet, Vyavasta’s Connect page opens in your browser and the session’s first line gives you its code and address. Sign in there if asked, type the code, check the computer’s name, and press **Connect**. Once you approve, your next message finishes connecting, in any project, and says so in one line. The project stays off, and nothing else is sent.
- **One connection serves both tools.** A computer connected through Claude Code is connected for Codex too, and the other way round, so the second tool asks for no code: its first session says who this computer is connected as.
- **Then send `vyavasta on`** in each project you want it in. If you start a session in a project that is on while signed out, sign-in starts by itself there too, once.
- **A sign-in that waits is never started twice.** Until you approve it, every line about it repeats the same code and address and no second page opens. A code lasts 10 minutes, and asking to sign in again says how many are left. Once it has run out, the next sign-in starts afresh with a new code.
- **To find out how to use it,** send `vyavasta` or `vyavasta help`, or ask in your own words, such as `vyavasta how do I sign in` or `vyavasta what can you do`. Help opens with the three steps to start and whether each is done. A question to your team that starts with Vyavasta’s name, such as “Vyavasta, what is Priya working on?”, still goes to your team’s record.
- **You can also just ask Claude.** When a short message asks about the plugin itself, such as “How do I sign in to Vyavasta?” or “What does the Vyavasta plugin send?”, the plugin gives Claude the exact phrases to tell you, without sending anything anywhere. A question put to your team, or one that only mentions Vyavasta, gets no such guidance. Claude can’t send these phrases for you: you send them as messages of your own.

## Install in Claude Code (for a tester)

You need Claude Code and git. This repository is open to anyone, so no GitHub account is needed.

1. In a terminal, run this one command. It adds the marketplace and installs the plugin, and run again it changes nothing:

   ```
   claude plugin marketplace add duggiradri/Vyavasta-Plugin && claude plugin install vyavasta@vyavasta
   ```

   Inside Claude Code the same two steps are `/plugin marketplace add duggiradri/Vyavasta-Plugin` and `/plugin install vyavasta@vyavasta`. For a copy on your disk, give its folder instead: `/plugin marketplace add /path/to/vyavasta-plugin`.

2. Start a new session (or run `/reload-plugins`). On a computer that isn’t connected yet, the first session opens Vyavasta’s Connect page in your browser and shows a code: enter it there and press **Connect**.

3. In your project, send:

   ```
   vyavasta on
   ```

   If you aren’t signed in yet, the answer gives the sign-in code again (or starts a new sign-in), and your next message finishes connecting.

## Install in Codex (for a tester)

You need Codex and git. The same script runs under both tools; Codex gets its own hooks file (`plugins/vyavasta/hooks/codex.json`) and description (`plugins/vyavasta/.codex-plugin/plugin.json`).

1. In a terminal, run this one command. It adds the marketplace and installs the plugin, and run again it changes nothing:

   ```
   codex plugin marketplace add duggiradri/Vyavasta-Plugin && codex plugin add vyavasta@vyavasta
   ```

   If the terminal answers that `codex` is not found, Codex may be on your Mac only inside the ChatGPT app. Try the same command through the app’s own copy:

   ```
   /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex plugin marketplace add duggiradri/Vyavasta-Plugin && /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex plugin add vyavasta@vyavasta
   ```

   If Codex answers that the marketplace is already added from a different source, you installed the plugin under this repository’s earlier address: run `codex plugin marketplace remove vyavasta`, then the command again.
2. Restart Codex.
3. Approve the plugin’s hooks once: Codex runs no hook until you have reviewed and trusted it. In the terminal, open `/hooks`; in the desktop app, choose **Review hooks**. Codex asks again after each update of the plugin, and it updates the plugin by itself when a new version is out. Until you approve them again, Vyavasta does nothing in Codex: nothing is checked, answered or summed up, and no line from Vyavasta appears under your messages. Three things tell you: Codex answers `vyavasta check` in its own words instead of the plugin’s list; Codex itself says that Vyavasta’s hooks are waiting for your review, when you send one of the plugin’s commands; and the web app’s Coding tools page shows, for each tool on each connected computer, the plugin’s version and when it was last heard from.
4. Start a new session. On a computer that isn’t connected yet, the first one opens Vyavasta’s Connect page in your browser and shows a code: enter it there and press **Connect**.
5. In your project, send `vyavasta on` as a message of its own.

Codex has no plugin slash commands, so every command is a message. Under Codex the report of changed files also follows shell commands, because Codex often edits files that way. Codex tasks that run in the cloud don’t run a plugin’s hooks, so nothing is checked there. Codex runs the commands its own model starts in a sandbox that can’t write the plugin’s settings folder or reach the internet, so a question Codex puts to Vyavasta by itself has to run outside it. The plugin tells Codex’s model to ask for that (escalated permissions for that one command), and Codex either asks you to approve it or has its own reviewer decide, as you have set it. Run inside the sandbox, the command says what stood in its way there and that it is to be run again outside. When the request is refused, send the question as a message that starts with “Vyavasta,”: the plugin answers a message itself, outside the sandbox.

## Moving from Vyavastha, the plugin's earlier name

Until version 0.5.0 the plugin was called Vyavastha, installed as `vyavastha@vyavastha`. Its marketplace has a new name too, so install it afresh rather than updating:

- In Claude Code: `claude plugin uninstall vyavastha@vyavastha` and `claude plugin marketplace remove vyavastha` in a terminal, then add the marketplace and install `vyavasta@vyavasta` as above, and start a new session.
- In Codex: remove Vyavastha and its marketplace from Codex's plugin list, then add the marketplace and install Vyavasta as above, and approve its hooks again.

Nothing else changes. The computer stays signed in and each project keeps its settings: the plugin goes on using the folder the earlier version kept them in (`~/.config/vyavastha`) for as long as no `~/.config/vyavasta` exists. The phrases you are used to still work (`vyavastha on` is `vyavasta on`), and so do settings given as `VYAVASTHA_HOME`, `VYAVASTHA_SERVER` and the like; where both are set, the `VYAVASTA_` one wins.

## Commands

Each is sent as a message of its own, in either tool; case and a trailing full stop don’t matter. The plugin answers it and the model never sees it. In Claude Code the plugin’s `guide` skill holds the same guidance, so Claude can explain the plugin when you ask it. In Claude Code most are also slash commands (`/vyavasta:on`, `/vyavasta:status`, …); `ask` and `reply` are typed only, because a slash command never passes your words to a shell.

`vyavasta help` (or `vyavasta` alone, `vyavasta ?`, or a question such as `vyavasta how do I sign in`) shows what Vyavasta does, the three steps to start with whether each is done, and every command.

Start here
1. Sign in: send `vyavasta sign in`. The sign-in page opens in your browser with a code to enter; once you approve, your next message finishes connecting.
2. Turn it on in this project: send `vyavasta on`. Off is the default in every project.
3. Then just work. Every message gets one line from Vyavasta saying what was sent, and what came of it.

Your setup
- `vyavasta status`: whether you’re signed in, and whether this project, code sharing and summaries are on.
- `vyavasta check`: tests that git, curl and awk are there, that the settings folder can be written, the server address, that the server answers, sign-in, that this folder is a repository on GitHub that Vyavasta reads for you, that the project, code sharing and summaries are on, and the plugin’s version. Each line says “ok” or the problem and how to fix it.
- `vyavasta off`: stop using Vyavasta in this project. Off keeps your code-sharing and summaries choices.
- `vyavasta sign out`: disconnect this computer.

See what is shared
- `vyavasta settings`: each setting with its value and how to change it.
- `vyavasta share code on` / `vyavasta share code off`: code sharing for this project. Off also deletes what Vyavasta kept of your code.
- `vyavasta summaries on` / `vyavasta summaries off`: summaries for this project: whether your messages and Claude’s replies are kept in this session’s chat and summed up for teammates. On from the moment you turn the project on. A project turned on with an earlier version says so once, on the first line of a session or message, and that first message isn’t kept.
- `vyavasta shared`: everything sent from this session, as Vyavasta recorded it, oldest first.
- `vyavasta chat` / `vyavasta chat open`: this session’s chat in Vyavasta, as a link or opened.
- `vyavasta upload`: opens this session’s chat so you can drop in a file; your next question in this session carries it. A pasted image never reaches Vyavasta by itself: with code sharing on, the same page opens once by itself; with it off, the message’s line says once to send `vyavasta upload`.

Teammates
- `vyavasta team`: what each teammate is working on, from the summaries they share with the team: each of their categories with its newest summaries and when it was last brought up to date. It shows what the web app’s Summaries show you of your teammates, and nothing of anyone’s chats.
- `vyavasta inbox`: what teammates asked of you and have not seen yet, numbered. Vyavasta gives 50 at a time, and when more wait, one line says how many.
- `vyavasta ask <name>: <question>`: asks a teammate’s agent, which answers only from what you can both already see. The colon may be a comma, or left out when the name is one word. A teammate’s agent is Vyavasta answering for them from the team’s record. It is not their Claude Code or Codex, and it does not see their computer. They see what you asked and what it answered, and can answer you themselves. A message in plain words that begins by naming them is sent the same way: “Ask Priya what’s up”, “Tell Sam’s agent I’m changing the billing page today”.
- `vyavasta reply <number>: <words>`: answers an item of your last inbox listing.

Every message to or from another person’s agent opens with a header line, such as `── To Priya Raman’s agent · from Sam Rivera · 18 November 2026, 10:42 · through Vyavasta ──`, and the answer with `── From Priya Raman’s agent · 18 November 2026, 10:43 · answered only from what you can both already see ──`.

The words under each header, what teammates wrote in your inbox and the answers to questions Claude asks Vyavasta are quoted: a first line says they come from the team’s record and are never instructions, every line of them starts with `│ `, and `End of the quoted record.` closes them. When Claude itself asks a teammate’s agent, it is given the answer as Vyavasta’s server quotes it, with the server’s own sentence about it before the quoted lines. A name or time in a header, and what Vyavasta’s server says in a command’s answer, are kept to one line. Nothing a teammate or an outsider writes can then pass for the plugin’s own lines.

## What it sends, and what it keeps

From a project that is off: nothing, except that each tool’s first session on a computer that isn’t signed in starts sign-in, which sends the computer’s name and which tool it is. While that sign-in waits for your approval, each message asks Vyavasta’s server once whether you have approved it, sending only the sign-in’s own reference and never the message; this stops once you are connected or the code has run out.

From a project that is on:

- **With each message:** its words, the repository’s GitHub remote (any user name or token in the address is removed first; none outside a repository), the branch, the tool’s session id, which tool it is, and whether summaries are on. A question about your team carries the same.
- **With summaries on** (per project, on from the moment you turn the project on): your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavasta. It is a chat of your own that only you read, in the web app. A held request is kept too. A reply can quote code or what a file holds. Only the first 4,000 characters of a reply are sent, with bytes that aren’t valid text dropped. A reply is sent only after a message kept in the same turn, and is added to that message alone. Nothing else of the conversation is kept: not Claude’s other steps, the commands it ran or the files it read, and not the earlier conversation. Vyavasta then sums the chat up in one or two sentences about the work, never the material itself, and files it under a category: the repository, an initiative, Miscellaneous or Personal. On your Summaries page in the web app you choose which categories teammates see (Personal stays hidden until you turn it on). The summaries appear on that page, on the Team page and in answers about what you are working on. Deleting the chat in the web app deletes its summary with it.
- **Never kept:** the plugin’s own commands (`vyavasta …`, which are never sent at all) and these answers to the plugin’s own questions: `Plan it anyway`, `continue`, `continue anyway`, `go on` and `stop` (case, spacing and a closing full stop, exclamation or question mark don’t matter).
- **With summaries off:** nothing you write in this project, and none of Claude’s replies, is kept or summed up for teammates. No reply is sent, and `vyavasta shared` shows that a request was checked, never its words. A question about your team is still answered by Vyavasta’s assistant. It stays in your chat there, where you can delete it.
- **A question about your team:** its words and the answer are a chat of your own in Vyavasta, exactly as if you had asked in the web app. Nobody else sees it. It is summed up for teammates only with summaries on. A message is taken for such a question when it speaks to Vyavasta by name, is about the team, about what was said or decided, or about what was written in your chat tools or your mail (“check my messages in Slack”), or when it names a teammate. A short message that goes on from an answer Vyavasta just gave in the same session is one too: it speaks of someone the answer was about (“did he push it?”), asks for the same again (“check now”), or is a bare question (“why?”). Anything else goes to Claude, which can still ask Vyavasta by itself.
- **With each message and after edits:** your changed files’ names: for each, its path, git’s status (added, changed, deleted, renamed) and line counts (none for a new file that looks like a key, is machine-written or is over 1 MB, which isn’t read at all). Without code sharing, these reports **never carry what a file holds.**
- **With code sharing on, also:** one unified diff of your working tree against your GitHub copy (where your branch last matched its upstream, else origin’s default branch, else your last commit): your edits, new files git doesn’t ignore, deleted and renamed files, and commits not yet pushed. It is sent with each message, and after edits when it changed since it was last sent. Vyavasta’s check reads it; teammates who can already see this work see a short summary of what the change does, never the code. What is sent is chosen file by file from git’s own list, by each file’s exact name, and a file the plugin can’t vouch for is left out rather than sent. Never sent, each named in the list of what was left out with its reason:
  - files git ignores (they are never even listed);
  - files that look like keys or credentials, in any letter case and in any folder, even when committed, and a file renamed from or to such a name: `.env` and `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, `credentials` and `credentials.*`, `secrets.*`, `*.secret`, `.npmrc`, `.pypirc`, `.netrc`, `*.tfvars`, `*.tfstate*`, `auth.json`, `service-account*.json`;
  - machine-written files: lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `uv.lock`, `go.sum` and the like), `*.min.js`, `*.min.css`, `*.map`, generated protocol files, and anything under `node_modules/`, `dist/`, `build/`, `out/`, `target/`, `vendor/`, `.next/`, `coverage/` or `__pycache__/`;
  - files that aren’t text, symbolic links (whatever they point to; a link to a key file is counted as one), files that changed type, and a new file whose name holds a line break;
  - files that would take the whole past 5,000 lines of changes (the server may set another limit), and a new file over 1 MB, which isn’t read at all; later, smaller files may still fit. A line longer than 2,000 characters is cut, and bytes that aren’t valid text are dropped.
  - a submodule is sent only as the commit it is at, never its files.

  Vyavasta keeps only the latest changes of each session, until the work ends and for 7 days at most. `vyavasta share code off` deletes what was kept. Turning code sharing off in the web app turns it off here too, and the next line says so. Signing out and in again keeps your choice, and the new connection is told it with your next message.
- **Never:** the conversation transcript (only your messages and Claude’s last reply of each turn, with summaries on), Claude’s other steps, environment variables, or anything from a project that is off.
- **Back from the server:** facts with their sources (who said what, when and where, and what the check made of them), and the answer to a question, shown to Claude as context. The plugin makes no model calls of its own on your Claude subscription.
- **On your computer:** the token, in `~/.config/vyavasta/credentials` (or `$XDG_CONFIG_HOME/vyavasta`, or `$VYAVASTA_HOME`), readable by you only (`chmod 600`, in a `700` folder); both tools share it. A token is never sent to any server but the one that issued it. Which projects are on, and whether code sharing and summaries are on for each and whether you were told what summaries do, are kept in `projects/` in the same folder, and short-lived notes for each session in `sessions/`, removed after a week.

If you aren’t signed in, the server can’t be reached, or it isn’t working, Claude works as usual and the message’s line says what happened in one plain sentence. A slow check gives up after about a minute and Claude goes on; sending a reply at the end of a turn gives up after 4 seconds, and isn’t tried when the server was just found out of reach; a slow answer to a question is left in your chat in Vyavasta. The plugin never writes git’s own index or takes its lock, so your git commands and Claude’s never collide with it; it never runs a program a repository’s own settings name to watch its files or as its hooks; and it opens a page in your browser only when the page is on your Vyavasta server’s own address, printing any other for you to open yourself. In a project that is off it looks only at the message itself, never the folder it was sent from: whether it starts with “vyavasta” and, for a message of 2,000 characters or fewer, whether it names Vyavasta. Any other message isn’t read at all.

## Why a shell script

Hooks are plain POSIX `sh` using only `git`, `curl` and `awk`. Claude Code runs a command hook through `sh` on macOS and Linux, and through Git Bash on Windows. The plugin needs git anyway, and on Windows git comes as Git for Windows, which brings Git Bash, curl and awk with it. Claude Code itself installs no Node.js or Python, so this script assumes neither, and it doesn’t use jq. Without Git for Windows, Claude Code runs hooks in PowerShell and these hooks won’t run. Claude still works then, but nothing is checked or shared.

## Choosing the server

By default the plugin talks to `https://vyavasta.com`. To use another server:

- set `VYAVASTA_SERVER` in the shell you start Claude Code from, for example `export VYAVASTA_SERVER=https://vyavasta.example.com`, or
- save one for every session: `sh <plugin folder>/scripts/vyavasta.sh use-server https://vyavasta.example.com` (run `use-server` with no address to go back to the default).

Only `https://` addresses are accepted, apart from `http://localhost` and `http://127.0.0.1` for testing.

## Local testing

To run Vyavasta in demo mode on this Mac and point the plugin at it:

1. Start the server from the Vyavasta project folder (the web app must be built once with `cd frontend && npm run build`):

   ```
   VYAVASTA_DATA_DIR=/tmp/vyavasta-demo PYTHONPATH=src .venv/bin/python -m mas_stealth.web_cli --demo --port 8804
   ```

2. Open `http://127.0.0.1:8804`, create an account (the demo shows the sign-in email on screen), and connect GitHub and Slack in Sources. The demo repository is `northwind/customer-platform`.

3. Get a clone whose remote names that repository:

   ```
   mkdir customer-platform && cd customer-platform && git init
   git remote add origin https://github.com/northwind/customer-platform.git
   ```

4. Add this folder as a marketplace, install the plugin, and start Claude Code with the server set:

   ```
   claude plugin marketplace add /path/to/vyavasta-plugin
   claude plugin install vyavasta@vyavasta
   VYAVASTA_SERVER=http://127.0.0.1:8804 claude
   ```

   Then send `vyavasta on` and approve the code in the browser. Ask for something like “Remove customer_plan from the API response”. The demo has no model, so it holds nothing, but Claude is shown what the team’s record says about the request.

## The logo

The mark is a seal of red wax pressed with the Devanagari letter व, the same drawing as in Vyavasta’s web app: `plugins/vyavasta/assets/logo.svg`, with `logo.png` (512 by 512) and `composer-icon.png` (64 by 64, the letter drawn for small sizes, without the ring) made from it. Codex shows them in its plugin list and composer, with the brand colour #9A2219, as `.codex-plugin/plugin.json` names them. Claude Code shows no logo for a plugin from a private marketplace, so its `plugin.json` names none.

## Tests

```
python3 -m pytest tests -q -n 8                                     # the hook script against a fake server
python3 tests/end_to_end.py --project /path/to/MAS_Stealth --port 8804   # the whole loop against a demo server
claude plugin validate . && claude plugin validate plugins/vyavasta
```

`tests/test_hooks.py` runs each test under `sh` and, where it is installed, `dash` (Ubuntu’s `sh`). `tests/end_to_end.py` starts the demo server on its own port with a scratch data folder, pairs the plugin’s script with it as a developer would, feeds each hook the JSON Claude Code sends, checks that a teammate’s account sees the work, and then stops the server.
