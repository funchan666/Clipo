#!/usr/bin/env python3
"""Read getV2 and sync its AdMob App ID before Archive; never invent an ID."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--user-id', required=True, help='userId returned by the current visitor login')
    parser.add_argument('--lang', default='en')
    parser.add_argument('--time-zone', default='Asia/Shanghai')
    parser.add_argument('--input-languages', default='en-US')
    args = parser.parse_args()
    config = Path(__file__).resolve().parents[1] / 'Config' / 'Clipo.xcconfig'
    source = config.read_text()

    def setting(key):
        match = re.search(r'^' + re.escape(key) + r'\s*=\s*([^\n]+)$', source, re.M)
        if not match:
            raise ValueError('Missing build setting: ' + key)
        return match.group(1).strip()

    host = setting('CLIPO_API_HOST')
    if not re.fullmatch(r'[a-zA-Z0-9.-]+', host):
        raise ValueError('Invalid API host')
    command = ['curl', '--fail', '--silent', '--show-error', '--max-time', '20', '--get',
               'https://' + host + '/app-api/flow/release-package/getV2']
    query = {'platform': 'IOS', 'name': 'Clipo', 'version': setting('MARKETING_VERSION'),
             'lang': args.lang, 'userId': args.user_id, 'time': args.time_zone, 'input': args.input_languages}
    for key, value in query.items():
        command += ['--data-urlencode', key + '=' + value]
    result = json.loads(subprocess.run(command, check=True, capture_output=True, text=True).stdout)
    if result.get('code') != 0 or not isinstance(result.get('data'), dict):
        raise ValueError('getV2 did not return a successful configuration; no files changed')
    units = result['data'].get('adList')
    if not isinstance(units, list) or not units:
        raise ValueError('getV2 has no adList. Backend configuration is required; no files changed')
    app_ids = set()
    for ad_type in (1, 5):
        matches = [unit for unit in units if unit.get('adType') == ad_type
                   and str(unit.get('advertiser', '')).lower() == 'google']
        if len(matches) != 1:
            raise ValueError('Expected one Google placement for adType ' + str(ad_type))
        values = matches[0].get('config') or {}
        app_id = str(values.get('appId', '')).strip()
        unit_id = str(values.get('adUnitId', '')).strip()
        if not re.fullmatch(r'ca-app-pub-[0-9]{16}~[0-9]{10}', app_id):
            raise ValueError('Invalid remote App ID; no files changed')
        if not re.fullmatch(r'ca-app-pub-[0-9]{16}/[0-9]{10}', unit_id):
            raise ValueError('Invalid remote ad unit ID; no files changed')
        if app_id.split('~')[0] != unit_id.split('/')[0]:
            raise ValueError('App and ad unit belong to different publishers; no files changed')
        if app_id == 'ca-app-pub-3940256099942544~1458002511':
            sample = {1: 'ca-app-pub-3940256099942544/5575463023',
                      5: 'ca-app-pub-3940256099942544/1712485313'}
            if unit_id != sample[ad_type]:
                raise ValueError('Unexpected unit for the official demo App ID')
        app_ids.add(app_id)
    if len(app_ids) != 1:
        raise ValueError('App-open and rewarded placements must share the same App ID; no files changed')
    app_id = app_ids.pop()
    updated, count = re.subn(r'^CLIPO_GOOGLE_ADS_APP_ID\s*=.*$',
                            'CLIPO_GOOGLE_ADS_APP_ID = ' + app_id, source, flags=re.M)
    if count != 1:
        raise ValueError('Expected one App ID build setting; no files changed')
    updated = updated.replace('// Pending: getV2 currently omits adList. Retain the existing SDK identity only;\n'
                              '// runtime never falls back to sample ads when remote configuration is absent.',
                              '// Runtime validates this App ID against getV2 and uses its ad unit IDs.')
    # Write only after both placements have passed validation.
    with tempfile.NamedTemporaryFile(mode='w', dir=config.parent, delete=False) as temporary:
        temporary.write(updated)
        pending = Path(temporary.name)
    try:
        pending.chmod(config.stat().st_mode)
        os.replace(pending, config)
    finally:
        pending.unlink(missing_ok=True)
    print('AdMob App ID synchronized from getV2: ' + app_id)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error))
