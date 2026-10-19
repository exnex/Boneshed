"""Real Chromium/WebGL input integration tests. Playwright is test tooling only.

Usage: python3 scripts/qa/browser_test.py RELEASE_DIR QA_DIR NEW_EVIDENCE_DIR
"""
import functools
import http.server
import json
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
        page.screenshot(path=str(output/'02_desktop_deflection.png'))
        command(page, 'reset')
        command(page, 'ai_off')
        start = state(page)['player']['position']
        page.keyboard.press('Space')
        wait(page, f'window.boneshedState.player.position[2] > {start[2] + 1}')
        check(state(page)['player']['position'][2] > start[2] + 1, 'browser_keyboard_dodge_moves_player')
        page.screenshot(path=str(output/'03_desktop_dodge.png'))
        command(page, 'reset')
        command(page, 'ai_off')
        start = state(page)['player']['position']
        page.keyboard.down('w')
        page.mouse.click(600, 400)
        wait(page, 'window.boneshedState.player.phase === 1 || window.boneshedState.player.phase === 2')
        page.mouse.move(810, 400)
        wait(page, 'window.boneshedState.player.phase === 3')
        moving_attack = state(page)
        page.keyboard.up('w')
        check(moving_attack['attack_distance'] > 1.0, 'browser_moves_while_swinging',
              {'distance_during_attack_phases': moving_attack['attack_distance']})
        check(moving_attack['attack_turn'] > .15, 'browser_turns_while_moving_and_swinging',
              {'radians_turned_during_moving_attack_phases': moving_attack['attack_turn']})
        page.screenshot(path=str(output/'04_desktop_moving_attack.png'))
        for defense in ['dodge', 'guard']:
            command(page, 'cancel_fixture')
            page.mouse.click(600, 400)
            wait(page, 'window.boneshedState.player.phase === 1')
            command(page, 'attack_on_' + defense)
            if defense == 'dodge':
                page.keyboard.down('Space')
            else:
                page.mouse.down(button='right')
            expected = 'evaded' if defense == 'dodge' else 'deflected'
            wait(page, f'window.boneshedState.player.event === "{expected}"')
            cancelled = state(page)
            if defense == 'dodge':
                page.keyboard.up('Space')
            else:
                page.mouse.up(button='right')
            check(cancelled['attack_cancelled'] and cancelled['player']['health'] == 100 and cancelled['enemy']['health'] == 100,
                  'browser_attack_cancels_to_' + defense, {'incoming_result': expected, 'health': cancelled['player']['health']})
        # Real browser wheel events, including pointer lock and held combat input.
        command(page, 'reset')
        command(page, 'ai_off')
        # Godot 4.7.2 Web scales DOM pixel deltas by 0.03; 100 px is three
        # wheel units. Send one unit here so the exact sensitivity assertion
        # matches native factor=1 events rather than assuming pixels are notches.
        wheel_pixels = 1.0 / 0.03
        zoom_start = state(page)['zoom']['preferred']
        page.mouse.wheel(0, -wheel_pixels)
        wait(page, f'window.boneshedState.zoom.preferred < {zoom_start}')
        zoom_close = state(page)['zoom']['preferred']
        check(abs(zoom_close - (zoom_start - state(page)['zoom']['step'])) < .001,
              'browser_wheel_up_zooms_closer', {'before': zoom_start, 'after': state(page)['zoom']})
        wait(page, 'Math.abs(window.boneshedState.zoom.requested - window.boneshedState.zoom.preferred) < .01')
        page.mouse.wheel(0, wheel_pixels)
        wait(page, f'window.boneshedState.zoom.preferred > {zoom_close}')
        check(abs(state(page)['zoom']['preferred'] - zoom_start) < .001, 'browser_wheel_down_zooms_farther')
        for _ in range(16):
            page.mouse.wheel(0, -wheel_pixels)
        wait(page, 'window.boneshedState.zoom.preferred === window.boneshedState.zoom.minimum')
        wait(page, 'Math.abs(window.boneshedState.zoom.actual - window.boneshedState.zoom.minimum) < .01')
        check(state(page)['zoom']['preferred'] == state(page)['zoom']['minimum'], 'browser_zoom_minimum_clamp')
        page.screenshot(path=str(output/'05_zoom_close.png'))
        for _ in range(16):
            page.mouse.wheel(0, wheel_pixels)
        wait(page, 'window.boneshedState.zoom.preferred === window.boneshedState.zoom.maximum')
        wait(page, 'Math.abs(window.boneshedState.zoom.actual - window.boneshedState.zoom.maximum) < .01')
        check(state(page)['zoom']['preferred'] == state(page)['zoom']['maximum'], 'browser_zoom_maximum_clamp')
        page.screenshot(path=str(output/'06_zoom_far.png'))
        command(page, 'zoom_wall')
        wait(page, 'window.boneshedState.zoom.actual < 1.5')
        check(state(page)['zoom']['preferred'] == state(page)['zoom']['maximum'], 'browser_wall_preserves_zoom')
        page.screenshot(path=str(output/'07_zoom_wall.png'))
        page.mouse.wheel(0, -wheel_pixels)
        wait(page, 'window.boneshedState.zoom.preferred < window.boneshedState.zoom.maximum')
        selected = state(page)['zoom']['preferred']
        command(page, 'zoom_clear')
        wait(page, f'Math.abs(window.boneshedState.zoom.actual - {selected}) < .01')
        check(abs(state(page)['zoom']['preferred'] - selected) < .001, 'browser_wall_recovers_selected_zoom')
        page.screenshot(path=str(output/'08_zoom_recovered.png'))
        command(page, 'reset')
        check(abs(state(page)['zoom']['preferred'] - selected) < .001, 'browser_retry_keeps_zoom')
        command(page, 'cancel_fixture')
        page.mouse.click(600, 400)
        wait(page, 'window.boneshedState.player.phase === 1')
        page.mouse.wheel(0, -wheel_pixels)
        wait(page, f'window.boneshedState.zoom.preferred < {selected}')
        check(state(page)['player']['phase'] == 1 and state(page)['player']['locked'], 'browser_zoom_during_locked_attack')
        page.mouse.down(button='right')
        wait(page, 'window.boneshedState.player.guarding')
        guard_zoom = state(page)['zoom']['preferred']
        page.mouse.wheel(0, wheel_pixels)
        wait(page, f'window.boneshedState.zoom.preferred > {guard_zoom}')
        check(state(page)['player']['guarding'] and state(page)['actions']['guard'], 'browser_wheel_preserves_held_guard')
        page.mouse.up(button='right')
        page.close()
        desktop.close()

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
