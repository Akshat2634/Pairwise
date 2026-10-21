import importlib.util
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "configure_cloudsql", ROOT / "infra/production/configure-cloudsql.py"
)
configure_cloudsql = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(configure_cloudsql)


class ConfigureCloudSQLTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.env_file = Path(self.temporary.name) / "generated" / ".env"
        self.env_file.parent.mkdir(mode=0o700)
        self.env_file.write_text(
            "API_DOMAIN=api.example.test\n"
            "LIVEKIT_API_KEY=AP123456789012345678901234\n"
            "LIVEKIT_API_SECRET=" + "a" * 64 + "\n"
            "PAIRDESK_DATABASE_URL=stale-value\n",
            encoding="utf-8",
        )
        os.chmod(self.env_file, 0o600)
        self.run = Mock(side_effect=[
            SimpleNamespace(stdout=json.dumps({
                "state": "RUNNABLE",
                "connectionName": "named-tube-444103-p0:us-central1:pairdesk-pg",
            })),
            SimpleNamespace(stdout="p@ss/w:rd%\n"),
        ])

    def tearDown(self):
        self.temporary.cleanup()

    def test_writes_private_proxy_dsn_and_preserves_other_deployment_values(self):
        connection = configure_cloudsql.configure(
            "named-tube-444103-p0", "pairdesk-pg", "pairdesk-db-password",
            self.env_file, run=self.run,
        )

        self.assertEqual(connection, "named-tube-444103-p0:us-central1:pairdesk-pg")
        content = self.env_file.read_text(encoding="utf-8")
        self.assertIn("API_DOMAIN=api.example.test", content)
        self.assertIn("LIVEKIT_API_KEY=AP123456789012345678901234", content)
        self.assertIn("PAIRDESK_CLOUD_SQL_CONNECTION_NAME=" + connection, content)
        self.assertIn(
            "PAIRDESK_DATABASE_URL=postgres://pairdesk_app:p%40ss%2Fw%3Ard%25"
            "@cloud-sql-proxy:5432/pairdesk?sslmode=disable",
            content,
        )
        self.assertNotIn("p@ss/w:rd%", content)
        self.assertEqual(stat.S_IMODE(self.env_file.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.env_file.parent.stat().st_mode), 0o700)
        self.assertEqual(self.run.call_count, 2)

    def test_refuses_instance_that_is_not_runnable_without_changing_config(self):
        original = self.env_file.read_bytes()
        self.run.side_effect = [SimpleNamespace(stdout=json.dumps({
            "state": "MAINTENANCE",
            "connectionName": "named-tube-444103-p0:us-central1:pairdesk-pg",
        }))]

        with self.assertRaisesRegex(ValueError, "not RUNNABLE"):
            configure_cloudsql.configure(
                "named-tube-444103-p0", "pairdesk-pg", "pairdesk-db-password",
                self.env_file, run=self.run,
            )

        self.assertEqual(self.env_file.read_bytes(), original)
        self.run.assert_called_once()

    def test_rejects_secret_with_newline_before_writing(self):
        original = self.env_file.read_bytes()
        self.run.side_effect = [
            SimpleNamespace(stdout=json.dumps({
                "state": "RUNNABLE",
                "connectionName": "named-tube-444103-p0:us-central1:pairdesk-pg",
            })),
            SimpleNamespace(stdout="password\nwith-line-break"),
        ]

        with self.assertRaisesRegex(ValueError, "line break"):
            configure_cloudsql.configure(
                "named-tube-444103-p0", "pairdesk-pg", "pairdesk-db-password",
                self.env_file, run=self.run,
            )

        self.assertEqual(self.env_file.read_bytes(), original)

    def test_rejects_unexpected_cloud_sql_connection_name(self):
        original = self.env_file.read_bytes()
        self.run.side_effect = [SimpleNamespace(stdout=json.dumps({
            "state": "RUNNABLE",
            "connectionName": "other-project:us-central1:pairdesk-pg",
        }))]

        with self.assertRaisesRegex(ValueError, "unexpected connection name"):
            configure_cloudsql.configure(
                "named-tube-444103-p0", "pairdesk-pg", "pairdesk-db-password",
                self.env_file, run=self.run,
            )

        self.assertEqual(self.env_file.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
