---
description: "Connect Claude Code on this computer to your team’s Vyavastha workspace."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavastha.sh" sign-in || true`

The lines above come from the Vyavastha plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
