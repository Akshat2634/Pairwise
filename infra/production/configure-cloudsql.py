#!/usr/bin/env python3
"""Configure the production stack to use its Cloud SQL Auth Proxy sidecar."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import quote


ROOT = Path(__file__).resolve().parent
PROJECT_RE = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
INSTANCE_RE = re.compile(r"^[a-z][a-z0-9-]{0,61}[a-z0-9]$")
SECRET_RE = re.compile(r"^[A-Za-z0-9_-]{1,255}$")
CONNECTION_RE = re.compile(r"^([a-z][a-z0-9-]{4,28}[a-z0-9]):([a-z0-9-]+):([a-z][a-z0-9-]{0,61}[a-z0-9])$")
CONFIG_KEYS = {"PAIRDESK_CLOUD_SQL_CONNECTION_NAME", "PAIRDESK_DATABASE_URL"}


def configure(project: str, instance: str, secret: str, env_file: Path,
              run=subprocess.run) -> str:
    if not PROJECT_RE.fullmatch(project):
        raise ValueError("Invalid GCP project ID")
    if not INSTANCE_RE.fullmatch(instance):
        raise ValueError("Invalid Cloud SQL instance name")
    if not SECRET_RE.fullmatch(secret):
        raise ValueError("Invalid Secret Manager secret name")
    if not env_file.is_file():
        raise ValueError("Production generated/.env is missing; run configure.py first")

    instance_result = run(
        ["gcloud", "sql", "instances", "describe", instance,
         f"--project={project}", "--format=json"],
        check=True, capture_output=True, text=True,
    )
    instance_info = json.loads(instance_result.stdout)
    connection_name = instance_info.get("connectionName", "")
    match = CONNECTION_RE.fullmatch(connection_name)
    if (instance_info.get("state") != "RUNNABLE" or match is None
            or match.group(1) != project or match.group(3) != instance):
        raise ValueError("Cloud SQL instance is not RUNNABLE or has an unexpected connection name")

    secret_result = run(
        ["gcloud", "secrets", "versions", "access", "latest",
         f"--secret={secret}", f"--project={project}"],
        check=True, capture_output=True, text=True,
    )
    password = secret_result.stdout.rstrip("\r\n")
    if not password or any(character in password for character in "\x00\r\n"):
        raise ValueError("The database password secret is empty or contains a line break")

    database_url = (
        "postgres://pairdesk_app:" + quote(password, safe="")
        + "@cloud-sql-proxy:5432/pairdesk?sslmode=disable"
    )
    _write_env(env_file, {
        "PAIRDESK_CLOUD_SQL_CONNECTION_NAME": connection_name,
        "PAIRDESK_DATABASE_URL": database_url,
    })
    return connection_name


def _write_env(path: Path, values: dict[str, str]) -> None:
    rows = [line for line in path.read_text(encoding="utf-8").splitlines()
            if line.split("=", 1)[0] not in CONFIG_KEYS]
    rows.extend(f"{key}={value}" for key, value in values.items())
    path.parent.chmod(0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".env.", dir=path.parent, text=True)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write("\n".join(rows) + "\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_name, path)
        path.chmod(0o600)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", required=True, help="GCP project containing PairDesk Cloud SQL")
    parser.add_argument("--instance", required=True, help="Cloud SQL instance name")
    parser.add_argument("--secret", required=True, help="Secret Manager database-password secret")
    parser.add_argument("--env-file", type=Path, default=ROOT / "generated/.env",
                        help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        name = configure(args.project, args.instance, args.secret, args.env_file)
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        parser.error(f"Cloud SQL configuration failed: {error}")
    print(f"Configured Cloud SQL Auth Proxy for {name}; generated/.env remains owner-only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
