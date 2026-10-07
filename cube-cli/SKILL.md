---
name: cube-cli
description: >-
  Use the cube-cli installed within its skill directory whenever the user asks to create, list, inspect, select a template for, refresh, pause, resume, snapshot, clone, roll back, or remove a CubeSandbox; manage persistent volumes; inspect sandbox ports; or diagnose control-plane access. This skill manages the sandbox control plane and lifecycle. Use aiod-cli for commands, files, PTYs, code, browser, and desktop actions inside an existing sandbox. Trigger on cube-cli, CubeSandbox, sandbox lifecycle, template selection, snapshots, volumes, or CUBESANDBOX_API_URL.
compatibility: Designed for Linux amd64/x86_64 and arm64/aarch64 with static musl CLI builds. Maintenance scripts prefer curl, gawk, and openssl (or use system awk and sha256sum). See references/compatibility-tests.md for tested versus untested platform coverage. Requires the CubeSandbox control-plane URL and any credentials required by the deployment.
---

# cube-cli

Use `cube-cli` to manage the **CubeSandbox control plane**: choose a suitable image, create and inspect sandboxes, manage lifecycle and persistence, and discover reachable ports. Once a sandbox exists, use the separate `aiod-cli` skill for commands and files inside it.

## Install and configure

The wrapper selects a Linux amd64/x86_64 or arm64/aarch64 binary. The static musl builds are designed for mainstream Linux distributions including Debian/Ubuntu, Fedora/RHEL, Arch, and Alpine; this test run executed on x86_64 only. Read [Compatibility and Test Results](references/compatibility-tests.md) before treating an untested distro or arm64 runtime as verified.

```sh
npx skills add otaku-say/skills --skill cube-cli -g
CUBE_SKILL_DIR="/path/to/installed/cube-cli"
sh "$CUBE_SKILL_DIR/bin/update.sh"
sh "$CUBE_SKILL_DIR/bin/cube-cli" version
```

Set the deployment values in the runtime's protected environment, not in this repository or a command transcript:

| Variable | Required for | Meaning |
|---|---|---|
| `CUBESANDBOX_API_URL` | Control-plane operations | CubeSandbox control-plane base URL |
| `CUBESANDBOX_API_KEY` | Deployments that require API-key auth | Control-plane API key; the current CLI deployment may allow it to be absent |
| `CUBESANDBOX_PROXY_URL` | Data-plane operations such as `exec`, file access, and port URLs | Data-plane gateway base URL |
| `CUBESANDBOX_AGENT_NAME` | Optional | Default agent label for newly created sandboxes |

Use placeholders in examples and never commit actual domains, tokens, sandbox IDs, or deployment-specific data. Do not print secret values when checking whether configuration exists.

The updater and verifier prefer static `curl`, `gawk`, and `openssl` from [ish-toolbox](https://github.com/otaku-say/ish-toolbox) when `ISH_TOOLBOX_BIN` points to its installed binary directory. The current toolbox does not provide standalone `sha256sum` or `mktemp`; scripts use `openssl dgst -sha256` or a system `sha256sum` fallback, and use a PID-scoped `mkdir` path instead of `mktemp`. Read the compatibility reference for exact tested helper behavior.

```sh
CUBE_SKILL_DIR="/path/to/cube-cli"
sh "$CUBE_SKILL_DIR/bin/cube-cli" version
sh "$CUBE_SKILL_DIR/bin/cube-cli" help
```

For remote data-plane access, the CLI constructs paths as:

```text
$CUBESANDBOX_PROXY_URL/sandbox/<sandbox-id>/<port>/<path>
```

The sandbox ID is a capability: anyone holding a working URL may have access. Do not publish it. The data-plane route is deployment-specific; do not substitute a guessed hostname or connect directly to a sandbox IP.

## Select a template by capability

Do not hardcode template IDs; they can change when templates are rebuilt. Use the capability selector and inspect the live result:

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" tpl-caps
sh "$CUBE_SKILL_DIR/bin/cube-cli" tpl-pick --need=browser
```

- `code` is sufficient for shell commands, files, Python, Node, and compilation.
- `browser` includes code capability and adds browser services.
- `desktop` includes browser capability and adds desktop/computer-use services.

The `--need` relation is inclusive: `desktop` satisfies `browser` and `code`; `browser` satisfies `code`. Select the least capable image that meets the task. `tpl-caps --probe` creates temporary resources to probe capabilities; do not run it without the user's authorization and an appropriate cleanup plan.

## Create and inspect a sandbox

Before creating a sandbox, identify the task, choose the minimum capability, and set an explicit idle timeout. Sandbox creation may incur cost. Include non-sensitive ownership metadata so concurrent work is identifiable; do not place secrets in metadata.

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" new \
  --need=code \
  --timeout=3600 \
  --agent="<agent-name>" \
  --task="<short task description>"
```

Capture the returned sandbox ID exactly. Then inspect it:

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" ls --json
sh "$CUBE_SKILL_DIR/bin/cube-cli" info <sandbox-id> --json
sh "$CUBE_SKILL_DIR/bin/cube-cli" logs <sandbox-id> --tail=50
```

A successful create response does not mean every service inside is ready. For an AIO image, set `SANDBOX_BASE` using the actual configured proxy domain and sandbox ID, then check `aiod-cli health` before dispatching work.

## Lifecycle operations

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" refresh <sandbox-id> --duration=300
sh "$CUBE_SKILL_DIR/bin/cube-cli" timeout <sandbox-id> --timeout=7200
sh "$CUBE_SKILL_DIR/bin/cube-cli" pause <sandbox-id>
sh "$CUBE_SKILL_DIR/bin/cube-cli" resume <sandbox-id>
sh "$CUBE_SKILL_DIR/bin/cube-cli" net <sandbox-id> --no-internet
```

`timeout` controls the idle-reclamation window, not a guaranteed total lifetime. Use the deployed CLI's help for exact behavior and options:

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" help all
sh "$CUBE_SKILL_DIR/bin/cube-cli" help new
```

Treat actions that destroy or replace state as irreversible: ask the user before `rm`, volume deletion, snapshot deletion, and destructive rollback/overwrite. State which exact sandbox, volume, or snapshot will be affected and what data can be lost. Never infer an ID from a name when an explicit ID is available.

## Snapshots, clones, and persistence

```sh
SNAPSHOT_ID=$(sh "$CUBE_SKILL_DIR/bin/cube-cli" snap <sandbox-id> --name=<label>)
sh "$CUBE_SKILL_DIR/bin/cube-cli" snap-ls --sandbox=<sandbox-id>
sh "$CUBE_SKILL_DIR/bin/cube-cli" clone <sandbox-id> --n=1
sh "$CUBE_SKILL_DIR/bin/cube-cli" vol-ls
```

A rollback changes the target sandbox's filesystem and memory state; preview/identify the snapshot and get explicit user approval first. A clone is a new sandbox; record its returned ID.

Snapshots, rollbacks, and clones do **not** copy or restore the data inside mounted volumes or host mounts. Treat those stores as separate persistence systems. A volume may be shared; inspect references and detach all sandboxes before asking to remove one. Host mounts are deployment-specific and can write directly to host data; do not configure them unless the user has specified the exact paths and access mode.

## Ports and data-plane access

```sh
sh "$CUBE_SKILL_DIR/bin/cube-cli" ports <sandbox-id>
```

Use the observed listener and returned gateway URL, not template declarations alone. Services generally need to bind to `0.0.0.0` to be reachable through the proxy; loopback-bound services are available only inside the sandbox. Avoid exposing services containing private or sensitive data. Capability URLs should be treated like credentials.

## Failure handling

- `401`: check that the configured control-plane key is present and valid; do not print it.
- Template not found or no matching READY template: list templates and choose by current capabilities instead of reusing a stale ID.
- Data-plane `502`: check whether the service is listening and bound to a reachable address using `ports` and the in-sandbox CLI.
- `503` during lifecycle operations: honor `Retry-After` and retry the same operation only after the indicated wait.
- New sandbox returns transient readiness errors: wait for the relevant health endpoint rather than issuing repeated create requests.
- Request size or duration limits: perform the work within the sandbox and use `aiod-cli` asynchronous jobs or chunked transfers.

Avoid retrying non-idempotent lifecycle operations blindly. Inspect the sandbox state first to determine whether the original request completed.

## Update and uninstall

Update the installed skill files from the repository when its documentation or wrapper changes:

```sh
npx skills update cube-cli -g
```

Verify and update the independently released CLI binaries from inside the installed skill directory:

```sh
CUBE_SKILL_DIR="/path/to/installed/cube-cli"
sh "$CUBE_SKILL_DIR/bin/verify.sh"
# Exit 0: host binary current (a non-host binary may only warn); 1: host binary stale; 2: latest version could not be checked.
sh "$CUBE_SKILL_DIR/bin/update.sh"
# --force redownloads both architecture builds.
sh "$CUBE_SKILL_DIR/bin/update.sh" --force
```

The updater verifies SHA256 values from the upstream Release before replacing files. Re-run `verify.sh` after updating. A verification result of 2 means unknown, not current.

Remove the installed skill with:

```sh
npx skills remove --global cube-cli
```

This removes the local skill and its CLI files. It does not remove any remote sandbox, volume, snapshot, or user data. Handle remote cleanup separately and only after explicit approval.

## Skill-local files

- `bin/cube-cli` selects the downloaded binary for the current architecture.
- `bin/cube-cli-aarch64-linux-musl` and `bin/cube-cli-x86_64-linux-musl` are downloaded into the skill directory by `bin/update.sh`; they are kept out of Git because the upstream Release is the versioned binary source.
- `bin/SHA256SUMS` contains the binary checksums.
- `bin/verify.sh` checks the downloaded builds against the latest upstream Release.
- `bin/update.sh` downloads and verifies replacement builds.
- [Compatibility and Test Results](references/compatibility-tests.md) distinguishes tested behavior from architecture/distro claims that have not been executed here.
- `references/cli-reference.txt` contains the complete `help all` output captured from CLI 0.2.0. The installed binary's help is authoritative if versions differ.
