---
description: "Stop sending your uncommitted changes to Vyavasta from this project, and delete what it kept."
disable-model-invocation: true
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" share-code off:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" share-code off || true`

The lines above come from the Vyavasta plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
