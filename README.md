# Sepolia (Glamsterdam) + Ethrex/Lighthouse

Run a Sepolia node with Ethrex as the execution-layer (EL) client and
Lighthouse as the consensus-layer (CL) client. The launcher builds each client's
Glamsterdam-ready release from source, using checkouts under `./src` by default:

| Client | Release |
| --- | --- |
| Ethrex | `v29.0.0` |
| Lighthouse | `v8.3.0-rc.0` |

Glamsterdam activates on Sepolia at epoch 353024 (slot 11296768),
2026-10-06 13:53:36 UTC. Both releases include Sepolia's genesis, bootnodes and
fork schedule, so the launcher passes `--network sepolia` and downloads no
network metadata.

## Requirements

The script assumes these are already installed:

- `bash`
- `openssl`
- `systemctl`, `systemd-run`, and `systemd-escape` for supervised `run-all`
- an accessible systemd user manager for supervised `run-all`
- `git` for cloning
- rustup with Rust and `cargo`; ethrex pins Rust 1.93.0 in its `rust-toolchain.toml`, and Lighthouse requires Rust 1.88 or newer
- a C/C++ compiler, CMake, and libclang development libraries for Lighthouse's native dependencies

Each client is built inside its checkout, so rustup applies the checkout's
toolchain file. The script does not install Rust or system dependencies. On
Debian/Ubuntu, native build prerequisites include `build-essential`, `cmake`,
and `libclang-dev`.

Ethrex documents 250 GB of disk as the minimum for Sepolia and 400 GB as
recommended, on NVMe; Lighthouse needs additional space. It documents 32 GB of
RAM as the minimum and 64 GB as recommended.

## Quick start

Clone and build the releases, then start both clients with chain data on a
large disk:

```bash
./sepolia.sh clone
./sepolia.sh build
DATA_DIR=/fast/sepolia ./sepolia.sh run-all
```

Pass the same `DATA_DIR` to every `run-all`, `run-el`, `run-cl`, and `clean`;
without it, chain data goes to `./data`. Ethrex stores its database in a
`sepolia` subdirectory of its data directory.

`run-all` creates or reuses the shared Engine API JWT secret and starts Ethrex
and Lighthouse as separate systemd user services. Lighthouse uses checkpoint
sync; Ethrex uses snap sync by default.

Each service restarts independently after a failure, including an OOM kill.
Restarts wait 10 seconds and stop after five failed starts within five minutes.

The services survive an SSH or tmux disconnection, but they are transient and
are not enabled across VM reboots. Run `run-all` again after a reboot.

## Manage services

Inspect the supervised clients and their readiness ports:

```bash
./sepolia.sh status
```

`status` exits successfully only when both units are active and their local
readiness ports are accepting connections. It also reports each main PID,
restart count, result, and current memory usage. Port readiness does not mean
the clients have finished syncing.

Stop services started by `run-all`:

```bash
./sepolia.sh stop
```

To restart both clients, run `stop` followed by `run-all`.

Application output is appended to `logs/ethrex.log` and `logs/lighthouse.log` across
automatic and manual restarts. Systemd lifecycle events are available with:

```bash
journalctl --user -u sepolia-ethrex.service
journalctl --user -u sepolia-lighthouse.service
```

Supervision recovers the clients after memory exhaustion, but it does not lower
their memory use. No memory ceiling or swap is configured by this launcher.

## Start fresh

Stop both services and restart with clean runtime data:

```bash
DATA_DIR=/fast/sepolia ./sepolia.sh run-all --clean
```

`run-all --clean` deletes both clients' chain data, the JWT secret, logs, and
PID files from the configured runtime directories. It preserves source
checkouts under `./src` and generates a new shared JWT.

To remove runtime data without restarting, use `./sepolia.sh clean` with the
same `DATA_DIR`.

## Run in the foreground

Run each command in a separate terminal. These processes run without systemd
supervision; stop them with Ctrl+C:

```bash
DATA_DIR=/fast/sepolia ./sepolia.sh run-el
DATA_DIR=/fast/sepolia ./sepolia.sh run-cl
```

## Configuration

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./sepolia.sh build

ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./sepolia.sh run-all
```

Available environment overrides:

- `DATA_DIR`: base directory for chain data (`./data` by default)
- `ETHREX_SRC`: existing ethrex checkout to use instead of `./src/ethrex`
- `LIGHTHOUSE_SRC`: existing Lighthouse checkout to use instead of `./src/lighthouse`
- `ETHREX_BIN`: explicit ethrex binary path
- `LIGHTHOUSE_BIN`: explicit Lighthouse binary path (otherwise use the checkout's `target/release/lighthouse`, then `lighthouse` on `PATH`)
- `ETHREX_SYNCMODE`: ethrex sync mode override (`snap` by default, set `full` if needed)
- `ETHREX_HTTP_API`: ethrex HTTP API modules (`eth,net,web3,debug` by default)
- `ETHREX_PRECOMPUTE_WITNESSES`: enable ethrex witness precomputation (`true` by default)
- `ETHREX_DATADIR`: ethrex base data directory (`DATA_DIR/ethrex` by default)
- `LIGHTHOUSE_GIT_URL`: Lighthouse repository URL (`https://github.com/sigp/lighthouse.git` by default)
- `LIGHTHOUSE_DATADIR`: Lighthouse database directory (`DATA_DIR/lighthouse` by default)
- `LIGHTHOUSE_HTTP_ADDR`: beacon API listen address (`127.0.0.1` by default)
- `LIGHTHOUSE_HTTP_PORT`: beacon API port (`5052` by default)
- `LIGHTHOUSE_P2P_LISTEN_ADDR`: P2P listen address (`0.0.0.0` by default)
- `LIGHTHOUSE_P2P_TCP_PORT`: P2P TCP port (`9000` by default)
- `LIGHTHOUSE_P2P_UDP_PORT`: discovery UDP port (`9000` by default)
- `LIGHTHOUSE_P2P_QUIC_PORT`: QUIC UDP port (`9001` by default)
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `v29.0.0`
- `LIGHTHOUSE_REF`: git ref to check out in `lighthouse` instead of the default `v8.3.0-rc.0`
- `CHECKPOINT_SYNC_URL`: beacon checkpoint sync endpoint (`https://checkpoint-sync.sepolia.ethpandaops.io` by default)
- `AUTHRPC_WAIT_SECS`: seconds to wait for Ethrex readiness during `run-all` (60 by default)
- `LIGHTHOUSE_WAIT_SECS`: seconds to wait for Lighthouse readiness during `run-all` (300 by default)
- `SRC_DIR`: change the default source checkout root from `./src`
- `WORKDIR`: move secrets, data, logs and source clones elsewhere

## Ports and sync checks

Default ports:

| Client | Interface | Address / port |
| --- | --- | --- |
| Ethrex | JSON-RPC | `127.0.0.1:8545` |
| Ethrex | Engine API | `127.0.0.1:8551` |
| Ethrex | P2P / discovery | TCP and UDP `30303` |
| Lighthouse | Beacon HTTP API | `127.0.0.1:5052` |
| Lighthouse | P2P / discovery | TCP and UDP `9000` |
| Lighthouse | QUIC | UDP `9001` |

Allow inbound TCP/UDP 30303, TCP/UDP 9000, and UDP 9001 for peer connections.
The JSON-RPC, Engine API, and beacon HTTP API listen on localhost by default.

After startup, inspect Lighthouse's peer count and sync state:

```bash
curl -fsS http://127.0.0.1:5052/eth/v1/node/peer_count
curl -fsS http://127.0.0.1:5052/eth/v1/node/syncing
curl -fsS http://127.0.0.1:5052/eth/v1/beacon/headers/head
curl -fsS -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://127.0.0.1:8545
```

Repeat the head checks to confirm both chains advance. Check `logs/lighthouse.log`
for checkpoint-sync progress and Engine API connection errors; an open API port
alone is not proof of synchronization.

After activation, the head state's fork reports the Gloas version `0x90000076`:

```bash
curl -fsS http://127.0.0.1:5052/eth/v1/beacon/states/head/fork
```

## Launcher checks

Run `bash -n sepolia.sh` and
`python3 -m unittest discover -s tests -v` for the isolated launcher checks.
These tests use temporary directories and fake clients/services; they do not
start real clients or change the current installation.

## Upstream references

- Announcement: https://blog.ethereum.org/2026/09/17/glamsterdam-testnet-announcement
- Ethrex release: https://github.com/lambdaclass/ethrex/releases/tag/v29.0.0
- Lighthouse release: https://github.com/sigp/lighthouse/releases/tag/v8.3.0-rc.0
