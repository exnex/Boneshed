"""Smoke-test the audited production Web export in a real desktop Chromium session.

This is an initial boot gate, not proof of game balance or a full expedition playthrough.
"""
import functools
import http.server
import os
from pathlib import Path
import sys
import threading
from playwright.sync_api import sync_playwright

root = Path(sys.argv[1]).resolve()
for name in ("index.html", "index.js", "index.wasm", "index.pck"):
    assert (root / name).is_file(), f"Missing browser asset: {name}"

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
errors = []
try:
    with sync_playwright() as pw:
        # GitHub ubuntu hosted runners include Google Chrome.
        chromium = os.environ.get("CHROMIUM_BIN", "/usr/bin/google-chrome")
        if not Path(chromium).exists():
            chromium = "/opt/google/chrome/chrome"
        browser = pw.chromium.launch(executable_path=chromium, headless=True,
            args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader",
                  "--enable-unsafe-swiftshader", "--disable-dev-shm-usage"])
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("pageerror", lambda err: errors.append(str(err)))
        response = page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        assert response and response.status == 200, "Web page did not load"
        page.wait_for_function(
            "() => typeof Engine !== 'undefined' && !document.querySelector('#status')",
            timeout=90000)
        page.wait_for_timeout(1000)
        assert page.locator("#canvas").count() == 1, "Godot canvas missing"
        assert not errors, f"Browser JavaScript errors: {errors}"
        page.screenshot(path=str(root.parent / "boneshed-web-smoke.png"))
        print("Real-browser release boot smoke passed; screenshot captured.")
        browser.close()
finally:
    server.shutdown()
