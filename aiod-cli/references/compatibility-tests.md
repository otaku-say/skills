# Compatibility and Test Results

Tested CLI release: `0.2.0` for both tools.

| Test | Result |
|---|---|
| Linux `amd64`/`x86_64` executable format | Passed: statically linked musl ELF binaries |
| Linux `arm64`/`aarch64` executable format | Passed: static ELF architecture and Release SHA256 checked; not executed on this host |
| `update.sh --force` | Passed on x86_64; downloaded both architecture assets and verified their Release checksums |
| `verify.sh` | Passed for both architecture assets against the upstream Release manifest |
| POSIX shell syntax | Passed with the host `/bin/sh` |
| Version and `help all` | Passed |
| Per-command help | Passed: 81 entries including aliases |
| `ish-toolbox` helpers | Passed using its x86_64 static `curl`, `gawk`, and `openssl` executables |
| Toolbox architecture/integrity doctor | Passed for both `amd64` and `arm64`; this verifies hashes, ELF architecture, and static linkage, but does not execute arm64 programs |
| Live aiod API on an Ubuntu 22.04 x86_64 code sandbox | Passed: health, sandbox metadata, sync exec, Python code, text write/read/delete, binary put/get round trip, async/log, command sessions, and PTY create/input/screen/remove |
| Browser and desktop APIs | Not tested: the test sandbox had the code image and no browser/computer capability |
| Skills CLI install/update/remove | Not executed; command syntax is documented, but those global lifecycle commands were not run |

The current `ish-toolbox` repository does not contain standalone `sha256sum` or `mktemp` executables. The maintenance scripts therefore prefer its `curl`, `gawk`, and `openssl`, fall back to system `awk`/`sha256sum`, and use a private PID-scoped directory made with `mkdir` instead of requiring `mktemp`.

The builds are intended for mainstream Linux distributions using either glibc or musl because the CLI ELF binaries are statically linked. This run executed only on the available x86_64 Linux host and tested aiod API behavior inside an Ubuntu 22.04 sandbox. Debian/Ubuntu, Fedora/RHEL, Arch, Alpine, and native arm64 runtime behavior still need testing on those hosts before claiming those matrix cells are executed-tested.
