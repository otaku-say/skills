# Agent Skills

Independently installable agent skills. Each skill has its own trigger description, entry instructions, and supporting files. See [CONTRIBUTING.md](CONTRIBUTING.md) for the required structure and rules for future additions.

## Skills

| Skill | Purpose | Boundary |
|---|---|---|
| [`aiod-cli/`](aiod-cli/SKILL.md) | Operate inside an existing CubeSandbox: commands, files, sessions, PTYs, code, browser, desktop, and MCP Hub | Data plane only; it does not create or remove sandboxes |
| [`cube-cli/`](cube-cli/SKILL.md) | Manage CubeSandbox lifecycle, templates, snapshots, volumes, and ports | Control plane only; use aiod-cli for in-sandbox work |

Install one or both skills globally with the Skills CLI:

```sh
npx skills add otaku-say/skills --skill aiod-cli -g
npx skills add otaku-say/skills --skill cube-cli -g
```

Update an installed skill with `npx skills update <skill-name> -g`. Remove one with `npx skills remove --global <skill-name>`. Each skill documents how to download/update its separate CLI binaries in its own directory.

## Standard layout

Every skill must have a `<skill-name>/SKILL.md` entry point whose frontmatter `name` matches its directory. Supporting directories are added only when needed:

```text
<skill-name>/
├── SKILL.md       # Required
├── references/    # Optional: longer documentation
├── scripts/       # Optional: deterministic helpers
├── assets/        # Optional: templates and output resources
└── bin/           # Optional: that skill's own CLI and maintenance tools
```

The current CLI skills follow the same structure:

```text
aiod-cli/ or cube-cli/
├── SKILL.md
├── bin/           # Wrapper, updater, verifier, and tool-specific checksums
└── references/    # Versioned CLI help and compatibility/test results
```

CLI binaries are fetched into their own skill's `bin/` directory from the versioned upstream Release and verified by checksum. They are not duplicated in Git. Maintenance scripts prefer static `curl`, `gawk`, and `openssl` from [`ish-toolbox`](https://github.com/otaku-say/ish-toolbox) when `ISH_TOOLBOX_BIN` points to its installed binary directory; current fallback behavior and the toolbox's missing standalone tools are documented in each skill. Examples use placeholders for deployment-specific URLs, IDs, paths, and credentials; never commit secrets or private infrastructure values.

Validate the repository before committing:

```sh
sh scripts/validate-skills.sh
```
