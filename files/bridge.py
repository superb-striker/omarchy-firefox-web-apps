#!/usr/bin/env python3
"""Firefox native host and local URL client. Never edits Firefox profile files."""
import fcntl
import json
import os
import queue
import shutil
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit

LIMIT = 65536
NAME = "omarchy-firefox-web-apps"


def endpoint():
    root = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/{NAME}-{os.getuid()}"))
    directory = root / NAME
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    st = directory.lstat()
    if directory.is_symlink() or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise RuntimeError("Bridge runtime directory must be owned by you with mode 0700.")
    return directory / "bridge.sock"


def validate_url(url):
    if not isinstance(url, str) or len(url.encode("utf-8")) > LIMIT // 2:
        raise ValueError("URL is missing or too long.")
    if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in url):
        raise ValueError("URL whitespace must be percent-encoded.")
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError("Only absolute HTTP and HTTPS URLs are supported.")
    return url


def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        part = stream.read(size - len(data))
        if not part:
            raise EOFError
        data.extend(part)
    return bytes(data)


def read_frame(stream):
    size = struct.unpack("=I", read_exact(stream, 4))[0]
    if size > LIMIT:
        raise ValueError("Native message exceeds size limit.")
    return json.loads(read_exact(stream, size))


def write_frame(stream, message):
    data = json.dumps(message).encode()
    stream.write(struct.pack("=I", len(data)) + data)
    stream.flush()


def serve():
    path = endpoint()
    # Hold a lock for the host lifetime; another profile cannot hijack its socket.
    with open(path.with_suffix(".lock"), "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another Firefox profile already owns the web-app bridge.")
        path.unlink(missing_ok=True)
        pending = {}
        pending_lock = threading.Lock()
        output_lock = threading.Lock()

        class Handler(socketserver.StreamRequestHandler):
            def handle(self):
                self.connection.settimeout(20)
                request_id = str(uuid.uuid4())
                replies = queue.Queue(maxsize=1)
                try:
                    raw = self.rfile.readline(LIMIT + 1)
                    if len(raw) > LIMIT or not raw.endswith(b"\n"):
                        raise ValueError("Invalid request framing.")
                    request = json.loads(raw)
                    if not isinstance(request, dict):
                        raise TypeError("Expected a JSON object.")
                    if request.get("type") == "ping":
                        response = {"ok": True}
                    else:
                        url = validate_url(request.get("url"))
                        with pending_lock:
                            pending[request_id] = replies
                        with output_lock:
                            write_frame(sys.stdout.buffer, {
                                "type": "open", "id": request_id, "url": url,
                            })
                        try:
                            response = replies.get(timeout=15)
                        except queue.Empty:
                            raise RuntimeError("Firefox did not acknowledge the launch. Check before retrying.")
                except (OSError, ValueError, RuntimeError) as error:
                    response = {"ok": False, "error": str(error)}
                finally:
                    with pending_lock:
                        pending.pop(request_id, None)
                try:
                    self.wfile.write(json.dumps(response).encode() + b"\n")
                except OSError:
                    pass

        class Server(socketserver.ThreadingUnixStreamServer):
            daemon_threads = True

        with Server(str(path), Handler) as server:
            os.chmod(path, 0o600)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            with output_lock:
                write_frame(sys.stdout.buffer, {"type": "ready"})
            try:
                while True:
                    reply = read_frame(sys.stdin.buffer)
                    if not isinstance(reply, dict) or not isinstance(reply.get("id"), str):
                        continue
                    with pending_lock:
                        target = pending.get(reply["id"])
                        if target and target.empty():
                            target.put_nowait(reply)
            except EOFError:
                pass
            finally:
                with pending_lock:
                    for target in pending.values():
                        if target.empty():
                            target.put_nowait({"ok": False, "error": "Firefox disconnected."})
                server.shutdown()
                path.unlink(missing_ok=True)


def request(message, start_browser=False):
    path = endpoint()
    deadline = time.monotonic() + (12 if start_browser else 0)
    launched = False
    while True:
        client = socket.socket(socket.AF_UNIX)
        client.settimeout(20)
        try:
            client.connect(str(path))
            break
        except (FileNotFoundError, ConnectionRefusedError):
            client.close()
            if not start_browser or time.monotonic() >= deadline:
                raise RuntimeError("Load Omarchy Firefox Web Apps in your Firefox profile (about:debugging for the unsigned build).")
            if not launched:
                firefox = shutil.which("firefox")
                if not firefox:
                    raise RuntimeError("Native Firefox executable was not found.")
                command = [firefox]
                if shutil.which("uwsm-app"):
                    command = ["uwsm-app", "--", *command]
                subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                launched = True
            time.sleep(0.15)
    with client:
        client.sendall(json.dumps(message).encode() + b"\n")
        with client.makefile("rb") as stream:
            raw = stream.readline(LIMIT + 1)
        if len(raw) > LIMIT or not raw.endswith(b"\n"):
            raise RuntimeError("Bridge closed without a complete response.")
        response = json.loads(raw)
        if response.get("ok") is not True:
            raise RuntimeError(response.get("error", "Firefox could not open the window."))
        return response


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--open":
        request({"url": validate_url(sys.argv[2])}, start_browser=True)
    elif sys.argv[1:] == ["--status"]:
        request({"type": "ping"})
        print("Firefox popup bridge connected.")
    else:
        # Firefox supplies the native manifest path and extension ID as args.
        serve()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Firefox web apps: {error}", file=sys.stderr)
        if sys.argv[1:2] == ["--open"] and shutil.which("notify-send"):
            subprocess.run(["notify-send", "Firefox web app", str(error)], check=False)
        sys.exit(1)
