# iOS 27 RC compatibility audit — September 11, 2026

## Result

**The app cannot yet be described as fully iOS 27 compatible.** The source audit found additional restoration bugs and a missing privacy declaration, now fixed on `fix/ios-27-launch-restoration`. Background vocal separation, UIKit implementation-dependent gestures/volume control, and multiple-window behavior remain release-verification items. An RC SDK build and real-device checks are still required.

This pass inventories all 217 Swift files in the iOS app and shared source directories (about 51,400 lines; 31 imported module names), inspects the corresponding build settings/resources, and reviews the phone/watch session bridge and pinned dependency implementations. The inventory is repository-wide static inspection; it is not a claim that every code path was executed or formally verified. Standalone Mac/TV feature parity is outside this iOS audit; shared code still needs to compile for those targets.

## Official baseline

The directly fetched Apple Markdown pages identify themselves as **iOS & iPadOS 27 RC Release Notes** and **Xcode 27 RC Release Notes**. Search-engine snapshots previously returned older beta notes. Apple documents scene lifecycle and launch-screen requirements, SwiftUI state-initialization changes, visible-tab selection enforcement, new text-selection interactions, and SDK-dependent presentation/menu changes. [iOS 27 RC notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)

Xcode 27 RC includes Swift 6.4 and requires macOS 26.6 or later on Apple silicon. This Mac has Xcode 26.6 / Swift 6.3.3 and an Intel simulator toolchain. Installing just a new simulator would not provide the RC compiler/SDK. [Xcode 27 RC notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)

## Fixes in this pass

| Area | Finding and change | Evidence |
| --- | --- | --- |
| Search tab | Swift 6.4 builds now use typed `UITabBarController.prominentTabIdentifier`; older SDK builds retain the guarded public ObjC bridge. Search keeps its semantic role and automatic activation. | `Twinskaraoke/App/TabBarMinimizeCoordinator.swift`; [Apple prominence API](https://developer.apple.com/documentation/uikit/uitabbarcontroller/prominenttabidentifier) |
| Phone/watch account | An unavailable phone credential could publish a signed-out descriptor or reply, causing the watch to delete its token. Descriptor availability and token replies now distinguish unavailable from signed out; foreground/unlock republishes the descriptor. | `AuthManager`, `WatchSessionPublisher`, `WatchSessionLink`, `WatchAuthManager`; token-reply regression test |
| Video history | A temporary credential failure could select the guest history bucket. An unresolved account now waits for a definitive account and retries on foreground/unlock; it does not load or save a guest bucket merely because Keychain is unavailable. | `VideoResumeStore`; account-identity regression test |
| Request builders | Library songs, playlist pagination, first-party translation, and QR approval still bypassed the typed credential read. They now fail/retry through their error paths instead of silently dropping authentication. | `LibrarySongsViewModel`, `PlaylistListLoader`, `LyricsTranslationService`, `AuthManager`; pagination regression test |
| Uploaded songs | A transient credential failure could become a permanently loaded “sign in” state and clear the list. It now preserves songs and remains retryable. | `UploadedSongsViewModel` |
| Privacy manifest | The existing manifest covered preferences and file timestamps but omitted system uptime used for playback timing, haptic throttling, and UI timers. Added SystemBootTime reason `35F9.1`; existing tracking and collected-data entries remain intact. | `Twinskaraoke/PrivacyInfo.xcprivacy`; [Apple required-reason categories](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) |
| Regression isolation | URL/lyrics/request tests now inject credentials instead of reading the unsigned test host’s Keychain. A separate test ensures unavailable credentials prevent anonymous request construction. | `LyricsLifecycleTests`, `SongModelTests`, `ModernizationRegressionTests`, `LaunchRestorationTests` |

The privacy declaration requirement predates iOS 27; it is a distribution gap found during this audit, not a newly introduced RC rule. [Apple required-reason guidance](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)

## Remaining findings

### High: background vocal separation is not established as compatible

`VocalSeparator.runSeparation2` creates `AudioSeparator2(modelURL:)`, with compute selection delegated to swift-spleeter. The pinned dependency loads Core ML without an app-supplied compute configuration. Its `AsyncThrowingStream` producer starts an unstructured `Task` without an `onTermination` cancellation handler. Cancelling the consuming app task therefore does not establish that the model has stopped running.

The app starts speculative full-song analysis while playing music and has no scene-background gate or continued-processing inference entitlement. Existing audio background mode does not establish permission to use the Neural Engine. Apple requires the background-inference entitlement for Neural Engine use while backgrounded, including outside continued-processing tasks. [Background Inference entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)

Before release: run foreground-to-background karaoke analysis on an Apple Intelligence-capable iPhone. Choose and implement a supported execution policy: continued processing with the appropriate entitlement/provisioning, or a dependency/pipeline change that controls compute resources and reliably stops or defers restricted inference. Merely cancelling the current wrapper task is insufficient. No unverified entitlement or performance-changing CPU-only policy was added in this audit.

### Medium: navigation and volume depend on UIKit internals

`ZoomPushDismissal.swift` identifies gesture recognizers by names containing `ParallaxTransition` and `ContentSwipeDismiss`, recursively disables them, and installs its own dismissal gesture. UIKit does not promise those private class names. A renamed/restructured recognizer can restore the old transition bug or let two dismissal mechanisms compete. Test playlist/artwork zoom pushes, cancelled swipes, nested pushes, immediate second taps, and accessibility navigation on the RC.

UIKit has a documented zoom interaction policy, but applying it to SwiftUI-owned transitions requires a deliberate integration change, not replacing the existing transition and losing SwiftUI’s source mapping. [Zoom interaction policy](https://developer.apple.com/documentation/uikit/uiviewcontroller/transition/zoomoptions/interactivedismissshouldbegin)

`SystemVolumeBridge.swift` finds a `UISlider` among `MPVolumeView`’s immediate subviews. That internal hierarchy is not a stable volume-setting API. Verify drag/release, hardware volume buttons, route changes, and AirPlay. Use the system volume view directly if the hierarchy assumption fails. [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview)

`ClearPresentationBackground` also walks ancestor views, but the source search found no active call sites; it is not an active launch blocker.

### Medium: multiple windows and resizing need targeted checks

`AppOrientationGate` uses a process-wide landscape count and chooses the first foreground scene. Its app-delegate orientation callback ignores the supplied window. `ShimejiSessionModifier` similarly chooses the first active scene for a singleton overlay. With two windows or an external display, a video/overlay action may affect a different window. This is an existing implementation limitation exposed by broader window use, not proof of a new RC regression.

The main app already uses a SwiftUI `WindowGroup`, has a scene manifest and a launch storyboard, supports the declared iPad orientations, and adapts its root shell by available width. Still test two windows, iPad resizing, iPhone Mirroring, video rotation, and dismissal back to the library. [UIKit scene guidance](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle), [UIKit updates](https://developer.apple.com/documentation/updates/uikit)

### Device-only integration checks remain

Audio playback, interruptions, media-services reset, AirPlay/Bluetooth, lock-screen commands, CarPlay, Photos authorization/save, camera QR capture, browser sign-in, paired-watch recovery, and background download/separation behavior need real-device verification. The unit suite uses controlled inputs and does not establish permission prompts, hardware routes, signed Keychain access, or live server compatibility. Update both phone and companion watch builds when testing the new unavailable-credential reply.

## API and implementation coverage

“No new source requirement found” means the inspected code does not match a documented migration trigger; it does not mean runtime certification.

| Area/modules | Inspection | Assessment |
| --- | --- | --- |
| SwiftUI/UIKit lifecycle | `TwinskaraokeApp`, `ContentView`, scene manifest, `LaunchScreen.storyboard`, build-generated plist keys | Required scene and launch setup present. Verify built artifact and RC launch. |
| SwiftUI state/Observation | All state declarations and six explicit `State(initialValue:)` assignments; observation bridge; main-actor models | Explicit initializers have no competing declaration value. No `@Entry` defaults or document-protocol migration trigger found. RC macro/compiler still needs compilation. |
| Tabs/navigation/search | All root enum cases, selection binding, sidebar selection, tab role, mini-player accessory, UIKit coordinator | Selection constrained to visible root cases. Typed API path added; private gesture risk remains. |
| Text/menus/presentation | Text selection, gestures, menu content, custom presentation and trait APIs | No `.textSelection(.enabled)`, custom `UIPresentationController`, or overridden presentation trait chain found. Menu appearance changes remain a visual check. |
| Foundation/network | Shared request/data/decoding helpers, direct URLSession call sites, URL/path escaping, account-scoped caches | Credential bypasses fixed. No `canOpenURL` calls or broad ATS exception found. Live endpoints not exercised. |
| Security/AuthenticationServices/CryptoKit | Keychain status handling, token cache, committed-session marker, browser continuation cancellation, QR approval, watch handoff | Unavailable credentials preserved; signed-device restoration still required. |
| AVFoundation/AVKit/CoreMedia/MediaPlayer | Engine/session setup, route/interruption/reset notifications, now-playing commands, crossfade, Pillarbox playback, volume/route picker | Session notifications hop to main actor; framework usage remains supported by current SDK. Hardware and UIKit-subview assumptions remain unverified. |
| CoreML/Accelerate/Spleeter | Model load, separation producer/consumer, trim reader/writer, cancellation and output publication | Background inference is the principal unresolved iOS 27 execution risk. |
| Foundation/Compression/Darwin storage | Download manifest/scan, caches, file metadata, compression, ZIP reads, deletion and promotion paths | Prior launch-restoration fixes retained. Privacy uptime declaration added. Protected-data/upgrade testing remains required. |
| Photos | Add-only authorization and async change requests in `ImageSaver`; saved-artwork lifecycle | Purpose string present; injected permission/write tests available. Real Photos check pending. |
| Camera | `AVCaptureSession`, serial session queue, non-zero preview-bounds gating, permissions, runtime errors | Camera purpose string present; no iOS 27-specific migration requirement identified. |
| WebKit | Captcha web view, navigation policy, external links | Public API usage; interactive sign-in/CAPTCHA check pending. |
| CarPlay | Scene delegate, template count limits, command integration, cancellation/disconnect cleanup | Uses scene API and system template limits. Entitlement/provisioning and vehicle controls need a signed device. |
| WatchConnectivity | Context publishing, token reply, activation/reachability, teardown/account scoping | Unavailable-state protocol fixed; paired-device check pending. |
| UserNotifications | Authorization, settings, migration, completion delivery | Existing lifecycle tests cover control flow; real notification delivery pending. |
| CoreHaptics/QuartzCore/CoreGraphics | Timers, display-rate use, animation geometry, haptic engine control | No deprecated application status-bar or `UIScreen.main` references found. Device animation/route check remains. |
| Combine/Network/OSLog/os | Notification delivery, network monitor, cancellation ownership, debug logs | Main-actor hops and cache locks reviewed at API boundaries; static review does not prove all races absent. |

## Dependencies and build checks

The pinned releases match the latest upstream releases returned during this audit:

- [SDWebImage 5.21.7](https://github.com/SDWebImage/SDWebImage/releases/tag/5.21.7)
- [SDWebImageSwiftUI 3.1.4](https://github.com/SDWebImage/SDWebImageSwiftUI/releases/tag/3.1.4)
- [Pillarbox 19.0.0](https://github.com/SRGSSR/pillarbox-apple/releases/tag/19.0.0)
- [swift-spleeter 0.2.0](https://github.com/jiyimeta/swift-spleeter/releases/tag/0.2.0)

Latest release status is not an iOS 27 compatibility guarantee. The Spleeter source inspection above is more informative than its version number. The deployment target remains iOS 26.5.

A dedicated `.github/workflows/ios27-compatibility.yml` records compiler/SDK/runtime versions, builds and analyzes Release, runs the complete iOS unit suite and three navigation UI checks, and retains results. It requires build **27A266a** for a successful RC verdict. GitHub’s `xcode-27` image README currently lists **27A5252f / beta 6**, so an available preview build must not be reported as RC validation. [GitHub runner image inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

## Validation results

Results are recorded below after the local and hosted runs complete. A green iOS 26.5 test run is backward-compatibility evidence, not iOS 27 runtime evidence.
