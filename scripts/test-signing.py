#!/usr/bin/env python3
"""Exercise profile validation with synthetic metadata; never use real keys."""
import copy
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from signing import Signing, APP_ID, EXTENSION_ID

TEAM = 'A123456789'
CERTIFICATE = b'synthetic-certificate-for-unit-test'
DIGEST = hashlib.sha1(CERTIFICATE).hexdigest().upper()

class SigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / 'app.provisionprofile'
        self.path.touch()
        self.environment = {'CAMERALIVE_SIGN_IDENTITY': DIGEST, 'CAMERALIVE_TEAM_ID': TEAM,
                            'CAMERALIVE_APP_PROFILE': str(self.path)}
        self.profile = {'ExpirationDate': datetime.datetime(2099, 1, 1),
                        'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
                        'DeveloperCertificates': [CERTIFICATE],
                        'Entitlements': {'com.apple.application-identifier': TEAM + '.' + APP_ID,
                                         'com.apple.developer.team-identifier': TEAM,
                                         'com.apple.developer.system-extension.install': True}}

    def build(self, profile=None):
        data = plistlib.dumps(self.profile if profile is None else profile)
        def output(args, **kwargs):
            return f'1) {DIGEST} "Developer ID Application: Test ({TEAM})"' if args[1] == 'find-identity' else data
        with patch.dict(os.environ, self.environment, clear=True), patch('signing.subprocess.check_output', side_effect=output):
            return Signing()

    def test_team_prefixed_group_needs_no_profile_group_or_extension_profile(self):
        signing = self.build()
        self.assertTrue(signing.enabled)
        self.assertEqual(signing.extension_entitlements['com.apple.security.application-groups'], [TEAM + '.' + APP_ID])
        self.assertTrue(signing.app_entitlements['com.apple.developer.system-extension.install'])

    def test_expired_profile_is_rejected(self):
        self.profile['ExpirationDate'] = datetime.datetime(2000, 1, 1)
        with self.assertRaisesRegex(ValueError, 'expired'): self.build()

    def test_wrong_team_or_app_is_rejected(self):
        for key, value in [('TeamIdentifier', ['Z123456789']), ('Entitlements', {'com.apple.application-identifier': TEAM + '.' + EXTENSION_ID})]:
            with self.subTest(key=key):
                profile = copy.deepcopy(self.profile); profile[key] = value
                with self.assertRaises(ValueError): self.build(profile)

    def test_profile_must_include_actual_signing_certificate(self):
        self.profile['DeveloperCertificates'] = [b'another certificate']
        with self.assertRaisesRegex(ValueError, 'certificate'): self.build()

    def test_install_capability_is_required(self):
        del self.profile['Entitlements']['com.apple.developer.system-extension.install']
        with self.assertRaisesRegex(ValueError, 'system-extension.install'): self.build()

    def test_legacy_app_prefix_can_differ_from_team(self):
        self.profile['ApplicationIdentifierPrefix'] = ['OLDPREFIX1']
        self.profile['Entitlements']['com.apple.application-identifier'] = 'OLDPREFIX1.' + APP_ID
        self.assertTrue(self.build().enabled)

    def test_partial_configuration_cannot_masquerade_as_signed(self):
        with patch.dict(os.environ, {'CAMERALIVE_TEAM_ID': TEAM}, clear=True):
            with self.assertRaises(ValueError): Signing()
        with patch.dict(os.environ, {}, clear=True):
            self.assertFalse(Signing().enabled)

if __name__ == '__main__': unittest.main()
