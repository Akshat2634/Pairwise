import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY = Path(__file__).resolve().parents[2]
MANAGE_SCRIPT = REPOSITORY / "infra/production/manage.sh"
COMMIT = "0123456789abcdef0123456789abcdef01234567"
OLD_IMAGE = "sha256:" + "a" * 64


class ProductionAPIDeployTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        production = self.root / "infra/production"
        generated = production / "generated"
        bin_dir = self.root / "bin"
        generated.mkdir(parents=True)
        bin_dir.mkdir()
        shutil.copy2(MANAGE_SCRIPT, production / "manage.sh")
        (generated / ".env").write_text(
            "API_DOMAIN=api.pairdesk.test\n"
            "MEDIA_DOMAIN=media.pairdesk.test\n"
            "TURN_DOMAIN=turn.pairdesk.test\n"
            "LIVEKIT_API_KEY=test-key\n"
            "LIVEKIT_API_SECRET=test-secret\n"
        )
        self.log = self.root / "commands.log"
        self.write_executable(bin_dir / "uname", "#!/bin/sh\nprintf 'Linux\\n'\n")
        self.write_executable(bin_dir / "sleep", "#!/bin/sh\nexit 0\n")
        self.write_executable(
            bin_dir / "python3",
            "#!/bin/sh\nexit \"${PAIRDESK_FAKE_HEALTH_STATUS:-0}\"\n",
        )
        self.write_executable(
            bin_dir / "docker",
            "#!/bin/sh\n"
            "printf 'docker %s build_commit=%s\\n' \"$*\" \"${PAIRDESK_BUILD_COMMIT:-}\" >> \"$PAIRDESK_MOCK_LOG\"\n"
            "if [ \"$1\" = compose ]; then\n"
            "  case \" $* \" in\n"
            "    *' images -q api '*) printf '%s\\n' \"$PAIRDESK_OLD_IMAGE\" ;;\n"
            "    *' build api '*) [ \"${PAIRDESK_FAKE_BUILD_STATUS:-0}\" = 0 ] || exit \"$PAIRDESK_FAKE_BUILD_STATUS\" ;;\n"
            "    *' up -d --no-deps --no-build api '*) [ \"${PAIRDESK_FAKE_UP_STATUS:-0}\" = 0 ] || exit \"$PAIRDESK_FAKE_UP_STATUS\" ;;\n"
            "  esac\n"
            "fi\n",
        )
        self.env = os.environ.copy()
        self.env.update(
            PATH=f"{bin_dir}:/usr/bin:/bin",
            PAIRDESK_MOCK_LOG=str(self.log),
            PAIRDESK_OLD_IMAGE=OLD_IMAGE,
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    @staticmethod
    def write_executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    def run_manage(self, *args, **env):
        return subprocess.run(
            ["/bin/bash", str(self.root / "infra/production/manage.sh"), *args],
            cwd=self.root / "infra/production", env={**self.env, **env},
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def command_log(self):
        return self.log.read_text() if self.log.exists() else ""

    def test_deploys_api_only_and_keeps_previous_image_tagged(self):
        result = self.run_manage("deploy-api", COMMIT)

        self.assertEqual(result.returncode, 0, result.stderr)
        log = self.command_log()
        self.assertIn(f"build api build_commit={COMMIT}", log)
        self.assertIn(f"{OLD_IMAGE} pairdesk-prod-api:rollback-{COMMIT[:12]}", log)
        self.assertIn("up -d --no-deps --no-build api", log)
        self.assertNotIn("up -d --no-deps --no-build edge", log)
        self.assertIn(f"healthy at commit {COMMIT}", result.stdout)

    def test_failed_health_check_restores_previous_api_image(self):
        result = self.run_manage("deploy-api", COMMIT, PAIRDESK_FAKE_HEALTH_STATUS="1")

        self.assertNotEqual(result.returncode, 0)
        log = self.command_log()
        self.assertIn(f"{OLD_IMAGE} pairdesk-prod-api:latest", log)
        self.assertGreaterEqual(log.count("up -d --no-deps --no-build api"), 2)

    def test_rejects_non_full_or_non_hex_commit_before_docker(self):
        result = self.run_manage("deploy-api", "not-a-commit")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.command_log(), "")

    def test_build_failure_does_not_recreate_running_api(self):
        result = self.run_manage("deploy-api", COMMIT, PAIRDESK_FAKE_BUILD_STATUS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("up -d --no-deps --no-build api", self.command_log())


if __name__ == "__main__":
    unittest.main()
