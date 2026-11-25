#!/usr/bin/env python3
"""Unit tests for `helpers/walkie_token.py` — where the loopback's token may be sent.

A scratch home, no network, nothing touches the running relay.
Run: `python3 evals/test_walkie_token.py` (also under `/usr/bin/python3`, 3.9).
"""
import os
import sys
import tempfile
import unittest
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "helpers"))
import walkie_token as wt  # noqa: E402

TOKEN = "ab" * 32


class WalkieTokenTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.old_env = os.environ.get("WALKIE_HOME")
        os.environ["WALKIE_HOME"] = self.home

    def tearDown(self):
        if self.old_env is None:
            os.environ.pop("WALKIE_HOME", None)
        else:
            os.environ["WALKIE_HOME"] = self.old_env
        self.tmp.cleanup()

    def put(self, name, text, mode=0o600):
        p = os.path.join(self.home, name)
        with open(p, "w") as f:
            f.write(text + "\n")
        os.chmod(p, mode)
        return p

    def test_the_token_goes_to_the_pinned_port_only(self):
        self.put("test-token", TOKEN)
        self.put("test-port", "8918")
        self.assertEqual(wt.pinned(), (TOKEN, 8918))
        self.assertEqual(wt.targets(), [(8918, {wt.HEADER: TOKEN})])
        self.assertEqual(wt.headers(8918), {wt.HEADER: TOKEN})
        self.assertEqual(wt.headers(8917), {})
        self.assertEqual(wt.headers(8919, {"a": "b"}), {"a": "b"})
        self.assertEqual(wt.curl_config(8917), "")
        self.assertIn(TOKEN, wt.curl_config(8918))

    def test_starting_sends_nothing_anywhere(self):
        self.put("test-token", TOKEN)
        self.put("test-port", "starting")
        self.assertEqual(wt.pinned(), (TOKEN, None))
        self.assertEqual(wt.targets(), [])
        for p in wt.PORTS:
            self.assertEqual(wt.headers(p), {})

    def test_a_port_outside_the_three_is_not_believed(self):
        self.put("test-token", TOKEN)
        self.put("test-port", "22")
        self.assertEqual(wt.targets(), [])

    def test_an_app_without_a_port_file_gets_8917_alone(self):
        self.put("test-token", TOKEN)
        self.assertEqual(wt.targets(), [(8917, {wt.HEADER: TOKEN})])
        self.assertEqual(wt.headers(8918), {})

    def test_an_app_from_before_the_gate_is_asked_on_all_three_tokenless(self):
        self.assertEqual(wt.targets(), [(p, {}) for p in wt.PORTS])

    def test_files_that_are_not_his_are_not_read(self):
        self.put("test-token", TOKEN, mode=0o644)
        self.put("test-port", "8917")
        self.assertEqual(wt.token(), "")
        os.chmod(os.path.join(self.home, "test-token"), 0o600)
        self.assertEqual(wt.token(), TOKEN)
        # A group-readable port file is not followed: the token goes nowhere.
        os.chmod(os.path.join(self.home, "test-port"), 0o664)
        self.assertEqual(wt.targets(), [])
        # A symlink in place of the token is not followed.
        real = self.put("elsewhere", "cd" * 32)
        os.remove(os.path.join(self.home, "test-token"))
        os.symlink(real, os.path.join(self.home, "test-token"))
        self.assertEqual(wt.token(), "")

    def test_the_installed_handler_adds_it_for_the_pinned_port_only(self):
        self.put("test-token", TOKEN)
        self.put("test-port", "8917")
        h = wt._Handler()
        for url, want in [("http://127.0.0.1:8917/test/state", TOKEN),
                          ("http://127.0.0.1:8918/test/state", None),
                          ("http://localhost:8917/test/state", None),
                          ("https://127.0.0.1:8917/test/state", None),
                          ("http://127.0.0.1:8917@evil.com/x", None),
                          ("http://evil.com:8917/x", None)]:
            req = h.http_request(urllib.request.Request(url))
            self.assertEqual(req.unredirected_hdrs.get(wt.HEADER.capitalize()), want, url)


if __name__ == "__main__":
    unittest.main()
