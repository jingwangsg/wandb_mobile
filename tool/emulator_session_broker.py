"""One-shot, loopback-only credential handoff to the local Android emulator."""
import hmac
import json
import netrc
from pathlib import Path
import secrets
import socket

output = Path('build/review/session-broker.json')
output.parent.mkdir(parents=True, exist_ok=True)
nonce = secrets.token_urlsafe(32)
with socket.socket() as server:
    server.bind(('127.0.0.1', 0))
    server.listen(1)
    server.settimeout(300)
    output.write_text(json.dumps({'SESSION_PORT': str(server.getsockname()[1]), 'SESSION_NONCE': nonce}))
    output.chmod(0o600)
    print('One-shot emulator session broker ready', flush=True)
    while True:
        connection, _ = server.accept()
        with connection:
            connection.settimeout(5)
            line = connection.makefile('rb').readline(256).decode().strip()
            if not hmac.compare_digest(line, nonce):
                continue
            auth = netrc.netrc(str(Path.home() / '.netrc')).authenticators('api.wandb.ai')
            if auth is None:
                raise RuntimeError('No W&B credentials found')
            connection.sendall(json.dumps({'apiKey': auth[2].strip()}).encode())
            print('Credential handed to emulator; broker closed', flush=True)
            break
