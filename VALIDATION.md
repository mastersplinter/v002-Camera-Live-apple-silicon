# Validation

## Release 2.4.2, 15 October 2026

Version 2.4.2/build 18 packages the smaller minimum window, combined controls popover, inspector cleanup and compact virtual-camera button accepted by the user in build 17. The executable source is unchanged from the accepted installation; only release version/build metadata changed. The camera extension remains 2.4.0/build 10.

- All 31 Swift tests across eight suites and all seven signing-configuration tests passed for this release. Native interface checks covered 21 layout scenarios and 12 extended toolbar cases, described below; the user accepted the delivered interface.
- The signed arm64 release passed architecture/dependency and platform-version audits and deep/strict signature verification. Apple accepted notarization `10e69120-1858-4237-8ae3-529a821da480`; its ticket was stapled and validated, and Gatekeeper accepted the app.
- The extracted `dist/releases/2.4.2/Camera-Live-2.4.2-arm64.zip` passed signature, notarization-ticket and Gatekeeper checks. Every file and symlink matches the signed build. SHA-256: `3297346fb5045f365580e3c8544f8249a8ce112f0ef66599e5af0801139f3e0d`.
- The extension retains CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`. Fresh live Canon/Zoom output was not independently retested for these interface-only changes.

## Compact virtual-camera button rendering, 15 October 2026

The user reported continuing movement in build 16 despite earlier stable outer-frame measurements. Version 2.4.1/build 17 uses one standard bordered compact button for both Start and Stop, with identical 56 × 40-point toolbar allocation and implicit animations disabled. The compact item explicitly hides its shared toolbar glass background, avoiding a second glass surface around the control. The full-width action retains its prior appearance. Apple's [standard button styles](https://developer.apple.com/documentation/SwiftUI/PrimitiveButtonStyle/borderedProminent) and [toolbar background API](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)) informed this adjustment.

- The baseline diagnostic still did not reproduce the reported jitter. This change removes a possible rendering/animation cause; the underlying cause was not independently confirmed.
- The extended native review uses generated moving images at approximately 30 Hz, statistics updates every six frames, the app's actual menu-command definitions, and samples of toolbar view frames plus descendant layer positions, bounds, transforms and animation keys. Across 180 samples per case at widths 240, 240.5, 319.5, 400, 599 and 600, with virtual output both on and off, all 12 cases showed no layout/layer movement or overflow. The 240- and 240.5-point cases began with the test app active and window key; the later cases ran after the app lost focus. Start and Stop both measured 56 × 40 below 600 points. The test display's backing scale was 1.0. Results: `.build/jitter-review/samples.txt`; baseline: `.build/jitter-review/before-build16.txt`.
- The signed arm64 package passed the build, architecture/dependency, platform-version and deep/strict signature checks. Apple accepted notarization `cf258956-9440-4658-bbd8-81724d867ace`; the ticket was stapled and validated, and Gatekeeper accepted the bundle. The extension remains build 10 with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`; the executable and resource signature match the signed build, and the installed process was observed after launch. Build 16 is retained under `.build/installed-backup-2.4.1-build16`.
- The user subsequently accepted the delivered interface as "perfect" and requested publication. This is user-reported visual acceptance; a fresh Canon/Zoom or physical-pointer hover test was not independently performed. Build 17 was the installed preview; release 2.4.2/build 18 packages the accepted changes.

## Smaller minimum and inspector cleanup, 15 October 2026

Version 2.4.1/build 16 reduces the minimum content area from 400 × 240 to 240 × 135 points, measured as a 240 × 187 native window including the title bar. Below 320 points wide, the controls popover combines Stream, Framing and Cameras so the virtual-camera action can remain visible. Wider windows retain separate camera/stream controls. The close button beside the Stream/Framing picker is removed; the toolbar toggle still closes the inspector, and popovers dismiss outside their bounds. Very short empty/error states can scroll to keep their actions reachable.

- An isolated native review compiled the production views and passed 21 layout scenarios, including the new minimum, narrow/tall and short/wide windows, all three popover pages, closing with the toolbar toggle, crossing the 320-point threshold with a popover open, and shrinking with regular panels open. The generated-image Metal preview submitted a 240 × 135 drawable at the minimum. Both the notice and empty-state areas expose scroll views in the shortest error case. Results: `.build/mini-review/results.txt`.
- With camera statistics changing five times per second, native toolbar views and their presentation layers stayed fixed across 90 samples per case at widths 240, 241, 319, 320, 400, 599, 600 and 1080, with output enabled and disabled (16 cases). Every expected control remained visible with no overflow. Results: `.build/toolbar-review/samples.txt`. These are simulated-camera layout checks, not a fresh Canon/Zoom or screenshot-based visual acceptance test.
- The signed arm64 bundle passed architecture, dependency, platform-version and deep/strict signature checks. Apple accepted notarization `546a642a-2ca9-477b-ba62-db07bfa632f7`; the ticket was stapled and validated, and Gatekeeper accepted the bundle.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`, preserving build 15 under `.build/installed-backup-2.4.1-build15`. The installed executable matches the signed build, and its running process was verified after launch completed.
- The camera extension remains 2.4.0/build 10, with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`. The published 2.4.1 release remains build 14.

## Compact toolbar stability, 15 October 2026

Version 2.4.1/build 15 gives toolbar items stable identities and moves the virtual-camera button into a separate view that observes only virtual-camera state. Its compact icon label has explicit dimensions before native button measurement. Windows narrower than 600 points omit the title from the toolbar, keeping room for Cameras, Stream Details and the virtual-camera action; larger windows restore the title and full action label.

- The isolated native review reproduced the Start action disappearing into toolbar overflow at the 400-point minimum width. The reported continuous jiggle was not independently reproduced by the baseline frame sampler, so this is a measured correction of the crowded layout plus isolation from frequent camera-statistics updates, not a before/after visual recording of that symptom.
- The corrected production views were exercised with simulated camera statistics changing five times per second. All three toolbar controls stayed visible, without overflow or frame/presentation-layer movement, across 90 samples per case at widths 400, 401, 599, 600, 700 and 1080 with the virtual camera both on and off (12 cases). Results are in `.build/toolbar-review/samples.txt`.
- The existing native resize review also passed all 16 scenarios, including Cameras, Stream and Framing popovers and shrinking with panels open. The minimum window remains 400 × 292 including the title bar. These checks use generated images and simulated output state; they do not establish a fresh Canon/Zoom video or user-visible jitter acceptance check.
- The signed arm64 package passed the architecture, dependency, platform-version and deep/strict signature checks. Apple accepted notarization `ec1607f4-b433-427a-b33a-80e117ef0fa4`; the ticket was stapled and validated, and Gatekeeper accepted the installed app.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`, retaining the previous build under `.build/installed-backup-2.4.0-build13`. The camera extension remains 2.4.0/build 10 with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`. The published 2.4.1 release remains build 14.

## Release 2.4.1, 15 October 2026

Version 2.4.1/build 14 packages the Cameras panel cleanup and compact-window interface tested in builds 12 and 13 below. The application changes from build 13 are release version/build metadata only; the user accepted the delivered update and requested publication.

- All 31 Swift tests across eight suites and all seven signing-configuration tests passed for this release. The compact interface was exercised in 16 native layout states as described below.
- The signed arm64 release passed architecture/dependency and platform-version audits and deep/strict signature verification. Apple accepted notarization `b074c71e-97a4-48f0-a495-2f7a1a742bf0`; its ticket was stapled and validated, and Gatekeeper accepted the app.
- The extracted `dist/releases/2.4.1/Camera-Live-2.4.1-arm64.zip` passed signature, notarization-ticket and Gatekeeper checks and matches the signed build's executables and resource signature. SHA-256: `11bf32b265d317f8c74fbd73ad1575fcdaff91617af8ddd8d87aaa1f738cc169`.
- The bundled camera extension remains 2.4.0/build 10 with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`. Fresh live Canon/Zoom output was not independently retested for these interface-only changes.

## Compact window resizing, 15 October 2026

Version 2.4.0/build 13 reduces the minimum content size from 760 × 480 to 400 × 240 points (400 × 292 including the native toolbar on this Mac). Below 700 points wide or 400 points tall, the preview uses the window and Cameras/Stream/Framing open in native toolbar popovers. Narrow windows use an icon-only virtual-camera button; short empty states and scrollable notices keep their actions reachable. Returning to a larger window restores the native split layout.

- An isolated native SwiftUI review app compiled the current view sources with simulated camera/output controllers and exercised 16 layout states: normal and minimum size, Stream and Framing popovers, switching to Cameras, empty preview and error notice, short/wide and narrow/tall windows, the regular-layout boundary with both panels open, and shrinking with panels open. The minimum remained 400 × 292 and opening compact popovers did not enlarge the main window. An initial sheet-based approach enlarged the window and was replaced before installation.
- The actual Metal preview view submitted the synthetic image at normal and minimum sizes; the minimum-size drawable was 400 × 225 with the correct 16:9 ratio. Review output is in `.build/resize-review/results.txt`. These are local layout/rendering checks, not a fresh Canon/Zoom or screenshot-based visual acceptance check.
- The signed native release passed architecture/dependency and platform-version audits and deep/strict signature verification. Apple accepted notarization `4a46a298-53ab-41fa-973d-10c5ef77b3f6`; the ticket was stapled and validated, and the installed app passed Gatekeeper assessment.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`, retaining build 12 under `.build/installed-backup-2.4.0-build12`. The extension remains build 10 with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`. The published 2.4.0 release remains build 11.

## Cameras panel cleanup, 15 October 2026

Version 2.4.0/build 12 removes the Sharing section, virtual-camera status and Zoom guidance from the Cameras sidebar. Camera selection and refresh actions, and the Stream inspector, are unchanged.

- The native release build, architecture/dependency and platform-version audits, and deep/strict signature verification passed. This view-only removal did not require new tests or a full camera regression run.
- Apple accepted notarization `0e8b8650-f0e9-48b6-bc68-9e586c263b25`. The ticket was stapled and validated, and the installed app passed Gatekeeper assessment.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`, retaining build 11 under `.build/installed-backup-2.4.0-build11`. The camera extension remains build 10 with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`.
- On-screen appearance and fresh live-camera/Zoom output were not independently checked for this sidebar-only update. The published 2.4.0 release remains build 11.

## macOS 26 interface refinements, 15 October 2026

Version 2.4.0/build 10 requires macOS 26 for both the host and camera extension. The older split-pane inspector fallback is removed. The interface uses the system title bar and window buttons, automatic toolbar styling, a native Liquid Glass primary action, and a Stream-first inspector that resets to Stream when reopened. The crop toolbar button, bottom status bar and requested explanatory text are removed.

The previous installed host's Mach-O header reported both `minos 13.0` and `sdk 13.0`, despite compilation using a newer SDK. The build wrapper now passes the selected SDK version explicitly to the linker. The package builder audits the deployment and SDK stamps for the host, diagnostic and extension, and rejects SDKs older than 26. This release reports `minos 26.0` and `sdk 27.0` on all three executables, matching the selected Command Line Tools SDK. Window buttons remain native system controls; their final appearance is a manual on-screen check.

- All 31 regression tests across eight suites passed on this macOS 26.7.1 Apple Silicon Mac.
- The signed release diagnostic passed GPU and CPU checks at 720p and 1080p: upright orientation, borderless fill, immutable in-flight buffers and standby output.
- The arm64 release, embedded dependency audit, deployment/SDK audit and deep/strict signature verification passed. Apple accepted notarization `0b534ddb-3973-4964-be1e-eb6acf8e83ba`; the ticket was stapled and validated, and Gatekeeper accepted the installed app as Notarized Developer ID.
- Installed and reopened `/Applications/Camera Live Apple Silicon.app`; the previous 2.3.0 app is retained under `.build/installed-backup-2.3.0`.
- The reopened app delivered ten live Canon EOS 550D Metal frames at 1056 × 704 to an independent read-only Syphon receiver. No camera images were saved.
- Initial build 10 ZIP (superseded and retained under `.build/replaced-release-2.4.0-build10/Camera-Live-2.4.0-arm64.zip`), SHA-256 `39a02fe6496bc3c5304fa63aa44177d859e40aef504df205647ce177a916f391`. Its separately extracted archive passed signature verification and matched the then-installed app. No GitHub publication was requested for this update.

At the initial post-install check, macOS still had extension 2.2.0/build 8 activated. macOS subsequently confirmed 2.4.0/build 10 **activated and enabled**. The user rejected build 10's appearance and supplied a screenshot showing a full-width grey strip across the loading preview. Build 10 therefore did not pass visual acceptance.

The host-only build 11 correction explicitly hides the automatic toolbar background while preserving native glass controls and the established inspector placement. An isolated SwiftUI review app using the same view source and a simulated loading state confirmed the full-width titlebar background views are hidden, while glass controls and 14 × 14-point system window buttons remain. Bitmap rendering omits native glass/SwiftUI layers in this environment, so that evidence establishes view visibility, not a screenshot-based visual pass. A forced small-window check reported oversized split-view frames and potential inspector-header overlap with either inspector placement; the sizing experiments did not resolve that result and were not added to production. Final on-screen confirmation, including small-window resizing, remains necessary.

- The final build 11 passed the arm64/dependency and platform-version audits and deep/strict signature verification. Apple accepted notarization `f22d5d8d-2d7d-4664-9fe2-4b8f12fe8c0d`; the ticket was stapled and validated, and the installed app passed Gatekeeper assessment.
- Installed and reopened build 11, preserving build 10 under `.build/installed-backup-2.4.0-build10`. The camera extension remains 2.4.0/build 10, with unchanged CodeDirectory hash `b0d31a735387c7211d5655f2a3874cdafc875d1d`; macOS still reports it **activated and enabled**.
- Final ZIP: `dist/releases/2.4.0/Camera-Live-2.4.0-arm64.zip`, SHA-256 `1690917a19108553dfe8485e1e4c76ed78c09f39b2fc42567a8b0e51593f4f1f`. The separately extracted archive passed signature verification and matches the installed host, diagnostic, extension executable and resource signature.
- The user has been asked to check that the grey bar is gone, the inspector looks correct and the Zoom picture still works. Those final on-screen results are pending.
- The post-install Syphon receiver received no frames. A follow-up process/USB check confirmed build 11 was running but no Canon device was present in the USB registry. The user has been asked to wake or reconnect the camera; live-video verification for build 11 is pending and no pass is claimed.

The user subsequently accepted the update ("that's great") and requested committing and publishing it to their personal GitHub repository. This records acceptance of the delivered update; it does not establish a fresh independent live-camera or Zoom check, or resolve the small-window diagnostic concern above. The release package is the same notarized build 11 installed for that review.

## Focus interface, 15 October 2026

Version 2.3.0/build 9 implements the selected Focus design with a native navigation split view, a collapsible camera sidebar, a prominent virtual-camera toolbar action, a compact status footer and a Framing/Stream inspector. Framing changes remain visible beside the preview. Native controls provide system appearance and accessibility adaptations; macOS 13 retains a split-pane inspector fallback.

Design references reviewed: Apple’s [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) and [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars). The implementation removes custom navigation backgrounds and uses system components. Camera selection is exposed on first launch; returning users open the Focus preview with a sidebar toggle available.

- All 31 regression tests across eight suites passed with native video-buffer access. The packaged diagnostic passed GPU and CPU checks for upright, borderless 720p/1080p output and buffer ownership.
- The arm64 release build, embedded dependency audit and deep/strict signature verification passed. Apple accepted notarization `ac066e56-b789-413d-8bf6-712f9e26d533`; the ticket was stapled and validated, and Gatekeeper accepted the installed app as Notarized Developer ID.
- The host is 2.3.0/build 9; the camera extension remains 2.2.0/build 8. Its CodeDirectory hash is unchanged (`c5152852f891a1121740e726a1b7081617f8eb69`), and macOS still reports it **activated and enabled**. The host checks the enabled extension version before requesting a replacement.
- Installed at `/Applications/Camera Live Apple Silicon.app`, retaining the previous app under `.build/installed-backup-2.2.0`. The extracted archive, installed app and build output match for both executables, the extension executable and resource signature.
- Packaged ZIP: `dist/releases/2.3.0/Camera-Live-2.3.0-arm64.zip`, SHA-256 `324d92c5e7e8b7a5a38df55845173a2ae068db555458e7930b6fb06073a91753`. No GitHub publication was requested for this update.
- An isolated app-owned review harness rendered the Focus preview with a clearly labelled simulated image at 1080-point width. Native glass/sidebar/inspector layers produced invalid bitmap captures in this environment, so these captures do not establish full visual acceptance. No real camera image or other application screen was captured. macOS 13 runtime behaviour, Reduce Transparency, VoiceOver interaction and full on-screen appearance remain manual checks.

The user checked the installed Focus layout, Framing inspector and live Zoom picture and explicitly confirmed: “Yes, layout and Zoom both work”. This is user-reported on-screen acceptance for 2.3.0. After an initial receiver attempt found no frames during restart, a subsequent read-only Syphon receiver obtained ten live Canon EOS 550D frames at 1056 × 704 from the reopened app. No source-selection change was needed.

Following that confirmation, an independent AVFoundation receiver passed eight-second live checks at both sizes. Each received 239 frames at 30.00 fps with zero invalid frames: 720p had 188 distinct sampled frames and a maximum timestamp gap of 37.9 ms; 1080p had 186 distinct sampled frames and a maximum gap of 37.2 ms. These measure the virtual camera’s delivery, not Zoom’s internal frame rate. No camera images were saved. Long-duration operation remains outside this check.

## Canvas and framing, 15 October 2026

Version 2.2.0/build 8 adds 720p/1080p canvases, default aspect-fill cropping, saved zoom/pan controls, a matching cropped preview, and multi-format camera-extension delivery. The original Syphon feed is unchanged.

- All 31 Swift tests across eight suites passed with native macOS video-buffer access. New checks cover the 550D's exact centred crop (1056 × 594 from 1056 × 704), portrait/wide sources, all pan limits, saved-setting validation, pixel colours/orientation at both output sizes, consumer resizing, and crop/canvas changes while publishing.
- The signed release diagnostic passed GPU and CPU pixel checks for 720p and 1080p, including upright orientation, filled edges, retained-buffer immutability and standby output.
- The native arm64 package passed its architecture/dependency audit and deep/strict signature verification. Both app and extension are version 2.2.0/build 8.
- The generated-pattern preview attempt published 748 frames at 30.00 fps, but the current desktop session presented zero drawable frames. Consequently, the on-screen preview check did **not** pass; no visual UI or on-screen pacing validation is claimed for this build.
- After the user's explicit approval, Apple accepted notarization `a485141a-8325-4c66-84be-ac6fc1048662`. The ticket was stapled and validated. The installed `/Applications/Camera Live Apple Silicon.app` passed deep/strict signature verification and Gatekeeper assessment as Notarized Developer ID. Its packaged GPU/CPU checks passed again after installation.
- Version 2.2.0/build 8 is installed and macOS reports its extension **activated and enabled**. The previous 2.1.1 app is retained under `.build/installed-backup-2.1.1`. The reopened app delivered ten live Canon EOS 550D frames at 1056 × 704 to the separate Syphon receiver. The first activation retained the old extension connection and required reopening the host, as with the previous release.
- The notarized ZIP is `dist/releases/2.2.0/Camera-Live-2.2.0-arm64.zip`, SHA-256 `09822fd09979830633451616af6b44d859915035ece1e9e7a414fdcba48b00e6`. It has not been published to GitHub.

The initial 720p diagnostic received 1080p buffers because an AVFoundation session preset does not by itself constrain video-data output dimensions on macOS. The receiver now explicitly requests width and height in `videoSettings` and reports the actual format/pixels when a check fails. The camera-extension code did not require a correction. With the host producer stopped and Zoom still open, the installed extension passed these generated-pattern checks:

| Producer canvas | Receiver output | Live frames | Standby frames after stop | Steady delivery | Maximum gap |
| --- | --- | --- | --- | --- | --- |
| 1280 × 720 | 1280 × 720 | 180 | 30 | 30.00 fps | 36.19 ms |
| 1920 × 1080 | 1920 × 1080 | 180 | 30 | 30.00 fps | 38.11 ms |
| 1920 × 1080 | 1280 × 720 | 180 | 30 | 29.99 fps | 87.74 ms |
| 1280 × 720 | 1920 × 1080 | 180 | 30 | 30.02 fps | 36.80 ms |

All four checks verified upright colours and filled edges with no invalid frames or gaps over 100 ms. These establish the real signed source/sink path through the extension sandbox and AVFoundation at both requested delivery sizes. AVFoundation can negotiate or scale frames when other consumers share the device; the checks do not imply independent hardware formats for every simultaneous client.

After the final reinstall/reopen, a read-only receiver obtained 239 valid 720p frames and 240 valid 1080p frames. Each run had only one distinct sampled frame, consistent with standby while awaiting the GUI start action; neither run established changing live Canon video. No camera images were saved. The installed app, separately extracted archive, and build output matched for the host executable, diagnostic executable, extension executable, and resource signature.

After starting the virtual camera and checking Framing and Zoom, the user explicitly confirmed: “Yes, the picture fills the canvas”. This establishes the requested borderless Zoom picture on this Mac as a user-reported acceptance result for 2.2.0. A subsequent read-only AVFoundation check independently received changing live video at both resolutions:

| Receiver output | Frames | Distinct sampled frames | Invalid frames | Delivery | Maximum timestamp gap |
| --- | --- | --- | --- | --- | --- |
| 1280 × 720 | 239 | 147 | 0 | 30.00 fps | 36.0 ms |
| 1920 × 1080 | 239 | 155 | 0 | 29.88 fps | 66.7 ms |

These eight-second checks measured delivery from the installed virtual camera, not Zoom's internal frame rate. No camera images were saved. The user confirmation and changing-frame checks complete the live acceptance check; the automated on-screen preview limitation above still applies. Long-duration operation remains outside this check.

## Virtual camera connection investigation, 15 October 2026

macOS now reports the Camera Live 2.1.0/build 3 extension as **activated and enabled**, and exposes both its video source and input sink. The earlier activation blocker is resolved.

The reported “Open virtual-camera input failed (0)” was reproduced: `CMIOStreamCopyBufferQueue` with a null callback returned success with no queue. Registering a callback returned a valid queue. The transport now registers that callback and unregisters it on shutdown or failed startup. Seven focused virtual-camera tests pass.

Host 2.1.1/build 4 passed signing, notarization (`cb1ea89d-cfed-438d-9b35-80d164ff04c2`), stapling and installed Gatekeeper verification. The user confirmed that the updated host advances past queue opening but receives “Start virtual camera failed (-4)”. The signed diagnostic reproduces that failure both from the command line and when launched as a separate app, after camera consent. System logs report that the extension refuses the streaming request. No end-to-end video or Zoom pass is claimed.

Build 5 added sender-authorization diagnostics and checks for a bundled extension update on the first start of a signed app. It built successfully and passed the same seven focused tests. The first notarization request was interrupted, leaving submission `0c008e95-7d03-40f7-b5cb-09aad1883b3a` in progress without upload confirmation. A new, explicitly confirmed upload was accepted as `a96eb539-df10-4caa-8660-db03cdca1e0c`; its ticket was stapled and validated, and the app was installed with its signature verified. macOS subsequently confirmed build 5 activated and enabled, validating the replacement path. The user and diagnostic still reproduced error -4. Foundation redacted the diagnostic text as private, so its absence from a text-filtered log was not evidence that the authorization callback was skipped. Stream enumeration confirmed that the host selected `Camera Live Input`, with output scope and direction 0.

Build 6 replaces the optional signing-ID comparison with code-signature validation against an Apple-trusted signature, the extension's signing team, and the app or diagnostic identifier. Its public diagnostic fields report the CMIO identifier and signature status once per connection. A signed local executable exercising the real verifier passed six checks: accept the running Camera Live app and signed diagnostic; reject a different team, missing team, another process, and an invalid PID. The full Swift regression suite also passed: 25 tests across seven suites. Apple accepted submission `adc2937d-cc7f-4b3b-98ad-bb7918082bcc`, the ticket was stapled/validated, and build 6 was installed with strict signature verification. The notarization script now persists a confirmed upload ID before waiting and reports connection errors; the revised workflow completed successfully for build 6.

Build 6 subsequently activated successfully. The app initially retained a connection to the replaced extension and reported waiting; reopening it reproduced error -4. The public authorization log identified the actual installed app PID with `reportedSigningID=unknown`, `signatureStatus=100001`, and an available input stream. Kernel sandbox logs explicitly denied reads of the installed Camera Live bundle and executable. A separate AVFoundation receiver obtained 240 valid standby frames in eight seconds at 30.00 fps, but no live video, confirming the output service itself was operating.

Build 7 requests `kSecGuestAttributeDynamicCode` when looking up the sender, avoiding reads of its on-disk bundle while retaining the signature requirement. A disposable sandbox denying all reads under `/Applications/Camera Live Apple Silicon.app` reproduced status 100001 with the old lookup and succeeded with the corrected lookup. The actual corrected verifier then passed all six acceptance/rejection checks under that restriction. Installation discovery now uses the System Extensions properties API before activation, deferring explicit CMIO discovery until replacement has completed. This change alone did not eliminate the same-launch discovery problem after replacement: the app still reported waiting, while a fresh process connected successfully.

All 25 regression tests across seven suites passed. Apple accepted notarization `613d82ce-8b22-4899-a3d9-5cc736b7deed`; the ticket was stapled and validated, Gatekeeper accepted the bundle, and the installed build 7 passed deep/strict signature verification. macOS confirmed build 7 activated and enabled. The signed diagnostic then passed the actual installed-extension test: 180 correctly oriented frames at 30.00 fps, maximum delivery gap 36.84 ms, no gaps over 100 ms, and 30 standby frames after stopping the sender. This establishes real sink authorization and delivery through the extension sandbox to AVFoundation. Separately, the running app's Canon EOS 550D Syphon output delivered 480 frames at 1056 × 704 and 23.99 fps, maximum gap 70.00 ms, with no gaps over 100 ms.

After reopening the GUI following extension replacement, the read-only AVFoundation check received 239 live Canon frames at 1280 × 720, 30.00 fps, with zero invalid frames and a maximum timestamp gap of 35.3 ms. There were 187 distinct sampled live-frame hashes, consistent with repeating the camera's approximately 24 fps input at the 30 Hz output cadence. No images were saved. The user then selected Camera Live in Zoom and explicitly confirmed a live picture. The Canon → Camera Live → macOS virtual camera → Zoom path is therefore confirmed on this Mac. The successful Zoom result is user-reported; orientation/colour validation used the diagnostic pattern rather than a visual inspection of Zoom. Long-duration operation, physical disconnect recovery while using Zoom, and extension uninstall remain outside this check.

The 2.1.1 release ZIP was extracted separately and passed deep/strict signature verification, stapled-ticket validation and Gatekeeper assessment. Its SHA-256 is `51c934a82650e5ac6568579ada7c418330d0b9ae7cc35bb2fabc0b3c9c19e3ea`.

## System Settings icon correction, 15 October 2026

Build 3 replaces the manually assembled ICNS with Apple's `iconutil` output and includes the identical compiled icon in the camera extension, referenced by its `CFBundleIconFile`. Both bundles retain the existing Camera Live artwork.

The previous installed app reproduced the reported green/red corruption through `NSWorkspace.icon(forFile:)` at 16, 24 and 32 pixels, even though directly decoding the ICNS with `NSImage` appeared correct. The rebuilt app rendered correctly through the macOS icon service at 16, 24, 32, 48, 64, 128, 256 and 512 pixels. The installed copy initially retained the old cached thumbnail; updating that app bundle's modification date and refreshing only its Launch Services registration corrected it. All eight installed-icon sizes then passed the grayscale pixel check, and the 32-pixel image was visually checked against the original artwork.

The signed arm64 release passed the package dependency audit and deep/strict signature verification. Apple accepted notarization submission `a011d516-ab67-44b8-8da3-21cdab19e368`; the ticket was stapled and validated. The updated `/Applications/Camera Live Apple Silicon.app` passed Gatekeeper as Notarized Developer ID. Icon rendering was verified through the macOS icon service; the System Settings window itself was not inspected.

## Virtual camera work, 14 October 2026

The virtual-camera implementation, Apple-signed packaging and notarization are validated. The app is installed at `/Applications/Camera Live Apple Silicon.app`, alongside the original Camera Live. Extension activation and real Zoom capture are **not yet verified**. No signing identity was installed when this work began. A public certificate request and protected local private key were prepared under the ignored `.signing` folder. The user obtained the matching Developer ID Application certificate and app provisioning profile. Certificate trust verification passed; the profile matches the app identifier, team and signing certificate, and grants System Extension installation. The certificate/key were imported into the login keychain and used to sign the complete application. The user stored notarization credentials in the login keychain. Signing assets and credentials are not part of the repository.

| Check | Result |
| --- | --- |
| Swift logic/image tests | 25 tests across 7 suites passed with native video-buffer access |
| Signing input validation | 7 Python tests passed using synthetic profile metadata, including incorrect team/app/certificate, expiration, missing capability and legacy App ID prefixes |
| Imported Developer ID identity | Matching certificate/private key installed; a disposable executable was signed with a secure timestamp and passed strict signature verification after Keychain approval |
| Apple-signed release package | App, diagnostics, extension and dependencies signed with the same Developer ID identity; secure timestamps and hardened runtime enabled; app profile embedded; deep/strict signature verification passed |
| Apple-signed diagnostic runtime | Packaged executable loaded its bundled libraries and passed GPU/CPU orientation, aspect fit, in-flight-buffer immutability and standby checks with hardened runtime enabled |
| Apple notarization | Accepted submission `600ca6bc-4f82-4a05-85d7-6f8a2fe5d4c7`; ticket stapled and validated |
| Installed application | Deep/strict signature and stapled ticket verified; Gatekeeper accepted it as Notarized Developer ID |
| Release package | App, diagnostics and camera extension built; all 10 embedded Mach-O binaries passed the arm64/dependency audit and the bundle passed deep/strict ad-hoc signature verification |
| Virtual-camera frame conversion | GPU and CPU paths passed upright red/blue pixels, aspect fitting at two source sizes, black margins and retained-buffer immutability |
| Standby image | Rendered PNG inspected; extra vertical text inversion found and corrected, then verified upright |
| Existing preview and Syphon | 738 generated frames published; receiver verified 50 frames across both source sizes with correct orientation/colour; 732 on-screen presentations, 29.87 fps steady state, maximum gap 125 ms, two gaps over 100 ms |
| Installed-extension diagnostic | Correctly reported that Camera Live is not installed as a system camera; no end-to-end pass claimed |

The Swift tests include source freshness, stop and resume through a fake transport; they do not exercise the real CMIO service. The synthetic signing tests validate input handling, not Apple's certificate trust or provisioning acceptance. The new AVFoundation diagnostic is ready to exercise the installed source/sink path after activation. Actual Zoom video, multiple consumers, extension replacement/removal and the activated extension's runtime behavior remain acceptance steps in [VIRTUAL_CAMERA.md](VIRTUAL_CAMERA.md).

## Automated acceptance

Run `python3 scripts/swift.py test --disable-sandbox --disable-xctest` after building the pinned native dependencies. These tests do not need a connected camera or a Syphon receiver:

- Malformed, truncated and excessive-dimension JPEG rejection.
- Valid JPEG decoding across live-view resolution changes.
- Bounded latest-frame buffering under concurrent producers.
- Old-session shutdown before opening a new camera.
- Rapid selection changes and suppression of stale error callbacks.
- Sleep/wake without overlapping camera sessions.
- USB reconnect with a changed address; ambiguity between identical cameras.
- Error recovery, retry and shutdown completion ordering.
- Full-rate preview delivery independent of statistics, latest-frame sampling, and rejection of late frames after closing a preview.
- Automatic discovery stays out of the active capture queue and resumes after shutdown.

`python3 scripts/build-app.py` verifies arm64 architecture for every embedded executable, shared library and driver module, and checks the complete bundle's code signature.

## Desktop integration

Run the test-pattern producer and Syphon receiver as separate processes in a logged-in macOS session. Require at least ten received Metal frames across 640 × 480 and 1056 × 704, using `--verify-pattern`. Verify image orientation, colour channels, and resolution changes. Repeat with a copy of the application outside the repository to detect absolute dependency paths.

## Physical Canon 550D acceptance

These checks require the actual camera and a Syphon receiver; automated tests and driver support declarations cannot substitute for them.

- Detect Canon 550D by USB; start live view without launching EOS Utility.
- Confirm the actual live-view image appears in both Camera Live and a separate Syphon client.
- Check orientation, colours, dimensions, delivered rate and practical latency.
- Stop and start repeatedly; switch away and back without leaving the camera busy.
- Unplug while streaming, then reconnect and verify recovery.
- Put the Mac to sleep and wake it; verify a fresh session resumes.
- Run for more than 35 minutes to exercise the keep-alive path.
- Quit while streaming, then verify another camera app can acquire the camera.

## Current run

Validated on 14 October 2026 on an arm64 Mac running macOS 26.7.1, using Swift 6.4 and Command Line Tools:

| Check | Result |
| --- | --- |
| Automated logic/image tests | 18 tests across 5 suites passed |
| Release build | Native arm64 Swift app and diagnostics built successfully |
| Desktop launch | Final packaged app launched and its native process remained running |
| Embedded architecture audit | All 9 Mach-O executables, libraries and camera/USB driver modules are arm64 |
| Bundle signature | Ad-hoc signature verified with deep/strict verification |
| Dependency audit | No non-system absolute dependency paths remain in packaged Mach-O load commands |
| Generated video, separate processes | 748 frames published in 25 seconds; receiver verified 57 frames across both resolutions, including orientation and colour channels |
| Physical Canon EOS 550D | 439 live-view frames captured in a 20-second session; a separate Syphon client received 10 frames at 1056 × 704 |
| Relocated app in a folder under /private/tmp | 744 generated frames published; receiver verified 59 frames across both resolutions |
| Relocated camera-driver discovery | Detected the 550D despite initially invalid CAMLIBS/IOLIBS environment variables, confirming bundled driver selection |
| Physical restart from the relocated app | 435 live-view frames captured in another 20-second session after the first session closed |

The original installed Camera Live app initially held the camera's USB interface. After the user approved quitting that app and its session finished closing, the new implementation acquired the camera successfully. No operating-system camera services were killed.

The restricted execution environment hides the Metal GPU and USB devices. Desktop/hardware integration checks were therefore run with the approved native device access; a restricted `--list` result alone is not reliable evidence that no camera is connected.

## Frame-pacing correction

The original rewrite accidentally sent the preview image through the statistics callback, limited to one update every 0.2 seconds. The in-app preview therefore ran at at most 5 fps even when Syphon received about 24 fps. The correction sends every decoded/published image to a session-scoped latest-frame store. A MetalKit view samples that store at the current monitor's refresh rate; SwiftUI observes only the slower status updates. Automatic discovery no longer interrupts the camera queue during capture.

Measured with the packaged release build, excluding the first two seconds of startup from gap/rate statistics:

| Check | Result |
| --- | --- |
| Original running app, separate Syphon receiver | 23.98 fps; median gap 41.81 ms, p95 56.55 ms, maximum 64.40 ms |
| Generated video, fixed publisher | 749 full-rate frames; 30.00 fps; maximum gap 40.82 ms |
| Generated video, actual on-screen Metal drawable presentation | 747 frames presented; 29.99 fps; median gap 33.33 ms, p95 41.67 ms, maximum 66.67 ms; no gaps over 100 ms |
| Generated video, separate Syphon receiver | 57 frames verified across 640 × 480 and 1056 × 704; orientation and colour checks passed |
| Canon EOS 550D acquisition and publishing | 457 frames at 1056 × 704; 23.99 fps; zero decoder/publisher drops; maximum published gap 66.32 ms |
| Canon EOS 550D, actual on-screen Metal drawable presentation | 454 frames presented; 24.02 fps; median gap 33.34 ms, p95 66.67 ms, maximum 83.34 ms; no gaps over 100 ms |
| Canon EOS 550D, separate Syphon receiver during the preview test | 454 frames received; 23.99 fps; maximum gap 67.63 ms; no gaps over 100 ms |

Run `python3 scripts/smoke-test.py --preview` with its window visible to repeat the on-screen and cross-process checks. Use the packaged diagnostic's `--capture --preview` for the camera and `--receive 'Canon EOS 550D' --measure` in a separate process for receiver timing. The preview check requires actual Metal drawable presentation callbacks, not just image delivery or GPU submission. These are short performance samples, not a sustained-load guarantee, and the preview does not synthesize intermediate motion frames.

After the successful camera preview test closed, the 550D stopped appearing in USB discovery again. The updated GUI app was reopened with its saved camera selection, but its resumed feed could not be confirmed while the device was absent. The on-screen camera result above was measured in the diagnostic window using the same `CameraPreviewView` as the GUI app.

## Preview orientation correction

The frame-pacing update introduced an extra vertical flip in the preview's drawable transform. The previous checks validated Syphon texture orientation and preview presentation timing, but did not inspect preview pixels. An added GPU readback of the actual drawable reproduced the inversion before the fix: blue appeared above red in a pattern intended to have red above blue.

Removing the preview's negative Y scale corrected that failure. The Syphon rendering path remains unchanged. `python3 scripts/smoke-test.py --preview` now checks both destinations independently and passed after the correction: the receiver verified 54 frames across both resolutions, and the preview presented 731 frames with its top/bottom colour check enabled. This run was concurrent with the live-camera app, rather than an isolated pacing benchmark (29.60 fps on-screen; maximum gap 150 ms).

The corrected packaged app was reopened, and a separate receiver confirmed 10 live Canon EOS 550D frames at 1056 × 704 from that app. Native arm64 packaging and deep/strict signature verification also passed.

Not physically exercised in this run: unplug/replug during streaming, actual system sleep/wake, simultaneous identical camera models, a session longer than 35 minutes, third-party receiver applications, macOS 13 runtime compatibility, Developer ID signing or notarization. Lifecycle recovery paths are covered by the automated tests. The measured frame counts are smoke-test results, not a latency or sustained-performance benchmark.
