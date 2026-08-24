# Glamsterdam devnet-8 + Ethrex/Prysm

This directory contains a bootstrap script for joining `glamsterdam-devnet-8` with:

- `ethrex` as the EL client
- `prysm` as the CL client

The script can do these tasks from a clean directory:

- Download the published `glamsterdam-devnet-8` EL and CL metadata.
- Create a shared JWT secret for the Engine API.
- Reuse local source checkouts under `./src` by default.
- Check out the `glamsterdam-devnet-8` branches for `ethrex` and `prysm` by default.
- Clone and build `ethrex` and `prysm` from source.

## Upgrade from devnet-7

Devnet-7 and devnet-8 have different genesis states. Do not use devnet-7 chain data with devnet-8.

If the devnet-7 services are active, stop them before you start devnet-8:

```bash
systemctl --user stop glamsterdam-devnet-7-prysm.service
systemctl --user stop glamsterdam-devnet-7-ethrex.service
```

Check out the new client branches and build both clients:

```bash
./glamsterdam-devnet-8.sh clone
./glamsterdam-devnet-8.sh build
```

Start devnet-8 with clean runtime data:

```bash
./glamsterdam-devnet-8.sh run-all --clean
```

CAUTION: The `--clean` option removes metadata, secrets, chain data, logs, and legacy PID files. It does not remove `./src`.

## Files

- `glamsterdam-devnet-8.sh`: bootstrap entrypoint

## Upstream references

- Network: https://plataberget.dev/
- Spec: https://notes.ethereum.org/@ethpandaops/glamsterdam-devnet-8
- Metadata: https://github.com/ethpandaops/glamsterdam-devnets/tree/master/network-configs/devnet-8/metadata

## Quick start

Clone the source repositories into `./src`. Then download the metadata, build the clients, and start the services:

```bash
./glamsterdam-devnet-8.sh clone
./glamsterdam-devnet-8.sh setup
./glamsterdam-devnet-8.sh build
./glamsterdam-devnet-8.sh run-all
```

`run-all` starts Ethrex and Prysm as separate transient systemd user services. Each
client is restarted independently after an unsuccessful exit, including an OOM
kill. Restarts wait 10 seconds and stop after five failed starts within five
minutes. The separate services also prevent systemd from stopping Prysm merely
because Ethrex was OOM-killed in the same tmux scope.

The services survive an SSH or tmux disconnection, but they are transient and
are not enabled across VM reboots. Run `run-all` again after a reboot.

Start with clean runtime data without removing `./src`:

```bash
./glamsterdam-devnet-8.sh run-all --clean
```

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-8.sh build

ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-8.sh run-all
```

Run the clients separately in the foreground without systemd supervision:

```bash
./glamsterdam-devnet-8.sh run-el
./glamsterdam-devnet-8.sh run-cl
```

Inspect the supervised clients and their readiness ports:

```bash
./glamsterdam-devnet-8.sh status
```

`status` exits successfully only when both units are active and their local
readiness ports are accepting connections. It also reports each main PID,
restart count, result, and current memory usage.

Stop services started by `run-all`:

```bash
./glamsterdam-devnet-8.sh stop
```

Application output is appended to `logs/ethrex.log` and `logs/prysm.log` across
automatic and manual restarts. Systemd lifecycle events are available with:

```bash
journalctl --user -u glamsterdam-devnet-8-ethrex.service
journalctl --user -u glamsterdam-devnet-8-prysm.service
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
- `PRYSM_P2P_LOCAL_IP`: Prysm P2P listen IP. The default is `auto`. Use an IP or `none` to skip detection.
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `glamsterdam-devnet-8`
- `PRYSM_REF`: git ref to check out in `prysm` instead of the default `glamsterdam-devnet-8`
- `CHECKPOINT_SYNC_URL`: override the beacon checkpoint sync endpoint
- `AUTHRPC_WAIT_SECS`: seconds to wait for Ethrex readiness during `run-all` (60 by default)
- `PRYSM_WAIT_SECS`: seconds to wait for Prysm readiness during `run-all` (300 by default)
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
