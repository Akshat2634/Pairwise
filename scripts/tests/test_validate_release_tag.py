import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "validate-release-tag.sh"


class ReleaseTagValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name)
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.name", "Pairwise CI")
        self.git("config", "user.email", "pairwise-ci@example.invalid")
        (self.repo / "tracked.txt").write_text("main history\n")
        self.git("add", "tracked.txt")
        self.git("commit", "--quiet", "-m", "main commit")

    def tearDown(self):
        self.temp_dir.cleanup()

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, check=True, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        ).stdout.strip()

    def validate(self, commit, main_ref="refs/heads/main"):
        return subprocess.run(
            ["sh", str(SCRIPT), commit, main_ref], cwd=self.repo,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def test_accepts_commit_reachable_from_main(self):
        main_commit = self.git("rev-parse", "HEAD")
        result = self.validate(main_commit)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_unmerged_commit(self):
        self.git("switch", "--quiet", "-c", "unmerged")
        (self.repo / "unmerged.txt").write_text("not merged\n")
        self.git("add", "unmerged.txt")
        self.git("commit", "--quiet", "-m", "unmerged commit")
        unmerged_commit = self.git("rev-parse", "HEAD")

        result = self.validate(unmerged_commit)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not reachable from main", result.stderr)

    def test_rejects_missing_main_ref(self):
        main_commit = self.git("rev-parse", "HEAD")
        result = self.validate(main_commit, "refs/remotes/origin/main")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main ref is unavailable", result.stderr)


if __name__ == "__main__":
    unittest.main()
