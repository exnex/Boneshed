"""Real-browser smoke for the experimental directional expedition Web export.

Boots the page, starts the default address from the selection screen with a real
click, walks with W, holds and releases an attack (LMB) and a guard (RMB), and checks
the page's console for the session-ready marker and for errors. A boot and input gate,
not proof of feel, balance or a full browser playthrough.
"""
import functools
import http.server
import os
from pathlib import Path
import sys
import threading
from playwright.sync_api import sync_playwright

root = Path(sys.argv[1]).resolve()
shots = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root.parent
shots.mkdir(parents=True, exist_ok=True)
for name in ("index.html", "index.js", "index.wasm", "index.pck"):
    assert (root / name).is_file(), f"Missing browser asset: {name}"

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
errors, console = [], []
try:
    with sync_playwright() as pw:
        chromium = os.environ.get("CHROMIUM_BIN", "/usr/bin/google-chrome")
        for candidate in (chromium, "/opt/google/chrome/chrome", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"):
            if Path(candidate).exists():
                chromium = candidate
                break
        browser = pw.chromium.launch(executable_path=chromium, headless=True,
            args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader",
                  "--enable-unsafe-swiftshader", "--disable-dev-shm-usage"])
        page = browser.new_page(viewport={"width": 1280, "height": 720})
        page.on("pageerror", lambda err: errors.append(str(err)))
        page.on("console", lambda msg: console.append(msg.text))
        response = page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        assert response and response.status == 200, "Web page did not load"
        page.wait_for_function("() => typeof Engine !== 'undefined' && !document.querySelector('#status')", timeout=120000)
        page.wait_for_timeout(2000)
        page.screenshot(path=str(shots / "web_directional_selection.png"))
        # "Begin expedition" sits near the bottom of the centred 700x600 selection panel.
        for y in range(530, 560, 6):
            page.mouse.click(640, y)
            page.wait_for_timeout(400)
            if any("BONESHED_DIRECTIONAL_READY" in line for line in console):
                break
        page.wait_for_timeout(3000)
        assert any("BONESHED_DIRECTIONAL_READY" in line for line in console), f"Session did not start: {console[-10:]}"
        page.keyboard.down("w")
        page.wait_for_timeout(1500)
        page.keyboard.up("w")
        page.mouse.move(640, 360)
        page.mouse.down(button="left")
        page.mouse.move(700, 360, steps=4)
        page.wait_for_timeout(600)
        page.mouse.up(button="left")
        page.wait_for_timeout(800)
        page.mouse.down(button="right")
        page.wait_for_timeout(600)
        page.mouse.up(button="right")
        page.keyboard.press("Space")
        page.wait_for_timeout(1500)
        page.screenshot(path=str(shots / "web_directional_session.png"))
        assert page.locator("#canvas").count() == 1, "Godot canvas missing"
        script_errors = [line for line in console if "SCRIPT ERROR" in line or line.startswith("ERROR")]
        assert not errors and not script_errors, f"Browser errors: {errors + script_errors}"
        print("Directional expedition Web smoke passed: boot, selection click, session ready, WASD/LMB/RMB/Space input.")
        browser.close()
finally:
    server.shutdown()
