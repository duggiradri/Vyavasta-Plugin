---
description: "Show whether Vyavastha is connected, whether it is on in this project, and whether code sharing and summaries are on."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavastha.sh" status || true`

The lines above come from the Vyavastha plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
