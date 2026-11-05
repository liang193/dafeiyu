#!/usr/bin/env python3
"""Local deployment controller. Only url/start print the private control URL."""
import fcntl
import json
import os
import pathlib
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path('/var/lib/feiyu')
PID = ROOT / 'engine.pid'  # Compatibility with the previous launcher.
LOG = ROOT / 'logs/panel.log'
BINARY = '/opt/feiyu/source/dist/dafeiyu-linux/dafeiyu'
SERVICE = 'feiyu-engine.service'
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def running():
    result = subprocess.run(['systemctl', 'show', SERVICE, '--property=MainPID', '--value'],
                            capture_output=True, text=True)
    candidates = [result.stdout.strip()]
    if PID.exists():
        candidates.append(PID.read_text().strip())
    for value in candidates:
        try:
            pid = int(value)
            cmd = pathlib.Path(f'/proc/{pid}/cmdline').read_bytes()
            if pid > 1 and BINARY.encode() in cmd:
                return pid
        except (OSError, ValueError):
            pass
    return None


def url(timeout=40):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if running():
            lines = LOG.read_text(errors='replace').splitlines() if LOG.exists() else []
            for line in reversed(lines):
                if not line.startswith('QQ_CONTROL_URL='):
                    continue
                link = line.split('=', 1)[1].strip()
                parsed = urllib.parse.urlsplit(link)
                if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.fragment:
                    break
                origin = f'http://127.0.0.1:{parsed.port}'
                request = urllib.request.Request(origin + '/api/status',
                    headers={'X-QQ-Control': parsed.fragment})
                try:
                    with HTTP.open(request, timeout=2) as response:
                        json.load(response)
                    return link
                except (OSError, ValueError):
                    break
        time.sleep(.25)
    raise RuntimeError('主面板尚未就绪。请查看 Status-FeiYu.cmd 和本机私有日志。')


def wait_bridge(timeout=60):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with HTTP.open('http://127.0.0.1:6099/webui/', timeout=2) as response:
                if response.status == 200:
                    return
        except OSError:
            pass
        time.sleep(.5)
    raise RuntimeError('QQ 桥接登录页未就绪。主面板已保留，请在 Status-FeiYu.cmd 查看状态后重试。')


def stop_engine():
    subprocess.run(['systemctl', 'stop', SERVICE], check=True)
    pid = running()
    if pid:
        os.killpg(pid, signal.SIGTERM)
        deadline = time.monotonic() + 10
        while running() and time.monotonic() < deadline:
            time.sleep(.1)
        if running():
            raise RuntimeError('旧主面板尚未停止，请检查状态。')


def main(action):
    if action == 'start':
        subprocess.run(['systemctl', 'start', 'docker'], check=True)
        subprocess.run(['docker', 'start', 'feiyu-qq'], check=True, stdout=subprocess.DEVNULL)
        if not running():
            if not pathlib.Path(BINARY).is_file():
                raise RuntimeError('Linux 构建文件不存在。')
            subprocess.run(['systemctl', 'start', SERVICE], check=True)
        link = url()
        wait_bridge()
        parsed = urllib.parse.urlsplit(link)
        origin = f'http://127.0.0.1:{parsed.port}'
        headers = {'X-QQ-Control': parsed.fragment, 'Origin': origin, 'Content-Type': 'application/json'}
        with HTTP.open(urllib.request.Request(origin+'/api/status', headers=headers), timeout=5) as response:
            state = json.load(response)
        if state.get('savedModelKey') and not state.get('connected'):
            payload = json.dumps({'action':'connect', 'configurationRevision':state['configurationRevision']}).encode()
            with HTTP.open(urllib.request.Request(origin+'/api/action', data=payload, headers=headers), timeout=30) as response:
                json.load(response)
        print(link)
    elif action in ('stop', 'stop-panel'):
        stop_engine()
        if action == 'stop':
            subprocess.run(['docker', 'stop', 'feiyu-qq'], check=True, stdout=subprocess.DEVNULL)
        print('大肥鱼服务已停止。')
    elif action == 'url':
        print(url())
    elif action == 'status':
        print('主面板：' + ('运行中' if running() else '已停止'))
        result = subprocess.run(['systemctl', 'is-active', SERVICE], capture_output=True, text=True)
        print('后台托管：' + result.stdout.strip())
        subprocess.run(['docker', 'ps', '-a', '--filter', 'name=^/feiyu-qq$',
            '--format', '{{.Names}} {{.Status}} {{.Ports}}'], check=True)
    elif action in ('web-token', 'onebot-token'):
        cfg = ROOT / 'qq-runtime/config'
        if action == 'web-token':
            print(json.loads((cfg / 'webui.json').read_text())['token'])
        else:
            print(json.loads((cfg / 'onebot11.json').read_text())['network']['websocketServers'][0]['token'])
    else:
        raise RuntimeError('未知操作。')


if __name__ == '__main__':
    os.umask(0o077)
    try:
        ROOT.mkdir(parents=True, exist_ok=True)
        with (ROOT / 'manager.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            main(sys.argv[1] if len(sys.argv) > 1 else 'status')
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('启动器：' + message, file=sys.stderr)
        sys.exit(1)
