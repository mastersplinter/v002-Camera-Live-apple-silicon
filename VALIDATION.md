# Validation

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
