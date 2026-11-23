---
description: "Show what your teammates are working on, from the summaries they share in Vyavasta."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" team || true`

The lines above come from the Vyavasta plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
