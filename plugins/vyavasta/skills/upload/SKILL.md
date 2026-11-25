---
description: "Open this session’s chat in Vyavasta so you can drop in a file for your next question."
disable-model-invocation: true
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" upload:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" upload || true`

The lines above come from the Vyavasta plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
