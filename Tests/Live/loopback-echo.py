#!/usr/bin/env python3
"""Echo test payloads on loopback only. Write assigned ports to the given file."""
import errno
import json
import signal
import socket
import sys
import threading
from pathlib import Path

stopped = threading.Event()
sockets = []
endpoints = []


def echo_tcp(server):
    while not stopped.is_set():
        try:
            connection, _ = server.accept()
            with connection:
                connection.settimeout(2)
                data = connection.recv(1024)
                if data:
                    connection.sendall(data)
        except (OSError, TimeoutError):
            pass


def echo_udp(server):
    while not stopped.is_set():
        try:
            data, address = server.recvfrom(1024)
            server.sendto(data, address)
        except (OSError, TimeoutError):
            pass


for host in ["127.0.0.1", "127.0.0.2", "::1"]:
    family = socket.AF_INET6 if host == "::1" else socket.AF_INET
    for transport, kind in [("tcp", socket.SOCK_STREAM), ("udp", socket.SOCK_DGRAM)]:
        server = socket.socket(family, kind)
        if family == socket.AF_INET6:
            server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        try:
            server.bind((host, 0))
        except OSError as error:
            server.close()
            if host == "127.0.0.2" and error.errno == errno.EADDRNOTAVAIL:
                print("Skipping unassigned loopback alias 127.0.0.2", flush=True)
                continue
            raise
        server.settimeout(0.5)
        if transport == "tcp":
            server.listen(4)
        sockets.append(server)
        endpoints.append(dict(host=host, port=server.getsockname()[1], transport=transport))
        threading.Thread(target=echo_tcp if transport == "tcp" else echo_udp, args=(server,), daemon=True).start()

Path(sys.argv[1]).write_text(json.dumps(endpoints, indent=2) + "\n")
print("Loopback-only echo servers ready", flush=True)
signal.signal(signal.SIGTERM, lambda *_: stopped.set())
signal.signal(signal.SIGINT, lambda *_: stopped.set())
stopped.wait()
for server in sockets:
    server.close()
