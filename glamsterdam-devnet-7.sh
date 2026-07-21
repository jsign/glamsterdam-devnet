#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
LAUNCH_DIR="$PWD"
WORKDIR="${WORKDIR:-$SCRIPT_DIR}"

NETWORK_NAME="${NETWORK_NAME:-glamsterdam-devnet-7}"
CONFIG_BASE_URL="${CONFIG_BASE_URL:-https://config.glamsterdam-devnet-7.ethpandaops.io}"
CHECKPOINT_SYNC_URL="${CHECKPOINT_SYNC_URL:-https://checkpoint-sync.glamsterdam-devnet-7.ethpandaops.io}"

METADATA_DIR="${METADATA_DIR:-$WORKDIR/metadata}"
SECRETS_DIR="${SECRETS_DIR:-$WORKDIR/secrets}"
DATA_DIR="${DATA_DIR:-$WORKDIR/data}"
LOG_DIR="${LOG_DIR:-$WORKDIR/logs}"
RUN_DIR="${RUN_DIR:-$WORKDIR/run}"
SRC_DIR="${SRC_DIR:-$WORKDIR/src}"

JWT_SECRET_PATH="${JWT_SECRET_PATH:-$SECRETS_DIR/jwt.hex}"

ETHREX_GIT_URL="${ETHREX_GIT_URL:-https://github.com/lambdaclass/ethrex.git}"
PRYSM_GIT_URL="${PRYSM_GIT_URL:-https://github.com/OffchainLabs/prysm.git}"
ETHREX_REF="${ETHREX_REF:-glamsterdam-devnet-7}"
PRYSM_REF="${PRYSM_REF:-glamsterdam-devnet-7}"

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
PRYSM_WAIT_SECS="${PRYSM_WAIT_SECS:-60}"

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
  ./$script_name status
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
  ETHREX_REF              Git ref to checkout in ETHREX_SRC (defaults to glamsterdam-devnet-7)
  PRYSM_REF               Git ref to checkout in PRYSM_SRC (defaults to glamsterdam-devnet-7)
  ETHREX_BIN              Explicit ethrex binary path
  PRYSM_BIN               Explicit Prysm beacon-chain binary path
  ETHREX_HTTP_API         ethrex HTTP API modules (defaults to eth,net,web3,debug)
  ETHREX_PRECOMPUTE_WITNESSES
                           Enable ethrex witness precomputation (defaults to true)
  PRYSM_P2P_LOCAL_IP       Local IP for Prysm P2P listeners (defaults to auto)
  CHECKPOINT_SYNC_URL     Beacon checkpoint sync endpoint
  AUTHRPC_WAIT_SECS       Ethrex readiness timeout for run-all (defaults to 60)
  PRYSM_WAIT_SECS         Prysm readiness timeout for run-all (defaults to 60)
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
  while IFS= read -r line || [[ -n "$line" ]]; do
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

port_is_open() {
  local host="$1"
  local port="$2"

  (exec 3<>"/dev/tcp/$host/$port") >/dev/null 2>&1
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

exec_el() {
  local ethrex_bin bootnodes

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

run_el() {
  setup
  exec_el
}

exec_cl() {
  local prysm_bin deposit_contract_block p2p_local_ip
  local -a prysm_args

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

run_cl() {
  setup
  exec_cl
}

supervisor_available() {
  command -v systemctl >/dev/null 2>&1 \
    && command -v systemd-run >/dev/null 2>&1 \
    && command -v systemd-escape >/dev/null 2>&1 \
    && systemctl --user show-environment >/dev/null 2>&1
}

require_supervisor() {
  require_cmd systemctl
  require_cmd systemd-run
  require_cmd systemd-escape
  systemctl --user show-environment >/dev/null 2>&1 \
    || die "could not connect to the systemd user manager"
}

service_unit_name() {
  local name="$1"

  systemd-escape --mangle "${NETWORK_NAME}-${name}.service"
}

unit_load_state() {
  local unit="$1"
  local state

  state="$(systemctl --user show "$unit" --property=LoadState --value 2>/dev/null || true)"
  printf '%s\n' "${state:-not-found}"
}

unit_active_state() {
  local unit="$1"
  local state

  state="$(systemctl --user show "$unit" --property=ActiveState --value 2>/dev/null || true)"
  printf '%s\n' "${state:-not-found}"
}

prepare_unit_start() {
  local unit="$1"
  local state
  local attempt

  state="$(unit_active_state "$unit")"
  case "$state" in
    active|activating|deactivating|reloading)
      die "systemd unit $unit is already $state; run '$SCRIPT_PATH stop' first"
      ;;
  esac

  if [[ "$(unit_load_state "$unit")" == "not-found" ]]; then
    return
  fi

  systemctl --user stop "$unit" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  for attempt in {1..20}; do
    [[ "$(unit_load_state "$unit")" == "not-found" ]] && return
    sleep 0.1
  done

  die "inactive transient unit $unit is still loaded; try 'systemctl --user reset-failed $unit'"
}

legacy_process_matches() {
  local name="$1"
  local pid="$2"
  local cmdline
  local executable
  local executable_name

  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ -r "/proc/$pid/cmdline" ]] || return 1
  cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline")"
  executable="$(readlink -f -- "/proc/$pid/exe" 2>/dev/null || true)"
  executable_name="$(basename -- "$executable")"

  case "$name" in
    ethrex)
      [[ "$executable_name" == "ethrex" \
        || (-n "$ETHREX_BIN" && "$executable" -ef "$ETHREX_BIN") \
        || "$cmdline" == *"$SCRIPT_PATH run-el"* ]]
      ;;
    prysm)
      [[ "$executable_name" == "beacon-chain" \
        || "$executable_name" == "prysm-beacon-chain" \
        || (-n "$PRYSM_BIN" && "$executable" -ef "$PRYSM_BIN") \
        || "$cmdline" == *"$SCRIPT_PATH run-cl"* ]]
      ;;
    *)
      return 1
      ;;
  esac
}

reject_legacy_process() {
  local name="$1"
  local pid_file="$RUN_DIR/$name.pid"
  local pid

  [[ -f "$pid_file" ]] || return 0
  pid="$(tr -d '[:space:]' < "$pid_file")"

  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" >/dev/null 2>&1; then
    if legacy_process_matches "$name" "$pid"; then
      die "legacy $name process $pid is still running; run '$SCRIPT_PATH stop' first"
    fi
    log "warn" "removing stale $name pid file; pid $pid belongs to another process"
  else
    log "info" "removing stale $name pid file"
  fi
  rm -f "$pid_file"
}

stop_legacy_one() {
  local name="$1"
  local pid_file="$RUN_DIR/$name.pid"
  local pid
  local waited=0

  if [[ ! -f "$pid_file" ]]; then
    return
  fi

  pid="$(tr -d '[:space:]' < "$pid_file")"
  if ! [[ "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
    log "info" "removing stale $name pid file"
    rm -f "$pid_file"
    return
  fi

  if ! legacy_process_matches "$name" "$pid"; then
    log "warn" "not signaling pid $pid because it does not look like $name; removing stale pid file"
    rm -f "$pid_file"
    return
  fi

  log "info" "stopping legacy $name pid $pid"
  kill "$pid"
  while kill -0 "$pid" >/dev/null 2>&1; do
    if (( waited >= 30 )); then
      log "error" "timed out waiting for legacy $name pid $pid to stop"
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  rm -f "$pid_file"
}

absolute_log_path() {
  local path="$1"
  local parent

  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
    return
  fi

  parent="$(cd -- "$(dirname -- "$path")" && pwd)"
  printf '%s/%s\n' "$parent" "$(basename -- "$path")"
}

append_service_log_marker() {
  local name="$1"
  local unit="$2"
  local log_file="$3"

  printf '\n[%s] [supervisor] starting %s as %s\n' \
    "$(date --iso-8601=seconds)" "$name" "$unit" >> "$log_file"
}

start_supervised_service() {
  local name="$1"
  local subcommand="$2"
  local log_file="$3"
  local unit="$4"
  local env_name
  local -a systemd_args
  local -a env_names=(
    WORKDIR NETWORK_NAME CONFIG_BASE_URL CHECKPOINT_SYNC_URL
    METADATA_DIR SECRETS_DIR DATA_DIR LOG_DIR RUN_DIR SRC_DIR JWT_SECRET_PATH
    ETHREX_GIT_URL PRYSM_GIT_URL ETHREX_REF PRYSM_REF ETHREX_SRC PRYSM_SRC
    ETHREX_BIN PRYSM_BIN HTTP_ADDR HTTP_PORT AUTHRPC_ADDR AUTHRPC_PORT
    ETHREX_P2P_PORT ETHREX_DISCOVERY_PORT ETHREX_SYNCMODE ETHREX_HTTP_API
    ETHREX_PRECOMPUTE_WITNESSES PRYSM_HTTP_ADDR PRYSM_HTTP_PORT
    PRYSM_P2P_LOCAL_IP PRYSM_P2P_TCP_PORT PRYSM_P2P_UDP_PORT
    PRYSM_P2P_QUIC_PORT PRYSM_DATADIR ETHREX_DATADIR AUTHRPC_CONNECT_HOST
    AUTHRPC_WAIT_SECS PRYSM_WAIT_SECS
  )

  log_file="$(absolute_log_path "$log_file")"
  append_service_log_marker "$name" "$unit" "$log_file"

  systemd_args=(
    systemd-run
    --user
    --quiet
    --collect
    --unit="$unit"
    --description="$NETWORK_NAME $name client"
    --service-type=exec
    --working-directory="$LAUNCH_DIR"
    --property=Restart=on-failure
    --property=RestartSec=10s
    --property=StartLimitBurst=5
    --property=StartLimitIntervalSec=5min
    --property=OOMPolicy=continue
    --property="StandardOutput=append:$log_file"
    --property="StandardError=append:$log_file"
  )
  for env_name in "${env_names[@]}"; do
    systemd_args+=("--setenv=${env_name}=${!env_name}")
  done
  systemd_args+=(-- "$SCRIPT_PATH" "$subcommand")

  log "info" "starting $name as systemd unit $unit"
  "${systemd_args[@]}"
}

wait_for_service_port() {
  local unit="$1"
  local host="$2"
  local port="$3"
  local timeout_secs="$4"
  local waited=0
  local state

  while (( waited < timeout_secs )); do
    if systemctl --user is-active --quiet "$unit" && port_is_open "$host" "$port"; then
      return
    fi

    state="$(unit_active_state "$unit")"
    if [[ "$state" == "failed" || "$state" == "inactive" || "$state" == "not-found" ]]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

stop_systemd_one() {
  local name="$1"
  local unit="$2"

  if [[ "$(unit_load_state "$unit")" == "not-found" ]]; then
    log "info" "no systemd unit for $name"
    return
  fi

  log "info" "stopping $name systemd unit $unit"
  if ! systemctl --user stop "$unit"; then
    log "error" "failed to stop $name systemd unit $unit"
    return 1
  fi
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
}

stop_all() {
  local failed=0
  local ethrex_unit
  local prysm_unit

  if supervisor_available; then
    ethrex_unit="$(service_unit_name ethrex)"
    prysm_unit="$(service_unit_name prysm)"
    stop_systemd_one "prysm" "$prysm_unit" || failed=1
    stop_systemd_one "ethrex" "$ethrex_unit" || failed=1
  fi

  stop_legacy_one "prysm" || failed=1
  stop_legacy_one "ethrex" || failed=1
  return "$failed"
}

prysm_connect_host() {
  case "$PRYSM_HTTP_ADDR" in
    0.0.0.0)
      printf '127.0.0.1\n'
      ;;
    ::|\[::\])
      printf '::1\n'
      ;;
    *)
      printf '%s\n' "$PRYSM_HTTP_ADDR"
      ;;
  esac
}

print_failed_unit() {
  local unit="$1"

  systemctl --user status "$unit" --no-pager >&2 || true
}

run_all() {
  local ethrex_unit
  local prysm_unit
  local prysm_host

  ensure_layout
  require_supervisor
  ethrex_unit="$(service_unit_name ethrex)"
  prysm_unit="$(service_unit_name prysm)"
  prysm_host="$(prysm_connect_host)"

  prepare_unit_start "$ethrex_unit"
  prepare_unit_start "$prysm_unit"
  reject_legacy_process "ethrex"
  reject_legacy_process "prysm"
  port_is_open "$AUTHRPC_CONNECT_HOST" "$AUTHRPC_PORT" \
    && die "auth RPC port $AUTHRPC_CONNECT_HOST:$AUTHRPC_PORT is already in use by an unmanaged process"
  port_is_open "$prysm_host" "$PRYSM_HTTP_PORT" \
    && die "Prysm HTTP port $prysm_host:$PRYSM_HTTP_PORT is already in use by an unmanaged process"

  setup
  detect_ethrex_bin >/dev/null
  detect_prysm_bin >/dev/null

  if ! start_supervised_service "ethrex" "service-el" "$LOG_DIR/ethrex.log" "$ethrex_unit"; then
    die "systemd failed to create $ethrex_unit"
  fi
  if ! wait_for_service_port "$ethrex_unit" "$AUTHRPC_CONNECT_HOST" "$AUTHRPC_PORT" "$AUTHRPC_WAIT_SECS"; then
    log "error" "ethrex did not become ready at $AUTHRPC_CONNECT_HOST:$AUTHRPC_PORT"
    print_failed_unit "$ethrex_unit"
    stop_systemd_one "ethrex" "$ethrex_unit" || true
    die "failed to start $NETWORK_NAME ethrex service"
  fi

  if ! start_supervised_service "prysm" "service-cl" "$LOG_DIR/prysm.log" "$prysm_unit"; then
    stop_systemd_one "ethrex" "$ethrex_unit" || true
    die "systemd failed to create $prysm_unit"
  fi
  if ! wait_for_service_port "$prysm_unit" "$prysm_host" "$PRYSM_HTTP_PORT" "$PRYSM_WAIT_SECS"; then
    log "error" "prysm did not become ready at $prysm_host:$PRYSM_HTTP_PORT"
    print_failed_unit "$prysm_unit"
    stop_systemd_one "prysm" "$prysm_unit" || true
    stop_systemd_one "ethrex" "$ethrex_unit" || true
    die "failed to start $NETWORK_NAME prysm service"
  fi

  cat <<EOF
Started $NETWORK_NAME as supervised systemd user services.

Ethrex unit:    $ethrex_unit
Prysm unit:     $prysm_unit
Ethrex log:     $LOG_DIR/ethrex.log
Prysm log:      $LOG_DIR/prysm.log

To inspect both:
  $SCRIPT_PATH status

To stop both:
  $SCRIPT_PATH stop
EOF
}

status_one() {
  local name="$1"
  local unit="$2"
  local host="$3"
  local port="$4"
  local healthy=0

  printf '%s (%s)\n' "$name" "$unit"
  if [[ "$(unit_load_state "$unit")" == "not-found" ]]; then
    printf 'LoadState=not-found\nReadyPort=%s:%s closed\n' "$host" "$port"
    return 1
  fi

  systemctl --user show "$unit" --no-pager \
    --property=LoadState \
    --property=ActiveState \
    --property=SubState \
    --property=MainPID \
    --property=NRestarts \
    --property=Result \
    --property=MemoryCurrent

  if systemctl --user is-active --quiet "$unit" && port_is_open "$host" "$port"; then
    printf 'ReadyPort=%s:%s open\n' "$host" "$port"
  else
    printf 'ReadyPort=%s:%s closed\n' "$host" "$port"
    healthy=1
  fi
  return "$healthy"
}

status_all() {
  local failed=0
  local ethrex_unit
  local prysm_unit
  local prysm_host

  require_supervisor
  ethrex_unit="$(service_unit_name ethrex)"
  prysm_unit="$(service_unit_name prysm)"
  prysm_host="$(prysm_connect_host)"

  status_one "ethrex" "$ethrex_unit" "$AUTHRPC_CONNECT_HOST" "$AUTHRPC_PORT" || failed=1
  printf '\n'
  status_one "prysm" "$prysm_unit" "$prysm_host" "$PRYSM_HTTP_PORT" || failed=1
  return "$failed"
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
    service-el)
      expect_no_args "$cmd" "$@"
      exec_el
      ;;
    service-cl)
      expect_no_args "$cmd" "$@"
      exec_cl
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
    status)
      expect_no_args "$cmd" "$@"
      status_all
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
