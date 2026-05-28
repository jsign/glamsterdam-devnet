# Glamsterdam devnet-4 + Ethrex/Prysm

This directory contains a small bootstrap script for joining `glamsterdam-devnet-4` with:

- `ethrex` as the EL client
- `prysm` as the CL client

The script is designed to work from a clean directory:

- it downloads the published `glamsterdam-devnet-4` EL and CL metadata
- it creates a shared JWT secret for the Engine API
- it reuses local source checkouts under `./src` by default
- it checks out the `glamsterdam-devnet-4` branches for `ethrex` and `prysm` by default
- it can also clone `ethrex` and `prysm` itself and build both from source

## Files

- `glamsterdam-devnet-4.sh`: bootstrap entrypoint

## Quick start

Clone the repos into `./src` if needed, then build and run them from there:

```bash
./glamsterdam-devnet-4.sh clone
./glamsterdam-devnet-4.sh setup
./glamsterdam-devnet-4.sh build
./glamsterdam-devnet-4.sh run-all
```

Start over from scratch without deleting `./src`:

```bash
./glamsterdam-devnet-4.sh run-all --clean
```

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-4.sh build

ETHREX_SRC=/path/to/ethrex \
PRYSM_SRC=/path/to/prysm \
./glamsterdam-devnet-4.sh run-all
```

Run the clients separately:

```bash
./glamsterdam-devnet-4.sh run-el
./glamsterdam-devnet-4.sh run-cl
```

Stop background processes started by `run-all`:

```bash
./glamsterdam-devnet-4.sh stop
```

## Useful overrides

- `ETHREX_SRC`: existing ethrex checkout to use instead of `./src/ethrex`
- `PRYSM_SRC`: existing Prysm checkout to use instead of `./src/prysm`
- `ETHREX_BIN`: explicit ethrex binary path
- `PRYSM_BIN`: explicit Prysm `beacon-chain` binary path
- `ETHREX_SYNCMODE`: ethrex sync mode override (`snap` by default, set `full` if needed)
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `glamsterdam-devnet-4`
- `PRYSM_REF`: git ref to check out in `prysm` instead of the default `glamsterdam-devnet-4`
- `CHECKPOINT_SYNC_URL`: override the beacon checkpoint sync endpoint
- `SRC_DIR`: change the default source checkout root from `./src`
- `WORKDIR`: move metadata, data, logs and source clones elsewhere

## Expected tools

The script assumes these are already installed:

- `bash`
- `curl`
- `openssl`
- `git` for cloning
- `cargo` for ethrex source builds
- `bazelisk` or `bazel` for Prysm source builds

It does not install Rust, Bazel, system dependencies, or Docker by itself.
