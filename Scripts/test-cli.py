#!/usr/bin/env python3
"""Exercise packaged CLI parsing/exit semantics without changing a real monitor.
Run swift test first to build the standalone debug executable.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
cli = root / '.build/debug/crg9-control'
listing = '''[1] C49RG9x (TEST-123)
 - Product name:  C49RG9x
 - Manufacturer:  SAM
 - AN Serial:     TEST-123
 - Display ID:    1
'''
with tempfile.TemporaryDirectory() as directory:
    helper = Path(directory) / 'fake-ddc'
    helper.write_text('#!/usr/bin/env python3\nimport sys\n'
                      + 'listing = ' + repr(listing) + '\n'
                      + 'print(listing if "list" in sys.argv else "Writing 10" if "set" in sys.argv else "9")\n')
    helper.chmod(0o755)
    env = dict(os.environ, CRG9_M1DDC_PATH=str(helper))
    cases = [(['input', 'dp2', '--display', 'TEST-123', '--json'], 3),
             (['input', 'dp1', '--display', 'TEST-123', '--json'], 0),
             (['input', 'hdmi', '--display', 'TEST-123', '--json', '--no-verify'], 0),
             (['status', '--display', 'absent', '--json'], 1),
             (['input', 'bad-input'], 2), (['--display'], 2)]
    for args, expected in cases:
        result = subprocess.run([str(cli), *args], env=env, capture_output=True, text=True)
        assert result.returncode == expected, (args, result.returncode, result.stderr, result.stdout)
        if '--json' in args:
            payload = json.loads(result.stdout)
            if expected == 3:
                assert payload['verified'] is False and payload['writeAccepted'] is True
            if '--no-verify' in args:
                assert 'verified' not in payload
        print('PASS', expected, ' '.join(args))
