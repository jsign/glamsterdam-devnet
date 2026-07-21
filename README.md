# Glamsterdam devnet-7 + Ethrex/Prysm

This directory contains a small bootstrap script for joining `glamsterdam-devnet-7` with:

- `ethrex` as the EL client
- `prysm` as the CL client

The script is designed to work from a clean directory:

- it downloads the published `glamsterdam-devnet-7` EL and CL metadata
- it creates a shared JWT secret for the Engine API
- it reuses local source checkouts under `./src` by default
- it checks out the `glamsterdam-devnet-7` branches for `ethrex` and `prysm` by default
- it can also clone `ethrex` and `prysm` itself and build both from source

To clean up a previous run before starting again:

```bash
./glamsterdam-devnet-7.sh clean
```

This stops supervised clients and removes generated metadata, secrets, chain data, logs and legacy PID files without deleting `./src`.

## Files

- `glamsterdam-devnet-7.sh`: bootstrap entrypoint

## Upstream references

- Spec: https://notes.ethereum.org/@ethpandaops/glamsterdam-devnet-7
- Metadata: https://github.com/ethpandaops/glamsterdam-devnets/tree/master/network-configs/devnet-7/metadata

## Quick start

Clone the repos into `./src` if needed, then build and run them from there:

```bash
./glamsterdam-devnet-7.sh clone
./glamsterdam-devnet-7.sh setup
./glamsterdam-devnet-7.sh build
./glamsterdam-devnet-7.sh run-all
```

`run-all` starts Ethrex and Prysm as separate transient systemd user services. Each
client is restarted independently after an unsuccessful exit, including an OOM
kill. Restarts wait 10 seconds and stop after five failed starts within five
minutes. The separate services also prevent systemd from stopping Prysm merely
because Ethrex was OOM-killed in the same tmux scope.

The services survive an SSH or tmux disconnection, but they are transient and
are not enabled across VM reboots. Run `run-all` again after a reboot.

Start over from scratch without deleting `./src`:

```bash
./glamsterdam-devnet-7.sh run-all --clean
```

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-7.sh build

ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-7.sh run-all
```

Run the clients separately in the foreground without systemd supervision:

```bash
./glamsterdam-devnet-7.sh run-el
./glamsterdam-devnet-7.sh run-cl
```

Inspect the supervised clients and their readiness ports:

```bash
./glamsterdam-devnet-7.sh status
```

`status` exits successfully only when both units are active and their local
readiness ports are accepting connections. It also reports each main PID,
restart count, result, and current memory usage.

Stop services started by `run-all`:

```bash
./glamsterdam-devnet-7.sh stop
```

Application output is appended to `logs/ethrex.log` and `logs/prysm.log` across
automatic and manual restarts. Systemd lifecycle events are available with:

```bash
journalctl --user -u glamsterdam-devnet-7-ethrex.service
journalctl --user -u glamsterdam-devnet-7-prysm.service
```

Supervision recovers the clients after memory exhaustion, but it does not lower
their memory use. No memory ceiling or swap is configured by this launcher.

## Useful overrides

- `ETHREX_SRC`: existing ethrex checkout to use instead of `./src/ethrex`
- `PRYSM_SRC`: existing Prysm checkout to use instead of `./src/prysm`
- `ETHREX_BIN`: explicit ethrex binary path
- `PRYSM_BIN`: explicit Prysm `beacon-chain` binary path
- `ETHREX_SYNCMODE`: ethrex sync mode override (`snap` by default, set `full` if needed)
- `ETHREX_HTTP_API`: ethrex HTTP API modules (`eth,net,web3,debug` by default)
- `ETHREX_PRECOMPUTE_WITNESSES`: enable ethrex witness precomputation (`true` by default)
- `PRYSM_P2P_LOCAL_IP`: Prysm P2P listen IP (`auto` by default; set an IP explicitly or `none` to skip)
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `glamsterdam-devnet-7`
- `PRYSM_REF`: git ref to check out in `prysm` instead of the default `glamsterdam-devnet-7`
- `CHECKPOINT_SYNC_URL`: override the beacon checkpoint sync endpoint
- `AUTHRPC_WAIT_SECS`: seconds to wait for Ethrex readiness during `run-all` (60 by default)
- `PRYSM_WAIT_SECS`: seconds to wait for Prysm readiness during `run-all` (60 by default)
- `SRC_DIR`: change the default source checkout root from `./src`
- `WORKDIR`: move metadata, data, logs and source clones elsewhere

## Expected tools

The script assumes these are already installed:

- `bash`
- `curl`
- `openssl`
- `ip` for automatic Prysm P2P local IP detection
- `systemctl`, `systemd-run`, and `systemd-escape` for supervised `run-all`
- an accessible systemd user manager for supervised `run-all`
- `git` for cloning
- `cargo` for ethrex source builds
- `bazelisk` or `bazel` for Prysm source builds

It does not install Rust, Bazel, system dependencies, or Docker by itself.
