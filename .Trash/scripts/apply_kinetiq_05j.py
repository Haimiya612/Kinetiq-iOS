#!/usr/bin/env python3
"""Apply Batch 05J to an existing Kinetiq-iOS checkout.

No network, credentials or Git operations. Fails closed when exact source
anchors change; does not overwrite the player's stream-resolution implementation.

Usage:
    python3 scripts/apply_kinetiq_05j.py --check
    python3 scripts/apply_kinetiq_05j.py --apply
"""

import argparse
import datetime as dt
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / 'Kinetiq/Features/Modules/ModuleRuntime.swift'
INSTALLER = ROOT / 'Kinetiq/Features/Modules/ModulePackageManager.swift'
PROJECT = ROOT / 'Kinetiq.xcodeproj/project.pbxproj'
NOTES = ROOT / 'release-notes.json'
REQUIRED_NEW_FILES = [
    ROOT / 'Kinetiq/Features/Modules/ModuleDiscoverySupport.swift',
    ROOT / 'Kinetiq/Features/Modules/ModuleDiscoveryViews.swift',
    ROOT / 'KinetiqTests/ModuleDiscoveryContractTests.swift',
]

NEW_FILES = [
    ('C2B05A1D82F84BE6A31F1001', 'C2B05A1D82F84BE6A31F1002', 'ModuleDiscoverySupport.swift'),
    ('C2B05A1D82F84BE6A31F1003', 'C2B05A1D82F84BE6A31F1004', 'ModuleDiscoveryViews.swift'),
    ('C2B05A1D82F84BE6A31F1005', 'C2B05A1D82F84BE6A31F1006', 'ModuleDiscoveryContractTests.swift'),
]


def replace_once(text: str, old: str, new: str, description: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise ValueError(f'{description}: expected 1 source anchor, found {count}. '
                         'Update manually after reviewing upstream changes.')
    return text.replace(old, new, 1)


def update_module_runtime(text: str) -> str:
    old = '    // The documented Synthetiq video contract has no trending/home handler.\n'
    if old in text:
        text = replace_once(text, old,
            '    // Source-provided discovery_v1 rows supplement saved content and search.\n',
            'discovery contract comment')
    old2 = '    // Explore therefore uses actual saved catalogue entries and explicitly\n'
    if old2 in text:
        text = replace_once(text, old2,
            '    // Older modules can still browse through the existing search shortcuts.\n',
            'explore fallback comment')
    old3 = '    // labeled search shortcuts, never manufactured trending/rating data.\n'
    if old3 in text:
        text = replace_once(text, old3,
            '    // Catalogue cards and source labels remain unchanged.\n',
            'explore labels comment')
    anchor = ('            VStack(alignment: .leading, spacing: 12) {\n'
              '                Label("Explore by search", systemImage: "sparkle.magnifyingglass")')
    insertion = ('''            if let runtime {
                KinetiqSourceDiscoveryView(
                    runtime: runtime,
                    sourceID: source.id,
                    sourceName: source.title
                )
            }

''' + anchor)
    return replace_once(text, anchor, insertion, 'source Home integration')


def update_installer(text: str) -> str:
    old = '''        guard contractVersion >= 3 else {
            throw ModulePackageError.invalidManifest(
                "The module must use contract version 3 or later."
            )
        }'''
    new = '''        // Known Player JS packages use V3 or V4. A future contract is
        // not automatically compatible just because the JSON decoder accepts it.
        guard (3...4).contains(contractVersion) else {
            throw ModulePackageError.invalidManifest(
                "Kinetiq currently supports video module contracts V3 and V4."
            )
        }'''
    return replace_once(text, old, new, 'bounded module contract versions')


def update_project(text: str) -> str:
    if NEW_FILES[0][0] in text:
        # Refuse an incomplete prior patch rather than duplicating references.
        for ref, build, _ in NEW_FILES:
            if ref not in text or build not in text:
                raise ValueError('Project file contains a partial 05J registration')
        return text
    app_refs = NEW_FILES[:2]
    test_ref = NEW_FILES[2]
    refs = ''.join(
        f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = "{name}"; sourceTree = "<group>"; }};\n'
        for ref, _, name in NEW_FILES
    )
    builds = ''.join(
        f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; '
        f'fileRef = {ref} /* {name} */; }};\n'
        for ref, build, name in NEW_FILES
    )
    anchor_ref = '\t\tD16B2E4F8A6C0D3E5F7A9B12 /* ModuleRuntime.swift */ = {isa = PBXFileReference;'
    text = replace_once(text, anchor_ref, refs + anchor_ref, 'PBX file references')
    anchor_build = '\t\tE27C3F5A9B7D1E4F6A8C0B23 /* ModuleRuntime.swift in Sources */ = {isa = PBXBuildFile;'
    text = replace_once(text, anchor_build, builds + anchor_build, 'PBX build references')

    old = 'D0A1B2C3D4E5F60718293A4B); path = Modules;'
    new = ('D0A1B2C3D4E5F60718293A4B, '
           + ', '.join(ref for ref, _, _ in app_refs)
           + '); path = Modules;')
    text = replace_once(text, old, new, 'Modules group')

    old = ('E27C3F5A9B7D1E4F6A8C0B23, '
           'E1B2C3D4E5F60718293A4B5C); '
           'runOnlyForDeploymentPostprocessing = 0;')
    new = (old.replace('); runOnlyForDeploymentPostprocessing',
           ', ' + ', '.join(build for _, build, _ in app_refs)
           + '); runOnlyForDeploymentPostprocessing'))
    text = replace_once(text, old, new, 'App target sources')

    old = '7A1A2A3A4A5A4A6A7A8A9A05); path = "KinetiqTests";'
    new = ('7A1A2A3A4A5A4A6A7A8A9A05, '
           f'{test_ref[0]}); path = "KinetiqTests";')
    text = replace_once(text, old, new, 'Test group')

    old = ('7A1A2A3A4A5A4A6A7A8A9A06); '
           'runOnlyForDeploymentPostprocessing = 0;')
    new = (old.replace('); runOnlyForDeploymentPostprocessing',
            f', {test_ref[1]}); runOnlyForDeploymentPostprocessing'))
    text = replace_once(text, old, new, 'Test target sources')
    return text


def update_release_notes(text: str) -> str:
    data = json.loads(text)
    if any(item.get('version') == '0.4.0' for item in data.get('releases', [])):
        return text
    data['releases'].append({
        'version': '0.4.0', 'date': '2026-11-08',
        'title': 'Your sources, brought to life',
        'notes': [
            {'symbol': 'rectangle.stack.fill', 'title': 'Source-powered Home',
             'detail': 'See genuine shelves supplied by compatible anime modules.'},
            {'symbol': 'arrow.right.circle', 'title': 'Explore entire feeds',
             'detail': 'Open source-advertised feeds and load additional pages.'},
            {'symbol': 'checkmark.shield', 'title': 'Module compatibility',
             'detail': 'Installer now explicitly accepts tested V3/V4 module contracts.'},
            {'symbol': 'heart', 'title': 'Your playback preserved',
             'detail': 'Existing AniWorld and other source playback code is unchanged.'}
        ]
    })
    return json.dumps(data, indent=2, ensure_ascii=False) + '\n'


def update_build_version(text: str) -> str:
    if 'MARKETING_VERSION = 0.4.0;' in text:
        return text
    if text.count('MARKETING_VERSION = 0.3.0;') != 2:
        raise ValueError('Expected 0.3.0 in both iOS build configurations')
    if text.count('CURRENT_PROJECT_VERSION = 3;') != 2:
        raise ValueError('Expected build 3 in both iOS build configurations')
    return text.replace('MARKETING_VERSION = 0.3.0;',
                        'MARKETING_VERSION = 0.4.0;').replace(
                        'CURRENT_PROJECT_VERSION = 3;', 'CURRENT_PROJECT_VERSION = 4;')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check', action='store_true')
    mode.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if not all(p.is_file() for p in REQUIRED_NEW_FILES):
        print('Missing new Swift files. Copy the ZIP contents into the repository root first.', file=sys.stderr)
        return 2

    originals = {}
    replacements = {}
    try:
        for path in [MAIN, INSTALLER, PROJECT, NOTES]:
            originals[path] = path.read_text(encoding='utf-8')
        replacements[MAIN] = update_module_runtime(originals[MAIN])
        replacements[INSTALLER] = update_installer(originals[INSTALLER])
        project = update_project(originals[PROJECT])
        replacements[PROJECT] = update_build_version(project)
        replacements[NOTES] = update_release_notes(originals[NOTES])
        changed = [p for p in replacements if replacements[p] != originals[p]]
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f'Upgrade preflight failed without modifying files: {exc}', file=sys.stderr)
        return 2

    print(f'Batch 05J preflight OK: {len(changed)} files to update')
    for path in changed:
        print('  ', path.relative_to(ROOT))
    if args.check:
        return 0
    if not changed:
        print('Already applied; no changes necessary.')
        return 0

    backup_root = ROOT / '.kinetiq-upgrade-backups' / dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    for path in changed:
        backup = backup_root / path.relative_to(ROOT)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
    for path in changed:
        path.write_text(replacements[path], encoding='utf-8')
    print(f'Applied. Originals backed up in {backup_root.relative_to(ROOT)}/')
    print('Next: run xcodebuild / GitHub Actions CI before shipping this version.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
