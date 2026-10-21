#!/usr/bin/env python3
"""Exercise production SNI routing with an isolated local certificate and Docker project."""
import importlib.util
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('config', ROOT / 'infra/production/configure.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)
fixture = Path(tempfile.mkdtemp(prefix='production-test-', dir=ROOT / '.cache'))
project = 'pairdesk-test-' + secrets.token_hex(4)
compose = ['docker', 'compose', '-p', project, '--env-file', str(fixture / 'generated/.env'), '-f', str(fixture / 'docker-compose.yml')]
try:
    config.render('api.pairdesk.example', 'media.pairdesk.example', 'turn.pairdesk.example', '8.8.8.8', 'test@pairdesk.example', fixture / 'generated')
    # Rendering twice must preserve secrets.
    original = (fixture / 'generated/.env').read_bytes()
    config.render('api.pairdesk.example', 'media.pairdesk.example', 'turn.pairdesk.example', '8.8.8.8', 'test@pairdesk.example', fixture / 'generated')
    assert original == (fixture / 'generated/.env').read_bytes()
    certificate = fixture / 'generated/certificates/live/pairdesk'
    certificate.mkdir(parents=True)
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=api.pairdesk.example', '-addext', 'subjectAltName=DNS:api.pairdesk.example,DNS:media.pairdesk.example,DNS:turn.pairdesk.example', '-keyout', str(certificate / 'privkey.pem'), '-out', str(certificate / 'fullchain.pem')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.chmod(certificate / 'privkey.pem', 0o600)
    content = (ROOT / 'infra/production/docker-compose.yml').read_text().replace('context: ../../server', 'context: ' + str(ROOT / 'server'))
    content = content.replace("'80:80/tcp'", "'127.0.0.1:18090:80/tcp'").replace("'443:443/tcp'", "'127.0.0.1:18443:443/tcp'")
    # TLS routing test doesn't publish media ports; it doesn't exercise ICE.
    content = content.replace("      - '7881:7881/tcp'\n      - '50000-50100:50000-50100/udp'\n      - '3478:3478/udp'", "      - '127.0.0.1:18881:7881/tcp'")
    (fixture / 'docker-compose.yml').write_text(content)
    # Validate that a configured Cloud SQL DSN selects a private, non-published
    # Auth Proxy service and wires the API to it. Do not connect to GCP here.
    cloudsql_env = fixture / 'cloudsql-test.env'
    cloudsql_env.write_text(
        (fixture / 'generated/.env').read_text()
        + 'PAIRDESK_CLOUD_SQL_CONNECTION_NAME=test-project:us-central1:pairdesk-pg\n'
        + 'PAIRDESK_DATABASE_URL=postgres://pairdesk_app:test@cloud-sql-proxy:5432/pairdesk?sslmode=disable\n'
    )
    cloudsql_compose = compose.copy()
    env_index = cloudsql_compose.index('--env-file') + 1
    cloudsql_compose[env_index] = str(cloudsql_env)
    cloudsql_compose += ['-f', str(ROOT / 'infra/production/docker-compose.cloudsql.yml'), 'config', '--format', 'json']
    cloudsql_config = json.loads(subprocess.run(cloudsql_compose, check=True, capture_output=True, text=True).stdout)
    proxy = cloudsql_config['services']['cloud-sql-proxy']
    assert proxy['image'] == 'gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.26.2'
    assert proxy['expose'] == ['5432'] and not proxy.get('ports')
    assert 'test-project:us-central1:pairdesk-pg' in proxy['command']
    assert cloudsql_config['services']['api']['environment']['PAIRDESK_DATABASE_URL'].startswith(
        'postgres://pairdesk_app:test@cloud-sql-proxy:5432/'
    )
    assert 'cloud-sql-proxy' in cloudsql_config['services']['api']['depends_on']
    subprocess.run(compose + ['build', 'api'], check=True)
    admin_password = secrets.token_hex(16)
    subprocess.run(compose + ['run', '--rm', '--no-deps', '-T', '-e', 'PAIRDESK_ADMIN_PASSWORD', '--entrypoint', '/pairdesk-admin', 'api', 'create-user', '--admin', '--name', 'Synthetic Operations Administrator', '--email', 'admin@pairdesk.invalid'], env={**os.environ, 'PAIRDESK_ADMIN_PASSWORD': admin_password}, check=True)
    subprocess.run(compose + ['up', '-d'], check=True)
    subprocess.run(compose + ['exec', '-T', 'edge', 'nginx', '-t'], check=True)
    context = ssl.create_default_context(cafile=str(certificate / 'fullchain.pem'))
    def connect(domain):
        return context.wrap_socket(socket.create_connection(('127.0.0.1', 18443), timeout=10), server_hostname=domain)
    for attempt in range(30):
        try:
            with connect('api.pairdesk.example') as connection:
                connection.sendall(b'GET /healthz HTTP/1.1\r\nHost: api.pairdesk.example\r\nConnection: close\r\n\r\n')
                received = b''
                while True:
                    part = connection.recv(4096)
                    if not part: break
                    received += part
                assert b'200 OK' in received and b'"ok":true' in received
            break
        except (OSError, AssertionError):
            if attempt == 29: raise
            time.sleep(1)
    body = json.dumps({'email': 'admin@pairdesk.invalid', 'password': admin_password}).encode()
    with connect('api.pairdesk.example') as connection:
        connection.sendall(b'POST /v1/login HTTP/1.1\r\nHost: api.pairdesk.example\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
        response = b''
        while True:
            part = connection.recv(4096)
            if not part: break
            response += part
        assert b'200 OK' in response and b'"token"' in response
    snapshot = fixture / 'backup.json'
    subprocess.run(compose + ['cp', 'api:/data/pairdesk.json', str(snapshot)], check=True)
    stored = json.loads(snapshot.read_text())
    assert len(stored['users']) == 1 and admin_password not in snapshot.read_text()
    with connect('media.pairdesk.example') as connection:
        connection.sendall(b'GET / HTTP/1.1\r\nHost: media.pairdesk.example\r\nConnection: close\r\n\r\n')
        assert b'200 OK' in connection.recv(4096)
    transaction = secrets.token_bytes(12)
    with connect('turn.pairdesk.example') as connection:
        # STUN Binding request: verify it reaches the embedded TURN service, not HTTP.
        connection.sendall(struct.pack('!HHI', 0x0001, 0, 0x2112A442) + transaction)
        received = b''
        while len(received) < 20:
            received += connection.recv(20 - len(received))
        kind, length, cookie = struct.unpack('!HHI', received[:8])
        assert kind == 0x0101 and cookie == 0x2112A442 and received[8:20] == transaction
    print('PASS: private config, secret preservation, nginx syntax, administrator bootstrap/login, consistent hashed-account backup, trusted fixture HTTPS/API, media HTTPS, TURN/TLS STUN routing on one port.')
    print('This does not verify public certificates, real DNS, TURN allocation or physical-Mac media.')
except Exception:
    with (ROOT / '.cache/production-services.log').open('w') as log:
        subprocess.run(compose + ['logs', '--tail', '80'], stdout=log, stderr=subprocess.STDOUT)
    raise
finally:
    subprocess.run(compose + ['down', '--volumes'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    shutil.rmtree(fixture)
