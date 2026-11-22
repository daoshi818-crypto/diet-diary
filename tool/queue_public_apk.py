"""Queue an authorized APK for public distribution using a repository-scoped key."""
import json, os, pathlib, re, shlex, subprocess, tempfile
import urllib.request, urllib.error, urllib.parse

PUBLIC_REPO = 'daoshi818-crypto/chiyoushu-food-data'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def api(route, binary=False):
    request = urllib.request.Request('https://api.github.com/' + route, headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'Accept': 'application/octet-stream' if binary else 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
    })
    if binary:
        try:
            response = urllib.request.build_opener(NoRedirect).open(request, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code != 302: raise RuntimeError('APK redirect unavailable') from None
            response = error
        url = response.headers.get('Location', '')
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != 'https' or parsed.hostname not in ('release-assets.githubusercontent.com', 'objects.githubusercontent.com'):
            raise RuntimeError('Unexpected APK asset host')
        return url
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)

def main():
    source = os.environ['GH_REPO']
    number = int(os.environ['RUN_NUMBER'])
    release = api('repos/' + source + '/releases/tags/apk-' + str(number))
    asset = next(a for a in release['assets'] if a['name'] == 'diet-diary.apk')
    update = json.loads(pathlib.Path('dist/UPDATE.json').read_text())
    if asset['size'] != update['bytes']: raise RuntimeError('APK size mismatch')
    payload = {'schemaVersion': 1, 'runNumber': number, 'sourceCommit': os.environ['HEAD_SHA'],
               'update': update, 'apkUrl': api('repos/' + source + '/releases/assets/' + str(asset['id']), binary=True),
               'buildInfo': json.loads(pathlib.Path('dist/BUILD_INFO.json').read_text())}
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        key = root / 'deploy-key'
        key.write_text(os.environ['PUBLIC_APK_DEPLOY_KEY'].strip() + '\n')
        key.chmod(0o600)
        known = root / 'known-hosts'
        known.write_text(''.join('github.com ' + key + '\n' for key in api('meta')['ssh_keys']))
        env = dict(os.environ, GIT_SSH_COMMAND='ssh -i ' + shlex.quote(str(key)) +
                   ' -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=' + shlex.quote(str(known)))
        checkout = root / 'public'
        subprocess.run(['git', 'clone', '--depth=1', '--branch=main', 'git@github.com:' + PUBLIC_REPO + '.git', str(checkout)], env=env, check=True)
        request = checkout / 'publication/request.json'
        request.parent.mkdir(exist_ok=True)
        request.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
        def git(*args): subprocess.run(['git', '-C', str(checkout), *args], env=env, check=True)
        git('config', 'user.name', 'github-actions[bot]')
        git('config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
        git('add', 'publication/request.json')
        git('commit', '-m', 'chore: publish Android ' + update['version'] + ' (' + str(update['versionCode']) + ')')
        git('push', 'origin', 'HEAD:main')
    print('Queued public APK ' + update['version'] + ' (' + str(update['versionCode']) + ')')

if __name__ == '__main__': main()
