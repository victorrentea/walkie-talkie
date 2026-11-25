#!/usr/bin/env python3
"""`walkie-dict sync` must not read a missing side as "he deleted every word".

    python3 evals/test_walkie_dict.py

Found by the Fable review (2026-11-25): with `vocabulary.txt` gone and the base still
there, every synced Wispr row was marked deleted — and Wispr's own sync pushes that to
the cloud and his other devices. Temp files only; the real dictionaries are not touched.
"""

import importlib.machinery
import importlib.util
import json
import os
import sqlite3
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader(
    "walkie_dict", os.path.join(HERE, "..", "helpers", "walkie-dict"))
_spec = importlib.util.spec_from_loader("walkie_dict", _loader)
wd = importlib.util.module_from_spec(_spec)
_loader.exec_module(wd)


class Sync(unittest.TestCase):

    def setUp(self):
        d = tempfile.mkdtemp()
        self.saved = (wd.VOCAB, wd.BASE, wd.WISPR_DB)
        wd.VOCAB = os.path.join(d, "vocabulary.txt")
        wd.BASE = os.path.join(d, "vocabulary-sync.json")
        wd.WISPR_DB = os.path.join(d, "flow.sqlite")
        db = sqlite3.connect(wd.WISPR_DB)
        db.execute("CREATE TABLE Dictionary (id TEXT, phrase TEXT, replacement TEXT,"
                   " teamDictionaryId TEXT, lastUsed TEXT, frequencyUsed INT,"
                   " remoteFrequencyUsed INT, manualEntry INT, createdAt TEXT,"
                   " modifiedAt TEXT, isDeleted INT, source TEXT, isSnippet INT, isStarred INT)")
        self.words = ["w%d" % i for i in range(10)]
        for w in self.words:
            db.execute("INSERT INTO Dictionary VALUES (?, ?, NULL, ?, NULL, 0, 0, 1, '', '',"
                       " 0, 'manual', 0, 0)", (w, w, wd.PERSONAL))
        db.commit()
        db.close()
        with open(wd.BASE, "w") as fh:
            json.dump({w: None for w in self.words}, fh)

    def tearDown(self):
        wd.VOCAB, wd.BASE, wd.WISPR_DB = self.saved

    def deleted(self):
        db = sqlite3.connect(wd.WISPR_DB)
        n = db.execute("SELECT COUNT(*) FROM Dictionary WHERE isDeleted = 1").fetchone()[0]
        db.close()
        return n

    def test_a_missing_file_is_refused_not_synced(self):
        with self.assertRaises(SystemExit):
            wd.sync(quiet=True)
        self.assertEqual(self.deleted(), 0)

    def test_an_emptied_file_is_refused_too(self):
        open(wd.VOCAB, "w").close()
        with self.assertRaises(SystemExit):
            wd.sync(quiet=True)
        self.assertEqual(self.deleted(), 0)

    def test_one_deleted_word_still_syncs(self):
        with open(wd.VOCAB, "w") as fh:
            fh.write("\n".join(self.words[1:]) + "\n")
        wd.sync(quiet=True)
        self.assertEqual(self.deleted(), 1)

    def test_force_applies_it(self):
        open(wd.VOCAB, "w").close()
        wd.sync(quiet=True, force=True)
        self.assertEqual(self.deleted(), 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
