---
description: Show whether Claude Code on this computer is connected to Vyavastha, and whether this repository is checked.
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavastha.sh" status`

The lines above come from the Vyavastha plugin. Show them to the developer exactly as they are, and do nothing else.
