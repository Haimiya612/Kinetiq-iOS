#!/usr/bin/env python3
"""Line-by-line static audit of the eight Synthetiq-family public repositories.

Reads JavaScript/Swift/Dart/config/docs and bounded ZIP source entries, recording
file paths, line numbers and pattern types without copying secrets or stream URLs.
Static-only: NOT a claim of iPhone playback, vulnerability or rights certification.

Usage: python3 scripts/audit_8_repos.py --root audit-workspace --out audit-results
"""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile, BadZipFile

REPOS = [
    'synthetiq-manga-sources', 'Synthetiq-Modules', 'AROKI-Connectors',
    'Testing-Modules-1-2-3-4', 'Module-Testing-PL', 'Testing-Modules-AR',
    'AnyGo-Sources', 'Kinetiq-Modules',
]
SOURCE_EXTENSIONS = {
    '.js', '.mjs', '.cjs', '.swift', '.dart', '.ts', '.tsx', '.json',
    '.py', '.sh', '.yml', '.yaml', '.md', '.txt',
}
PATTERNS = {
    'fetchv2_bridge': re.compile(r'\bfetchv2\s*\('),
    'interactive_page_bridge': re.compile(r'\bpagev2\s*\('),
    'discovery_home': re.compile(r'\bdiscoveryHome\b'),
    'discovery_feed': re.compile(r'\bdiscoveryFeed\b'),
    'search_handler': re.compile(r'\bsearchResults\b'),
    'stream_handler': re.compile(r'\bextractStreamUrl\b'),
    'chapter_handler': re.compile(r'\bextractChapters\b'),
    'image_handler': re.compile(r'\bextractImages\b'),
    'manual_redirect': re.compile(r'followRedirects'),
    'stream_headers': re.compile(r'\bstreamHeaders\b|\brequestHeaders\b'),
    'network_host_policy': re.compile(r'\ballowedHosts\b|\bhostAllowlist\b'),
    'browser_execution_review': re.compile(r'\beval\s*\(|\bnew\s+Function\s*\('),
    'plain_http_review': re.compile(r'http://(?!127\.0\.0\.1|localhost)'),
    'loopback_review': re.compile(r'127\.0\.0\.1|localhost|0\.0\.0\.0'),
    'embedded_credential_review': re.compile(r'(?i)(?:api[_-]?key|bearer|authorization|secret|password)\s*[:=]'),
}
MAX_TEXT_BYTES = 2_500_000
MAX_ARCHIVE_UNCOMPRESSED_BYTES = 30_000_000
MAX_ARCHIVE_MEMBERS = 1_000
MAX_EVIDENCE_PER_RULE = 350


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def scan(root: Path):
    results = []
    for repo in REPOS:
        base = root / repo
        result = {'name': repo, 'present': base.is_dir(), 'scannedFiles': 0,
                  'scannedLines': 0, 'skippedFiles': 0, 'archivesScanned': 0,
                  'archiveEntriesScanned': 0, 'archiveErrors': [], 'jsonErrors': [],
                  'ruleCounts': {}, 'findings': [], 'manifests': []}
        if not base.is_dir():
            results.append(result)
            continue
        counters = Counter()

        def scan_text(rel: str, data: bytes):
            result['scannedFiles'] += 1
            extension = Path(rel).suffix.lower()
            decoded = data.decode('utf-8', errors='replace')
            if extension == '.json':
                try:
                    obj = json.loads(decoded)
                except json.JSONDecodeError as exc:
                    result['jsonErrors'].append({'path': rel, 'line': exc.lineno, 'message': exc.msg})
                else:
                    if Path(rel).name in ('module.json', 'manifest.json', 'connector.json') and isinstance(obj, dict):
                        result['manifests'].append({
                            'path': rel,
                            'id': obj.get('id') or obj.get('moduleId'),
                            'version': obj.get('moduleVersion') or obj.get('version'),
                            'contractVersion': obj.get('contractVersion'),
                            'contentType': obj.get('contentType'),
                            'sha256': sha256(data),
                        })
            for index, line in enumerate(decoded.splitlines(), 1):
                result['scannedLines'] += 1
                for rule, pattern in PATTERNS.items():
                    if pattern.search(line):
                        counters[rule] += 1
                        if counters[rule] <= MAX_EVIDENCE_PER_RULE:
                            result['findings'].append({'rule': rule, 'file': rel, 'line': index})

        for path in sorted(base.rglob('*')):
            if not path.is_file() or '.git' in path.parts or 'node_modules' in path.parts:
                continue
            rel = path.relative_to(base).as_posix()
            suffix = path.suffix.lower()
            if suffix in SOURCE_EXTENSIONS and path.stat().st_size <= MAX_TEXT_BYTES:
                scan_text(rel, path.read_bytes())
            elif suffix == '.zip':
                # Source archives in the Player catalogues contain nested
                # module.json and index.js. Scan these without executing JS.
                budget = MAX_ARCHIVE_UNCOMPRESSED_BYTES
                try:
                    with ZipFile(path) as archive:
                        if len(archive.infolist()) > MAX_ARCHIVE_MEMBERS:
                            raise ValueError('too many archive entries')
                        result['archivesScanned'] += 1
                        for member in archive.infolist():
                            member_path = Path(member.filename)
                            if (member.is_dir() or member.flag_bits & 1 or
                                    member_path.is_absolute() or '..' in member_path.parts or
                                    member.filename.startswith('\\') or ':' in member.filename or
                                    member_path.suffix.lower() not in SOURCE_EXTENSIONS or
                                    member.file_size > MAX_TEXT_BYTES or
                                    member.file_size > budget):
                                continue
                            budget -= member.file_size
                            scan_text(f'{rel}!{member.filename}', archive.read(member))
                            result['archiveEntriesScanned'] += 1
                except (OSError, ValueError, BadZipFile) as exc:
                    result['archiveErrors'].append({'path': rel, 'error': type(exc).__name__})
            else:
                result['skippedFiles'] += 1
        result['ruleCounts'] = dict(sorted(counters.items()))
        results.append(result)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    data = {'generatedUTC': datetime.now(timezone.utc).isoformat(),
            'limitations': ('Static pattern matches need manual review. '
                            'No media URL, credential, source snippet or user history is exported. '
                            'Archive reading is bounded. No iPhone playback certification.'),
            'repositories': scan(Path(args.root))}
    (out / 'source-audit.json').write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    lines = ['# Eight-repository source audit', '',
             'Static review leads only; **not** playback, security or rights certification.', '',
             '| Repository | Files read | Lines | ZIPs | ZIP source members | JSON errors |',
             '|---|---:|---:|---:|---:|---:|']
    for r in data['repositories']:
        lines.append(f'| {r["name"]} | {r["scannedFiles"]} | {r["scannedLines"]:,} | '
                     f'{r["archivesScanned"]} | {r["archiveEntriesScanned"]} | {len(r["jsonErrors"])} |')
    lines.extend(['', '## Pattern occurrences by repository', '',
                  'Counts are leads for review, not vulnerability findings.', ''])
    for r in data['repositories']:
        lines.append(f'### {r["name"]}')
        if not r['present']:
            lines.append('Repository was not present in the checkout folder.\n')
            continue
        for name, count in r['ruleCounts'].items():
            lines.append(f'- `{name}`: {count}')
        lines.append('')
    lines.extend(['## Exact line references', '',
                  'See `source-audit.json` for repository-relative paths and precise line numbers '
                  '(including `archive.zip!index.js`). Source lines are intentionally omitted.'])
    (out / 'source-audit.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print('Wrote', out / 'source-audit.md')
    print('Wrote', out / 'source-audit.json')


if __name__ == '__main__':
    main()
