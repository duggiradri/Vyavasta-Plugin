---
name: vyavastha
description: The team’s record in Vyavastha, and its plugin. Use when you need to know what a teammate is working on, what the team decided or who said what; and when the developer asks how to use the Vyavastha plugin, what it sends, or why a request was held.
---

The Vyavastha plugin checks each request against the team’s record before it reaches you. It is off in every
project until the developer turns it on there. It answers its own commands by itself: they never reach you, so you
cannot run them for the developer. Tell the developer to send the one they need as a message of its own:

Start here
- `vyavastha on` / `vyavastha off`: use Vyavastha in this project, or stop.
- `vyavastha status`: whether this computer is signed in, and whether this project, code sharing and summaries are on.
- `vyavastha check`: tests sign-in, the connection, this project and the plugin’s version, and says how to fix each problem.
- `vyavastha sign in` / `vyavastha sign out`: connect or disconnect this computer.

See what is shared
- `vyavastha settings`: every setting and how to change it.
- `vyavastha share code on` / `vyavastha share code off`: send the uncommitted changes with each message (teammates see only a summary, never the code), or stop and delete what was kept.
- `vyavastha summaries on` / `vyavastha summaries off`: keep the developer’s messages and your replies in a chat of their own in Vyavastha, summed up for teammates under categories they control there (on when the project is turned on), or stop.
- `vyavastha shared`: everything sent from this session.
- `vyavastha chat` (or `vyavastha chat open`): this session’s chat in Vyavastha.
- `vyavastha upload`: opens that chat so the developer can drop in a file for their next question.

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
that may keep it from reaching Vyavastha; when it says so, tell the developer they can ask the same thing by sending a message that starts
with “Vyavastha,”. Do not guess what the team’s record says, and run nothing else of the plugin’s script.
