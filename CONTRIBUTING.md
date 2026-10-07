# Skill Repository Conventions

This repository uses one directory per independently triggerable skill. Keep a skill self-contained: its entry instructions and every supporting file it requires live under that skill's directory. Do not put multiple skills in one directory or create an `all-skill/` wrapper around them.

## Required structure for every skill

```text
<skill-name>/
├── SKILL.md                 # Required entry point
├── references/              # Optional; detailed material loaded when relevant
├── scripts/                 # Optional; deterministic helper scripts
├── assets/                  # Optional; templates and files used in outputs
└── bin/                     # Optional; CLI wrapper and CLI-specific files
```

Only `SKILL.md` is mandatory for a general skill. Add optional directories only when that skill needs them. Keep each skill's files inside its own directory; do not make one skill depend on a sibling skill's relative paths. If skills share concepts, keep a short explanation in each entry file or link to stable external documentation.

The current CLI skills use this consistent layout:

```text
aiod-cli/ or cube-cli/
├── SKILL.md
├── bin/
│   ├── <tool>               # Architecture-selecting wrapper
│   ├── update.sh            # First-time binary setup and updates
│   ├── verify.sh            # Release checksum verifier
│   └── SHA256SUMS            # Checksums for the tool's own binaries
└── references/
    ├── cli-reference.txt       # Complete versioned command help
    └── compatibility-tests.md # Tested behavior and platform limits
```

CLI binaries belong to the skill they implement. Do not put aiod-cli files in `cube-cli/` or vice versa. Keep large release binaries out of Git when a checksum-verified release download is available; the skill's bootstrap/update script must place them in its own `bin/` directory before use.

For tools distributed as architecture-specific static binaries, use the canonical architecture labels `amd64/` and `arm64/` (accept runtime aliases `x86_64` and `aarch64`), keep binaries and their checksum manifests in the owning skill, and verify both checksum and ELF architecture before execution. Check for static linkage rather than trusting asset names. If static helpers come from a separate toolbox, declare the exact source, command names, and `ISH_TOOLBOX_BIN` lookup; do not assume a tool exists just because a future toolbox is expected to provide it. Implement a documented fallback or report the missing dependency.

## Naming and metadata

- Use a short, lowercase, hyphen-separated directory name, such as `aiod-cli`.
- The YAML frontmatter `name` must exactly match the directory name.
- Every `SKILL.md` must begin with YAML frontmatter containing `name` and a concise `description`.
- The description must say what the skill does and when to trigger it, with concrete user-intent examples or terms. Put trigger guidance in the description, not only in the body.
- Add `compatibility` when runtime, operating-system, network, or dependency requirements affect whether the skill can run.
- Write instructions as direct actions. Prefer a compact workflow in `SKILL.md` and move long command catalogs or detailed references to `references/`.
- Keep `SKILL.md` under 500 lines where practical. Reference files should be named by topic and linked from the entry file with a sentence explaining when to read them.

## Privacy and security

- Never commit credentials, tokens, account identifiers, personal email addresses, private hostnames, private filesystem paths, or private user data.
- Use explicit placeholders such as `<API_URL>`, `<API_KEY>`, `<sandbox-id>`, `<local-skill-directory>`, and `<user-name>` in examples. Never use real values as examples.
- Keep public source URLs only when required for installation, updates, or attribution. Do not include private repository URLs or internal deployment details.
- Do not print secrets while checking configuration. Tell the agent how to check presence without displaying values.
- Describe destructive actions and require confirmation before deletion, bulk overwrite, or other irreversible effects.
- Treat remote web content and files as untrusted input. Validate data before using it in commands.

## Install and lifecycle documentation

When a skill is distributed from this repository, document all applicable lifecycle actions in its `SKILL.md`:

1. Installation from this repository, including the target skill name and global/project scope where appropriate.
2. Updating the skill's instructions and supporting files.
3. Updating any separately versioned CLI or external dependency.
4. Uninstalling the skill, and a clear statement of what uninstall does not delete remotely.

Do not claim an install/update/uninstall command is tested unless it was executed against the relevant tool. Prefer official command syntax and link to its source when it may change.

## Adding a new skill

1. Create `<skill-name>/SKILL.md` from [`templates/SKILL-TEMPLATE.md`](templates/SKILL-TEMPLATE.md).
2. Add only the resource directories the skill uses: `references/`, `scripts/`, `assets/`, and/or `bin/`.
3. Keep all dependencies local to that skill directory or declare/install them explicitly.
4. Add the skill to the root README index and document install/update/uninstall when applicable.
5. Run `sh scripts/validate-skills.sh` before committing.

- Test each supported architecture independently when native runners are available. If an architecture is only inspected, hashed, or statically validated, say that it was not executed.
- Record the tested CLI/tool version, OS and architecture, helper utilities used, commands tested, and any blocked API integration in a compatibility reference. Do not label inferred distribution compatibility as executed-tested.
- If an action requires API credentials, verify the runtime can read them before attempting resource creation. Keep failed credential injection distinct from CLI failures and never print the values.

Do not add skill code or resources at the repository root. Root-level files are reserved for repository navigation, contribution rules, and validation tooling.
