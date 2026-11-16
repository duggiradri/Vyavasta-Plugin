---
name: vyavastha
description: How to sign in to, sign out of, or check the status of the Vyavastha plugin. Use when the developer asks how to connect Codex to Vyavastha or why a request was held.
---

The Vyavastha plugin checks each request against the team’s record before it reaches you, and it answers three
messages by itself. They never reach you, so you cannot run them for the developer. Tell the developer to send one
of these as a message of its own:

- `vyavastha sign in` shows a code and opens Vyavastha’s Connect page, where they approve this computer.
- `vyavastha status` says whether this computer is connected and whether this repository is one Vyavastha reads.
- `vyavastha sign out` ends this computer’s connection.

When a request was held, the developer was told what stands in the way. They go ahead by sending `Plan it anyway`.
Do not run the plugin’s script yourself, and do not guess what the team’s record says.
