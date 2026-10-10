#!/usr/bin/env python3
"""Check trusted HTTPS and TURN TLS handshake; does not claim media relay allocation."""
import json
from pathlib import Path
import socket
import ssl
import urllib.request

root = Path(__file__).resolve().parent
values = dict(line.split('=', 1) for line in (root / 'generated/.env').read_text().splitlines() if '=' in line)
context = ssl.create_default_context()
with urllib.request.urlopen('https://' + values['API_DOMAIN'] + '/healthz', context=context, timeout=15) as response:
    if json.load(response).get('ok') is not True:
        raise SystemExit('API health check failed')
print('Trusted HTTPS API health passed')
for domain in [values['MEDIA_DOMAIN'], values['TURN_DOMAIN']]:
    with socket.create_connection((domain, 443), timeout=15) as raw:
        with context.wrap_socket(raw, server_hostname=domain) as connection:
            if not connection.getpeercert():
                raise SystemExit('TLS certificate missing')
    print('Trusted TLS handshake passed: ' + domain)
print('Run the four-client call and physical-Mac relay tests before marking media ready.')
