# SPDX-License-Identifier: Apache-2.0
"""Only a fake claude executable is used, including the real subprocess paths."""

import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import support as S
sys.path.insert(0, str(S.HARNESS / "shim"))
sys.path.insert(0, str(S.HARNESS / "arm2"))
import record
import driver

FAKE = '''#!PYTHON
# SPDX-License-Identifier: Apache-2.0
import base64, json, os, pathlib, sys, time
root = pathlib.Path(__file__).resolve().parent
config = json.loads((root / "fake.json").read_text())
if sys.argv[1:] == ["--version"]:
    sys.stdout.write(config.get("version", "2.1.322 (Claude Code)\\n"))
    raise SystemExit(0)
request = sys.stdin.buffer.read()
counter = root / "counter"
index = int(counter.read_text()) if counter.exists() else 0
counter.write_text(str(index+1))
(root / ("request-%d.bin" % index)).write_bytes(request)
(root / ("observation-%d.json" % index)).write_text(json.dumps({
    "env": dict(os.environ), "argv": sys.argv[1:], "cwd": os.getcwd(), "files": os.listdir(".")}))
if config.get("sleep"):
    time.sleep(config["sleep"])
if "replies" in config:
    output = (json.dumps({"type":"result", "is_error":False, "result":config["replies"][index]})+"\\n").encode()
else:
    output = request + base64.b64decode(config.get("suffix", ""))
sys.stdout.buffer.write(output)
sys.stdout.buffer.flush()
sys.stderr.buffer.write(base64.b64decode(config.get("stderr", "")))
raise SystemExit(config.get("exit", 0))
'''


class FakeCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fake_dir = self.root / "bin"
        self.fake_dir.mkdir()
        self.fake = self.fake_dir / "claude"
        self.fake.write_text(FAKE.replace("PYTHON", sys.executable, 1))
        self.fake.chmod(0o700)
        self.configure()

    def configure(self, **values):
        (self.fake_dir / "fake.json").write_text(json.dumps(values))

    def invoke(self, data=b"synthetic", *arguments, timeout=900, env=None):
        inherited = dict(os.environ, PATH=str(self.fake_dir) + ":/usr/bin:/bin")
        inherited.update(env or {})
        return subprocess.run([sys.executable, str(S.HARNESS / "shim" / "record.py"),
                               "--record-dir", str(self.root / "receipts"), "--timeout", str(timeout),
                               "--", *arguments], input=data, capture_output=True, env=inherited, timeout=20)

    def receipt(self):
        folder = next((self.root / "receipts").iterdir())
        return folder, json.loads((folder / "receipt.json").read_bytes())


class ShimTest(FakeCase):
    def test_binary_equality_and_receipt_hashes(self):
        data = bytes(range(256)) * 8192 + b"\x00\xff\r\n"
        error = b"\xff\x00warning\r\n"
        self.configure(suffix=base64.b64encode(b"\xfeanswer").decode(), stderr=base64.b64encode(error).decode(), exit=7)
        result = self.invoke(data, "-p", "synthetic \u2603")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, data + b"\xfeanswer")
        self.assertEqual(result.stderr, error)
        folder, receipt = self.receipt()
        self.assertTrue(receipt["passThrough"])
        self.assertEqual(receipt["argv"], ["-p", "synthetic \u2603"])
        self.assertEqual(base64.b64decode(receipt["argvBytesBase64"][1]), "synthetic \u2603".encode())
        for name, value in (("stdin", data), ("stdout", result.stdout), ("stderr", error)):
            self.assertEqual((folder / (name + ".bin")).read_bytes(), value)
            self.assertEqual(receipt["streams"][name]["sha256"], hashlib.sha256(value).hexdigest())
            self.assertTrue(receipt["streams"][name]["equal"])
        self.assertEqual((folder / "receipt.sha256").read_text().strip(),
                         hashlib.sha256((folder / "receipt.json").read_bytes()).hexdigest())

    def test_environment_is_allowlisted(self):
        self.invoke(env={"ANTHROPIC_API_KEY": "synthetic-key", "ANTHROPIC_BASE_URL": "synthetic-url",
                         "CLAUDECODE": "1", "UNRELATED_SECRET": "synthetic", "HOME": str(self.root),
                         "CLAUDE_CODE_OAUTH_TOKEN": "synthetic-login", "__CF_USER_TEXT_ENCODING": "synthetic-parent-value"})
        observed = json.loads((self.fake_dir / "observation-0.json").read_bytes())["env"]
        runtime_added = {"__CF_USER_TEXT_ENCODING"} if sys.platform == "darwin" else set()
        self.assertLessEqual(set(observed) - runtime_added, record.ALLOWLIST)
        self.assertNotEqual(observed.get("__CF_USER_TEXT_ENCODING"), "synthetic-parent-value")
        self.assertEqual(record.environment({"__CF_USER_TEXT_ENCODING": "synthetic", "ANTHROPIC_API_KEY": "synthetic"}), {})
        self.assertFalse(any(key.startswith("ANTHROPIC_") for key in observed))
        self.assertEqual(observed["CLAUDE_CODE_OAUTH_TOKEN"], "synthetic-login")
        self.assertNotIn("UNRELATED_SECRET", observed)
        self.assertNotIn("synthetic-login", (self.receipt()[0] / "receipt.json").read_text())

    def test_wrong_version_refuses_before_request(self):
        for version in ("2.1.321 (Claude Code)\n", "2.1.3220\n", "2.1.322 forged\n"):
            with self.subTest(version=version):
                self.configure(version=version)
                result = self.invoke()
                self.assertEqual(result.returncode, 125)
                self.assertEqual(result.stdout, b"")
                self.assertFalse((self.fake_dir / "counter").exists())

    def test_timeout_is_recorded(self):
        self.configure(sleep=10)
        result = self.invoke(timeout=0.4)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(self.receipt()[1]["status"], "timeout")

    def test_installed_wrapper_survives_marty_environment_scrub(self):
        wrapper = self.root / "wrapper"
        subprocess.run([sys.executable, str(S.HARNESS / "shim" / "record.py"), "--executable", str(self.fake),
                        "--record-dir", str(self.root / "receipts"), "--install", str(wrapper)], check=True)
        self.assertFalse((self.fake_dir / "counter").exists())
        env = record.environment(dict(os.environ, PATH=str(wrapper) + ":/usr/bin:/bin"))
        result = subprocess.run([str(wrapper / "claude"), "-p"], input=b"arm1 bytes\x00", env=env, capture_output=True)
        self.assertEqual(result.stdout, b"arm1 bytes\x00")
        self.assertTrue(self.receipt()[1]["passThrough"])

    def test_relative_executable_is_refused(self):
        with self.assertRaises(ValueError):
            record.resolve("./claude")


class DriverTest(FakeCase):
    HTML = "```html\n<!doctype html><head></head><body>Synthetic blocks</body>\n```"

    def flow(self, replies, render_error=None, blank=False, clock=None):
        self.configure(replies=replies)
        self.output = self.root / "run"
        lock = json.loads((S.BENCH / "LOCK.json").read_bytes())
        self.system = driver.locked_prompt(lock, "systemPrompt")
        repair = driver.locked_prompt(lock, "repairPrompt")
        self.author = driver.Author(str(self.fake), self.output / "calls", self.system, "claude-opus-5-5")
        self.render_calls = []

        def renderer(source, output, timeout):
            self.render_calls.append((source, timeout))
            report = driver.error_report(render_error or "synthetic placeholder", output)
            report.update(complete=not render_error, harnessErrors=[render_error] if render_error else [], allBlank=blank)
            (output / "report.json").write_text(json.dumps(report))
            return report

        return driver.run("  Synthetic blocks?\r\n\u2603\n", self.output, self.author, renderer, repair,
                          **({"clock": clock} if clock else {}))

    def test_accept_first_authored_try(self):
        result = self.flow([self.HTML, "ACCEPT"])
        self.assertEqual((result["calls"], len(result["tries"]), result["status"]), (2, 1, "rendered"))
        self.assertTrue(result["accepted"])
        request = json.loads((self.fake_dir / "request-0.bin").read_bytes())
        self.assertEqual(request["message"]["content"], [{"type": "text", "text": "  Synthetic blocks?\r\n\u2603\n"}])
        repair = json.loads((self.fake_dir / "request-1.bin").read_bytes())["message"]["content"]
        self.assertEqual([block["type"] for block in repair], ["text"] + ["image"] * 5)
        self.assertIn("You have 3 repair(s) left.", repair[0]["text"])
        observations = [json.loads(path.read_bytes()) for path in self.fake_dir.glob("observation-*.json")]
        self.assertEqual(len({item["cwd"] for item in observations}), 2)
        for item in observations:
            self.assertEqual(item["files"], [])
            args = item["argv"]
            for flag in ("--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence"):
                self.assertIn(flag, args)
            self.assertEqual(args[args.index("--tools") + 1], "")
            self.assertEqual(args[args.index("--setting-sources") + 1], "")
            self.assertEqual(args[args.index("--model") + 1], "claude-opus-5-5")
        for receipt in (self.output / "calls").glob("*/system-prompt.bin"):
            self.assertEqual(receipt.read_bytes(), self.system.encode())

    def test_accept_on_fourth_and_last_call(self):
        result = self.flow([self.HTML] * 3 + ["ACCEPT"])
        self.assertEqual((result["calls"], len(result["tries"]), result["accepted"]), (4, 3, True))
        self.assertEqual(result["status"], "rendered")

    def test_fourth_html_is_final_without_fifth_call(self):
        result = self.flow([self.HTML] * 4)
        self.assertEqual((result["calls"], len(result["tries"]), result["accepted"]), (4, 4, False))
        self.assertEqual(result["status"], "rendered")
        self.assertEqual(len(self.render_calls), 4)
        self.assertTrue(all(0 < timeout <= 300 for _, timeout in self.render_calls))

    def test_malformed_html_gets_exact_error_and_five_placeholders(self):
        result = self.flow(["not HTML", self.HTML, "ACCEPT"])
        self.assertEqual(result["status"], "rendered")
        repair = json.loads((self.fake_dir / "request-1.bin").read_bytes())["message"]["content"]
        self.assertIn("No ```html code block found.", repair[0]["text"])
        self.assertEqual(len(repair), 6)
        self.assertEqual(len(self.render_calls), 1)

    def test_all_malformed_exhausts(self):
        result = self.flow(["bad"] * 4)
        self.assertEqual((result["calls"], result["status"]), (4, "failed"))
        self.assertEqual(self.render_calls, [])

    def test_accept_cannot_override_render_failure(self):
        result = self.flow([self.HTML, "ACCEPT"], render_error="synthetic frame failure")
        self.assertEqual(result["status"], "failed")

    def test_all_blank_fails(self):
        result = self.flow([self.HTML, "ACCEPT"], blank=True)
        self.assertEqual(result["status"], "failed")

    def test_deadline_stops_calls(self):
        values = iter([0, 0, 3601, 3601])
        result = self.flow([self.HTML], clock=lambda: next(values))
        self.assertEqual(result["calls"], 1)
        self.assertEqual(result["status"], "failed")
        self.assertIn("60-minute", result["error"])

    def test_malformed_stream_is_failure(self):
        for value in (b"not JSON", b'{"type":"result","is_error":true,"result":"x"}', b'{}'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                driver.reply_text(value)

    def test_hash_mismatch_refuses_prompt(self):
        lock = json.loads((S.BENCH / "LOCK.json").read_bytes())
        lock["arm2"]["systemPrompt"]["sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            driver.locked_prompt(lock, "systemPrompt")

    def test_repair_console_limit_and_exact_template(self):
        output = self.root / "render"
        report = driver.error_report("synthetic error", output)
        report["console"] = ["line-%d" % index for index in range(60)]
        lock = json.loads((S.BENCH / "LOCK.json").read_bytes())
        template = driver.locked_prompt(lock, "repairPrompt")
        blocks = driver.repair_blocks(template, "Q {html}", "<body>{left}</body>", 3, report, output)
        self.assertEqual(len(blocks), 6)
        self.assertIn("Question: Q {html}\n", blocks[0]["text"])
        self.assertIn("<body>{left}</body>", blocks[0]["text"])
        self.assertIn("line-49", blocks[0]["text"])
        self.assertNotIn("line-50", blocks[0]["text"])
        self.assertIn("You have 1 repair(s) left.", blocks[0]["text"])

    def test_existing_run_directory_is_not_overwritten(self):
        destination = self.root / "existing"
        destination.mkdir()
        marker = destination / "original"
        marker.write_bytes(b"keep")
        with self.assertRaises(FileExistsError):
            driver.run("synthetic", destination, None, None, "")
        self.assertEqual(marker.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main()
