---
description: Save text to Kemory, or your last reply when given none
argument-hint: "[text]"
---

On Claude Code 2.1.267 and later the Kemory module saves this itself.
Elsewhere, save it with `kemory_store_memory` in the `shared` namespace:

$ARGUMENTS

If no text was given, save the substance of your last reply. Write it so it
opens with the question someone would later ask, in plain words, then the
answer with the exact identifiers. Confirm in one line what you saved.
