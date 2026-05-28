# Glamsterdam devnet-4 + Ethrex

This directory contains a small bootstrap script for joining `glamsterdam-devnet-4` with:

- `ethrex` as the EL client
- `lighthouse` as the CL client

The script is designed to work from a clean directory:

- it downloads the published `glamsterdam-devnet-4` EL and CL metadata
- it creates a shared JWT secret for the Engine API
- it reuses local source checkouts under `./src` by default
- it checks out the `glamsterdam-devnet-4` branches for `ethrex` and `lighthouse` by default
- it can also clone `ethrex` and `lighthouse` itself and build both from source

## Files

- `glamsterdam-devnet-4-ethrex.sh`: bootstrap entrypoint

## Quick start

Clone the repos into `./src` if needed, then build and run them from there:

```bash
./glamsterdam-devnet-4-ethrex.sh clone
./glamsterdam-devnet-4-ethrex.sh setup
./glamsterdam-devnet-4-ethrex.sh build
./glamsterdam-devnet-4-ethrex.sh run-all
```

Start over from scratch without deleting `./src`:

```bash
./glamsterdam-devnet-4-ethrex.sh run-all --clean
```

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./glamsterdam-devnet-4-ethrex.sh build

ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./glamsterdam-devnet-4-ethrex.sh run-all
```

Run the clients separately:

```bash
./glamsterdam-devnet-4-ethrex.sh run-el
./glamsterdam-devnet-4-ethrex.sh run-cl
```

Stop background processes started by `run-all`:

```bash
./glamsterdam-devnet-4-ethrex.sh stop
```

## Useful overrides

- `ETHREX_SRC`: existing ethrex checkout to use instead of `./src/ethrex`
- `LIGHTHOUSE_SRC`: existing lighthouse checkout to use instead of `./src/lighthouse`
- `ETHREX_BIN`: explicit ethrex binary path
- `LIGHTHOUSE_BIN`: explicit lighthouse binary path
- `ETHREX_SYNCMODE`: ethrex sync mode override (`snap` by default, set `full` if needed)
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `glamsterdam-devnet-4`
- `LIGHTHOUSE_REF`: git ref to check out in `lighthouse` instead of the default `glamsterdam-devnet-4`
- `CHECKPOINT_SYNC_URL`: override the beacon checkpoint sync endpoint
- `SRC_DIR`: change the default source checkout root from `./src`
- `WORKDIR`: move metadata, data, logs and source clones elsewhere

## Expected tools

The script assumes these are already installed:

- `bash`
- `curl`
- `openssl`
- `git` for cloning
- `cargo` for source builds

It does not install Rust, system dependencies, or Docker by itself.
