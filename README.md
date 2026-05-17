# BIZSOOQ Flutter App Handoff

This README is a handoff file for continuing the project in a new chat.

## Project Summary

BIZSOOQ is a Flutter mobile buying/selling app for Android and iOS.

The app has two modes:

- Buyer mode: default mode when the app opens. Buyers do not need an account. They can browse feed items, watch stories/reels, search, open item details, call sellers, WhatsApp sellers, and open seller profiles.
- Seller mode: enabled after register/login. Sellers can add items, manage listings, edit settings, upload a profile picture, and logout.

Firebase is used for Firestore, Storage, and Cloud Functions. Firebase Auth OTP pages still exist, but the current app flow does not use OTP authentication. Seller register/login is currently direct Firestore/session based because the client requested authentication be postponed.

## Current App Identity

- App name: `BIZSOOQ`
- Android package: `com.example.souqali`
- Firebase project: `souqali-42fd9`
- Firebase Storage bucket: `souqali-42fd9.firebasestorage.app`
- Main logo asset: `assets/branding/logo.png`
- OMR/riyal icon asset: `assets/images/omr_logo.png`
- Android launcher icons are under `android/app/src/main/res/mipmap-*`
- iOS launcher icons are under `ios/Runner/Assets.xcassets/AppIcon.appiconset`

## Important Commands

Run commands from the project root:

```powershell
cd D:\souqaliv1
```

If Java is not found, use Android Studio JBR:

```powershell
$env:JAVA_HOME='D:\AndroidStudio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
```

Debug build:

```powershell
flutter build apk --debug
```

Release build:

```powershell
flutter build apk --release
```

Release APK output:

```text
D:\souqaliv1\build\app\outputs\flutter-apk\app-release.apk
```

Run analyzer:

```powershell
flutter analyze
```

Deploy Firebase cleanup function:

```powershell
firebase.cmd deploy --only functions:cleanupExpiredItems
```

## Main Flutter Files

- `lib/main.dart`: app startup and Firebase initialization.
- `lib/seller_home_page.dart`: main shell, bottom menu, buyer/seller mode logic, login gate for seller-only tabs.
- `lib/seller_session.dart`: seller session storage using `SharedPreferences`.
- `lib/seller_register_page.dart`: seller create-account flow.
- `lib/otp_verification_page.dart`: old OTP flow kept for future use.
- `lib/seller_tabs/seller_feed_tab.dart`: main feed, grid/list layout, search animation.
- `lib/seller_tabs/seller_stories_tab.dart`: stories/reels tab.
- `lib/seller_tabs/seller_add_item_tab.dart`: add listing page, media picker/camera, upload flow.
- `lib/seller_tabs/seller_listings_tab.dart`: seller listings management.
- `lib/seller_tabs/seller_search_tab.dart`: search tab/page.
- `lib/seller_tabs/seller_settings_tab.dart`: seller settings, CR number, location, profile image, logout.
- `lib/item_detail_page.dart`: item detail page.
- `lib/item_edit_page.dart`: edit listing page.
- `lib/seller_profile_page.dart`: seller profile page and active posts.
- `lib/story_viewer_page.dart`: full-screen story/reel playback.
- `lib/story_repository.dart`: story table writes/deletes when item videos change.
- `lib/camera_capture_page.dart`: custom camera capture page.
- `lib/widgets/item_card.dart`: feed/search/seller-profile item card UI.
- `lib/widgets/media_carousel.dart`: media carousel UI.
- `lib/widgets/price_with_currency.dart`: price display with riyal icon.
- `lib/widgets/profile_image.dart`: shared profile image widget. Supports URL images and inline Firestore base64 images.

## Firebase Collections

### `sellers`

Seller documents are usually stored by seller phone number/session id.

Important fields:

- `uid`
- `name`
- `phoneNumber`
- `profile_image_url`
- `profile_image_data`
- `cr_number`
- `crNumber`
- `location`
- `createdAt`
- `updatedAt`

Notes:

- Profile pictures are currently compressed and saved inline in Firestore as a `data:image/jpeg;base64,...` string in `profile_image_url` and `profile_image_data`.
- This was done to avoid Firebase Storage rule errors for profile photos.
- CR is saved under both `cr_number` and `crNumber` for compatibility.
- Seller location is saved under `location`. Add Item uses this as the default location if available.

### `items`

Listing documents.

Important fields:

- `seller_uid`
- `seller_name`
- `seller_phone`
- `item_name`
- `item_price`
- `price_unit`
- `location`
- `image_urls`
- `media_files`
- `time_period_days`
- `time_period_extra_hours`
- `time_period_hours`
- `expires_at`
- `created_at`
- `updated_at`

Notes:

- `item_name` is optional.
- `location` is required.
- At least one image/video is required.
- Price defaults to `0`; if price is `0`, the UI shows `Contact for Price`.
- Price units are `/ kg`, `/ box`, `/ bag`.
- Max price input is `1,000,000`.
- Time period UI uses days/hours picker:
  - Default: `0 days 18 hours`
  - Max: `3 days`
  - If `3 days` is selected, extra hours must be `0`.

### `stories`

Each uploaded video creates its own story document.

Important fields:

- `seller_uid`
- `seller_id`
- `seller_name`
- `seller_phone`
- `item_id`
- `item_name`
- `item_price`
- `video_url`
- `created_at`

Notes:

- Stories are displayed as single videos, latest first.
- Same seller uploading multiple videos creates multiple story circles/videos.
- Stories are removed when their item is deleted or item videos are removed.
- Story display fetches the latest item and seller data where needed.

## Firebase Cloud Function Cleanup

The cleanup function is in:

```text
functions/index.js
```

Current schedule:

```js
schedule: "every 24 hours"
```

What it does:

- Queries expired `items` using `expires_at <= now`.
- Re-checks expiry using `created_at + time_period_hours`.
- Deletes item media from Firebase Storage.
- Deletes related story documents from `stories`.
- Deletes the item document from `items`.
- Does not delete sellers.

If the schedule is changed, redeploy:

```powershell
firebase.cmd deploy --only functions:cleanupExpiredItems
```

Important behavior:

- The app itself filters out expired items before showing them, so users should not see expired items even if the Cloud Function has not run yet.
- The Cloud Function is responsible for permanently removing expired Firestore docs and Storage files.

## Buyer/Seller Flow

Default launch:

- If there is no saved seller session, app opens in buyer mode.
- Buyer can use Feed, Stories, Search.
- Buyer cannot use Add, Listings, Settings seller actions.
- Seller-only tabs show an embedded login/create-account prompt.

Register:

- User enters company name and phone number.
- Phone number is stored with Oman prefix logic through existing phone utilities.
- If the same phone number already exists in `sellers`, registration should be blocked.
- On success, seller session is saved and the app enters seller mode.

Login:

- User enters phone number in the seller access prompt.
- App looks up seller in `sellers`.
- On success, seller session is saved and the app enters seller mode.

Logout:

- Clears `SellerSession`.
- App returns to buyer feed mode, not the login page.

Session keys in `SharedPreferences`:

- `seller_id`
- `seller_name`
- `seller_phone`

## Media Behavior

Add Item:

- Opens a WhatsApp-like media picker/camera bar.
- Supports images and videos.
- Maximum selected media: 9.
- Images appear before videos.
- Videos are stored last in the uploaded media list.
- Captured video currently bypasses the old preview/crop/trim flow.
- Images/videos are compressed before upload where implemented.

Edit Item:

- Uses add-item-like media UI.
- Seller can add/delete media.
- At least one media item must remain.
- Deleted media should be removed from Firebase Storage and story docs should be synced.

Feed/item media:

- Cards use full-image layouts.
- Both 1-by-1 and 2-by-2 layouts exist.
- Media counts appear on top of cards.
- Dots were removed from feed cards.
- Item detail still has media page dots when more than one media exists.

## Profile Picture Behavior

Settings page:

- User taps camera icon near profile.
- Image-only picker/camera flow opens.
- User crops the image.
- Cropped image is compressed and saved inline to the seller document.

Display locations:

- Settings page profile.
- Item detail seller section.
- Seller profile page.
- Story/reel seller avatar.

If no profile picture exists, the app falls back to the current default profile icon.

## UI Notes

Primary orange:

```text
#FF7801
```

Important layout rules already implemented:

- Feed header/footer hide on scroll.
- Other pages mostly keep header/footer fixed unless specifically removed.
- Some pages intentionally have no orange header:
  - Item detail page.
  - Story/reel section.
  - Seller profile page.
  - Settings page.
  - Listing page.
- Android hardware back behavior:
  - From most pages, back should return to Feed.
  - On Feed, first back shows `Please click back again to exit`.
  - Fast second back exits app.

## Known Firebase/Rules Notes

The app still uploads item media to Firebase Storage. If item media upload says:

```text
User is not authorized to perform the desired action.
```

then check Firebase Storage rules for item media paths.

Profile pictures should not require Storage rules now because they are saved inline in Firestore.

## Current Dependencies

Important packages from `pubspec.yaml`:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_storage`
- `image_picker`
- `photo_manager`
- `camera`
- `video_player`
- `video_compress`
- `flutter_image_compress`
- `image_cropper`
- `cached_network_image`
- `shared_preferences`
- `url_launcher`
- `font_awesome_flutter`

## Notes For Future Chat

- Do not delete `otp_verification_page.dart`; it is intentionally kept for later authentication work.
- Current seller auth is not Firebase Auth OTP.
- Be careful before changing `seller_uid`, because item ownership, listings, stories, cleanup, and seller profile pages depend on it.
- Be careful before changing `time_period_hours` or `expires_at`, because feed filtering and Cloud Function cleanup both depend on them.
- If changing profile images back to Storage, Firebase Storage rules must be updated first.
- If replacing logos again, update:
  - `assets/branding/logo.png`
  - Android `mipmap-*` launcher icons
  - iOS `AppIcon.appiconset` images

