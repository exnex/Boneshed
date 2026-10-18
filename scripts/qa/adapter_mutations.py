"""Prove adapter wiring checks detect dropped fields and misspelled typed targets.

Runs in a temporary project copied from the current sources, never mutates the
working checkout, and retains logs/results in the native runner's evidence dir.
"""
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def run_mutations(engine, repo, output):
    output.mkdir(parents=True, exist_ok=False)
    records = []
    adapter_path = Path('scripts/combat/build_adapter.gd')
    original = (repo / adapter_path).read_text()
    assignments = re.findall(r'^\tstate\.([a-z_]+) = values\..+$', original, re.MULTILINE)
    assert len(assignments) == len(set(assignments)) == 20, assignments

    with tempfile.TemporaryDirectory(prefix='adapter-mutations-', dir=output) as temp:
        project = Path(temp)
        for directory in ('scripts', 'scenes', 'data'):
            shutil.copytree(repo / directory, project / directory)
        shutil.copy2(repo / 'project.godot', project / 'project.godot')
        base = [engine, '--headless', '--path', str(project)]

        def execute(name, args):
            result = subprocess.run(args, capture_output=True, text=True, timeout=60)
            text = result.stdout + result.stderr
            (output / (name + '.log')).write_text(text)
            return result.returncode, text

        code, text = execute('import', base + ['--editor', '--import'])
        assert code == 0 and 'ERROR:' not in text, 'mutation project import failed'
        target = project / adapter_path
        probe = project / 'scripts/qa/adapter_target_negative.gd'
        probe.write_text('''extends SceneTree
const Adapter = preload("res://scripts/combat/build_adapter.gd")
func _initialize() -> void:
	create_timer(0.25).timeout.connect(func(): quit(1))
	call_deferred("probe")
func probe() -> void:
	var result := Adapter.load_encounter()
	print(JSON.stringify({"ok": result.ok, "errors": result.errors, "empty": result.configs.is_empty() and result.resolved.is_empty() and result.states.is_empty()}))
	quit(0 if result.ok else 1)
''')
        state_path = project / 'scripts/combat/combat_state.gd'
        state_original = state_path.read_text()
        for field in assignments:
            # Omission is valid code: only a value-changing assertion can catch it.
            omitted, count = re.subn(r'^\tstate\.' + field + r' = values\..+\n', '', original, flags=re.MULTILINE)
            assert count == 1
            target.write_text(omitted)
            name = 'omitted_' + field
            code, text = execute(name, base + ['--script', 'res://scripts/qa/combat_build_tests.gd'])
            checks = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
            failed = [r['check'] for r in checks if r.get('passed') is False]
            expected = 'parameter_applied_' + field + '_player'
            assert code == 1 and 'ERROR:' not in text and expected in failed, (name, code, failed)
            assert any(r.get('summary') and r['failed'] > 0 for r in checks), name
            records.append({'mutation': name, 'exit': code, 'detected_by': expected})

            # Godot defers some typed writes until execution; direct writes must
            # raise an engine error instead of silently falling back to defaults.
            target.write_text(original.replace('state.' + field + ' = values.', 'state.' + field + '_typo = values.'))
            name = 'misspelled_' + field
            code, text = execute(name, base + ['--script', 'res://scripts/qa/adapter_target_negative.gd'])
            assert code == 1 and 'Invalid assignment of property' in text and field + '_typo' in text, (name, code, text)
            records.append({'mutation': name, 'exit': code, 'detected_by': 'direct assignment engine error'})
            target.write_text(original)

            # Simulate a legitimate CombatState member rename, including its own
            # internal references. Preparation must return a structured failure.
            state_path.write_text(re.sub(r'\b' + field + r'\b', field + '_renamed', state_original))
            name = 'renamed_state_' + field
            code, text = execute(name, base + ['--script', 'res://scripts/qa/adapter_target_negative.gd'])
            checks = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
            assert code == 1 and 'ERROR:' not in text and len(checks) == 1, (name, code, text)
            record = checks[0]
            error = record['errors'][0]['state_errors'][0]
            assert not record['ok'] and record['empty'] and error == {'code': 'missing_state_property', 'field': field}, record
            records.append({'mutation': name, 'exit': code, 'detected_by': 'missing_state_property; no configs/resolved/states'})
            state_path.write_text(state_original)

        state_path.write_text(state_original.replace('var max_health := 100.0', 'var max_health := 100'))
        code, text = execute('mistyped_state_max_health', base + ['--script', 'res://scripts/qa/adapter_target_negative.gd'])
        checks = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
        assert code == 1 and 'ERROR:' not in text and len(checks) == 1, text
        record = checks[0]
        assert not record['ok'] and record['empty'] and record['errors'][0]['state_errors'][0] == {'code': 'invalid_state_property_type', 'field': 'max_health'}, record
        records.append({'mutation': 'mistyped_state_max_health', 'exit': code, 'detected_by': 'invalid_state_property_type; no configs/resolved/states'})
        state_path.write_text(state_original)

        # A translation-key typo must propagate out of preparation, with no states.
        target.write_text(original.replace('state.guard_posture_overrides = resolved.', 'state.guard_posture_overrides_typo = resolved.'))
        probe = project / 'scripts/qa/adapter_preparation_negative.gd'
        probe.write_text('''extends SceneTree
const Adapter = preload("res://scripts/combat/build_adapter.gd")
func _initialize() -> void:
	var result := Adapter.load_encounter()
	var detected: bool = not result.ok and result.configs.is_empty() and result.resolved.is_empty() and result.states.is_empty() and result.errors[0].state_errors[0].code == "unknown_combat_parameter"
	print(JSON.stringify({"translation_typo_rejected_atomically": detected, "errors": result.errors}))
	quit(0 if detected else 1)
''')
        code, text = execute('translation_typo', base + ['--script', 'res://scripts/qa/adapter_preparation_negative.gd'])
        assert code == 0 and 'ERROR:' not in text and json.loads(next(line for line in text.splitlines() if line.startswith('{')))['translation_typo_rejected_atomically'], text
        records.append({'mutation': 'translation_typo', 'exit': code, 'detected_by': 'unknown_combat_parameter; no configs/resolved/states'})
        target.write_text(original)

        # Keep the pre-existing independent control for resolver profile overrides.
        rules = project / 'scripts/builds/build_rules.gd'
        source = rules.read_text()
        mutated, count = re.subn(r'^\t+effective\.merge\(catalog\.profiles.+\n', '', source, flags=re.MULTILINE)
        assert count == 1
        rules.write_text(mutated)
        code, text = execute('omitted_profile_overrides', base + ['--script', 'res://scripts/qa/combat_build_tests.gd'])
        checks = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
        failed = [r['check'] for r in checks if r.get('passed') is False]
        assert code == 1 and 'ERROR:' not in text and 'enemy_per_attack_timing_preserved' in failed, (code, failed)
        records.append({'mutation': 'omitted_profile_overrides', 'exit': code, 'detected_by': 'enemy_per_attack_timing_preserved'})

    assert len(records) == 63, len(records)
    (output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'All {len(records)} adapter mutation controls detected.', flush=True)


if __name__ == '__main__':
    run_mutations(sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
