# iOS Build Notes

Last updated: July 15, 2026

## Project State

- Project: Bizsooq / Souq Ali
- Flutter project root: `/Users/user297237/Bizsooq/Projects/Souq_Ali`
- Current branch: `main`
- Current synced Git commit: `7a89bf0 added item seen, limited item renew`
- iOS bundle identifier: `com.bizsooq.app`
- Apple Developer team: `Mohammed Ali`
- Apple Team ID: `56Z6734H8L`
- Current archive version seen in Xcode Organizer: `1.0.2 (16)`

## Current Tooling

- Flutter: `3.44.6`
- Xcode: `26.5`
- CocoaPods: `1.16.2`
- iOS simulator used for testing:
  - Device: `iPhone 17`
  - Device ID: `752D6868-8063-4C1A-BEA1-FCCF59E0D2C4`
  - Runtime: iOS `26.5`

## Latest Code Sync

On July 15, 2026, the latest Flutter-side code was pulled into this iOS working folder.

Pulled commit:

```text
7a89bf0 added item seen, limited item renew
```

Files changed by that upstream commit included:

- `functions/index.js`
- `lib/seller_home_page.dart`
- `lib/seller_tabs/seller_listings_tab.dart`
- `lib/widgets/item_card.dart`
- `pubspec.yaml`

The pull was done with Git autostash so existing local iOS changes were protected, the new Flutter-side commit was merged, and the local iOS changes were reapplied.

After the pull:

- No merge conflicts were reported.
- `flutter pub get` completed successfully.
- The app launched successfully on the iPhone 17 simulator.

## Completed iOS Setup

- Reviewed Flutter iOS configuration before the first iOS build.
- Confirmed `GoogleService-Info.plist` exists in `ios/Runner`.
- Confirmed Firebase iOS bundle ID matches the app bundle ID:
  - App bundle ID: `com.bizsooq.app`
  - Firebase plist bundle ID: `com.bizsooq.app`
- Confirmed important iOS permission strings exist in `ios/Runner/Info.plist`:
  - Camera
  - Microphone
  - Photo library read
  - Photo library add/save
- Fixed CocoaPods setup for the MacinCloud environment.
- Ran `pod install` successfully.
- Generated `ios/Podfile.lock`.
- Generated/updated `ios/Pods`.
- Updated `ios/Runner.xcworkspace` to include CocoaPods project wiring.
- Updated the Xcode project with CocoaPods build phases and framework references.
- Raised the iOS deployment target from `13.0` to `15.0`.

## Why iOS Deployment Target Is 15.0

The first simulator build failed because Firebase Swift Package Manager products required iOS `15.0` or newer while the app target supported iOS `13.0`.

The affected Firebase products included:

- `cloud-firestore`
- `cloud-functions`
- `firebase-auth`
- `firebase-core`
- `firebase-storage`

Fix applied:

- `ios/Podfile` platform was raised to iOS `15.0`.
- Xcode project deployment target was raised to iOS `15.0`.

This means the app supports iPhone devices that can run iOS 15 or newer.

## CocoaPods Notes

Installed pods included:

- `Flutter`
- `flutter_image_compress_common`
- `permission_handler_apple`
- `video_compress`
- `Mantle`
- `SDWebImage`
- `SDWebImageWebPCoder`
- `libwebp`

The MacinCloud environment did not allow creating the normal user-level CocoaPods folder:

```bash
/Users/user297237/.cocoapods
```

So CocoaPods was run with a project-local home:

```bash
CP_HOME_DIR=../.cocoapods pod install
```

This is an environment/tooling workaround only. It does not change app logic.

## Swift Package Manager Notes

Flutter/Xcode may show this warning:

```text
The following plugins do not support Swift Package Manager for ios:
- flutter_image_compress_common
- permission_handler_apple
- video_compress
```

Current status:

- This is only a warning right now.
- The app still builds and runs.
- Flutter says this may become an error in a future Flutter version.

## iOS Permission Work

The iOS camera/microphone permission flow was corrected.

Changes made:

- Enabled iOS `permission_handler` compile-time macros in `ios/Podfile`:
  - `PERMISSION_CAMERA=1`
  - `PERMISSION_MICROPHONE=1`
- Reran `pod install`.
- Removed the extra light custom "Grant Permission" page for the first-time camera path.
- First-time iOS users now receive native iOS permission popups.
- If camera/microphone permission is denied, the app now stays inside the black camera surface and shows an `Open Settings` action.

Important simulator note:

- Native permission popups were confirmed working after permission reset/reinstall.
- The iOS simulator can still show a camera error because simulator camera behavior is limited. Real iPhone testing is still needed for true camera capture validation.

## iOS Status Bar and Safe Area Work

Android needed a black top status bar, but iOS should not show that black strip on normal screens.

Changes made:

- Added platform-aware system UI styling.
- Android keeps the existing black status bar behavior.
- iOS normal screens use a transparent status bar with dark icons.
- Camera screens still use a black status bar for contrast.
- Fixed the seller profile page so its transparent iOS status bar reveals the correct page background instead of black.

Relevant files:

- `lib/utils/system_ui_styles.dart`
- `lib/widgets/app_status_bar.dart`
- `lib/main.dart`
- `lib/item_edit_page.dart`
- `lib/camera_capture_page.dart`
- `lib/seller_profile_page.dart`

## iOS Live Gradient Work

For Live Feed, live Listings, and Seller Profile when LIVE is selected, the pink gradient background now starts from behind the transparent iOS status bar.

Changes made:

- Added `lib/widgets/live_page_background.dart`.
- Integrated it into the relevant seller pages.
- Kept the behavior iOS-focused so Android styling remains unchanged.

Relevant files:

- `lib/widgets/live_page_background.dart`
- `lib/seller_home_page.dart`
- `lib/seller_tabs/seller_feed_tab.dart`
- `lib/seller_tabs/seller_listings_tab.dart`
- `lib/seller_profile_page.dart`

## iOS Pull-To-Refresh Work

Issue observed:

- On iOS, pulling down to refresh was dragging the full header/content down.
- Android already had the preferred behavior: only the circular refresh ring appears.

Changes made:

- Added iOS-only clamping refresh physics.
- Feed, Live, Listings, and Seller Profile now keep the header stable on iOS pull-to-refresh.
- Android refresh physics remain unchanged.

Relevant files:

- `lib/utils/refresh_scroll_physics.dart`
- `lib/seller_tabs/seller_feed_tab.dart`
- `lib/seller_tabs/seller_listings_tab.dart`
- `lib/seller_profile_page.dart`

## Simulator Run Status

After pulling the latest Flutter commit on July 15, 2026:

- `flutter pub get` completed successfully.
- `flutter run -d 752D6868-8063-4C1A-BEA1-FCCF59E0D2C4` completed successfully.
- Xcode build completed successfully.
- The app launched on the iPhone 17 simulator.
- Flutter hot reload is available while the run session is active.

Run command:

```bash
cd ~/Bizsooq/Projects/Souq_Ali
flutter run -d 752D6868-8063-4C1A-BEA1-FCCF59E0D2C4
```

## Xcode / Flutter Cache Reset Performed

On July 13, 2026, a full non-destructive Xcode/Flutter cache refresh was run:

```bash
killall Xcode || true
rm -rf ~/Library/Developer/Xcode/DerivedData
flutter clean
flutter pub get
flutter build ios --config-only
```

Verified regenerated files:

- `ios/Flutter/Generated.xcconfig`
- `ios/Flutter/flutter_export_environment.sh`
- `ios/Flutter/Flutter.podspec`

## Xcode Workspace Notes

Always open the workspace, not the project file:

```bash
open ios/Runner.xcworkspace
```

Do not open only:

```bash
ios/Runner.xcodeproj
```

Opening only the project can cause Xcode to show false or missing dependency errors such as:

```text
No such module 'Flutter'
```

That issue was seen during setup. It was resolved by opening the workspace, letting Xcode index, refreshing generated Flutter config, and clearing Xcode caches.

## Signing and Archive Status

Xcode signing was configured with:

- Team: `Mohammed Ali`
- Bundle ID: `com.bizsooq.app`
- Automatic signing enabled

Archive status:

- A real iOS archive was successfully created.
- Xcode Organizer showed:
  - App: `Runner`
  - Version: `1.0.2 (16)`
  - Identifier: `com.bizsooq.app`
  - Type: `iOS App Archive`
  - Architecture: `arm64`
  - Team: `Mohammed Ali`

This confirms the Flutter/Xcode archive side can succeed.

## App Store Connect / Apple Account Blocker

After archive succeeded, Xcode validation failed during App Store Connect app record creation.

Errors shown by Xcode validation:

```text
STATE_ERROR.DPLA_OUTDATED_ERROR
Developer Program License Agreement outdated.
You need to sign the latest Apple Developer Program License Agreement.
```

```text
STATE_ERROR.APP_CREATE.PLATFORM_NOT_ALLOWED_DUE_TO_CONTRACT_STATE
One or more platforms cannot be created for this app due to your provider's contract state.
Creation of apps for the platform(s) iOS is not available due to your provider's contract state.
```

```text
The App Name you entered is already being used.
```

What was confirmed:

- The Apple Developer account Agreements page showed agreements as accepted:
  - Apple Developer Program License Agreement: accepted July 9, 2026
  - Apple Developer Agreement: accepted May 8, 2026
- App Store Connect still showed:
  - `Apple Developer Program License Agreement Updated`
  - `Free Apps Agreement`
  - Status: `Active (New Agreement Available)`
- No usable `Review`, `Accept`, `Agree`, or `Update` button was visible.
- Chrome, Chrome incognito, and Safari were tried.
- App Store Connect Business agreements page only exposed country/region `View` text and did not expose the needed agreement action.

Conclusion:

- This is an Apple account/App Store Connect contract-state issue.
- It is not a Flutter code issue.
- It is not an Xcode archive issue.
- Apple Developer Support must refresh/fix the account agreement/contract state before app creation/upload can continue.

Support message prepared for Apple:

```text
My Apple Developer Program License Agreement shows accepted in developer.apple.com/account, but App Store Connect still blocks me with "Apple Developer Program License Agreement Updated."

In App Store Connect > Business > Agreements, Free Apps Agreement shows "Active (New Agreement Available)," but there is no Review, Accept, or Agree button. I am the Account Holder.

Please refresh/fix the agreement state so I can create a new app and submit my iOS app.
```

## App Name Note

Xcode validation also reported that the selected app name is already in use.

If App Store Connect still rejects `Bizsooq`, try a unique display/app record name such as:

- `Bizsooq Oman`
- `Bizsooq Marketplace`
- `Bizsooq Souq`
- `Souqali Bizsooq`

The bundle ID can remain:

```text
com.bizsooq.app
```

## Current Known Remaining Items

- Apple must fix or expose the latest Developer Program License Agreement acceptance flow.
- App Store Connect app record still needs to be created successfully.
- App name may need to be changed to a unique App Store Connect name.
- Real iPhone camera capture still needs testing because simulator camera behavior is limited.
- Android-only packages should be reviewed before final iOS release:
  - `sms_autofill`
  - `in_app_update`
- iOS forced-update URL handling should later send iOS users to the App Store, not Play Store.
- SPM plugin warning should be monitored for future Flutter upgrades.

## Recommended Next Steps

1. Wait for Apple Developer Support to fix the agreement/contract-state issue.
2. Create the app manually in App Store Connect using bundle ID `com.bizsooq.app`.
3. Use a unique App Store Connect app name if `Bizsooq` is unavailable.
4. Reopen Xcode Organizer.
5. Select the successful archive.
6. Use `Distribute App` to upload to App Store Connect/TestFlight.
7. After upload, test through TestFlight on a real iPhone.
8. Validate camera, microphone, gallery picker, video compression, Firebase auth, listings, live views, profile pages, and update flows on a real device.
