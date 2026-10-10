"""Trusted manual iOS builds; signed outputs are retained only in a private repo."""
from __future__ import annotations

import argparse, base64, hashlib, json, os, plistlib, re, sys, tarfile, tempfile, time, zipfile
from pathlib import Path, PurePosixPath
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener, urlopen

import direct_iphone as direct
from github_ios import validate_inputs, validate_profile
from prepare_testflight import publisher_inputs

ROOT = direct.ROOT
BUILD_REPO = 'baewumnote-studio/gasleft-ios-public-build'
VAULT_REPO = 'baewumnote-studio/gasleft'


class NoCredentialRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('Private artifact API credentials cannot be redirected to another endpoint.')


def guard(environ):
    if (environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
            or environ.get('GITHUB_REPOSITORY') != BUILD_REPO
            or environ.get('GITHUB_REF') != 'refs/heads/main'
            or environ.get('GITHUB_ACTOR') != 'baewumnote-studio'
            or environ.get('GITHUB_TRIGGERING_ACTOR') != 'baewumnote-studio'):
        raise ValueError('Only the owner may manually build the exact main branch.')
    event = json.loads(Path(environ['GITHUB_EVENT_PATH']).read_text())
    if event.get('repository', {}).get('private') is not False:
        raise ValueError('Public standard-runner approval must be completed before any workflow runs.')
    mode = environ.get('GASLEFT_MODE')
    if mode not in {'unsigned', 'adhoc', 'testflight'}:
        raise ValueError('Choose unsigned, adhoc or testflight.')
    if not re.fullmatch(r'[1-9][0-9]{0,8}', environ.get('GASLEFT_BUILD_NUMBER', '')):
        raise ValueError('Use a positive build number of at most nine digits.')
    if environ.get('ADMOB_USE_TEST_ADS') not in {'true', 'false'}:
        raise ValueError('Choose a boolean test-ad mode.')
    if mode in {'unsigned', 'adhoc'} and environ.get('ADMOB_USE_TEST_ADS') != 'true':
        raise ValueError('Unsigned compilation and direct iPhone QA must use test ads.')
    if mode != 'unsigned' and (not re.fullmatch(r'[a-f0-9]{40}', environ.get('GITHUB_SHA', ''))
                              or environ.get('GASLEFT_UNSIGNED_VERIFIED_SHA') != environ['GITHUB_SHA']):
        raise ValueError('The exact source commit must pass the unsigned Mac build first.')
    direct.verify_source()


def vault_api(path, method='GET', payload=None, binary=None, content_type='application/json'):
    token = os.environ.get('GASLEFT_PRIVATE_ARTIFACT_TOKEN', '')
    if not token:
        raise ValueError('Set the expiring, single-private-repository artifact token before signing.')
    host = 'https://uploads.github.com/' if binary is not None else 'https://api.github.com/'
    req = Request(host + path, method=method,
                  data=binary if binary is not None else json.dumps(payload).encode() if payload is not None else None,
                  headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                           'X-GitHub-Api-Version': '2026-03-10', 'User-Agent': 'GasLeft-private-artifact-retention',
                           'Content-Type': content_type})
    # Only GitHub API/upload hosts are used; no signed redirect URLs are logged.
    with build_opener(NoCredentialRedirect()).open(req, timeout=120) as response:
        data = response.read()
        return json.loads(data) if data else {}


def private_vault():
    repo = vault_api('repos/' + VAULT_REPO)
    if repo.get('full_name') != VAULT_REPO or repo.get('private') is not True or not repo.get('permissions', {}).get('push'):
        raise ValueError('The signing output destination must be the exact writable PRIVATE GasLeft repo.')


def apple_app_check():
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    encode = lambda data: base64.urlsafe_b64encode(data).rstrip(b'=')
    key = serialization.load_pem_private_key(os.environ['GASLEFT_ASC_PRIVATE_KEY'].encode(), None)
    if not isinstance(key, ec.EllipticCurvePrivateKey) or not isinstance(key.curve, ec.SECP256R1):
        raise ValueError('Use the existing Apple ES256 API key.')
    header = encode(json.dumps({'alg': 'ES256', 'kid': os.environ['GASLEFT_ASC_KEY_ID'], 'typ': 'JWT'}).encode())
    claims = encode(json.dumps({'iss': os.environ['GASLEFT_ASC_ISSUER_ID'], 'iat': int(time.time()),
                                'exp': int(time.time()) + 300, 'aud': 'appstoreconnect-v1'}).encode())
    message = header + b'.' + claims
    r, s = decode_dss_signature(key.sign(message, ec.ECDSA(hashes.SHA256())))
    jwt = (message + b'.' + encode(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))).decode()
    app_id = os.environ['APP_STORE_APPLE_ID']
    def get(path):
        with urlopen(Request('https://api.appstoreconnect.apple.com/v1/' + path,
                             headers={'Authorization': 'Bearer ' + jwt}), timeout=30) as response:
            return json.load(response)
    app = get('apps/' + app_id)['data']
    if app['attributes'].get('bundleId') != direct.BUNDLE:
        raise ValueError('The real App Store app record must match GasLeft.')
    builds = get('builds?' + urlencode({'filter[app]': app_id, 'filter[version]': os.environ['GASLEFT_BUILD_NUMBER'], 'limit': '200'}))['data']
    if builds:
        raise ValueError('This App Store build number is already present; select an unused number.')


def preflight():
    guard(os.environ)
    if os.environ.get('GASLEFT_SIGNING_APPROVED') != 'true':
        raise ValueError('The owner must approve this repository and protected signing Environment.')
    private_vault()
    if os.environ['GASLEFT_MODE'] == 'adhoc':
        direct.preflight('openssl')
    else:
        validate_inputs(os.environ)
        profile = direct.decode_profile(base64.b64decode(os.environ['GASLEFT_PROFILE_BASE64'], validate=True), 'openssl')
        validate_profile(profile, direct.BUNDLE, direct.TEAM)
        if profile.get('Entitlements', {}).get('get-task-allow') is not False:
            raise ValueError('The App Store profile must explicitly disable debugging.')
        direct.check_p12(base64.b64decode(os.environ['GASLEFT_P12_BASE64'], validate=True),
                         os.environ['GASLEFT_P12_PASSWORD'], profile, 'openssl')
        apple_app_check()
    print('PASS: trusted source, actual signing inputs and private artifact destination checked before Mac allocation.')


def configure():
    guard(os.environ)
    if os.environ['GASLEFT_MODE'] in {'unsigned', 'adhoc'}:
        direct.configure()
    else:
        config = publisher_inputs(os.environ)
        # TestFlight and production share the verified real privacy page.
        direct.configure()
        sys.path.insert(0, str(ROOT / 'tools'))
        import assemble_flutter_ios as assembler
        assembler.patch_xcconfigs(ROOT, config['admob_app_id'])
        (ROOT / 'build/gasleft/release_dart_defines.json').write_text(json.dumps(config['defines']), encoding='utf-8')


def verify_store_ipa(path):
    config = publisher_inputs(os.environ)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if any(PurePosixPath(name).is_absolute() or '..' in PurePosixPath(name).parts or '\\' in name for name in names):
            raise ValueError('Unsafe IPA archive path.')
        infos = [n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2]
        if len(infos) != 1 or any('.appex/Info.plist' in n for n in names):
            raise ValueError('Expected one GasLeft app and no extension.')
        info = plistlib.loads(archive.read(infos[0]))
        if (info.get('CFBundleIdentifier') != direct.BUNDLE or info.get('CFBundleShortVersionString') != '1.0.0'
                or info.get('CFBundleVersion') != os.environ['GASLEFT_BUILD_NUMBER'] or info.get('MinimumOSVersion') != '15.0'
                or info.get('UIDeviceFamily') != [1] or info.get('GADApplicationIdentifier') != config['admob_app_id']):
            raise ValueError('Exported App Store app settings differ from the approved build.')
        profile = direct.decode_profile(archive.read(infos[0].removesuffix('Info.plist') + 'embedded.mobileprovision'), 'openssl')
        validate_profile(profile, direct.BUNDLE, direct.TEAM)
        if not any(hashlib.sha256(cert).hexdigest() == direct.CERT_SHA256 for cert in profile['DeveloperCertificates']):
            raise ValueError('Exported profile does not use the existing approved certificate.')
    with tempfile.TemporaryDirectory(dir=os.environ['RUNNER_TEMP']) as folder:
        temporary = Path(folder)
        direct.run(['ditto', '-x', '-k', path, temporary])
        app = temporary / infos[0].removesuffix('/Info.plist')
        direct.run(['codesign', '--verify', '--deep', '--strict', app], timeout=60)
        prefix = temporary / 'signer'
        direct.run(['codesign', '-d', '--extract-certificates=' + str(prefix), app])
        if hashlib.sha256(Path(str(prefix) + '0').read_bytes()).hexdigest() != direct.CERT_SHA256:
            raise ValueError('Exported App Store certificate differs.')
    archived = list((ROOT / 'build/ios/archive').glob('*.xcarchive/Products/Applications/*.app/Info.plist'))
    if len(archived) != 1:
        raise ValueError('Preserve exactly one original archive.')
    original = plistlib.loads(archived[0].read_bytes())
    if original.get('CFBundleIdentifier') != direct.BUNDLE or original.get('CFBundleVersion') != os.environ['GASLEFT_BUILD_NUMBER']:
        raise ValueError('Original archive identity mismatch.')
    report = {'ipaSha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'certificateSha256': direct.CERT_SHA256,
              'bundleId': direct.BUNDLE, 'version': '1.0.0', 'buildNumber': os.environ['GASLEFT_BUILD_NUMBER'],
              'codesignVerifiedOnMac': True, 'originalArchivePreserved': True, 'profileType': 'APP_STORE',
              'testAds': config['defines']['ADMOB_USE_TEST_ADS'] == 'true'}
    (ROOT / 'build/gasleft/ipa-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('PASS: actual exported App Store signature, profile, certificate and original archive verified.')


def verify_unsigned():
    guard(os.environ)
    app = ROOT / 'build/ios/iphoneos/Runner.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if (info.get('CFBundleIdentifier') != direct.BUNDLE or info.get('CFBundleShortVersionString') != '1.0.0'
            or info.get('CFBundleVersion') != os.environ['GASLEFT_BUILD_NUMBER']
            or info.get('UIDeviceFamily') != [1] or info.get('MinimumOSVersion') != '15.0'
            or (app / 'embedded.mobileprovision').exists() or not (app / 'Runner').is_file()):
        raise ValueError('Unsigned Release output must match GasLeft and contain no device profile.')
    print('PASS: unsigned native Release app compiled for the exact preserved GasLeft source commit.')
    print('Verified unsigned commit: ' + os.environ['GITHUB_SHA'])


def retain():
    private_vault()
    ipas = sorted((ROOT / 'build/ios/ipa').glob('*.ipa'))
    archive_root = ROOT / 'build/ios/archive'
    if not ipas and not archive_root.exists():
        print('No signed build output exists to retain.')
        return
    number = os.environ['GASLEFT_BUILD_NUMBER']
    tag = f"gasleft-{os.environ['GASLEFT_MODE']}-{number}-{os.environ['GITHUB_RUN_ID']}-{os.environ['GITHUB_RUN_ATTEMPT']}"
    # Releases are private because the destination is checked immediately before mutation.
    if len(ipas) > 1:
        raise ValueError('Expected at most one exported IPA.')
    release = vault_api('repos/' + VAULT_REPO + '/releases', 'POST',
                        {'tag_name': tag, 'target_commitish': 'main', 'name': tag, 'prerelease': True,
                         'body': 'Private signed output from ' + BUILD_REPO + ' commit ' + os.environ['GITHUB_SHA'] + '. Verification report is required before installation.'})
    release_id = release['id']
    files = [(p, 'gasleft-' + os.environ['GASLEFT_MODE'] + '-' + number + '.ipa') for p in ipas]
    report = ROOT / 'build/gasleft/ipa-verification.json'
    if report.exists():
        files.append((report, 'ipa-verification.json'))
    if archive_root.exists():
        out = Path(os.environ['RUNNER_TEMP']) / ('gasleft-' + number + '.xcarchive.tar.gz')
        with tarfile.open(out, 'w:gz') as archive:
            archive.add(archive_root, arcname='archive')
        files.append((out, out.name))
    hashes = {name: hashlib.sha256(p.read_bytes()).hexdigest() for p, name in files}
    manifest = Path(os.environ['RUNNER_TEMP']) / 'private-artifact-manifest.json'
    manifest.write_text(json.dumps({'sourceCommit': os.environ['GITHUB_SHA'], 'runId': os.environ['GITHUB_RUN_ID'],
                                    'verificationReportPresent': report.exists(), 'files': hashes}, indent=2), encoding='utf-8')
    files.append((manifest, manifest.name))
    for path, name in files:
        result = vault_api('repos/' + VAULT_REPO + '/releases/' + str(release_id) + '/assets?' + urlencode({'name': name}),
                           'POST', binary=path.read_bytes(), content_type='application/octet-stream')
        if result.get('state') != 'uploaded' or result.get('size') != path.stat().st_size:
            raise ValueError('Private artifact upload did not complete.')
    print('PASS: signed IPA, available verification report and original archive retained in the private GasLeft release.')
    print('Private release: ' + release['html_url'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['guard', 'preflight', 'configure', 'verify-store', 'verify-unsigned', 'retain'])
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'guard':
            guard(os.environ)
        elif args.action == 'verify-store':
            verify_store_ipa(args.ipa)
        elif args.action == 'verify-unsigned':
            verify_unsigned()
        else:
            globals()[args.action]()
    except (ValueError, KeyError, OSError, HTTPError, zipfile.BadZipFile) as error:
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        print('GasLeft protected build failed: ' + direct.redact(detail), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
