"""Browser smoke: load isolated Adaptive Combat Lab, exercise inputs and catch script errors."""
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
for file in ("index.html", "index.js", "index.wasm", "index.pck"):
    assert (root/file).is_file(), file

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_): pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(root)))
threading.Thread(target=server.serve_forever, daemon=True).start()
errors, logs = [], []
try:
    with sync_playwright() as pw:
        chrome = next((s for s in (os.environ.get("CHROMIUM_BIN", "/usr/bin/google-chrome"), "/opt/google/chrome/chrome", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome") if Path(s).exists()), None)
        assert chrome, "Chromium not found"
        browser = pw.chromium.launch(executable_path=chrome, headless=True, args=["--no-sandbox", "--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--disable-dev-shm-usage"])
        page = browser.new_page(viewport={"width":1280,"height":720})
        page.on("pageerror", lambda x: errors.append(str(x)))
        page.on("console", lambda msg: logs.append(msg.text))
        result = page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        assert result and result.status == 200
        page.wait_for_function("() => typeof Engine !== 'undefined' && !document.querySelector('#status')", timeout=120000)
        page.wait_for_timeout(3000)
        page.locator("#canvas").click(position={"x":600,"y":350})
        page.keyboard.press("1")
        page.mouse.click(620,350,button="left")
        page.keyboard.press("f")
        page.mouse.click(620,350,button="right")
        page.keyboard.press("Space")
        page.keyboard.press("b")
        page.keyboard.press("g")
        page.keyboard.press("2")
        page.wait_for_timeout(2000)
        page.screenshot(path=str(shots/"adaptive_web_smoke.png"))
        assert any("BONESHED_ADAPTIVE_READY" in line for line in logs), f"Adaptive scene never reached ready: {logs[-12:]}"
        assert page.locator("#canvas").count() == 1
        unexpected = [line for line in logs if "SCRIPT ERROR" in line or line.startswith("ERROR")]
        assert not errors and not unexpected, errors + unexpected
        print("Adaptive Combat Lab browser smoke passed: boot, scene-ready, object controls and input.")
        browser.close()
finally:
    server.shutdown()
