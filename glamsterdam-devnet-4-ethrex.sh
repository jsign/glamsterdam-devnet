#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$SCRIPT_DIR}"

NETWORK_NAME="${NETWORK_NAME:-glamsterdam-devnet-4}"
CONFIG_BASE_URL="${CONFIG_BASE_URL:-https://config.glamsterdam-devnet-4.ethpandaops.io}"
CHECKPOINT_SYNC_URL="${CHECKPOINT_SYNC_URL:-https://checkpoint-sync.glamsterdam-devnet-4.ethpandaops.io}"

METADATA_DIR="${METADATA_DIR:-$WORKDIR/metadata}"
SECRETS_DIR="${SECRETS_DIR:-$WORKDIR/secrets}"
DATA_DIR="${DATA_DIR:-$WORKDIR/data}"
LOG_DIR="${LOG_DIR:-$WORKDIR/logs}"
RUN_DIR="${RUN_DIR:-$WORKDIR/run}"
SRC_DIR="${SRC_DIR:-$WORKDIR/src}"

JWT_SECRET_PATH="${JWT_SECRET_PATH:-$SECRETS_DIR/jwt.hex}"

ETHREX_GIT_URL="${ETHREX_GIT_URL:-https://github.com/lambdaclass/ethrex.git}"
LIGHTHOUSE_GIT_URL="${LIGHTHOUSE_GIT_URL:-https://github.com/sigp/lighthouse.git}"
ETHREX_REF="${ETHREX_REF:-glamsterdam-devnet-4}"
LIGHTHOUSE_REF="${LIGHTHOUSE_REF:-glamsterdam-devnet-4}"

ETHREX_SRC="${ETHREX_SRC:-$SRC_DIR/ethrex}"
LIGHTHOUSE_SRC="${LIGHTHOUSE_SRC:-$SRC_DIR/lighthouse}"

ETHREX_BIN="${ETHREX_BIN:-}"
LIGHTHOUSE_BIN="${LIGHTHOUSE_BIN:-}"

HTTP_ADDR="${HTTP_ADDR:-127.0.0.1}"
HTTP_PORT="${HTTP_PORT:-8545}"
AUTHRPC_ADDR="${AUTHRPC_ADDR:-127.0.0.1}"
AUTHRPC_PORT="${AUTHRPC_PORT:-8551}"
ETHREX_P2P_PORT="${ETHREX_P2P_PORT:-30303}"
ETHREX_DISCOVERY_PORT="${ETHREX_DISCOVERY_PORT:-30303}"
ETHREX_SYNCMODE="${ETHREX_SYNCMODE:-snap}"

LIGHTHOUSE_HTTP_ADDR="${LIGHTHOUSE_HTTP_ADDR:-127.0.0.1}"
LIGHTHOUSE_HTTP_PORT="${LIGHTHOUSE_HTTP_PORT:-5052}"
LIGHTHOUSE_P2P_PORT="${LIGHTHOUSE_P2P_PORT:-9000}"
LIGHTHOUSE_DISCOVERY_PORT="${LIGHTHOUSE_DISCOVERY_PORT:-9000}"
LIGHTHOUSE_DATADIR="${LIGHTHOUSE_DATADIR:-$DATA_DIR/lighthouse}"
ETHREX_DATADIR="${ETHREX_DATADIR:-$DATA_DIR/ethrex}"

AUTHRPC_CONNECT_HOST="${AUTHRPC_CONNECT_HOST:-127.0.0.1}"
AUTHRPC_WAIT_SECS="${AUTHRPC_WAIT_SECS:-60}"

usage() {
  local script_name
  script_name="$(basename -- "$0")"

  cat <<EOF
Usage:
  ./$script_name setup
  ./$script_name clone
  ./$script_name build
  ./$script_name run-el
  ./$script_name run-cl
  ./$script_name run-all [--clean]
  ./$script_name stop
  ./$script_name clean
  ./$script_name paths

Main environment overrides:
  WORKDIR                  Base directory for metadata, data, logs and cloned repos
  SRC_DIR                  Base directory for source checkouts (defaults to WORKDIR/src)
  ETHREX_SRC              Existing ethrex checkout to use instead of cloning
  LIGHTHOUSE_SRC          Existing lighthouse checkout to use instead of cloning
  ETHREX_GIT_URL          ethrex clone URL when ETHREX_SRC does not already exist
  LIGHTHOUSE_GIT_URL      lighthouse clone URL when LIGHTHOUSE_SRC does not already exist
  ETHREX_REF              Git ref to checkout in ETHREX_SRC (defaults to glamsterdam-devnet-4)
  LIGHTHOUSE_REF          Git ref to checkout in LIGHTHOUSE_SRC (defaults to glamsterdam-devnet-4)
  ETHREX_BIN              Explicit ethrex binary path
  LIGHTHOUSE_BIN          Explicit lighthouse binary path
  CHECKPOINT_SYNC_URL     Beacon checkpoint sync endpoint
EOF
}

log() {
  printf '[%s] %s\n' "$1" "$2"
}

die() {
  log "error" "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

expect_no_args() {
  local cmd="$1"
  shift

  (( $# == 0 )) || die "$cmd does not accept extra arguments: $*"
}

ensure_layout() {
  mkdir -p \
    "$METADATA_DIR/el" \
    "$METADATA_DIR/cl" \
    "$SECRETS_DIR" \
    "$DATA_DIR" \
    "$LOG_DIR" \
    "$RUN_DIR" \
    "$SRC_DIR"
}

download_file() {
  local url="$1"
  local out="$2"

  log "info" "downloading $url"
  curl -fsSL "$url" -o "$out"
}

create_jwt_secret() {
  if [[ -s "$JWT_SECRET_PATH" ]]; then
    log "info" "reusing jwt secret at $JWT_SECRET_PATH"
    return
  fi

  require_cmd openssl
  openssl rand -hex 32 | tr -d '\n' > "$JWT_SECRET_PATH"
  printf '\n' >> "$JWT_SECRET_PATH"
  log "info" "created jwt secret at $JWT_SECRET_PATH"
}

write_lighthouse_bootstrap_yaml() {
  local src="$METADATA_DIR/cl/bootstrap_nodes.txt"
  local dst="$METADATA_DIR/cl/bootstrap_nodes.yaml"

  : > "$dst"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf -- '- "%s"\n' "$line" >> "$dst"
  done < "$src"
}

setup() {
  require_cmd curl
  ensure_layout

  download_file "$CONFIG_BASE_URL/el/genesis.json" "$METADATA_DIR/el/genesis.json"
  download_file "$CONFIG_BASE_URL/el/enodes.txt" "$METADATA_DIR/el/enodes.txt"

  download_file "$CONFIG_BASE_URL/cl/config.yaml" "$METADATA_DIR/cl/config.yaml"
  download_file "$CONFIG_BASE_URL/cl/genesis.ssz" "$METADATA_DIR/cl/genesis.ssz"
  download_file "$CONFIG_BASE_URL/cl/deposit_contract.txt" "$METADATA_DIR/cl/deposit_contract.txt"
  download_file "$CONFIG_BASE_URL/cl/deposit_contract_block.txt" "$METADATA_DIR/cl/deposit_contract_block.txt"
  download_file "$CONFIG_BASE_URL/cl/deposit_contract_block_hash.txt" "$METADATA_DIR/cl/deposit_contract_block_hash.txt"
  download_file "$CONFIG_BASE_URL/cl/bootstrap_nodes.txt" "$METADATA_DIR/cl/bootstrap_nodes.txt"

  write_lighthouse_bootstrap_yaml
  create_jwt_secret

  log "info" "$NETWORK_NAME metadata is ready under $METADATA_DIR"
}

clone_repo() {
  local name="$1"
  local url="$2"
  local dir="$3"
  local ref="$4"

  require_cmd git

  if [[ -d "$dir/.git" ]]; then
    log "info" "reusing existing $name checkout at $dir"
  elif [[ -e "$dir" ]]; then
    die "$name target path exists but is not a git checkout: $dir"
  else
    mkdir -p "$(dirname -- "$dir")"
    log "info" "cloning $name into $dir"
    git clone "$url" "$dir"
  fi

  if [[ -n "$ref" ]]; then
    log "info" "checking out $name ref $ref"
    git -C "$dir" fetch --all --tags
    git -C "$dir" checkout "$ref"
  fi
}

clone_all() {
  ensure_layout
  clone_repo "ethrex" "$ETHREX_GIT_URL" "$ETHREX_SRC" "$ETHREX_REF"
  clone_repo "lighthouse" "$LIGHTHOUSE_GIT_URL" "$LIGHTHOUSE_SRC" "$LIGHTHOUSE_REF"
}

build_ethrex() {
  require_cmd cargo
  [[ -d "$ETHREX_SRC" ]] || die "ethrex source directory does not exist: $ETHREX_SRC"
  log "info" "building ethrex from $ETHREX_SRC"
  cargo build --release --bin ethrex --manifest-path "$ETHREX_SRC/Cargo.toml"
}

build_lighthouse() {
  require_cmd cargo
  [[ -d "$LIGHTHOUSE_SRC" ]] || die "lighthouse source directory does not exist: $LIGHTHOUSE_SRC"
  log "info" "building lighthouse from $LIGHTHOUSE_SRC"
  cargo build --release --bin lighthouse --manifest-path "$LIGHTHOUSE_SRC/Cargo.toml"
}

build_all() {
  build_ethrex
  build_lighthouse
}

detect_ethrex_bin() {
  if [[ -n "$ETHREX_BIN" ]]; then
    [[ -x "$ETHREX_BIN" ]] || die "ETHREX_BIN is not executable: $ETHREX_BIN"
    printf '%s\n' "$ETHREX_BIN"
    return
  fi

  if [[ -x "$ETHREX_SRC/target/release/ethrex" ]]; then
    printf '%s\n' "$ETHREX_SRC/target/release/ethrex"
    return
  fi

  if command -v ethrex >/dev/null 2>&1; then
    command -v ethrex
    return
  fi

  die "ethrex binary not found; run build first or set ETHREX_BIN"
}

detect_lighthouse_bin() {
  if [[ -n "$LIGHTHOUSE_BIN" ]]; then
    [[ -x "$LIGHTHOUSE_BIN" ]] || die "LIGHTHOUSE_BIN is not executable: $LIGHTHOUSE_BIN"
    printf '%s\n' "$LIGHTHOUSE_BIN"
    return
  fi

  if [[ -x "$LIGHTHOUSE_SRC/target/release/lighthouse" ]]; then
    printf '%s\n' "$LIGHTHOUSE_SRC/target/release/lighthouse"
    return
  fi

  if command -v lighthouse >/dev/null 2>&1; then
    command -v lighthouse
    return
  fi

  die "lighthouse binary not found; run build first or set LIGHTHOUSE_BIN"
}

comma_join_file() {
  local file="$1"

  awk '
    NF {
      if (seen) {
        printf ","
      }
      printf "%s", $0
      seen = 1
    }
    END {
      printf "\n"
    }
  ' "$file"
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local timeout_secs="$3"
  local waited=0

  while ! (echo >"/dev/tcp/$host/$port") >/dev/null 2>&1; do
    sleep 1
    waited=$((waited + 1))
    if (( waited >= timeout_secs )); then
      die "timed out waiting for $host:$port"
    fi
  done
}

run_el() {
  local ethrex_bin bootnodes

  setup
  ethrex_bin="$(detect_ethrex_bin)"
  bootnodes="$(comma_join_file "$METADATA_DIR/el/enodes.txt")"

  exec "$ethrex_bin" \
    --network "$METADATA_DIR/el/genesis.json" \
    --bootnodes "$bootnodes" \
    --syncmode "$ETHREX_SYNCMODE" \
    --datadir "$ETHREX_DATADIR" \
    --http.addr "$HTTP_ADDR" \
    --http.port "$HTTP_PORT" \
    --authrpc.addr "$AUTHRPC_ADDR" \
    --authrpc.port "$AUTHRPC_PORT" \
    --authrpc.jwtsecret "$JWT_SECRET_PATH" \
    --p2p.port "$ETHREX_P2P_PORT" \
    --discovery.port "$ETHREX_DISCOVERY_PORT"
}

run_cl() {
  local lighthouse_bin

  setup
  lighthouse_bin="$(detect_lighthouse_bin)"

  exec "$lighthouse_bin" bn \
    --testnet-dir "$METADATA_DIR/cl" \
    --datadir "$LIGHTHOUSE_DATADIR" \
    --execution-endpoint "http://${AUTHRPC_CONNECT_HOST}:${AUTHRPC_PORT}" \
    --execution-jwt "$JWT_SECRET_PATH" \
    --checkpoint-sync-url "$CHECKPOINT_SYNC_URL" \
    --http \
    --http-address "$LIGHTHOUSE_HTTP_ADDR" \
    --http-port "$LIGHTHOUSE_HTTP_PORT" \
    --port "$LIGHTHOUSE_P2P_PORT" \
    --discovery-port "$LIGHTHOUSE_DISCOVERY_PORT"
}

start_background() {
  local name="$1"
  local log_file="$2"
  shift 2

  log "info" "starting $name in background"
  "$@" >"$log_file" 2>&1 &
  echo "$!" > "$RUN_DIR/$name.pid"
  log "info" "$name pid $(cat "$RUN_DIR/$name.pid"), logs at $log_file"
}

run_all() {
  setup
  ensure_layout

  start_background "ethrex" "$LOG_DIR/ethrex.log" "$0" run-el
  wait_for_port "$AUTHRPC_CONNECT_HOST" "$AUTHRPC_PORT" "$AUTHRPC_WAIT_SECS"
  start_background "lighthouse" "$LOG_DIR/lighthouse.log" "$0" run-cl

  cat <<EOF
Started $NETWORK_NAME services.

Ethrex log:     $LOG_DIR/ethrex.log
Lighthouse log: $LOG_DIR/lighthouse.log
Ethrex PID:     $(cat "$RUN_DIR/ethrex.pid")
Lighthouse PID: $(cat "$RUN_DIR/lighthouse.pid")

To stop both:
  $0 stop
EOF
}

stop_one() {
  local name="$1"
  local pid_file="$RUN_DIR/$name.pid"

  if [[ ! -f "$pid_file" ]]; then
    log "info" "no pid file for $name"
    return
  fi

  local pid
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    log "info" "stopping $name pid $pid"
    kill "$pid"
  fi
  rm -f "$pid_file"
}

stop_all() {
  stop_one "lighthouse"
  stop_one "ethrex"
}

clean() {
  stop_all
  rm -rf "$METADATA_DIR" "$SECRETS_DIR" "$DATA_DIR" "$LOG_DIR" "$RUN_DIR"
  log "info" "removed metadata, secrets, data, logs and pid files under $WORKDIR"
}

print_paths() {
  cat <<EOF
WORKDIR=$WORKDIR
METADATA_DIR=$METADATA_DIR
SECRETS_DIR=$SECRETS_DIR
DATA_DIR=$DATA_DIR
LOG_DIR=$LOG_DIR
RUN_DIR=$RUN_DIR
ETHREX_SRC=$ETHREX_SRC
LIGHTHOUSE_SRC=$LIGHTHOUSE_SRC
JWT_SECRET_PATH=$JWT_SECRET_PATH
CONFIG_BASE_URL=$CONFIG_BASE_URL
CHECKPOINT_SYNC_URL=$CHECKPOINT_SYNC_URL
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    setup)
      expect_no_args "$cmd" "$@"
      setup
      ;;
    clone)
      expect_no_args "$cmd" "$@"
      clone_all
      ;;
    build)
      expect_no_args "$cmd" "$@"
      build_all
      ;;
    run-el)
      expect_no_args "$cmd" "$@"
      run_el
      ;;
    run-cl)
      expect_no_args "$cmd" "$@"
      run_cl
      ;;
    run-all)
      case "${1:-}" in
        "")
          run_all
          ;;
        --clean)
          shift
          expect_no_args "$cmd --clean" "$@"
          clean
          run_all
          ;;
        *)
          die "unknown option for $cmd: $1"
          ;;
      esac
      ;;
    stop)
      expect_no_args "$cmd" "$@"
      stop_all
      ;;
    clean)
      expect_no_args "$cmd" "$@"
      clean
      ;;
    paths)
      expect_no_args "$cmd" "$@"
      print_paths
      ;;
    help|-h|--help|"")
      expect_no_args "${cmd:-help}" "$@"
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"
