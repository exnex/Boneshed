"""Real Chromium/WebGL input integration tests. Playwright is test tooling only.

Usage: python3 scripts/qa/browser_test.py RELEASE_DIR QA_DIR NEW_EVIDENCE_DIR
"""
import functools
import http.server
import json
import math
import os
from pathlib import Path
import threading
import sys
import time

from playwright.sync_api import sync_playwright

release, qa, output = map(lambda s: Path(s).resolve(), sys.argv[1:4])
output.mkdir(parents=True, exist_ok=False)
records = []
errors = []
console = []


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def serve(directory):
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(directory)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f'http://127.0.0.1:{server.server_port}/index.html'


def check(condition, label, detail=None):
    record = {'check': label, 'passed': bool(condition)}
    if detail is not None:
        record['detail'] = detail
    records.append(record)
    print(json.dumps(record), flush=True)
    assert condition, label


def state(page):
    return page.evaluate('window.boneshedState')


def wait(page, expression):
    try:
        page.wait_for_function('() => window.boneshedState && (' + expression + ')', timeout=15000)
    except Exception:
        (output/'failure-state.json').write_text(json.dumps(state(page), indent=2)+'\n')
        page.screenshot(path=str(output/'failure.png'), timeout=5000)
        raise
    return state(page)


def command(page, name):
    previous = state(page)['tick']
    page.evaluate('(name) => window.boneshedCommand(name)', name)
    wait(page, f'window.boneshedState.tick > {previous + 1}')


def observe(page):
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda msg: console.append({'type': msg.type, 'text': msg.text}))


class Touches:
    def __init__(self, page, context):
        self.page = page
        self.cdp = context.new_cdp_session(page)
        self.points = {}

    def point(self, role):
        s = state(self.page)
        box = self.page.locator('#canvas').bounding_box()
        x, y = s['buttons'][role]
        return [box['x'] + x / s['viewport'][0] * box['width'], box['y'] + y / s['viewport'][1] * box['height']]

    def send(self, kind):
        points = [{'id': i, 'x': p[0], 'y': p[1], 'radiusX': 7, 'radiusY': 7, 'force': 1} for i, p in self.points.items()]
        self.cdp.send('Input.dispatchTouchEvent', {'type': kind, 'touchPoints': points})

    def down(self, index, point):
        self.points[index] = point
        self.send('touchStart')

    def move(self, index, point):
        self.points[index] = point
        self.send('touchMove')

    def up(self, index):
        point = self.points.pop(index)
        # Chromium's touchEnd command identifies the released contacts here;
        # passing the remaining contacts would lift the wrong finger.
        released = [{'id': index, 'x': point[0], 'y': point[1], 'radiusX': 7, 'radiusY': 7, 'force': 1}] if self.points else []
        self.cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': released})

    def clear(self):
        self.points.clear()
        self.send('touchCancel')

    def tap(self, role):
        before = state(self.page)['tick']
        self.down(5, self.point(role))
        wait(self.page, f'window.boneshedState.tick > {before + 2} && window.boneshedState.contacts > 0')
        self.up(5)


servers = []
try:
    server, release_url = serve(release)
    servers.append(server)
    server, qa_url = serve(qa)
    servers.append(server)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(executable_path=os.environ.get('CHROMIUM_BIN', '/usr/bin/chromium'), headless=True,
            args=['--no-sandbox', '--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'])
        desktop = browser.new_context(viewport={'width': 960, 'height': 540})
        page = desktop.new_page()
        observe(page)
        page.goto(release_url)
        page.wait_for_function('() => typeof Engine !== "undefined" && !document.querySelector("#status")', timeout=60000)
        page.wait_for_timeout(1000)
        check(any('BONESHED_WEB_READY' in r['text'] for r in console), 'release_boots_in_real_browser')
        check(page.evaluate('typeof window.boneshedCommand === "undefined"'), 'release_has_no_qa_bridge')
        check(page.evaluate('!crossOriginIsolated'), 'single_threaded_without_isolation_headers')
        await_box = page.locator('#canvas').bounding_box()
        page.mouse.click(600, 400)
        page.wait_for_timeout(200)
        check(page.evaluate('document.pointerLockElement === document.querySelector("#canvas")'), 'release_click_captures_mouse')
        page.keyboard.press('r')
        page.wait_for_timeout(250)
        page.screenshot(path=str(output/'01_release_desktop.png'))
        page.keyboard.press('Escape')
        page.close()

        page = desktop.new_page()
        observe(page)
        page.goto(qa_url)
        wait(page, 'window.boneshedState.tick > 3')
        command(page, 'ai_off')
        check(not state(page)['touch_ui'], 'desktop_has_no_touch_overlay')
        page.locator('#canvas').focus()
        start = state(page)['player']['position']
        page.keyboard.down('w')
        wait(page, f'window.boneshedState.player.position[2] < {start[2] - .75}')
        page.keyboard.up('w')
        page.wait_for_timeout(250)
        check(state(page)['player']['position'][2] < start[2] - .5, 'browser_keyboard_moves_player', {'start': start, 'end': state(page), 'focus': page.evaluate('document.activeElement.id')})
        page.mouse.click(600, 400)
        wait(page, 'window.boneshedState.player.phase !== 0')
        check(state(page)['player']['phase'] != 0, 'browser_mouse_attack')
        yaw = state(page)['player']['yaw']
        page.mouse.move(710, 430)
        wait(page, f'Math.abs(window.boneshedState.player.yaw - {yaw}) > .05')
        check(abs(state(page)['player']['yaw'] - yaw) > .05, 'captured_mouse_rotates_camera')
        page.keyboard.press('Tab')
        wait(page, 'window.boneshedState.player.locked')
        check(state(page)['player']['locked'], 'browser_keyboard_lock')
        page.keyboard.press('r')
        wait(page, 'window.boneshedState.player.health === 100 && !window.boneshedState.player.locked')
        check(abs(state(page)['player']['position'][2] - 4) < .05, 'browser_keyboard_reset')
        page.keyboard.press('Escape')
        command(page, 'fixture')
        page.mouse.click(600, 400)
        wait(page, 'window.boneshedState.enemy.health < 100')
        check(state(page)['enemy']['health'] == 82, 'browser_mouse_attack_damages_enemy')
        page.keyboard.press('Escape')
        command(page, 'fixture')
        page.mouse.down(button='right')
        wait(page, 'window.boneshedState.player.guarding && window.boneshedState.player.guard_age > .3')
        command(page, 'fresh_attack')
        wait(page, 'window.boneshedState.player.event === "guard"')
        check(state(page)['player']['health'] < 100 and state(page)['enemy']['posture'] == 0, 'mouse_held_guard_is_not_deflection')
        page.mouse.up(button='right')
        page.wait_for_timeout(100)
        command(page, 'fixture')
        command(page, 'attack_on_guard')
        page.mouse.down(button='right')
        wait(page, 'window.boneshedState.player.event === "deflected"')
        check(state(page)['player']['health'] == 100 and state(page)['enemy']['posture'] == 42, 'mouse_timed_deflection')
        page.mouse.up(button='right')
        page.close()
        desktop.close()

        phone = browser.new_context(viewport={'width': 844, 'height': 390}, screen={'width': 844, 'height': 390},
            device_scale_factor=1, is_mobile=True, has_touch=True,
            user_agent='Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Mobile Safari/537.36')
        page = phone.new_page()
        observe(page)
        page.goto(qa_url)
        wait(page, 'window.boneshedState.tick > 3')
        command(page, 'ai_off')
        check(state(page)['touch_ui'], 'touch_overlay_on_android_emulation')
        s = state(page)
        box = page.locator('#canvas').bounding_box()
        check(abs(s['viewport'][0] / s['viewport'][1] - 844/390) < .02 and box['width'] == 844 and box['height'] == 390, 'landscape_canvas_fills_viewport')
        touch = Touches(page, phone)
        start = state(page)['player']['position']
        center = touch.point('stick')
        touch.down(1, center)
        touch.move(1, [center[0], center[1] - 70])
        wait(page, f'window.boneshedState.player.position[2] < {start[2] - .75}')
        check(state(page)['player']['position'][2] < start[2] - .5, 'touch_joystick_moves_player')
        touch.down(2, touch.point('attack'))
        wait(page, 'window.boneshedState.contacts === 2 && window.boneshedState.actions.attack')
        check(state(page)['actions']['move_forward'] > 0 and state(page)['player']['phase'] in [1,2,3], 'simultaneous_joystick_and_attack')
        touch.up(2)
        touch.up(1)
        wait(page, '!window.boneshedState.actions.attack && window.boneshedState.actions.move_forward === 0')
        check(not state(page)['actions']['attack'] and state(page)['actions']['move_forward'] == 0, 'touch_release_clears_actions')
        command(page, 'fixture')
        touch.tap('attack')
        wait(page, 'window.boneshedState.enemy.health < 100')
        check(state(page)['enemy']['health'] == 82, 'touch_attack_damages_enemy')
        # A pure movement finger must never produce an emulated LMB attack.
        command(page, 'reset')
        command(page, 'ai_off')
        touch.down(1, touch.point('stick'))
        page.wait_for_timeout(150)
        check(not state(page)['actions']['attack'] and state(page)['player']['phase'] == 0, 'joystick_does_not_emulate_mouse_attack')
        touch.up(1)
        touch.tap('lock_on')
        wait(page, 'window.boneshedState.player.locked')
        check(state(page)['player']['locked'], 'touch_lock_toggle')
        touch.tap('reset')
        wait(page, '!window.boneshedState.player.locked')
        check(abs(state(page)['player']['position'][2] - 4) < .05, 'touch_reset')
        yaw = state(page)['player']['yaw']
        touch.down(1, [420, 150])
        touch.move(1, [480, 170])
        wait(page, f'Math.abs(window.boneshedState.player.yaw - {yaw}) > .05')
        check(abs(state(page)['player']['yaw'] - yaw) > .05, 'touch_camera_drag')
        touch.up(1)
        command(page, 'fixture')
        touch.down(1, touch.point('guard'))
        wait(page, 'window.boneshedState.player.guarding && window.boneshedState.player.guard_age > .3')
        guard_age = state(page)['player']['guard_age']
        touch.down(2, [420, 160])
        touch.move(2, [450, 170])
        wait(page, f'window.boneshedState.player.guard_age > {guard_age + .05}')
        check(state(page)['player']['guarding'] and state(page)['player']['guard_age'] > guard_age, 'camera_drag_does_not_rearm_held_guard')
        touch.up(2)
        wait(page, 'window.boneshedState.contacts === 1 && window.boneshedState.actions.guard')
        check(state(page)['player']['guarding'], 'lifting_camera_finger_preserves_guard')
        command(page, 'fresh_attack')
        wait(page, 'window.boneshedState.player.event === "guard"')
        check(state(page)['player']['health'] < 100 and state(page)['enemy']['posture'] == 0, 'touch_held_guard_is_not_deflection')
        touch.up(1)
        command(page, 'fixture')
        command(page, 'attack_on_guard')
        touch.down(1, touch.point('guard'))
        wait(page, 'window.boneshedState.player.event === "deflected"')
        check(state(page)['player']['health'] == 100 and state(page)['enemy']['posture'] == 42, 'touch_timed_deflection')
        page.screenshot(path=str(output/'02_phone_deflection.png'))
        touch.up(1)
        command(page, 'reset')
        command(page, 'ai_off')
        start = state(page)['player']['position']
        touch.tap('dodge')
        wait(page, f'Math.abs(window.boneshedState.player.position[2] - {start[2]}) > 1')
        end = state(page)['player']['position']
        check(math.dist(start, end) > 1, 'touch_dodge_moves_player')
        touch.down(1, touch.point('guard'))
        touch.down(2, touch.point('stick'))
        touch.move(2, [center[0], center[1]-50])
        touch.clear()
        wait(page, 'window.boneshedState.contacts === 0 && !window.boneshedState.actions.guard && window.boneshedState.actions.move_forward === 0')
        check(state(page)['contacts'] == 0, 'canceled_touches_release_guard_and_movement')
        # Physical keyboard input should take over and hide the touch overlay.
        page.keyboard.press('r')
        wait(page, '!window.boneshedState.touch_ui')
        check(not state(page)['touch_ui'], 'keyboard_hides_touch_overlay')
        touch.tap('lock_on')
        wait(page, 'window.boneshedState.touch_ui')
        check(state(page)['touch_ui'], 'touch_returns_after_keyboard')
        page.wait_for_timeout(650)
        # The first mouse entry into a touch-emulated canvas can have zero
        # relative motion; subsequent steps represent an actual mouse move.
        page.mouse.move(450, 180, steps=4)
        wait(page, '!window.boneshedState.touch_ui')
        check(not state(page)['touch_ui'], 'physical_mouse_hides_touch_overlay')
        touch.tap('lock_on')
        wait(page, 'window.boneshedState.touch_ui')
        page.set_viewport_size({'width': 915, 'height': 412})
        page.wait_for_timeout(400)
        s = state(page)
        check(abs(s['viewport'][0]/s['viewport'][1] - 915/412) < .02, 'landscape_resize_reflows_controls')
        page.screenshot(path=str(output/'03_phone_landscape.png'))
        # Real release (without fixture code) also boots with mobile input enabled.
        page.goto(release_url)
        page.wait_for_function('() => typeof Engine !== "undefined" && !document.querySelector("#status")', timeout=60000)
        page.wait_for_timeout(600)
        page.screenshot(path=str(output/'04_release_phone.png'))
        check(page.evaluate('typeof window.boneshedCommand === "undefined"'), 'mobile_release_has_no_fixture_code')
        phone.close()
        browser.close()
    fatal = [r for r in console if r['type'] == 'error' and any(t in r['text'] for t in ['SCRIPT ERROR', 'ERROR:', 'RuntimeError', 'Aborted', 'failed to compile'])]
    check(not errors and not fatal, 'no_fatal_browser_or_engine_errors', {'page_errors': errors, 'fatal_console': fatal})
except Exception as error:
    records.append({'check': 'runner_completed', 'passed': False, 'error': str(error)})
    try:
        (output/'failure-state.json').write_text(json.dumps(state(page), indent=2)+'\n')
        page.screenshot(path=str(output/'failure.png'), timeout=5000)
    except Exception:
        pass
    raise
finally:
    for server in servers:
        server.shutdown()
    (output/'checks.json').write_text(json.dumps(records, indent=2)+'\n')
    (output/'console.json').write_text(json.dumps(console, indent=2)+'\n')
    (output/'page-errors.json').write_text(json.dumps(errors, indent=2)+'\n')
