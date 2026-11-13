#!/usr/bin/env python3
"""Check that a packaged app starts without its original SwiftPM resource bundle."""
import pathlib
import os
import signal
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
build_bundle = pathlib.Path(sys.argv[2]).resolve()
with tempfile.TemporaryDirectory(dir=build_bundle.parent) as directory:
    hidden = pathlib.Path(directory) / build_bundle.name
    build_bundle.rename(hidden)
    try:
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen([str(app / "Contents/MacOS/Reqnivo")],
                                       stdout=log, stderr=subprocess.STDOUT,
                                       start_new_session=True)
            try:
                process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                print("Verified packaged app stays running without build resources")
            else:
                log.seek(0)
                raise SystemExit(f"App exited during launch ({process.returncode}):\n"
                                 + log.read().decode(errors="replace"))
            finally:
                # Capture can start automatically; stop the engine as well as the app.
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
    finally:
        hidden.rename(build_bundle)
