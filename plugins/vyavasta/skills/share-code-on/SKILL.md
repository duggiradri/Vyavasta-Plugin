---
description: "Send your uncommitted changes to Vyavasta’s check from this project; teammates see only a summary (never keys, ignored, machine-written or non-text files)."
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

!`sh "${CLAUDE_PLUGIN_ROOT}/scripts/vyavasta.sh" share-code on || true`

The lines above come from the Vyavasta plugin. Show them to the developer exactly as they are, including any address and code, and do nothing else.
