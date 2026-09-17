"""Isolated launcher checks: no real services, downloads, or chain data."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "glamsterdam-devnet-8.sh"

# One fake executable backs the external commands used by the launcher. All
# state stays outside the runtime directories so clean() can be inspected.
STUB = r'''#!/usr/bin/env python3
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["TEST_ROOT"])
with (root / "calls").open("a") as f:
    f.write(json.dumps([name, args, os.getcwd()]) + "\n")
state_file = root / "units.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
if name == "curl":
    out = pathlib.Path(args[args.index("-o") + 1])
    out.write_text("enr:first\n\nenr:second\n" if out.name == "bootstrap_nodes.txt" else "0\n")
elif name == "systemd-escape":
    print(args[-1])
elif name == "systemd-run":
    unit = next(a.split("=", 1)[1] for a in args if a.startswith("--unit="))
    if os.environ.get("FAIL_START", "!") in unit:
        sys.exit(1)
    state[unit] = "active"
elif name == "systemctl":
    command = args[1]
    unit = next((a for a in args if a.endswith(".service")), "")
    if command == "show":
        if "--property=LoadState" in args and "--value" in args:
            print("loaded" if unit in state else "not-found")
        elif "--property=ActiveState" in args and "--value" in args:
            print(state.get(unit, "inactive"))
        else:
            print("ActiveState=" + state.get(unit, "inactive"))
    elif command == "is-active":
        sys.exit(0 if state.get(unit) == "active" else 1)
    elif command == "stop":
        if os.environ.get("FAIL_STOP", "!") in unit:
            sys.exit(1)
        state.pop(unit, None)
state_file.write_text(json.dumps(state))
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="lighthouse-launcher-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / "runtime with spaces"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("curl", "systemctl", "systemd-run", "systemd-escape", "cargo", "git"):
            self.executable(self.bin / name, STUB)
        # Avoid inherited overrides pointing tests at a real installation.
        self.env = {
            "PATH": f"{self.bin}:/usr/bin:/bin",
            "HOME": str(self.root),
            "WORKDIR": str(self.work),
            "TEST_ROOT": str(self.root),
        }

    def executable(self, path, body=STUB):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        path.chmod(0o755)
        return path

    def run_shell(self, code, *, success=True, **overrides):
        result = subprocess.run(
            ["bash", "-c", 'source "$1"; ' + code, "test", str(SCRIPT)],
            env={**self.env, **overrides}, capture_output=True, text=True, timeout=15,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def calls(self, name):
        path = self.root / "calls"
        return [row for row in map(json.loads, path.read_text().splitlines()) if row[0] == name] if path.exists() else []

    def set_units(self, **states):
        units = {f"glamsterdam-devnet-8-{name}.service": state for name, state in states.items()}
        (self.root / "units.json").write_text(json.dumps(units))

    def fake_clients(self):
        for name in ("ethrex", "lighthouse"):
            self.executable(self.work / "src" / name / "target/release" / name)

    def supervised(self, code="run_all", **kwargs):
        # Before a service exists, its port is closed. Afterwards it is ready.
        return self.run_shell('''
port_is_open() {
  local client=lighthouse
  [[ "$2" == "$AUTHRPC_PORT" ]] && client=ethrex
  [[ "${FAIL_READY:-}" != "$client" ]] || return 1
  systemctl --user is-active --quiet "$(service_unit_name "$client")"
}
''' + code, **kwargs)

    def test_binary_precedence_and_invalid_override(self):
        fallback = self.executable(self.bin / "lighthouse")
        self.assertEqual(self.run_shell("detect_lighthouse_bin").stdout.strip(), str(fallback))
        built = self.executable(self.work / "src/lighthouse/target/release/lighthouse")
        self.assertEqual(self.run_shell("detect_lighthouse_bin").stdout.strip(), str(built))
        explicit = self.executable(self.root / "custom lighthouse")
        self.assertEqual(self.run_shell("detect_lighthouse_bin", LIGHTHOUSE_BIN=str(explicit)).stdout.strip(), str(explicit))
        self.run_shell("detect_lighthouse_bin", success=False, LIGHTHOUSE_BIN=str(self.root / "missing"))
        built.unlink()
        fallback.unlink()
        self.run_shell("detect_lighthouse_bin", success=False)

    def test_setup_and_foreground_arguments(self):
        self.fake_clients()
        self.run_shell("run_cl")
        args = self.calls("lighthouse")[0][1]
        self.assertEqual(args, [
            "beacon_node", "--testnet-dir", str(self.work / "metadata/cl"),
            "--datadir", str(self.work / "data/lighthouse"),
            "--execution-endpoint", "http://127.0.0.1:8551",
            "--execution-jwt", str(self.work / "secrets/jwt.hex"),
            "--checkpoint-sync-url", "https://checkpoint-sync.glamsterdam-devnet-8.ethpandaops.io",
            "--http", "--http-address", "127.0.0.1", "--http-port", "5052",
            "--listen-address", "0.0.0.0", "--port", "9000",
            "--discovery-port", "9000", "--quic-port", "9001",
        ])
        self.assertEqual((self.work / "metadata/cl/bootstrap_nodes.yaml").read_text(), '- "enr:first"\n- "enr:second"\n')
        jwt = (self.work / "secrets/jwt.hex").read_text()
        self.assertRegex(jwt, r"^[0-9a-f]{64}\n$")
        self.run_shell("setup")
        self.assertEqual((self.work / "secrets/jwt.hex").read_text(), jwt)

    def test_clone_and_build(self):
        self.run_shell("clone_all")
        calls = self.calls("git")
        self.assertIn(["clone", "https://github.com/sigp/lighthouse.git", str(self.work / "src/lighthouse")], [c[1] for c in calls])
        self.assertIn(["-C", str(self.work / "src/lighthouse"), "checkout", "glamsterdam-devnet-8"], [c[1] for c in calls])
        self.fake_clients()
        self.run_shell("build_all")
        call = self.calls("cargo")[-1]
        self.assertEqual(call[1], ["build", "--release", "--locked", "--bin", "lighthouse"])
        self.assertEqual(call[2], str(self.work / "src/lighthouse"))

    def test_runtime_overrides(self):
        client = self.executable(self.root / "custom-lighthouse")
        self.run_shell(
            "exec_cl", LIGHTHOUSE_BIN=str(client),
            LIGHTHOUSE_DATADIR=str(self.root / "custom data"),
            LIGHTHOUSE_HTTP_ADDR="127.0.0.2", LIGHTHOUSE_HTTP_PORT="6052",
            LIGHTHOUSE_P2P_LISTEN_ADDR="192.0.2.1", LIGHTHOUSE_P2P_TCP_PORT="19000",
            LIGHTHOUSE_P2P_UDP_PORT="19001", LIGHTHOUSE_P2P_QUIC_PORT="19002",
            AUTHRPC_CONNECT_HOST="192.0.2.2", AUTHRPC_PORT="18551",
            CHECKPOINT_SYNC_URL="https://checkpoint.example", JWT_SECRET_PATH="/custom/jwt",
        )
        args = self.calls("custom-lighthouse")[0][1]
        expected = {
            "--datadir": str(self.root / "custom data"),
            "--http-address": "127.0.0.2", "--http-port": "6052",
            "--listen-address": "192.0.2.1", "--port": "19000",
            "--discovery-port": "19001", "--quic-port": "19002",
            "--execution-endpoint": "http://192.0.2.2:18551",
            "--checkpoint-sync-url": "https://checkpoint.example",
            "--execution-jwt": "/custom/jwt",
        }
        for flag, value in expected.items():
            self.assertEqual(args[args.index(flag) + 1], value)

    def test_supervision_environment_status_and_stop(self):
        self.fake_clients()
        self.supervised("run_all; status_all; stop_all", LIGHTHOUSE_HTTP_PORT="6052", LIGHTHOUSE_P2P_LISTEN_ADDR="192.0.2.1", LIGHTHOUSE_WAIT_SECS="1")
        starts = self.calls("systemd-run")
        self.assertEqual(len(starts), 2)
        args = starts[1][1]
        for expected in (
            "--unit=glamsterdam-devnet-8-lighthouse.service",
            "--setenv=LIGHTHOUSE_HTTP_PORT=6052",
            "--setenv=LIGHTHOUSE_P2P_LISTEN_ADDR=192.0.2.1",
            "--setenv=LIGHTHOUSE_WAIT_SECS=1",
            "--property=Restart=on-failure", "--property=RestartSec=10s",
            "--property=StartLimitBurst=5", "--property=StartLimitIntervalSec=5min",
            "--property=OOMPolicy=continue",
            f"--property=StandardOutput=append:{self.work}/logs/lighthouse.log",
        ):
            self.assertIn(expected, args)
        self.assertEqual(args[-2:], [str(SCRIPT), "service-cl"])
        self.assertFalse(any("PRYSM_" in a for a in args))
        self.assertEqual(json.loads((self.root / "units.json").read_text()), {})

    def test_start_and_readiness_failures_stop_started_services(self):
        self.fake_clients()
        for env in ({"FAIL_START": "lighthouse"}, {"FAIL_READY": "lighthouse"}, {"FAIL_READY": "ethrex"}):
            with self.subTest(env=env):
                self.set_units()
                self.supervised(success=False, AUTHRPC_WAIT_SECS="1", LIGHTHOUSE_WAIT_SECS="1", **env)
                self.assertEqual(json.loads((self.root / "units.json").read_text()), {})

    def test_old_prysm_blocks_all_cl_start_paths(self):
        for command in ("run_cl", "exec_cl", "run_all"):
            for state in ("active", "activating", "deactivating", "reloading"):
                with self.subTest(command=command, state=state):
                    self.set_units(prysm=state)
                    result = self.run_shell(command, success=False)
                    self.assertIn("old Prysm unit", result.stderr)
        self.assertFalse(self.calls("curl"))
        self.assertFalse(self.calls("systemd-run"))

    def test_clean_requires_successful_shutdown_and_preserves_sources(self):
        self.fake_clients()
        self.run_shell("setup")
        old_source = self.work / "src/prysm/keep"
        old_source.parent.mkdir()
        old_source.touch()
        self.set_units(ethrex="active", lighthouse="active", prysm="active")
        self.run_shell("clean", success=False, FAIL_STOP="prysm")
        self.assertTrue((self.work / "secrets/jwt.hex").exists())
        self.run_shell("clean")
        for directory in ("metadata", "secrets", "data", "logs", "run"):
            self.assertFalse((self.work / directory).exists())
        self.assertTrue(old_source.exists())
        self.assertTrue((self.work / "src/lighthouse").exists())

    def test_legacy_prysm_and_unrelated_pid(self):
        self.run_shell("ensure_layout")
        executable = self.root / "beacon-chain"
        shutil.copyfile("/bin/sleep", executable)
        executable.chmod(0o755)
        process = subprocess.Popen([str(executable), "60"])
        self.addCleanup(lambda: process.poll() is None and process.kill())
        pid_file = self.work / "run/prysm.pid"
        pid_file.write_text(str(process.pid))
        self.run_shell("reject_old_prysm", success=False)
        # Reap in the parent while the stop loop waits for /proc to disappear.
        stop = subprocess.Popen(
            ["bash", str(SCRIPT), "stop"], env=self.env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
        )
        process.wait(timeout=10)
        stdout, stderr = stop.communicate(timeout=10)
        self.assertEqual(stop.returncode, 0, stdout + stderr)
        self.assertFalse(pid_file.exists())
        pid_file.write_text(str(os.getpid()))
        self.run_shell("stop_all")
        self.assertFalse(pid_file.exists())
        pid_file.write_text("999999999")
        self.run_shell("reject_old_prysm")
        self.assertFalse(pid_file.exists())

    def test_unrelated_command_text_is_not_a_client(self):
        process = subprocess.Popen(
            ["bash", "-c", "sleep 60 & wait", f"{SCRIPT} run-cl"], start_new_session=True,
        )
        try:
            self.run_shell(f"legacy_process_matches prysm {process.pid}", success=False)
        finally:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)

    def test_wildcard_readiness_and_inactive_status(self):
        for address, expected in (("0.0.0.0", "127.0.0.1"), ("::", "::1"), ("127.0.0.2", "127.0.0.2")):
            self.assertEqual(self.run_shell("lighthouse_connect_host", LIGHTHOUSE_HTTP_ADDR=address).stdout.strip(), expected)
        self.supervised("status_all", success=False)
        self.set_units(ethrex="active", lighthouse="active")
        self.supervised("status_all", success=False, FAIL_READY="lighthouse")


if __name__ == "__main__":
    unittest.main()
