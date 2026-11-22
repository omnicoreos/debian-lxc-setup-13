#!/usr/bin/env python3
"""sudo python3 tests/terminal-regression.py: real su, isolated nobody home.

Only the user/terminal stage runs; no APT, accounts or real CLI downloads.
"""
import errno
import os
from pathlib import Path
import pty
import pwd
import select
import shlex
import shutil
import signal
import tempfile
import time

assert os.geteuid() == 0, 'Run with sudo to exercise the real su transition'
source = (Path(__file__).resolve().parents[1] / 'debian-lxc-setup.sh').read_text()
stage = source.split("<<'DEBIAN_STAGE'\n", 1)[1].split('\nDEBIAN_STAGE', 1)[0]
transition = next(line.strip() for line in source.splitlines() if 'exec su ' in line)
transition = transition.replace('--login debian ', '--login nobody ')
account = pwd.getpwnam('nobody')


def scenario(answers, fail_codex=False):
    home = Path(tempfile.mkdtemp(prefix='debian-lxc-terminal-'))
    child = None
    try:
        (home / '.local/bin').mkdir(parents=True)
        for name in ('.profile', '.bashrc'):
            (home / name).touch()
        curl = home / '.local/bin/curl'
        curl.write_text('''#!/bin/bash
case "$*" in
    *chatgpt.com*) name=codex ;;
    *claude.ai*) name=claude ;;
    *) exit 99 ;;
esac
if [[ $name == codex && -f "$HOME/fail-codex" ]]; then exit 22; fi
printf 'printf "#!/bin/sh\\\\necho %s-test-version\\\\n" > "$HOME/.local/bin/%s"\nchmod +x "$HOME/.local/bin/%s"\n' "$name" "$name" "$name"
''')
        curl.chmod(0o755)
        if fail_codex:
            (home / 'fail-codex').touch()
        for path in [home, *home.rglob('*')]:
            os.chown(path, account.pw_uid, account.pw_gid)
        # nobody has no home. Substitute only fixture HOME; retain the real su.
        fixture_stage = 'export HOME=' + shlex.quote(str(home)) + '\n' + stage
        wrapper = ('exec 3<>/dev/tty\nuser_stage=' + shlex.quote(fixture_stage)
                   + '\n' + transition)
        # Pipe the launcher itself, as wget does, while answers use the PTY.
        command = 'printf %s ' + shlex.quote(wrapper) + ' | bash'
        child, fd = pty.fork()
        if child == 0:
            os.execv('/bin/bash', ['bash', '-o', 'pipefail', '-c', command])
        output = ''
        sent = 0
        shell_sent = False
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], .2)[0]:
                continue
            try:
                chunk = os.read(fd, 65536).decode(errors='replace')
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output += chunk
            prompts = output.count('[y/N]: ') + output.count('Responde y o n.')
            if prompts > sent and sent < len(answers):
                os.write(fd, (answers[sent] + '\n').encode())
                sent += 1
            if 'Para salir de esta sesión' in output and not shell_sent:
                os.write(fd, b'test -t 0 && head -c 0 /dev/tty && printf "SHELL_UID=%s\\n" "$(id -u)"; exit\n')
                shell_sent = True
        else:
            raise AssertionError('Timeout: ' + output)
        _, status = os.waitpid(child, 0)
        child = None
        os.close(fd)
        assert os.waitstatus_to_exitcode(status) == 0, output
        assert f'SHELL_UID={account.pw_uid}' in output, output
        assert 'No such device' not in output, output
        assert 'no job control' not in output, output
        assert sent == len(answers), output
        if 'Y' in answers:
            expected = 'ERROR: Codex' if fail_codex else 'Codex instalado correctamente.'
            assert expected in output, output
            assert 'Claude Code instalado correctamente.' in output, output
        print(f'PASS real su + piped launcher + answers {answers} + final shell; fail_codex={fail_codex}')
    finally:
        if child:
            os.kill(child, signal.SIGTERM)
            os.waitpid(child, 0)
        shutil.rmtree(home)


scenario(['n', 'n'])
scenario(['invalid', 'Y', 'Y'])
scenario(['Y', 'Y'], fail_codex=True)
