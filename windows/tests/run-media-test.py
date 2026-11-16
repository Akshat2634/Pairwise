"""Run synthetic native transport tests against an isolated loopback LiveKit.

The server uses development credentials generated here, never account sessions.
No microphone, camera, desktop capture or production server is used.
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time
import urllib.request
import zipfile


def token(identity):
    def encode(value):
        return base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip("=")
    now = int(time.time())
    header = encode({"alg": "HS256", "typ": "JWT"})
    payload = encode({"iss": "devkey", "sub": identity, "nbf": now - 5, "exp": now + 300,
                      "video": {"roomJoin": True, "room": "pairwise-windows-ci", "canPublish": True,
                                "canSubscribe": True, "canPublishData": True}})
    unsigned = f"{header}.{payload}"
    signature = base64.urlsafe_b64encode(hmac.new(b"secret", unsigned.encode(), hashlib.sha256).digest()).decode().rstrip("=")
    return f"{unsigned}.{signature}"


def run(executable, server):
    with tempfile.TemporaryDirectory(prefix="pairwise-media-") as directory:
        directory = pathlib.Path(directory)
        if server is None:
            archive = directory / "livekit.zip"
            urllib.request.urlretrieve("https://github.com/livekit/livekit/releases/download/v1.8.4/livekit_1.8.4_windows_amd64.zip", archive)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != "e694983155bf6c01c94f73bfd189ec214210ed400e489af721d6abfe1835278e":
                raise RuntimeError("Media server checksum mismatch")
            with zipfile.ZipFile(archive) as bundle:
                bundle.extractall(directory)
            server = directory / "livekit-server.exe"
        log = (directory / "server.log").open("wb")
        process = subprocess.Popen([str(server), "--dev", "--bind", "127.0.0.1", "--node-ip", "127.0.0.1", "--port", "17890"], stdout=log, stderr=subprocess.STDOUT)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError("Local media server exited before startup")
                try:
                    with socket.create_connection(("127.0.0.1", 17890), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("Local media server did not become ready")
            env = os.environ.copy()
            env.update(PAIRWISE_MEDIA_TEST_URL="ws://127.0.0.1:17890", PAIRWISE_MEDIA_SENDER_TOKEN=token("sender"), PAIRWISE_MEDIA_RECEIVER_TOKEN=token("receiver"))
            subprocess.run([str(executable.resolve())], env=env, check=True, timeout=60)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=pathlib.Path)
    parser.add_argument("--server", type=pathlib.Path)
    args = parser.parse_args()
    run(args.executable, args.server)
