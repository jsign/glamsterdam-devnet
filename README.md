# bal-devnet-3 + Ethrex

This directory contains a small bootstrap script for joining `bal-devnet-3` with:

- `ethrex` as the EL client
- `lighthouse` as the CL client

The script is designed to work from a clean directory:

- it downloads the published `bal-devnet-3` EL and CL metadata
- it creates a shared JWT secret for the Engine API
- it reuses local source checkouts under `./src` by default
- it checks out the `bal-devnet-3` branches for `ethrex` and `lighthouse` by default
- it can also clone `ethrex` and `lighthouse` itself and build both from source

## Files

- `bal-devnet-3-ethrex.sh`: bootstrap entrypoint

## Quick start

Clone the repos into `./src` if needed, then build and run them from there:

```bash
./bal-devnet-3-ethrex.sh clone
./bal-devnet-3-ethrex.sh setup
./bal-devnet-3-ethrex.sh build
./bal-devnet-3-ethrex.sh run-all
```

Start over from scratch without deleting `./src`:

```bash
./bal-devnet-3-ethrex.sh run-all --clean
```

Use different source checkouts explicitly:

```bash
ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./bal-devnet-3-ethrex.sh build

ETHREX_SRC=/path/to/ethrex \
LIGHTHOUSE_SRC=/path/to/lighthouse \
./bal-devnet-3-ethrex.sh run-all
```

Run the clients separately:

```bash
./bal-devnet-3-ethrex.sh run-el
./bal-devnet-3-ethrex.sh run-cl
```

Stop background processes started by `run-all`:

```bash
./bal-devnet-3-ethrex.sh stop
```

## Useful overrides

- `ETHREX_SRC`: existing ethrex checkout to use instead of `./src/ethrex`
- `LIGHTHOUSE_SRC`: existing lighthouse checkout to use instead of `./src/lighthouse`
- `ETHREX_BIN`: explicit ethrex binary path
- `LIGHTHOUSE_BIN`: explicit lighthouse binary path
- `ETHREX_SYNCMODE`: ethrex sync mode override (`snap` by default, set `full` if needed)
- `ETHREX_REF`: git ref to check out in `ethrex` instead of the default `bal-devnet-3`
- `LIGHTHOUSE_REF`: git ref to check out in `lighthouse` instead of the default `bal-devnet-3`
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
