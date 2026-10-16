# Resource optimization — Camera Live 2.4.3

Goal: reduce memory footprint, CPU/GPU work and wakeups while preserving the
accepted interface, native Canon capture, smooth preview, Syphon sharing, both
virtual-camera resolutions, crop controls, recovery and cleanup behaviour.
The optimization is installed and accepted in live Canon/Zoom use. The published
baseline is commit `3eeb8cb` (2.4.2); the prior installation was 2.4.1/build 17,
with the same executable source. Live, sustained and controlled fixture results
are recorded below.
The installed update is 2.4.3/build 19; the extension remains 2.4.0/build 10.

The local candidate passed the native build, platform/architecture/dependency
audits, deep/strict signature verification and ZIP integrity check. Its extension
CodeDirectory hash remains `b0d31a735387c7211d5655f2a3874cdafc875d1d`.
Release package: `dist/releases/2.4.3/Camera-Live-2.4.3-arm64.zip`.
SHA-256: `285a008d445d7820592ea7fdb4ed52aca1e623eb53cbbf883efe106fb2c3ad12`.
The user explicitly approved upload, installation and a brief restart on 16 October.
Apple accepted notarization `9b8d33f0-7c03-4635-8b64-2630291bc254`; its ticket
was stapled and validated, and Gatekeeper accepted the signed app. The release ZIP
was created from that exact accepted build. Its separately extracted app passed
strict signature, ticket and Gatekeeper checks; every file and symlink matches
the signed bundle. The earlier unstapled candidate ZIP is superseded.

## Implementation

- Keep the Syphon server discoverable, but create its Core Image context,
  command queue and shared texture only when a viewer connects. Release those
  resources after the last viewer disconnects. Decoding, preview delivery and
  statistics continue at their existing cadence. A viewer can join later.
- Replace the preview's continuous display-link polling with coalesced frame
  notifications and explicit Metal draws. Resize and crop changes also request
  a draw, even without another camera frame. Hidden/detached previews unsubscribe;
  restoring them samples the latest frame. GPU backpressure queues at most one
  retry. Temporary render objects have a per-draw autorelease pool.
- Create the preview's Core Image context on first use and release it after five
  seconds hidden, or immediately on detach/teardown. Restoring the preview creates
  a fresh context. Streaming restoration passed both the native fixture and
  the user's live Canon/Zoom check; held-frame instrumentation limits are below.
- Replace the virtual publisher's idle 30 Hz polling with a coalesced frame
  subscription; keep the existing 30 Hz active output and one-second recovery
  backoff. Stale input and stop release its renderer and pixel-buffer pool.
  A generation counter rejects cancelled timer callbacks; the subscription
  resamples the store to cover a frame arriving during the transition to idle.
- Add reproducible process profiling, late Syphon connection/reconnection checks,
  notification concurrency/cancellation tests, and a native preview lifecycle
  diagnostic. No layouts, labels, controls, resolutions or image transforms changed.

## Initial measurements

macOS 26.7.1, arm64. Each video run lasts 25 seconds; process measurements exclude
the first five seconds. Synthetic JPEG input alternates 640 × 480 and 1056 × 704
every two seconds at 30 fps. Visible-preview runs additionally read back test
pixels from the actual drawable and collect Metal presentation timestamps.
They are diagnostic workloads, **not whole-app/live-Canon/Zoom measurements**.

CPU is a percentage of one core. Memory is the kernel's physical footprint,
including charged graphics allocations, rather than RSS alone. CPU counters use
the Mach timebase (125/3 on this machine); a four-second CPU-bound control reported
92.1% of one core. The sampler does not measure total system energy or GPU power.

| Diagnostic | CPU | Median footprint | Interrupt wakeups/sec |
| --- | ---: | ---: | ---: |
| Baseline, no preview or Syphon viewer | 7.14% | 151.6 MiB | 69.6 |
| Conditional Syphon rendering, no preview/viewer | 1.19% | 14.5 MiB | 69.6 |
| Baseline, visible cropped preview | 10.29% | 211.1 MiB | 195.8 |
| Conditional Syphon rendering, original preview loop | 7.85–8.26% | 195.0–195.2 MiB | 197.6–199.7 |
| Explicit frame-driven preview, first run | 6.45% | 204.4 MiB | 80.4 |

The last row predates the per-draw autorelease-pool addition; follow-up candidate
and controlled visibility measurements are recorded below. Its CPU and wakeups improved, but its memory
footprint was higher than the Syphon-only change. Do not describe this as a
memory improvement over that intermediate version. The first attempt using
AppKit draw invalidation instead of explicit draws used 10.47% CPU and was replaced.

On resuming with the display available, the packaged 2.4.3 candidate passed the
visible cropped-preview check: 744 of 746 delivered frames were actually
presented, at 30.01 fps. Median/p95/p99/max presentation gaps were
33.33/41.67/41.67/83.33 ms, with no gaps over 100 ms. The current build, including
per-draw autorelease pools and hidden-context cleanup, used 6.96% CPU, 204.0 MiB
median footprint and 81.1 interrupt wakeups/second. File:
`candidate-preview-unlocked.json/.log`. A fresh baseline under these same display
conditions has not completed, so this run is not a new controlled A/B comparison.

## Preview visibility comparison, 16 October 2026

The original and current previews were then measured serially on an available
display, with a temporary display-sleep assertion limited to the diagnostic run.
The same native fixture supplies changing 1056 × 704 images from a background
queue at 30 Hz, uses a 960 × 640-point cropped preview, hides its window, waits
for cache cleanup, and restores it. It requires actual presentation in both
visible phases. It includes the fixture's input generation and event-loop work;
it excludes USB capture, JPEG decoding, Syphon and virtual output. The original
preview class is copied from the published baseline; the current class links
against the candidate's compiled core module.

| Phase | Baseline CPU | Current CPU | Baseline footprint | Current footprint | Baseline wakeups/s | Current wakeups/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Visible | 7.35% | 6.59% | 184.4 MiB | 174.9 MiB | 193.6 | 76.6 |
| Hidden, after settling | 6.04% | 2.40% | 183.5 MiB | 43.6 MiB | 180.2 | 72.8 |
| Restored | 8.76% | 8.55% | 184.8 MiB | 184.5 MiB | 194.6 | 76.4 |
| Stopped | 0.59% | 0.59% | 53.3 MiB | 53.1 MiB | 48.4 | 48.2 |

Footprint is median physical footprint; wakeups are interrupts. The profiler
excludes the first two seconds of each phase. The hidden measurement starts six
seconds after hiding, past the five-second cache-release delay. In its eight-second
hidden phase the original submitted 240 GPU renders; the candidate submitted
zero. On restoration, the candidate presented 360 frames in twelve seconds after
recreating its rendering resources (the original presented 323). The candidate
also presented 355 frames in the first visible phase. Both controls passed their
visible/restored presentation checks. The fixture's original-mode final message
mentions hidden suppression generically; that assertion applies only to the
optimized mode, and the original's recorded hidden renders are intentionally
retained for comparison.

This demonstrates about 140 MiB less retained memory and no preview GPU work
while hidden in this workload. Active memory after restoration was effectively
unchanged. It does not establish whole-app/live-Canon memory or total system
energy use. Files: `preview-visibility-{baseline,current}.json/.log`; fixture:
`.build/performance/visibility-comparison/`. Earlier incomplete attempts from a
locked display were superseded by these successful runs and are not used here.

Baseline and intermediate bundles are preserved under `.build/performance/`.
Calibrated samples are `baseline-idle-syphon-2.json`,
`optimized-idle-syphon-2.json`, `baseline-preview.json`, `optimized-preview.json`,
`syphon-only-preview-repeat.json` and `direct-preview.json`, with matching logs.
Early samples without Mach conversion are explicitly separated under
`exploratory-uncalibrated/` and must not be used for CPU comparisons.

## Virtual-camera resource measurements

The signed diagnostic uses the production publisher and installed CMIO extension,
with an AVFoundation receiver in the measured process. A reusable 1056 × 704 image
is submitted at 30 Hz. Each run includes waiting (8 s), live (20 s), stale (8 s),
resumed (20 s), and stopped (8 s). Phase summaries exclude the first two seconds
and the final 0.2 seconds. The receiver remains open during stale/stopped phases
and receives standby video. These numbers exclude USB/JPEG decoding and preview;
they include the diagnostic receiver's work. The baseline differs only in the
publisher scheduling/resource changes for this workload.

| Canvas / phase | Baseline CPU | Current CPU | Baseline footprint | Current footprint | Baseline wakeups/s | Current wakeups/s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 720p / waiting | 0.06% | 0.03% | 9.5 MiB | 9.2 MiB | 30.8 | 1.6 |
| 720p / live | 6.10% | 5.04% | 312.3 MiB | 316.4 MiB | 213.1 | 209.4 |
| 720p / stale | 1.50% | 1.02% | 166.9 MiB | 160.5 MiB | 181.5 | 147.8 |
| 720p / resumed | 6.83% | 4.98% | 296.2 MiB | 300.3 MiB | 212.5 | 204.8 |
| 720p / stopped | 1.38% | 0.94% | 159.8 MiB | 160.4 MiB | 151.9 | 146.2 |
| 1080p / waiting | 0.14% | 0.00% | 9.3 MiB | 6.5 MiB | 30.8 | 1.3 |
| 1080p / live | 6.02% | 5.50% | 331.0 MiB | 328.6 MiB | 232.4 | 228.5 |
| 1080p / stale | 1.16% | 0.90% | 185.6 MiB | 160.6 MiB | 187.4 | 145.5 |
| 1080p / resumed | 6.04% | 7.28% | 314.9 MiB | 313.6 MiB | 236.3 | 229.3 |
| 1080p / stopped | 1.32% | 1.41% | 161.9 MiB | 160.5 MiB | 151.6 | 149.7 |

Memory is median physical footprint and wakeups are interrupt wakeups. Rounded
0.00% is below this display precision, not literally zero work. All live/resumed
phases delivered 596–598 valid frames in 20 seconds, with no invalid frames.
The demonstrated gains are idle wakeups and stale-input buffer cleanup. Active
memory is broadly unchanged; these short runs do not establish an active CPU
improvement (notably the resumed 1080p result). Startup peaks were approximately
524–528 MiB including the AVFoundation receiver. Data: `publisher-baseline-720`,
`publisher-optimized-720`, `publisher-baseline-1080`, `publisher-optimized-1080`
JSON/log pairs under `.build/performance/`.

The current 1080p sustained check ran two 120-second live phases separated by
stale input. It received 3,597 and 3,598 valid frames, both at 30.00 fps, with
maximum steady frame gaps of 42.53 and 47.62 ms and no gaps over 100 ms. Steady
footprint stayed below 332.2 MiB in the first phase and 316.2 MiB after resume,
then fell to about 162 MiB with standby reception still running. These are bounded
observations over four minutes of live output, not proof against all leaks.
The separately sampled extension's public RSS was 15.3–26.2 MiB during live
output; its private physical footprint was unavailable. RSS must not be added to
the host's physical footprint. Files: `publisher-long-1080.json/.log` and
`extension-long-1080-public.json`.

The same-duration baseline also passed. Baseline/current active CPU was
6.84%/7.03% for the first phase and 7.51%/7.31% after resume: effectively unchanged
in these serial runs. Median live footprint was 332.2/330.8 MiB and resumed
footprint 316.0/315.0 MiB. The larger improvements remained in idle states:
waiting wakeups 31.1/1.4 per second and stale footprint 186.8/162.0 MiB.
File: `publisher-baseline-long-1080.json/.log`. This comparison supports reduced
idle work without evidence of an active-output resource regression; it is not a
claim of lower active CPU or zero memory growth over arbitrarily long operation.

The full app, with no USB camera and a locked display, used 0.96% CPU / 70.5 MiB
median footprint in the published baseline and 0.93% / 72.0 MiB in the candidate.
Both woke about 6.1 times/second. These 20-second runs exclude their first five
seconds. This idle state is broadly unchanged; no discovery/reconnect behaviour
was altered. Files: `app-idle-baseline.json` and `app-idle-current.json`.

## Correctness evidence

- All 37 Swift tests passed after adding observer and publisher tests: concurrent producers
  coalesce to the latest frame, cancellation suppresses queued delivery, callbacks
  can close the store without deadlock, and late frames cannot revive a closed store.
  The existing 31 tests cover capture orchestration, crop geometry/pixels, virtual
  delivery, stale input, recovery, format changes and sample ownership.
  New publisher tests cover late/replaced input, disabling a waiting publisher,
  repeated enable calls, extension backoff, and recovery when it becomes available.
  The final current suite passed again, and the separate GPU/CPU pixel diagnostic
  passed both canvas sizes, upright orientation, borderless fill, immutable
  in-flight buffers and standby output (`current-tests.log`, `current-pixels.log`).
- All four producer/receiver canvas combinations passed through the installed
  extension: 720p→720p, 720p→1080p, 1080p→720p and 1080p→1080p. Each delivered
  180 correct live frames and 30 standby frames, at 29.99–30.02 fps, with maximum
  frame gaps of 40.08–44.55 ms and no gaps over 100 ms. This validates actual CMIO
  and AVFoundation output, including upright orientation and borderless fill.
- A Syphon receiver joined after five seconds without clients, received both
  resolutions with correct colours/orientation, disconnected, and reconnected
  successfully. The producer delivered 750 frames at 30.00 fps; maximum steady
  gap 57.65 ms and no gaps over 100 ms.
  The current signed rerun also passed both connections and source sizes,
  delivering 750 preview-ready frames at 30.00 fps, maximum gap 53.50 ms
  (`current-syphon-reconnect.log`).
- Concurrent Syphon and virtual output passed at both canvas sizes. The producer
  decoded alternating 640 × 480 / 1056 × 704 JPEGs; Syphon viewers joined for
  each live phase, disconnected during stale input and rejoined after resume.
  At each canvas size AVFoundation received 597 and 598 valid live frames at
  30.00 fps, with no invalid frames and valid standby/recovery/stop states.
  Syphon received 589–596 frames per connection at 29.99–30.00 fps and verified
  source dimensions, orientation and colour. Maximum gaps were 48.62 ms for
  virtual output and 57.39 ms for Syphon, with no gaps over 100 ms. Files:
  `combined-{720p,1080p}.log` and the matching `*-{live,resumed}-syphon.log`.
- The explicit-preview streaming check presented 745 of 747 submitted frames.
  After startup, presentation was 30.01 fps; median/p95/p99/max gaps were
  33.33/41.67/41.67/50.00 ms, with no gaps over 100 ms.
- Native lifecycle checks verified zero idle draw callbacks, crop/resize redraws
  of a held frame, suppression while hidden/detached, restoration and teardown,
  with actual GPU pixel readback. These were render-only checks. A stricter final
  packaged rerun requiring actual presentation at every single-frame transition
  did not pass; the baseline behaves the same, as described below.
- A separate original-versus-optimized single-frame harness returned zero
  presentation timestamps in **both** implementations, despite successful GPU
  renders. Therefore lifecycle checks establish completed drawable pixels and
  scheduling, not independent on-screen presentation of a single held frame.
  Streaming diagnostics retain their real-presentation check. Subsequent lifecycle
  runs correctly did not draw while occluded. A read-only registry check confirmed
  `CGSSessionScreenIsLocked = true`; do not repeat visible-window tests until the
  Mac is unlocked. The current lifecycle diagnostic explicitly requires both GPU
  completion and nonzero presentation timestamps; it has not yet passed that
  stricter gate. No visual pass is inferred from rendering alone.
- A resumed strict held-frame check still returned no positive presentation
  timestamp despite a visible window and a completed render. Isolated original
  and optimized previews did the same, including with active/key floating windows
  and the normal AppKit event loop. This reproduced in both versions on 16 October
  with a temporary display-sleep assertion (`held-comparison/*-awake.log`), after
  the successful streaming visibility comparisons. This leaves held-frame on-screen verification
  unresolved; neither a rendering-only pass nor a proven optimization regression
  is claimed. The packaged live-stream check above did report real presentation.
- A separate visible/hidden/restored resource fixture could not complete its
  original-preview control. Its final attempt supplied 360 frames but received
  zero GPU renders, and a subsequent registry check confirmed the display had
  locked again. These incomplete runs are excluded from resource comparisons.
  The fixture remains under `.build/performance/visibility-comparison/`; rerun
  only with the display available, and require real presentation before trusting
  its measurements. No production-code change was made in response to it.

## Installed acceptance and measurement limits

- Apple accepted the explicitly approved candidate upload. The installed app's
  executable, diagnostic and resource signature match the signed build, and
  its notarization ticket and Gatekeeper assessment passed. The unchanged
  extension remains 2.4.0/build 10 with the hash recorded above. The previous
  installation is retained at `.build/installed-backup-20261016-074812/`.
- After installation, the user confirmed: “Yes, preview and Zoom are smooth”.
  They then tried cropping, a small window, minimizing for at least ten seconds
  and restoring, and confirmed: “Yes, everything still works”, including Zoom
  continuing smoothly throughout. These are user-reported functional checks.
- Independent read-only AVFoundation checks received changing live Canon video:
  238 valid 720p frames in eight seconds (187 distinct sampled frames, 29.75 fps,
  maximum timestamp gap 100.0 ms), then 240 valid 1080p frames (211 distinct,
  30.00 fps, maximum gap 37.7 ms). No invalid frames or saved camera images.
  This overlapped the user's interactive checks and is not a controlled steady
  pacing comparison. Files: `live-candidate-receiver-{720p,1080p}.log`.
- Streaming presentation, hidden-render suppression, restoration and actual
  drawable pixels passed automated checks. The optional strict single-held-frame
  diagnostic still lacks positive presentation timestamps in both original and
  optimized isolated previews. It remains an instrumentation/behaviour uncertainty;
  no single-held-frame presentation pass or proven regression is claimed.
  This limitation is separate from the accepted working live-camera interface.
- Measurements are finite observations on this Mac. They do not prove an absence
  of all future leaks or quantify total system energy. Live scene content was not
  replayed, and the extension's private footprint was inaccessible. The controlled
  synthetic comparisons isolate changes more tightly than the live observations.
- After accepting the installed update, the user requested committing and releasing
  version 2.4.3 to their personal GitHub repository. The release packages the same
  notarized app; release preparation changes documentation only.

## Live Canon baseline, 16 October 2026

The user launched installed 2.4.1/build 17 and confirmed live preview and virtual
camera were active. Its executable source matches published 2.4.2. A passive
30-second measurement, excluding the first five seconds, recorded 39.79% CPU,
259.09 MiB median physical footprint (260.50 MiB maximum steady footprint), and
184.96 interrupt wakeups/second. The process was not changed by the profiler.
File: `live-app-baseline-2.4.1.json` (PID 89651). The camera appeared in the USB
registry as a Canon device. This is an observational baseline; preview visibility,
scene complexity and consumer state must be considered in any candidate comparison.

The same 30-second passive measurement after installation, with preview and
virtual camera active and confirmed smooth in Zoom, recorded the following:

| Live app | CPU, % of one core | Median physical footprint | Interrupt wakeups/sec |
| --- | ---: | ---: | ---: |
| Installed baseline 2.4.1/build 17 | 39.79% | 259.09 MiB | 184.96 |
| Optimized 2.4.3/build 19 | 28.56% | 228.00 MiB | 70.51 |
| Observed reduction | 28.2% | 12.0% | 61.9% |

The candidate's first/last footprint was 227.69/228.34 MiB and its steady maximum
229.55 MiB. File: `live-app-candidate-2.4.3.json` (PID 91789). Both samples exclude
five seconds, and neither controls the existing app process. User-confirmed output
state matches; these are live observations rather than an identical replay.

A subsequent two-minute passive run after the interactive crop/resize/hide/restore
checks recorded 32.11% CPU, 242.33 MiB median footprint, 244.50 MiB maximum,
and 72.24 interrupt wakeups/second. First/last steady footprint was 238.27/242.84
MiB; the four successive interval medians were 241.92, 242.13, 242.39 and 242.72
MiB. Memory remained below 245 MiB over this observation, but this finite run is
not proof against long-term growth. This is a post-interaction stability observation,
not a second matched baseline comparison; window/framing/consumer activity may
affect resource use. File: `live-app-candidate-2.4.3-sustained.json`.

Brief stack samples (`live-app-{baseline-2.4.1,candidate-2.4.3}.sample.txt`) show
ImageIO/CMPhoto JPEG work reached from Core Image, as well as UI updates. Sampling
does not establish duplicate decoding or precise CPU attribution by itself.
No speculative decoder or UI redesign was introduced on the basis of those stacks.

## Reproduction

```sh
python3 scripts/profile-process.py --output .build/performance/run.json -- \
  'dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics' \
  --test-pattern 'Performance check' --preview --framed-preview --keep-visible
python3 scripts/smoke-test.py --reconnect
python3 scripts/profile-preview.py --baseline-ref v2.4.2
'dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics' \
  --virtual-resource-test --canvas 1080p --receive-output --stream-seconds 120
'dist/Camera Live.app/Contents/MacOS/camera-live-diagnostics' \
  --preview-lifecycle-test --framed-preview --keep-visible
python3 scripts/swift.py test --disable-sandbox --disable-xctest
```

Keep comparisons serial, with the same display/workload and no concurrent builds.
The optional floating window is a diagnostic feature only. It does not change the
app's window behaviour.

`profile-preview.py` preserves the visibility benchmark fixture in the repository,
builds it against the current core, and extracts the original preview from the
specified local Git commit. It records the resolved baseline commit, SDK and
current checkout status alongside the measurements. `--build-only` builds without
opening test windows. The fixture's input generator and event-loop work are
included in process metrics, as described above.

`--virtual-resource-test --syphon-source NAME` adds actual JPEG decoding and a
Syphon server to the resource phases. A second diagnostic can join that name
with `--receive NAME --verify-pattern --measure` during each live phase to check
both outputs concurrently. The canvas selects virtual output; the Syphon feed
retains the original camera image dimensions.

API references: [Syphon viewer demand](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h),
[MetalKit drawing modes](https://developer.apple.com/documentation/metalkit/mtkview),
[Metal drawable lifetime](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html),
[XNU process resource counters](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c).
