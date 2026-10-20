"""Meaningful negative controls in isolated copies; never mutate the checkout."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def run(engine: str, repo: Path, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=False)
    mutations = [
        ('combat/duel_progression.gd', 'result != Rules.DEFEATED', 'false',
         'debug_death_without_lethal_contact_grants_nothing'),
        ('combat/duel_progression.gd', 'not owns(ref.item)', 'true',
         'duplicate_claim_rejected'),
        ('combat/combat_state.gd', 'attacker.signature.health_damage', '0.0',
         'lunge_damage_posture_Pilgrimhit'),
        ('combat/combat_state.gd', 'attacker.hit_consumed = true', 'attacker.hit_consumed = false',
         'one_contact_per_lunge_Pilgrimhit'),
        # Equipment presentation: the bone must grow from the resolved (left) arm,
        # the lunge pose must follow the bone, and handedness must come from the build.
        ('characters/fighter_visual.gd', 'chest * Vector3(side * 0.42', 'chest * Vector3(0.42',
         'marrow_left_sword_right_visual_Pilgrim'),
        ('characters/presentation/pose_sampler.gd', '(bone_mirrored if authored_final else weapon_mirrored)', 'weapon_mirrored',
         'lunge_from_left_bone_sword_stays_right_Pilgrimhit'),
        ('characters/fighter_visual.gd', 'var mirrored: bool = look.weapon_side < 0.0', 'var mirrored: bool = look.marrow_side != 0.0',
         'marrow_left_sword_right_visual_Pilgrim'),
        ('builds/build_catalog.gd', 'return body_item_id.is_empty() or bool(items[body_item_id].anatomy.grip)', 'return true',
         'equipment_rules_reject_sword_in_marrow_hand'),
    ]
    results = []
    with tempfile.TemporaryDirectory(prefix='marrow-mutations-', dir=output) as temp:
        project = Path(temp)
        for name in ('scripts', 'scenes', 'data'):
            shutil.copytree(repo / name, project / name)
        shutil.copy2(repo / 'project.godot', project / 'project.godot')
        base = [engine, '--headless', '--path', str(project)]
        imported = subprocess.run(base + ['--editor', '--import'], capture_output=True, text=True, timeout=60)
        (output / 'import.log').write_text(imported.stdout + imported.stderr)
        assert imported.returncode == 0 and 'ERROR:' not in imported.stdout + imported.stderr
        for name, old, new, expected in mutations:
            target = project / 'scripts' / name
            source = target.read_text()
            assert source.count(old) == 1, (name, old)
            target.write_text(source.replace(old, new))
            try:
                result = subprocess.run(base + ['--script', 'res://scripts/qa/marrow_tests.gd'],
                                        capture_output=True, text=True, timeout=60)
                text = result.stdout + result.stderr
                (output / (expected + '.log')).write_text(text)
                records = [json.loads(line) for line in text.splitlines() if line.startswith('{')]
                failed = [r['check'] for r in records if r.get('passed') is False]
                assert result.returncode == 1 and 'ERROR:' not in text and expected in failed, (expected, result.returncode, failed)
                assert any(r.get('summary') and r['failed'] > 0 for r in records)
                results.append({'mutation': old + ' -> ' + new, 'caught_by': expected, 'exit': result.returncode})
            finally:
                target.write_text(source)
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'All {len(results)} Marrow mutation controls detected.')


if __name__ == '__main__':
    run(sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve())
