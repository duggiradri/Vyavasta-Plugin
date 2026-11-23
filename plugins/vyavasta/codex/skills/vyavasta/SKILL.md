---
name: vyavasta
description: The team’s record in Vyavasta, and its plugin. Use when you need to know what a teammate is working on, what the team decided or who said what; when the developer asks how to use, connect, sign in to or set up Vyavasta, how to turn it on or off, what it sends or shares, or why a request was held; and when one of its own commands (a message such as “vyavasta check”) reaches you unanswered, which means the plugin is not running.
---

Vyavasta connects Codex to the developer’s team. In a project where it is on, it checks each request against what
the team has said and decided before you change code, sums each session up for teammates under categories the
developer controls, answers questions about the team, and lets the developer ask teammates’ agents. It is off in
every project until the developer turns it on there, and from a project that is off it sends nothing of the developer’s work.

The plugin answers its own commands itself, before they reach you, so you cannot run them for the developer. Tell the
developer which phrase to send, as a message of its own.

`vyavasta help` shows what Vyavasta does, the three steps to start with whether each is done, and every command.

Start here
1. Sign in: `vyavasta sign in` opens the sign-in page in the browser with a code to enter there, and once the developer approves, the next message finishes connecting, in any project. A computer already connected through Claude Code needs no sign-in here, because one connection serves both tools.
2. Turn it on in this project: `vyavasta on`, in each project the developer wants it in.
3. Then just work: every message gets one line saying what was sent to Vyavasta and what came of it.

Your setup
- `vyavasta status`: whether this computer is signed in, and whether this project, code sharing and summaries are on.
- `vyavasta check`: tests sign-in, the connection, this project and the plugin’s version, and says how to fix each problem.
- `vyavasta off`: stop using Vyavasta in this project.
- `vyavasta sign out`: disconnect this computer.

See what is shared
- `vyavasta settings`: every setting and how to change it.
- `vyavasta share code on` / `vyavasta share code off`: code sharing, off until the developer turns it on, also sends the uncommitted changes with each message for the check (teammates see only a short summary, never the code; key files, ignored files, machine-written files and files that aren’t text are never sent); off stops it and deletes what was kept.
- `vyavasta summaries on` / `vyavasta summaries off`: summaries keep the developer’s messages and your replies in a chat of their own in Vyavasta, summed up for teammates under categories they control there (on when the project is turned on), or stop.
- `vyavasta shared`: everything sent from this session.
- `vyavasta chat` (or `vyavasta chat open`): this session’s chat in Vyavasta.
- `vyavasta upload`: opens that chat so the developer can drop in a file for their next question.

Otherwise, from a project that is on, each message’s words, the repository and branch, and changed files’ names are
sent.

Teammates
- `vyavasta team`: what each teammate is working on, from the summaries they share with the team.
- `vyavasta inbox`: what teammates asked of the developer.
- `vyavasta ask <name>: <question>`: asks a teammate’s agent, which is Vyavasta answering for that teammate, only from what the developer and they can both already see. It does not see the teammate’s computer or coding session. The teammate sees the question and can answer it themselves. A message in plain words that names the teammate first (“ask Priya what’s up”) is sent the same way.
- `vyavasta reply <number>: <words>`: answers an item of the inbox.

When a request was held, the developer was told what stands in the way. They go ahead by sending `Plan it anyway`.
When the plugin says something the team has said stands against the change being made, the developer answers
`continue` or `stop`.

Questions about the team. Vyavasta keeps the team’s record: what teammates said, decided and promised, and what
each is working on. A message of the developer’s that asks about the team is answered by Vyavasta before it
reaches you, and you are given the answer: pass it on as it stands. When you need something else from the record,
ask Vyavasta before any other source such as email or chat tools, with the command the plugin gave you at the
start of the session (the plugin’s script with `ask "<the question>"`). Run that command outside Codex’s sandbox, by
asking for escalated permissions for it: it needs the internet to reach Vyavasta and its own settings folder, it only
asks a question, and it changes nothing in the project. Inside the sandbox it cannot reach Vyavasta, and says so. If
the request is refused, tell the developer they can ask the same thing by sending a message that starts with
“Vyavasta,”. Do not guess what the team’s record says, and run nothing else of the plugin’s script.

When the plugin is not running. Codex runs a plugin’s hooks only after the developer has reviewed and trusted them,
and it asks them to review again after every update of the plugin. Until they do, Vyavasta does nothing in Codex:
nothing is checked, answered or summed up, and no line from Vyavasta appears under the developer’s messages. You can
tell that this is so when one of the plugin’s own commands (a message such as `vyavasta check`, `vyavasta status` or
`vyavasta on`) reaches you, because the plugin answers those itself whenever it runs; and when the session began
with no note from Vyavasta in a project the developer says it is on in. Then run nothing of the plugin’s script. Tell
the developer that Vyavasta’s hooks are waiting for their review in Codex (Codex says the hooks need review), that
trusting them and starting a new session turns Vyavasta on again, and that Codex asks this once more after each
update of the plugin.
