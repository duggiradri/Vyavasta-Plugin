---
name: vyavastha
description: The team’s record in Vyavastha, and its plugin. Use when you need to know what a teammate is working on, what the team decided or who said what; and when the developer asks how to connect Codex to Vyavastha or why a request was held.
---

The Vyavastha plugin checks each request against the team’s record before it reaches you, and it answers three
messages by itself. They never reach you, so you cannot run them for the developer. Tell the developer to send one
of these as a message of its own:

- `vyavastha sign in` shows a code and opens Vyavastha’s Connect page, where they approve this computer.
- `vyavastha status` says whether this computer is connected and whether this repository is one Vyavastha reads.
- `vyavastha sign out` ends this computer’s connection.

When a request was held, the developer was told what stands in the way. They go ahead by sending `Plan it anyway`.

Questions about the team. Vyavastha keeps the team’s record: what teammates said, decided and promised, and what
each is working on. A message of the developer’s that asks about the team is answered by Vyavastha before it
reaches you, and you are given the answer: pass it on as it stands. When you need something else from the record,
ask Vyavastha before any other source such as email or chat tools, with the command the plugin gave you at the
start of the session (the plugin’s script with `ask "<the question>"`). Do not guess what the team’s record says,
and run nothing else of the plugin’s script.
