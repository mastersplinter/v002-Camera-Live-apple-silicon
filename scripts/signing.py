"""Validate Apple signing inputs without storing certificates or profiles in Git."""
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import subprocess

APP_ID = 'info.v002.CameraLive.AppleSilicon'
EXTENSION_ID = APP_ID + '.CameraExtension'

class Signing:
    def __init__(self):
        self.identity = os.environ.get('CAMERALIVE_SIGN_IDENTITY', '-')
        self.team = os.environ.get('CAMERALIVE_TEAM_ID', '')
        self.app_profile = os.environ.get('CAMERALIVE_APP_PROFILE', '')
        self.extension_profile = os.environ.get('CAMERALIVE_EXTENSION_PROFILE', '')
        self.enabled = self.identity != '-'
        supplied = self.team or self.app_profile or self.extension_profile
        if supplied and not self.enabled:
            raise ValueError('Set CAMERALIVE_SIGN_IDENTITY as well as the team and profiles, or omit all signing inputs for a local preview build.')
        self.group = (self.team or 'UNSIGNED') + '.' + APP_ID
        self.app_entitlements = {}
        self.extension_entitlements = {'com.apple.security.app-sandbox': True,
                                       'com.apple.security.application-groups': [self.group]}
        if self.enabled:
            if not re.fullmatch('[A-Z0-9]{10}', self.team):
                raise ValueError('CAMERALIVE_TEAM_ID must be the ten-character Apple Developer team ID.')
            identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
            matches = [(digest, name) for digest, name in re.findall(r'([A-Fa-f0-9]{40}) "([^"]+)"', identities)
                       if self.identity.upper() == digest.upper() or self.identity == name]
            if len(matches) != 1:
                raise ValueError('Select one valid signing identity installed with its private key; use its SHA-1 fingerprint if the name is ambiguous.')
            self.identity = matches[0][0].upper()
            app = self.profile(self.app_profile, APP_ID)
            extension = self.profile(self.extension_profile, EXTENSION_ID) if self.extension_profile else {}
            if not app.get('com.apple.developer.system-extension.install'):
                raise ValueError('The app profile must allow com.apple.developer.system-extension.install.')
            self.app_entitlements = {'com.apple.developer.system-extension.install': True,
                                     'com.apple.security.application-groups': [self.group],
                                     'com.apple.security.device.camera': True}
            for target, granted in [(self.app_entitlements, app), (self.extension_entitlements, extension)]:
                for key in ('com.apple.application-identifier', 'com.apple.developer.team-identifier', 'com.apple.security.get-task-allow'):
                    if key in granted: target[key] = granted[key]

    def profile(self, filename, bundle_id):
        if not filename or not Path(filename).is_file():
            raise ValueError(f'A provisioning profile is required for {bundle_id}. See VIRTUAL_CAMERA.md.')
        decoded = subprocess.check_output(['security', 'cms', '-D', '-i', filename])
        profile = plistlib.loads(decoded)
        expiration = profile.get('ExpirationDate')
        if expiration is None or expiration.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
            raise ValueError(f'Provisioning profile for {bundle_id} is expired or has no expiration date.')
        entitlements = profile.get('Entitlements', {})
        if self.team not in profile.get('TeamIdentifier', []):
            raise ValueError(f'Provisioning profile for {bundle_id} belongs to a different team.')
        prefixes = profile.get('ApplicationIdentifierPrefix', [self.team])
        if entitlements.get('com.apple.application-identifier') not in [prefix + '.' + bundle_id for prefix in prefixes]:
            raise ValueError(f'Provisioning profile does not match {bundle_id}. Use an explicit app identifier.')
        certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
        if self.identity not in certificates:
            raise ValueError(f'Provisioning profile for {bundle_id} does not authorize the selected signing certificate.')
        # TEAMID-prefixed macOS groups are authorized by the signing team, not
        # registered/provisioned like group.* identifiers. See Apple's Xcode
        # documentation, "Use app groups that you don't provision".
        return entitlements

    def sign(self, path, run, entitlements=None, identifier=None):
        args = ['codesign', '--force', '--sign', self.identity]
        if self.enabled: args += ['--options', 'runtime', '--timestamp']
        if identifier: args += ['--identifier', identifier]
        if entitlements: args += ['--entitlements', str(entitlements)]
        run(*args, path)
