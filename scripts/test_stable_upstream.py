"""Offline tests: all Git mutations are confined to temporary fixture repositories."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import stable_upstream as updater

GRADLE = '''signingConfigs { testkey { storeFile file("fixed.p12") } }
signingConfig signingConfigs.testkey
applicationId "one"
resValue "string", "app_name", "Tyrantlator"
applicationId "two"
applicationId "com.tencent.ig"
'''


class PolicyTests(unittest.TestCase):
    def test_stable_tag(self):
        self.assertEqual(updater.stable_tag(dict(tag_name="3.1.6", draft=False, prerelease=False)), "3.1.6")

    def test_reject_other_release_inputs(self):
        for tag, draft, pre in [("3.1.6-pre1", False, True), ("../main", False, False),
                                ("3.1.6;bad", False, False), ("3.1.6", True, False),
                                ("3.1.6", False, None)]:
            with self.subTest(tag=tag, draft=draft, pre=pre), self.assertRaises(ValueError):
                updater.stable_tag(dict(tag_name=tag, draft=draft, prerelease=pre))

    def test_version_change_keeps_identity(self):
        self.assertEqual(updater.identity(GRADLE), updater.identity(GRADLE + 'versionCode 99\n'))

    def test_identity_requires_all_flavors(self):
        with self.assertRaises(ValueError):
            updater.identity(GRADLE.replace('applicationId "one"', ''))

    def test_signing_change_detected(self):
        self.assertNotEqual(updater.identity(GRADLE), updater.identity(GRADLE.replace("fixed.p12", "other.p12")))


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "origin"
        self.clone = self.root / "checkout"
        self.source.mkdir()
        self.old = Path.cwd()
        self.addCleanup(os.chdir, self.old)
        os.chdir(self.source)
        self.env = patch.dict(os.environ, {
            "GIT_AUTHOR_NAME": "Updater fixture", "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
            "GIT_COMMITTER_NAME": "Updater fixture", "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
            "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "commit.gpgSign", "GIT_CONFIG_VALUE_0": "false"})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.raw_git = updater.git
        self.raw_git("init", "-b", "profiling")
        self.write("app/build.gradle", GRADLE)
        self.write("custom.txt", "custom baseline\n")
        self.write("shared.txt", "baseline\n")
        self.write(".github/workflows/_build.yml", "trusted\n")
        self.write("keystore/testkey.p12", "fixture only\n")
        self.commit("baseline")
        self.baseline = self.raw_git("rev-parse", "HEAD").stdout.strip()
        self.raw_git("checkout", "-b", "upstream")

    def write(self, name, content):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def commit(self, message):
        self.raw_git("add", "--all")
        self.raw_git("commit", "-m", message)

    def run_merge(self, changes, custom_conflict=False):
        for name, content in changes.items():
            if content is None:
                Path(name).unlink()
            else:
                self.write(name, content)
        self.commit("upstream stable")
        self.raw_git("tag", "3.1.6")
        self.raw_git("checkout", "profiling")
        self.write("custom.txt", "keep my customizations\n")
        if custom_conflict:
            self.write("shared.txt", "custom edit\n")
        self.commit("custom changes")
        self.raw_git("clone", "--no-hardlinks", str(self.source), str(self.clone))
        os.chdir(self.clone)
        def local_git(*args, **kwargs):
            args = tuple(str(self.source) if arg == updater.UPSTREAM else arg for arg in args)
            return self.raw_git(*args, **kwargs)
        report = {}
        with patch.object(updater, "git", local_git):
            updater.prepare(dict(tag_name="3.1.6", draft=False, prerelease=False), report)
        return report

    def test_clean_merge_retains_custom_commit_and_two_parents(self):
        report = self.run_merge({"new.txt": "new upstream feature\n"})
        self.assertEqual(report["status"], "ready")
        self.assertEqual(Path("custom.txt").read_text(), "keep my customizations\n")
        self.assertEqual(self.raw_git("rev-parse", "HEAD^1").stdout.strip(), report["base"])
        self.assertEqual(self.raw_git("rev-parse", "HEAD^2").stdout.strip(), report["upstream"])
        self.assertEqual(self.raw_git("status", "--porcelain").stdout, "")

    def test_conflict_aborts_without_changing_base(self):
        report = self.run_merge({"shared.txt": "upstream edit\n"}, custom_conflict=True)
        self.assertEqual(report["status"], "blocked")
        self.assertEqual(report["conflicts"], ["shared.txt"])
        self.assertEqual(self.raw_git("rev-parse", "HEAD").stdout.strip(), report["base"])
        self.assertEqual(self.raw_git("status", "--porcelain").stdout, "")

    def test_workflow_change_blocks(self):
        self.assertEqual(self.run_merge({".github/workflows/_build.yml": "changed\n"})["status"], "blocked")

    def test_signing_key_change_blocks(self):
        self.assertEqual(self.run_merge({"keystore/testkey.p12": "changed\n"})["status"], "blocked")

    def test_package_change_blocks(self):
        report = self.run_merge({"app/build.gradle": GRADLE.replace("com.tencent.ig", "other.package")})
        self.assertEqual(report["status"], "blocked")

    def test_deleted_custom_file_blocks(self):
        self.assertEqual(self.run_merge({"keystore/testkey.p12": None})["status"], "blocked")

    def test_already_integrated_is_noop(self):
        report = self.run_merge({"new.txt": "new feature\n"})
        with patch.object(updater, "UPSTREAM", str(self.source)):
            self.raw_git("branch", "-f", "profiling", report["candidate"])
            self.raw_git("remote", "set-url", "origin", ".")
            again = {}
            updater.prepare(dict(tag_name="3.1.6", draft=False, prerelease=False), again)
        self.assertEqual(again["status"], "current")

    def test_dirty_checkout_is_rejected(self):
        self.write("untracked.txt", "preserve me")
        with self.assertRaisesRegex(RuntimeError, "clean"):
            updater.prepare(dict(tag_name="3.1.6", draft=False, prerelease=False), {})
        self.assertEqual(Path("untracked.txt").read_text(), "preserve me")


if __name__ == "__main__":
    unittest.main()
