# iOS modernization review — 2026-09-09

## Baseline and scope

The deployment target remains **iOS 26.5**, as requested. The installed toolchain is Xcode 26.6 (17F113), with iOS/iPadOS 26.5 SDKs and simulators. There is no Xcode 27 installation or iOS 27 simulator on this machine.

The audit includes repository-wide API/availability/concurrency searches, build settings, dependency versions, shared decoding and observation, authentication, pagination, playback/cache execution, scene/tab integration, and targeted regression/UI tests. This is a compatibility audit with concrete fixes, not proof that every path is bug-free.

## Changes

- Explicit `@concurrent` execution for artwork decoding and blocking audio-cache lookup/download validation. With approachable concurrency, `nonisolated async` alone does not guarantee execution away from the calling actor.
- Main-actor playlist pagination with owned task cancellation, raw server offsets, within-page deduplication, and retryable malformed responses. Display counts no longer determine server offsets.
- Shared lossy decoding advances using a child decoder, guaranteeing progress across malformed entries and exposing the original entry count for pagination.
- Observation registers the next change before invoking its callback, preserving changes made by callbacks. Redundant teardown and stale Combine imports removed.
- Tab-bar scroll coordination belongs to each installer; recognizers and observations are removed when it is destroyed. Separate windows no longer share a single controller reference.
- Sign-ins are serialized and generation-checked after suspension. Cancellation and logout prevent stale successful responses from committing credentials. Browser cancellation explicitly resolves its continuation once. iOS and macOS use the modern authentication callback initializer.
- Player UI checks use the system status-bar frame rather than a fixed 60pt threshold and allow sub-pixel floating-point rounding for the 44pt touch target.
- Cocoa framework lookup uses the selected SDK rather than a hard-coded macOS 26.0 SDK path.
- Analysis CI explicitly builds all four app platforms in Release, preserves diagnostics, and permits selecting Xcode when manually dispatched. Added a shared TV scheme. Test CI sorts simulator versions numerically and permits selecting Xcode.

## iOS 27 review

Apple's current [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) were reviewed for relevant UIKit and SwiftUI changes. The app already has a scene lifecycle and a generated launch-screen declaration. Root tab selection remains within the displayed enum cases. The source scan found no conflicting explicitly initialized `@State` declarations and initializers. No deprecated application status-bar accessors, `canOpenURL`, or custom presentation-controller trait overrides were found.

The existing guarded dynamic call to the documented [prominentTabIdentifier](https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier) API remains necessary to preserve its iOS 27 behavior when building with the installed iOS 26 SDK. A typed replacement should be compiled and tested with Xcode 27.

## Retained compatibility code

No pre-iOS-26 availability branches remain in first-party Swift sources. Credential migration and old on-disk audio/download migration are **data-format compatibility**, not support for old operating systems. They remain so existing users can upgrade without losing sign-in or downloaded content. Platform conditionals remain for the Watch, TV, and Mac apps. The video player's Combine integration remains because its dependency exposes publishers and its state-object lifetime is intentional.

Direct dependencies were checked against their upstream releases and are already current: Pillarbox 19.0.0, SDWebImage 5.21.7, SDWebImageSwiftUI 3.1.4, and swift-spleeter 0.2.0.

## Validation

- iOS unit tests: 232 passed (241 executions including parameterized cases), zero failures on final app code; `/private/tmp/modernization-verified.xcresult`. That combined bundle also contains the separate UI failure described below.
- Watch unit tests: 43 passed, zero failures; `/private/tmp/modernization-watch.xcresult`.
- iOS Release build and static analysis: passed; `/private/tmp/modernization-release-analysis.log`.
- macOS Release build: passed; `/private/tmp/modernization-mac-final.log`.
- tvOS Release build: passed; `/private/tmp/modernization-tv.log`.
- Four targeted iOS UI checks passed (launch, adaptive navigation, library/search drill-down, account/settings). The player/sleep-timer case passed after correcting its assertions; `/private/tmp/modernization-player-verified.xcresult`. Five targeted iPhone UI scenarios passed across these runs; the complete UI suite was not rerun.
- iPad Pro 13-inch / iPadOS 26.5 adaptive navigation UI check: passed; `/private/tmp/modernization-ipad.xcresult`.
- Workflow YAML, shared-scheme XML, and `git diff --check`: passed. The remote GitHub workflows have not been dispatched.

The initial player UI assertion expected a midpoint greater than 60pt and reported 55.67pt on iOS 26.5. A diagnostic attempt also showed that the system status bar is not exposed in the application's own accessibility hierarchy. The system-owned status-bar check passed; the next assertion exposed floating-point rounding of a 44pt frame to 43.99999999999999. The test now allows a 0.001pt tolerance. These failed runs are retained at `/private/tmp/modernization-ios-final.xcresult`, `/private/tmp/modernization-player-retry.xcresult`, and `/private/tmp/modernization-verified.xcresult`.

## Remaining release verification

Build and test with the final Xcode 27 SDK and run on iOS/iPadOS 27, including tab prominence/minimization, window resizing, text-selection gestures, video transitions, background audio, AirPlay/Bluetooth, CarPlay, and real browser sign-in. Hardware routes and live account mutations are not established by simulator tests. The available toolchain cannot certify final iOS 27 compatibility.

Pre-existing signing/bundle identifiers, the local CarPlay entitlement override, localization edits, and existing review documents were preserved.

## Second pass — 2026-09-09

The second pass focused on lyrics/translation, artwork request replacement, shared timestamp and QR parsing, platform sign-in cancellation, and remaining callback-based resource operations.

Additional fixes:

- iOS lyrics use an owned async task and the shared API client's status/retry/session-expiry handling. Cancellation and generation checks prevent a late response for the same song from replacing current state. Teardown cancels work; explicit retry now replaces an active request.
- Fetched, adopted, and cached lyrics are ordered by timestamp. The shared parser rejects nonfinite timestamps, overflow, and negative time components, preventing invalid timing data from reaching iOS/TV playback views.
- Translation results and failures are ignored after their task is cancelled or their source is replaced, even when the song ID is unchanged. Cached translations must match both source text and timing.
- Cancelled artwork failures no longer invalidate a newer request for the same playlist; malformed artwork payloads permit retry.
- TV lyrics suppress cancelled URL-session errors, including after switching away from and back to the same song. TV playlist loads reject results from replaced credentials, and sign-out immediately clears the playlist store. Cancelled QR completion cannot clear replacement state after cache invalidation.
- QR session IDs are encoded as a single URL path component; empty and navigation-component IDs are rejected.
- Mac and TV password sign-ins are serialized and invalidated on sign-out. Their QR flows cannot race password/browser sign-in. Mac browser sign-in explicitly resolves cancellation and ignores callbacks from older attempts, with callback state changes isolated to the main actor.

The remaining download callbacks were reviewed for temporary-file ownership: moving a downloaded file before its completion handler returns is intentional. No blanket callback-to-task conversion was applied to those resource operations.

Second-pass validation:

- iOS unit tests: 240 passed, 255 executions including parameterized cases; `/private/tmp/modernization-pass2-verified.xcresult`.
- The first regression attempt exposed the active-request retry bug; its failing result is retained at `/private/tmp/modernization-pass2-ios.xcresult`.
- Watch unit tests: 43 passed; `/private/tmp/modernization-pass2-watch.xcresult`.
- Final iOS Release build and static analysis passed without diagnostics; `/private/tmp/modernization-pass2-analysis.log`.
- Final Mac and TV Release builds passed without diagnostics; `/private/tmp/modernization-pass2-mac-final.log`, `/private/tmp/modernization-pass2-tv-final.log`.
- `git diff --check` passed. The first-pass UI checks were not repeated for these service/model changes.

The new lifecycle tests use controlled responses and do not perform live authentication. Mac/TV browser and account behavior still need device/service verification; these platforms do not currently have dedicated authentication unit-test targets. This pass does not change the iOS 27 SDK/runtime limitation above.

## Third pass — installed Xcode retained

This pass keeps iOS 26.5 as the minimum and uses the installed Xcode without adding SDK 27-only source dependencies.

- Artwork saving now uses async PhotoKit authorization and change requests instead of `UIImageWriteToSavedPhotosAlbum` and Objective-C selectors. It requests add-only permission, rechecks authorization for each save, and preserves FIFO ordering through failures and reentrant completion callbacks. Accepted writes remain alive when the originating view disappears. See Apple's [PhotoKit authorization documentation](https://developer.apple.com/documentation/photos/phphotolibrary) and [async change requests](https://developer.apple.com/documentation/photos/phphotolibrary/performchanges(_:completionhandler:)).
- The gallery waits for the final SDWebImage completion before saving, rejects stale generations, and removes its unreachable non-UIKit download fallback. Save completions are explicitly main-actor isolated.
- The full-screen player's save-result reset uses a generation rather than status equality, so an older timer cannot clear a newer identical success/failure result.
- New injected PhotoKit regression tests cover denied/restricted/undetermined permission, failure recovery, FIFO/reentrant requests, and authorization changes. They do not access the real photo library.

Validation: 243 iOS unit tests passed, 260 executions including parameterized cases, zero failures or skips (`/private/tmp/modernization-pass3-verified.xcresult`). An initial compile attempt caught an incorrectly positioned SDWebImage completion parameter; the corrected signature is included in the passing run. Real Photos permission prompts and saved-image results still need a device check.

The remaining availability scan found only the intentional iOS 27 tab API guard. Apple's [iOS 27 notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes) also describe restricted background Neural Engine access. Vocal separation currently delegates model configuration to swift-spleeter, which loads Core ML with default configuration. Foreground-to-background inference therefore remains a specific iOS 27 hardware verification item; this audit does not establish its behavior or add an unverified entitlement.

An iOS 26.5 SDK build can be tested on an iOS 27 device through a supported installation/distribution route without changing this machine's Xcode. Such runtime testing is distinct from building against the iOS 27 SDK; neither has been performed here. Existing source/SDK checks are not a guarantee of final iOS 27 compatibility.

Final third-pass Release build and static analysis passed without diagnostics (`/private/tmp/modernization-pass3-release.log`). `git diff --check` passed. Cross-platform and UI suites were not repeated for these iOS-only artwork changes.
