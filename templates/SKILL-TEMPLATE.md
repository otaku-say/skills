---
name: <skill-name>
description: >-
  Use this skill whenever the user asks to <primary task>. Trigger on requests
  involving <specific intent or domain terms>. It <main action or outcome>.
compatibility: <runtime, tools, network, or OS requirements; omit if none>
---

# <Skill Title>

In one short paragraph, state the skill's boundary and the result it helps produce. Name related workflows only to distinguish scope; keep this skill self-contained.

## Workflow

1. Confirm the user's target and constraints from their request.
2. Inspect the relevant current state before acting; do not guess identifiers or options.
3. Perform the smallest task-scoped operation and verify its result.
4. Ask before irreversible changes or any action requiring confirmation.

## Usage

Show concise examples with placeholders only:

```sh
<command> --target=<resource-id>
```

Move long command references to `references/` and explain when to read each one.

## Safety and troubleshooting

Describe sensitive inputs, untrusted data, destructive actions, and the most likely failure cases. Never put real credentials or private deployment values in this file.

## Install, update, and uninstall

Document the verified commands for installing this skill, updating the skill files, updating any separate tool binaries, and removing the skill. State which remote resources are unaffected by uninstall. Use placeholders where an owner, path, credential, or deployment value is user-specific.

## Resources

List only files that exist in this skill directory and describe when the agent should load or run them.
