"""Exercise authenticated input recovery and GC using an isolated Nix store."""

import base64
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


HELPER = Path(os.environ.get(
    "PRIVATE_INPUT_HELPER",
    Path(__file__).resolve().parents[1] / "scripts/prefetch-framework-inputs.sh",
))
CONTENT = b'{"apiUrl":"https://disposable.invalid"}\n'
AUTH = "Basic " + base64.b64encode(b"fixture:disposable").decode()


class PrivateInputs(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        shutil.copy2(HELPER, self.repo / "scripts" / HELPER.name)
        self.requests = []
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests.append(self.headers.get("Authorization") == AUTH)
                if not owner.requests[-1]:
                    self.send_response(401)
                    self.send_header("WWW-Authenticate", 'Basic realm="fixture"')
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Length", str(len(CONTENT)))
                self.end_headers()
                self.wfile.write(CONTENT)

            def log_message(self, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"http://127.0.0.1:{self.server.server_port}/deployment.json"
        netrc = self.root / "fixture.netrc"
        netrc.write_text("machine 127.0.0.1 login fixture password disposable\n")
        netrc.chmod(0o600)
        self.sudo_calls = self.root / "sudo-calls"
        binaries = self.root / "bin"
        binaries.mkdir()
        sudo = binaries / "sudo"
        sudo.write_text(
            f'#!{shutil.which("bash")}\nset -eu\n'
            'echo invoked >> "$PREFETCH_TEST_SUDO_CALLS"\n'
            'exec "$@" --option netrc-file "$PREFETCH_TEST_NETRC"\n'
        )
        sudo.chmod(0o755)
        self.env = dict(os.environ)
        self.env.update(
            NIX_REMOTE=f"local?root={self.root / 'store'}",
            NIX_CONFIG="experimental-features = nix-command flakes\nsubstituters =\nflake-registry =\nbuild-users-group =\nnetrc-file = /dev/null\n",
            XDG_CACHE_HOME=str(self.root / "cache"),
            PATH=f"{binaries}:{os.environ['PATH']}",
            PREFETCH_TEST_NETRC=str(netrc),
            PREFETCH_TEST_SUDO_CALLS=str(self.sudo_calls),
        )
        self.run_command("nix-store", "--init")
        fixture = self.root / "deployment.json"
        fixture.write_bytes(CONTENT)
        self.hash = self.run_command("nix", "hash", "path", str(fixture)).stdout.strip()
        self.write_lock(self.hash)
        self.expected = self.run_command(
            "nix-store", "--print-fixed-path", "--recursive", "sha256", self.hash, "source"
        ).stdout.strip()

    def run_command(self, *args, check=True):
        result = subprocess.run(
            args, env=self.env, cwd=self.repo, capture_output=True, text=True
        )
        if check and result.returncode:
            self.fail(f"{args!r} failed:\n{result.stdout}\n{result.stderr}")
        return result

    def write_lock(self, nar_hash):
        (self.repo / "flake.lock").write_text(json.dumps({
            "root": "root",
            "nodes": {
                "root": {"inputs": {"floppa-deployment": "renamed-node"}},
                "renamed-node": {"locked": {
                    "type": "file", "url": self.url, "narHash": nar_hash
                }},
            },
        }))

    def prefetch(self, check=True):
        return self.run_command("bash", str(self.repo / "scripts" / HELPER.name), check=check)

    def test_cold_fetch_gc_retention_and_recovery(self):
        before = (self.repo / "flake.lock").read_bytes()
        self.prefetch()
        self.assertIn(True, self.requests)
        self.assertEqual(self.sudo_calls.read_text().splitlines(), ["invoked"])
        request_count = len(self.requests)
        self.run_command("nix-store", "--gc")
        self.run_command("nix-store", "--check-validity", self.expected)
        self.prefetch()
        self.assertEqual(len(self.requests), request_count)
        self.assertEqual(self.sudo_calls.read_text().splitlines(), ["invoked"])
        (self.repo / ".work/floppa-deployment").unlink()
        self.run_command("nix-store", "--gc")
        self.assertNotEqual(
            self.run_command("nix-store", "--check-validity", self.expected, check=False).returncode, 0
        )
        self.prefetch()
        self.run_command("nix-store", "--check-validity", self.expected)
        self.assertEqual(self.sudo_calls.read_text().splitlines(), ["invoked", "invoked"])
        self.assertEqual((self.repo / "flake.lock").read_bytes(), before)

    def test_hash_mismatch_aborts_without_creating_root_or_changing_lock(self):
        self.write_lock("sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
        before = (self.repo / "flake.lock").read_bytes()
        result = self.prefetch(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("hash mismatch", result.stderr)
        self.assertFalse((self.repo / ".work/floppa-deployment").is_symlink())
        self.assertEqual((self.repo / "flake.lock").read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
