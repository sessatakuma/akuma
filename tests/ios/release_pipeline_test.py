"""Exercise release commands with fake Xcode; never signs, installs, or uploads."""
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ReleasePipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='akuma-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.directory = pathlib.Path(self.temp.name)
        self.bin = self.directory / 'bin'
        self.bin.mkdir()
        self.log = self.directory / 'calls.jsonl'
        self.artifacts = self.directory / 'release with spaces'
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('IOS_', 'ASC_', 'APPLE_', 'AKUMA_TEST_'))}
        self.env.update(PATH=str(self.bin) + ':' + os.environ['PATH'], APPLE_TEAM_ID='ABCDE12345',
                        IOS_MARKETING_VERSION='1.2.3', IOS_BUILD_NUMBER='42', IOS_RELEASE_DIR=str(self.artifacts),
                        AKUMA_TEST_LOG=str(self.log), AKUMA_TEST_ROOT=str(ROOT), IOS_LOCAL_ENV_FILE='/dev/null')
        xcode = self.bin / 'xcodebuild'
        xcode.write_text('#!' + sys.executable + '\n' + '''
import json, os, pathlib, plistlib, shutil, sys
args = sys.argv[1:]
if args == ['-version']:
    print('Mock Xcode'); sys.exit(0)
with open(os.environ['AKUMA_TEST_LOG'], 'a') as f: f.write(json.dumps(args)+'\\n')
if os.environ.get('AKUMA_TEST_FAIL') == '1': sys.exit(1)
if 'archive' in args:
    archive = pathlib.Path(args[args.index('-archivePath')+1])
    app = archive / 'Products/Applications/Akuma.app'
    app.mkdir(parents=True)
    settings = dict(a.split('=',1) for a in args if '=' in a)
    info = {'CFBundleIdentifier':'dev.sessatakuma.akuma','CFBundleShortVersionString':settings['MARKETING_VERSION'],
            'CFBundleVersion':settings['CURRENT_PROJECT_VERSION'],'UIDeviceFamily':[1,2],
            'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'UIRequiresFullScreen':True}
    with (app/'Info.plist').open('wb') as f: plistlib.dump(info,f)
    shutil.copy(pathlib.Path(os.environ['AKUMA_TEST_ROOT'])/'apps/ios/Akuma/PrivacyInfo.xcprivacy',app)
else:
    with open(args[args.index('-exportOptionsPlist')+1],'rb') as f: options=plistlib.load(f)
    with open(os.environ['AKUMA_TEST_LOG'],'a') as f: f.write(json.dumps(options)+'\\n')
''')
        xcode.chmod(0o755)

    def run_action(self, action, success=True, **overrides):
        result = subprocess.run(['bash', str(ROOT / 'scripts/ios-release.sh'), action],
                                env=self.env | overrides, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    @property
    def app(self):
        return self.artifacts / 'Akuma.xcarchive/Products/Applications/Akuma.app'

    def test_config_check_never_builds_or_uploads(self):
        self.run_action('check')
        self.assertEqual(self.calls(), [])

    def test_local_settings_load_without_executing_shell(self):
        settings = self.directory / '.env.local'
        marker = self.directory / 'must-not-exist'
        settings.write_text(
            '  # Local signing configuration\nAPPLE_TEAM_ID="LOCAL12345"\n'
            "IOS_BUILD_NUMBER='99'\n"
            f'ASC_KEY_ID=$(touch {marker})\n'
            'UNRELATED_SETTING=ignored\n')
        env = self.env | {'IOS_LOCAL_ENV_FILE': str(settings)}
        env.pop('APPLE_TEAM_ID')
        command = 'source "$1"; printf "%s\\n" "$APPLE_TEAM_ID" "$IOS_BUILD_NUMBER" "$ASC_KEY_ID" "${UNRELATED_SETTING-unset}"'
        result = subprocess.run(['bash', '-eu', '-c', command, 'test',
                                 str(ROOT / 'scripts/ios-common.sh')],
                                env=env, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines(),
                         ['LOCAL12345', '42', f'$(touch {marker})', 'unset'])
        self.assertFalse(marker.exists())

    def test_invalid_build_and_partial_credentials_fail_early(self):
        for build in ['', '0', '../42', '10000', '3;touch /tmp/no']:
            self.run_action('archive', False, IOS_BUILD_NUMBER=build)
        self.run_action('archive', False, ASC_KEY_ID='PARTIAL')
        self.assertEqual(self.calls(), [])

    def test_archive_is_release_and_preserves_version_record(self):
        self.run_action('archive')
        args = self.calls()[0]
        self.assertEqual(args[args.index('-configuration')+1], 'Release')
        self.assertIn('SWIFT_ACTIVE_COMPILATION_CONDITIONS=', args)
        self.assertIn('CURRENT_PROJECT_VERSION=42', args)
        self.assertEqual(json.loads((self.artifacts/'release.json').read_text())['build'], '42')
        self.run_action('archive', False)
        self.assertEqual(len(self.calls()), 1)

    def test_export_stays_local_and_upload_uses_same_build(self):
        self.run_action('archive')
        self.run_action('export')
        self.assertEqual(self.calls()[-1]['destination'], 'export')
        self.run_action('upload')
        options = self.calls()[-1]
        self.assertEqual(options['destination'], 'upload')
        self.assertFalse(options['manageAppVersionAndBuildNumber'])
        self.assertTrue(options['uploadSymbols'])
        self.run_action('upload', False, IOS_MARKETING_VERSION='2.0.0')

    def test_missing_or_failed_archive_does_not_upload(self):
        self.run_action('upload', False)
        self.assertEqual(self.calls(), [])
        self.run_action('archive', False, AKUMA_TEST_FAIL='1')
        self.assertEqual(len(self.calls()), 1)
        self.assertFalse((self.artifacts/'release.json').exists())

    def test_app_contract_rejects_landscape_and_missing_manifest(self):
        self.run_action('archive')
        info_path = self.app/'Info.plist'
        with info_path.open('rb') as f: info = plistlib.load(f)
        info['UISupportedInterfaceOrientations~ipad'] = ['UIInterfaceOrientationLandscapeLeft']
        with info_path.open('wb') as f: plistlib.dump(info,f)
        self.run_action('upload', False)
        info.pop('UISupportedInterfaceOrientations~ipad')
        with info_path.open('wb') as f: plistlib.dump(info,f)
        (self.app/'PrivacyInfo.xcprivacy').unlink()
        self.run_action('upload', False)
        self.assertEqual(len(self.calls()), 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
