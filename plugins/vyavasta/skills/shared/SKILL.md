---
description: "List everything this session sent to Vyavasta."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" shared || true`

The lines above come from the Vyavasta plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
