# Camera Live virtual camera

The new output is a macOS Core Media IO camera extension. After Apple signing, notarization, installation and macOS approval, video apps can select **Camera Live** as a camera without an OBS/Syphon bridge. The existing preview and Syphon output remain available.

## Current build status

The implementation is included in the app and the extension is packaged under `Contents/Library/SystemExtensions`. A default local build is ad-hoc signed and **cannot activate the virtual camera**. It still supports the USB camera, preview and Syphon. Native camera-extension activation and Zoom capture require the Apple signing setup below, followed by a live acceptance test. Compilation or tests alone do not establish Zoom compatibility on this Mac.

## Signing setup

Use an Apple Developer Program team with a valid signing certificate **and its private key installed in this Mac's login keychain**. A Developer ID Application identity is the intended route for an app used outside the App Store. A certificate file without its corresponding private key is not sufficient. Keep private keys out of Git.

To prepare a new signing request, run `python3 scripts/prepare-signing.py`. This creates a public `.certSigningRequest` and a matching private key in the ignored, permission-restricted `.signing` directory. Upload only the request to Apple when creating a Developer ID Application certificate. Keep the matching key; do not regenerate it after requesting the certificate. Import the resulting Apple certificate and the matching key into the login keychain before building. `security find-identity -v -p codesigning` must list a valid identity.

Use these macOS identifiers with the same team:

| Item | Identifier / capability |
| --- | --- |
| Containing app | Register `info.v002.CameraLive.AppleSilicon` with the System Extension capability |
| Camera extension | `info.v002.CameraLive.AppleSilicon.CameraExtension` |
| Shared macOS app group | `TEAMID.info.v002.CameraLive.AppleSilicon` — replace `TEAMID` with your ten-character team ID |

Create/download a Developer ID provisioning profile for the app and its signing certificate. It must grant `com.apple.developer.system-extension.install`. The team-prefixed macOS app group does not require portal registration or inclusion in a profile: macOS authorizes it through the signing team. The extension uses only the sandbox and this group, so its provisioning profile is optional. If supplied, the builder validates and embeds it. The extension receives frames through a Core Media IO sink stream rather than accessing the USB camera itself.

Set these environment variables in the terminal used to build (the paths and team below are examples to replace):

```sh
export CAMERALIVE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export CAMERALIVE_TEAM_ID='YOURTEAMID'
export CAMERALIVE_APP_PROFILE='/path/to/CameraLive.provisionprofile'
# Optional, if your signing workflow provides an extension profile:
# export CAMERALIVE_EXTENSION_PROFILE='/path/to/CameraLiveExtension.provisionprofile'
python3 scripts/build-app.py
```

The builder validates the installed identity and each supplied profile's identifier, team, expiry and authorized certificate before building. It signs every bundled dependency, the camera extension and the containing app with the same identity, embeds the profiles, and verifies the resulting signatures. It rejects partial signing configuration instead of silently producing an installable-looking unsigned build. Provisioning profiles and private-key exports are ignored by Git.

### Notarization

Developer ID system extensions must be notarized before activation with normal macOS security settings, including this local installation. Store notarization credentials interactively in your login keychain (never put an Apple password in source files or chat):

```sh
xcrun notarytool store-credentials CameraLive --apple-id 'YOUR_APPLE_ACCOUNT' --team-id 'YOURTEAMID'
python3 scripts/notarize-app.py --keychain-profile CameraLive
```

`notarytool` prompts for an Apple app-specific password. The helper submits the signed app, checks for Apple's Accepted result, staples and validates the ticket, and checks Gatekeeper acceptance. It saves results in `.build/notary`. Neither certificate issuance nor notarization has been completed merely by building the default ad-hoc app.

## First use

1. Copy the signed, notarized **Camera Live.app** to `/Applications` and open that copy.
2. Connect/select the Canon 550D as usual.
3. Click **Enable Virtual Camera**. Approve Camera Live when macOS requests it. On current macOS this is under **System Settings → General → Login Items & Extensions → Camera Extensions**; older macOS versions place approval in Privacy & Security.
4. In Zoom's video settings, choose **Camera Live**. Reopen Zoom if its device list was already open before installation.
5. On subsequent launches, click **Start Virtual Camera**. **Stop Virtual Camera** stops broadcasting; the Camera Live menu can remove the installed extension.

The output supports 1280 × 720 and 1920 × 1080 BGRA at a 30 Hz delivery cadence. Open **Stream Details** (⇧⌘I), then select **Framing** to choose the canvas; the default is a centred fill crop with no added black margins. Zoom and horizontal/vertical positioning adjust the crop without stretching or exposing space outside the source. Settings persist, the preview matches the virtual-camera crop, and Syphon retains the uncropped source. Video apps can request either advertised resolution; the extension resizes the composed image if the consumer chooses a different size. Changing the canvas briefly restarts the producer stream. A 24 fps camera still provides 24 distinct motion frames per second; repeating the latest frame does not interpolate motion. There is no audio output. A stopped/disconnected/stalled camera switches to a standby image instead of leaving the last camera image frozen. The app and extension each enforce a half-second freshness timeout; normal stop closes the sink immediately, while independent stalls can add both timeouts plus a delivery tick.

## Validation

`python3 scripts/test-signing.py` checks signing configuration with synthetic profile data; Swift tests cover format/timestamps, stale input, crop geometry and pixels, persisted settings, and publisher stop/recovery and canvas changes. The packaged diagnostic's `--virtual-frame-test` verifies GPU and CPU pixels at both resolutions, upright orientation, borderless filling, and immutable in-flight buffers. Add `--standby-image /path/to/standby.png` to inspect the standby text visually. Use `--virtual-camera-test --canvas 1080p` to check the installed 1080p stream, or add `--receive-canvas 720p` to verify consumer resizing. Stop the app's virtual camera before running that diagnostic.

After installation, run `"/Applications/Camera Live.app/Contents/MacOS/camera-live-diagnostics" --virtual-camera-test` with the app's virtual output stopped. It feeds a known pattern through the real CMIO sink and captures it through AVFoundation, checking orientation, dimensions, monotonic timestamps and standby output after stopping. This does not substitute for the actual Canon/Zoom acceptance check.

Before declaring the feature ready for Zoom, verify the signed installed extension with all of these checks:

- Camera Live appears in AVFoundation and Zoom's camera selection.
- Actual Canon 550D video has correct orientation, proportions, colours and cadence in Zoom.
- A second consumer can use it concurrently; closing one consumer does not stop the other.
- Stop/start, camera disconnect, app quit and stalled input produce the standby image and recover cleanly.
- Uninstall removes Camera Live from the system camera list.

The app/extension use Apple's supported system-extension route. Do not disable System Integrity Protection or weaken Zoom's signature to install this feature.

## Apple references

- [Creating a camera extension with Core Media I/O](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)
- [Installing system extensions and drivers](https://developer.apple.com/documentation/systemextensions/installing-system-extensions-and-drivers)
- [System Extensions — signing and notarization requirements](https://developer.apple.com/documentation/systemextensions)
- [Accessing app group containers — team-prefixed macOS groups](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [Create camera extensions with Core Media IO — source and sink streams](https://developer.apple.com/videos/play/wwdc2022/10022/)
