#!/usr/bin/env python3
"""Provide a :3390 compatibility port while macrdp listens on :3389."""
import select
import socket
import socketserver
import sys

if len(sys.argv) != 5:
    raise SystemExit("usage: alias.py <bind-ip> <bind-port> <target-ip> <target-port>")
bind_ip, bind_port, target_ip, target_port = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])

class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            with socket.create_connection((target_ip, target_port), timeout=10) as remote:
                peers = (self.request, remote)
                while True:
                    readable, _, _ = select.select(peers, [], [], 120)
                    for src in readable:
                        data = src.recv(65536)
                        if not data:
                            return
                        (remote if src is self.request else self.request).sendall(data)
        except OSError as exc:
            print("RDP relay closed: " + type(exc).__name__, flush=True)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server((bind_ip, bind_port), Relay) as server:
    print("RDP compatibility listener active", flush=True)
    server.serve_forever(poll_interval=0.5)
