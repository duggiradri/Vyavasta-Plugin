---
description: "Stop sending your uncommitted changes to Vyavastha from this project, and delete what it kept."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavastha.sh" share-code off || true`

The lines above come from the Vyavastha plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
