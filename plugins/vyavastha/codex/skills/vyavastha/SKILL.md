---
name: vyavastha
description: The team’s record in Vyavastha, and its plugin. Use when you need to know what a teammate is working on, what the team decided or who said what; and when the developer asks how to use, connect, sign in to or set up Vyavastha, how to turn it on or off, what it sends or shares, or why a request was held.
---

Vyavastha connects Codex to the developer’s team. In a project where it is on, it checks each request against what
the team has said and decided before you change code, sums each session up for teammates under categories the
developer controls, answers questions about the team, and lets the developer ask teammates’ agents. It is off in
every project until the developer turns it on there, and from a project that is off it sends nothing of the developer’s work.

The plugin answers its own commands itself, before they reach you, so you cannot run them for the developer. Tell the
developer which phrase to send, as a message of its own.

`vyavastha help` shows what Vyavastha does, the three steps to start with whether each is done, and every command.

Start here
1. Sign in: `vyavastha sign in` opens the sign-in page in the browser with a code to enter there, and once the developer approves, the next message finishes connecting, in any project.
2. Turn it on in this project: `vyavastha on`, in each project the developer wants it in.
3. Then just work: every message gets one line saying what was sent to Vyavastha and what came of it.

Your setup
- `vyavastha status`: whether this computer is signed in, and whether this project, code sharing and summaries are on.
- `vyavastha check`: tests sign-in, the connection, this project and the plugin’s version, and says how to fix each problem.
- `vyavastha off`: stop using Vyavastha in this project.
- `vyavastha sign out`: disconnect this computer.

See what is shared
- `vyavastha settings`: every setting and how to change it.
- `vyavastha share code on` / `vyavastha share code off`: code sharing, off until the developer turns it on, also sends the uncommitted changes with each message for the check (teammates see only a short summary, never the code; key files, ignored files, machine-written files and files that aren’t text are never sent); off stops it and deletes what was kept.
- `vyavastha summaries on` / `vyavastha summaries off`: summaries keep the developer’s messages and your replies in a chat of their own in Vyavastha, summed up for teammates under categories they control there (on when the project is turned on), or stop.
- `vyavastha shared`: everything sent from this session.
- `vyavastha chat` (or `vyavastha chat open`): this session’s chat in Vyavastha.
- `vyavastha upload`: opens that chat so the developer can drop in a file for their next question.

Otherwise, from a project that is on, each message’s words, the repository and branch, and changed files’ names are
sent.

Teammates
- `vyavastha inbox`: what teammates asked of the developer.
- `vyavastha ask <name>: <question>`: asks a teammate’s agent, which answers only from what the developer and that teammate can both already see.
- `vyavastha assign <name>: <task>`: gives a teammate a task (owners and administrators).
- `vyavastha reply <number>: <words>`, `vyavastha start <number>`, `vyavastha done <number>`, `vyavastha decline <number>`: answer an item of the inbox. Starting a task gives you its words as the developer’s request.

When a request was held, the developer was told what stands in the way. They go ahead by sending `Plan it anyway`.
When the plugin says something the team has said stands against the change being made, the developer answers
`continue` or `stop`.

Questions about the team. Vyavastha keeps the team’s record: what teammates said, decided and promised, and what
each is working on. A message of the developer’s that asks about the team is answered by Vyavastha before it
reaches you, and you are given the answer: pass it on as it stands. When you need something else from the record,
ask Vyavastha before any other source such as email or chat tools, with the command the plugin gave you at the
start of the session (the plugin’s script with `ask "<the question>"`). Codex runs that command in a closed-off space
that may keep it from reaching Vyavastha; when it says so, tell the developer they can ask the same thing by sending
a message that starts with “Vyavastha,”. Do not guess what the team’s record says, and run nothing else of the
plugin’s script.
