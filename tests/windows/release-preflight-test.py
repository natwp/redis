#!/usr/bin/env python3
"""Run the actual workflow preflight against a local, closed GitHub API fixture."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[2]
MOCK_GH = r'''#!/usr/bin/env python3
import base64, json, os, sys
from urllib.parse import parse_qs, urlsplit
config = json.load(open(os.environ['PREFLIGHT_FIXTURE']))
args = sys.argv[1:]
if args[:2] == ['release', 'view']:
    sys.exit(0 if config.get('existing_release') else 1)
if not args or args[0] != 'api':
    raise SystemExit('Only read-only preflight API calls are allowed')
request = next(arg for arg in args if arg.startswith('/repos/'))
path = urlsplit(request).path.removeprefix('/repos/example/redis')
query = parse_qs(urlsplit(request).query)
lines = ['mingw-8.10', 'mingw-8.8', 'mingw-7.4', 'mingw-7.2', 'mingw-6.2']
versions = ['8.10.2', '8.8.3', '7.4.11', '7.2.16', '6.2.24']
revisions = ['1', '1', '1', '2', '2']
shas = [str(i + 1) * 40 for i in range(5)]
if path.startswith('/git/ref/heads/'):
    line = path.removeprefix('/git/ref/heads/')
    value = {'object': {'sha': 'f' * 40 if config.get('moved_tip') == line else shas[lines.index(line)]}}
elif path.startswith('/contents/'):
    sha = query['ref'][0]
    index = shas.index(sha)
    if path.endswith('version.h'):
        version = '0.0.0' if config.get('old_version') == lines[index] else versions[index]
        content = '#define REDIS_VERSION "' + version + '"\n'
    elif path.endswith('windows-revision'):
        if config.get('missing_revision') == lines[index]: sys.exit(1)
        content = config.get('source_revision', {}).get(lines[index], revisions[index]) + '\n'
    else:
        raise SystemExit('Unexpected contents request: ' + path)
    value = {'content': base64.b64encode(content.encode()).decode()}
elif path.startswith('/git/commits/'):
    value = {'tree': {'sha': 'b' * 40}}
elif path == '/immutable-releases':
    value = {'enabled': not config.get('mutable_releases', False)}
elif path.startswith('/git/ref/tags/'):
    if not config.get('existing_tag'): sys.exit(1)
    value = {'object': {'sha': 'a' * 40}}
elif path.startswith('/compare/'):
    value = {'status': 'ahead', 'files': [{'filename': config.get('control_file', '.github/workflows/release.yml')}]}
elif path == '/actions/workflows/full-validation.yml/runs':
    line = query['branch'][0]
    index = lines.index(line)
    value = [{'workflow_runs': [{'head_sha': 'f' * 40 if config.get('stale_run') == line else shas[index],
              'head_branch': line, 'event': 'push', 'status': 'completed',
              'conclusion': 'failure' if config.get('failed_run') == line else 'success',
              'run_number': 1, 'id': 100 + index, 'path': '.github/workflows/full-validation.yml'}]}]
elif path.startswith('/actions/runs/') and path.endswith('/artifacts'):
    index = int(path.split('/')[3]) - 100
    value = [{'artifacts': [{'name': 'windows-qualification-' + shas[index], 'expired': config.get('expired', False)}]}]
else:
    raise SystemExit('Unexpected API request: ' + request)
if '--jq' in args:
    expression = args[args.index('--jq') + 1]
    for key in expression.removeprefix('.').split('.'):
        value = value[key]
    print(json.dumps(value) if isinstance(value, bool) else value)
else:
    print(json.dumps(value))
'''


class ReleasePreflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="redis-preflight-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        mock = self.path / "gh"
        mock.write_text(MOCK_GH)
        mock.chmod(0o755)
        workflow = (ROOT / ".github/workflows/release.yml").read_text()
        marker = "      - name: Check exact source, version, tag, and all maintained-line tips"
        block = workflow.split(marker, 1)[1].split("        run: |\n", 1)[1].split("\n  attest:", 1)[0]
        self.script = textwrap.dedent(block)
        self.env = dict(os.environ, PATH=str(self.path) + os.pathsep + os.environ["PATH"],
                        PREFLIGHT_FIXTURE=str(self.path / "api.json"),
                        GITHUB_REPOSITORY="example/redis", GITHUB_REF_TYPE="branch",
                        GITHUB_REF_NAME="mingw-7.2", GITHUB_SHA="4" * 40,
                        GITHUB_OUTPUT=str(self.path / "outputs"), RUNNER_TEMP=str(self.path),
                        INPUT_SOURCE_BRANCH="mingw-7.2", INPUT_SOURCE_SHA="4" * 40,
                        INPUT_WINDOWS_REVISION="2", INPUT_CONFIRM_TAG="v7.2.16-windows.2")

    def verify(self, config=None, passed=False):
        (self.path / "api.json").write_text(json.dumps(config or {}))
        result = subprocess.run(["bash", "-c", self.script], env=self.env,
                                cwd=self.path, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, passed, result.stdout + result.stderr)
        if passed:
            self.assertIn("revision=2\n", (self.path / "outputs").read_text())

    def test_revision_two_push_qualification_is_selected(self):
        self.verify(passed=True)
        self.assertIn("qualification_run_id=103\n", (self.path / "outputs").read_text())

    def test_missing_and_invalid_source_revisions(self):
        for config in ({"missing_revision": "mingw-7.2"},
                       {"source_revision": {"mingw-7.2": "0"}},
                       {"source_revision": {"mingw-7.2": "1"}},
                       {"missing_revision": "mingw-7.4"}):
            with self.subTest(config=config):
                self.verify(config)

    def test_all_five_lines_must_be_updated_and_qualified(self):
        for key in ("stale_run", "failed_run", "old_version"):
            with self.subTest(key=key):
                self.verify({key: "mingw-7.4"})

    def test_moved_source_tip(self):
        self.verify({"moved_tip": "mingw-7.2"})

    def test_expired_artifact(self):
        self.verify({"expired": True})

    def test_existing_tags_and_releases_are_rejected(self):
        self.verify({"existing_tag": True})
        self.verify({"existing_release": True})

    def test_immutability_is_required(self):
        self.verify({"mutable_releases": True})

    def test_mismatched_tag_and_workflow_source(self):
        self.env["INPUT_CONFIRM_TAG"] = "v7.2.16-windows.1"
        self.verify()
        self.env["INPUT_CONFIRM_TAG"] = "v7.2.16-windows.2"
        self.env["GITHUB_SHA"] = "f" * 40
        self.verify()

    def test_control_ref_only_changes_release_workflow(self):
        self.env.update(GITHUB_REF_NAME="release/control-7.2", GITHUB_SHA="f" * 40)
        self.verify(passed=True)
        self.verify({"control_file": "src/server.c"})


if __name__ == "__main__":
    unittest.main()
