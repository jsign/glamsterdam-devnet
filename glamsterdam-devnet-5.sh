#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$SCRIPT_DIR}"

NETWORK_NAME="${NETWORK_NAME:-glamsterdam-devnet-5}"
CONFIG_BASE_URL="${CONFIG_BASE_URL:-https://config.glamsterdam-devnet-5.ethpandaops.io}"
CHECKPOINT_SYNC_URL="${CHECKPOINT_SYNC_URL:-https://checkpoint-sync.glamsterdam-devnet-5.ethpandaops.io}"

METADATA_DIR="${METADATA_DIR:-$WORKDIR/metadata}"
SECRETS_DIR="${SECRETS_DIR:-$WORKDIR/secrets}"
DATA_DIR="${DATA_DIR:-$WORKDIR/data}"
LOG_DIR="${LOG_DIR:-$WORKDIR/logs}"
RUN_DIR="${RUN_DIR:-$WORKDIR/run}"
SRC_DIR="${SRC_DIR:-$WORKDIR/src}"

JWT_SECRET_PATH="${JWT_SECRET_PATH:-$SECRETS_DIR/jwt.hex}"

ETHREX_GIT_URL="${ETHREX_GIT_URL:-https://github.com/lambdaclass/ethrex.git}"
PRYSM_GIT_URL="${PRYSM_GIT_URL:-https://github.com/OffchainLabs/prysm.git}"
ETHREX_REF="${ETHREX_REF:-glamsterdam-devnet-5}"
PRYSM_REF="${PRYSM_REF:-glamsterdam-devnet-5}"

ETHREX_SRC="${ETHREX_SRC:-$SRC_DIR/ethrex}"
PRYSM_SRC="${PRYSM_SRC:-$SRC_DIR/prysm}"

ETHREX_BIN="${ETHREX_BIN:-}"
PRYSM_BIN="${PRYSM_BIN:-}"

HTTP_ADDR="${HTTP_ADDR:-127.0.0.1}"
HTTP_PORT="${HTTP_PORT:-8545}"
AUTHRPC_ADDR="${AUTHRPC_ADDR:-127.0.0.1}"
AUTHRPC_PORT="${AUTHRPC_PORT:-8551}"
ETHREX_P2P_PORT="${ETHREX_P2P_PORT:-30303}"
ETHREX_DISCOVERY_PORT="${ETHREX_DISCOVERY_PORT:-30303}"
ETHREX_SYNCMODE="${ETHREX_SYNCMODE:-snap}"
ETHREX_HTTP_API="${ETHREX_HTTP_API:-eth,net,web3,debug}"
ETHREX_PRECOMPUTE_WITNESSES="${ETHREX_PRECOMPUTE_WITNESSES:-true}"

PRYSM_HTTP_ADDR="${PRYSM_HTTP_ADDR:-127.0.0.1}"
PRYSM_HTTP_PORT="${PRYSM_HTTP_PORT:-3500}"
PRYSM_P2P_LOCAL_IP="${PRYSM_P2P_LOCAL_IP:-auto}"
PRYSM_P2P_TCP_PORT="${PRYSM_P2P_TCP_PORT:-13000}"
PRYSM_P2P_UDP_PORT="${PRYSM_P2P_UDP_PORT:-12000}"
PRYSM_P2P_QUIC_PORT="${PRYSM_P2P_QUIC_PORT:-13000}"
PRYSM_DATADIR="${PRYSM_DATADIR:-$DATA_DIR/prysm}"
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
  PRYSM_SRC               Existing Prysm checkout to use instead of cloning
  ETHREX_GIT_URL          ethrex clone URL when ETHREX_SRC does not already exist
  PRYSM_GIT_URL           Prysm clone URL when PRYSM_SRC does not already exist
  ETHREX_REF              Git ref to checkout in ETHREX_SRC (defaults to glamsterdam-devnet-5)
  PRYSM_REF               Git ref to checkout in PRYSM_SRC (defaults to glamsterdam-devnet-5)
  ETHREX_BIN              Explicit ethrex binary path
  PRYSM_BIN               Explicit Prysm beacon-chain binary path
  ETHREX_HTTP_API         ethrex HTTP API modules (defaults to eth,net,web3,debug)
  ETHREX_PRECOMPUTE_WITNESSES
                           Enable ethrex witness precomputation (defaults to true)
  PRYSM_P2P_LOCAL_IP       Local IP for Prysm P2P listeners (defaults to auto)
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

write_prysm_bootstrap_yaml() {
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

  write_prysm_bootstrap_yaml
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
  clone_repo "prysm" "$PRYSM_GIT_URL" "$PRYSM_SRC" "$PRYSM_REF"
}

build_ethrex() {
  require_cmd cargo
  [[ -d "$ETHREX_SRC" ]] || die "ethrex source directory does not exist: $ETHREX_SRC"
  log "info" "building ethrex from $ETHREX_SRC"
  cargo build --release --bin ethrex --manifest-path "$ETHREX_SRC/Cargo.toml"
}

build_prysm() {
  local bazel_bin

  [[ -d "$PRYSM_SRC" ]] || die "Prysm source directory does not exist: $PRYSM_SRC"
  if command -v bazelisk >/dev/null 2>&1; then
    bazel_bin="$(command -v bazelisk)"
  elif command -v bazel >/dev/null 2>&1; then
    bazel_bin="$(command -v bazel)"
  else
    die "missing required command for Prysm build: bazelisk or bazel"
  fi

  log "info" "building Prysm beacon-chain from $PRYSM_SRC"
  (cd "$PRYSM_SRC" && "$bazel_bin" build //cmd/beacon-chain:beacon-chain)
}

build_all() {
  build_ethrex
  build_prysm
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

detect_prysm_bin() {
  local candidate

  if [[ -n "$PRYSM_BIN" ]]; then
    [[ -x "$PRYSM_BIN" ]] || die "PRYSM_BIN is not executable: $PRYSM_BIN"
    printf '%s\n' "$PRYSM_BIN"
    return
  fi

  for candidate in \
    "$PRYSM_SRC/bazel-bin/cmd/beacon-chain/beacon-chain_/beacon-chain" \
    "$PRYSM_SRC/bazel-bin/cmd/beacon-chain/beacon-chain"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  if command -v beacon-chain >/dev/null 2>&1; then
    command -v beacon-chain
    return
  fi

  if command -v prysm-beacon-chain >/dev/null 2>&1; then
    command -v prysm-beacon-chain
    return
  fi

  die "Prysm beacon-chain binary not found; run build first or set PRYSM_BIN"
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

detect_default_ipv4() {
  command -v ip >/dev/null 2>&1 || return 1

  ip -4 route get 1.1.1.1 2>/dev/null | awk '
    {
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }
  '
}

run_el() {
  local ethrex_bin bootnodes

  setup
  ethrex_bin="$(detect_ethrex_bin)"
  bootnodes="$(comma_join_file "$METADATA_DIR/el/enodes.txt")"

  export ETHREX_HTTP_API
  export ETHREX_PRECOMPUTE_WITNESSES

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
  local prysm_bin deposit_contract_block p2p_local_ip
  local -a prysm_args

  setup
  prysm_bin="$(detect_prysm_bin)"
  deposit_contract_block="$(tr -d '[:space:]' < "$METADATA_DIR/cl/deposit_contract_block.txt")"
  [[ -n "$deposit_contract_block" ]] || deposit_contract_block=0
  p2p_local_ip="$PRYSM_P2P_LOCAL_IP"

  if [[ "$p2p_local_ip" == "auto" ]]; then
    p2p_local_ip="$(detect_default_ipv4 || true)"
    [[ -n "$p2p_local_ip" ]] || die "could not auto-detect Prysm P2P local IP; set PRYSM_P2P_LOCAL_IP explicitly or set PRYSM_P2P_LOCAL_IP=none"
  fi

  prysm_args=(
    --chain-config-file "$METADATA_DIR/cl/config.yaml"
    --genesis-state "$METADATA_DIR/cl/genesis.ssz"
    --bootstrap-node "$METADATA_DIR/cl/bootstrap_nodes.yaml"
    --datadir "$PRYSM_DATADIR"
    --execution-endpoint "http://${AUTHRPC_CONNECT_HOST}:${AUTHRPC_PORT}"
    --jwt-secret "$JWT_SECRET_PATH"
    --checkpoint-sync-url "$CHECKPOINT_SYNC_URL"
    --contract-deployment-block "$deposit_contract_block"
    --accept-terms-of-use
    --http-host "$PRYSM_HTTP_ADDR"
    --http-port "$PRYSM_HTTP_PORT"
    --p2p-tcp-port "$PRYSM_P2P_TCP_PORT"
    --p2p-udp-port "$PRYSM_P2P_UDP_PORT"
    --p2p-quic-port "$PRYSM_P2P_QUIC_PORT"
  )

  if [[ -n "$p2p_local_ip" && "$p2p_local_ip" != "none" ]]; then
    log "info" "using Prysm P2P local IP $p2p_local_ip"
    prysm_args+=(--p2p-local-ip "$p2p_local_ip")
  fi

  exec "$prysm_bin" "${prysm_args[@]}"
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
  start_background "prysm" "$LOG_DIR/prysm.log" "$0" run-cl

  cat <<EOF
Started $NETWORK_NAME services.

Ethrex log:     $LOG_DIR/ethrex.log
Prysm log:      $LOG_DIR/prysm.log
Ethrex PID:     $(cat "$RUN_DIR/ethrex.pid")
Prysm PID:      $(cat "$RUN_DIR/prysm.pid")

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
  stop_one "prysm"
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
PRYSM_SRC=$PRYSM_SRC
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
