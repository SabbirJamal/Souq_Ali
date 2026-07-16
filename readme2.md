# Bizsooq Project Handoff

This file is for the next Codex chat. Read this first before touching code.

## Project

- App name: Bizsooq / BIZSOOQ
- Local path: `D:\souqaliv1`
- Stack: Flutter app + Firebase + Twilio Verify + Algolia + Cloud Run media processor
- Main Firebase production project currently used: `souqali-42fd9`

Follow `AGENTS.md` strictly:

- Do not scan the full repo unless the user explicitly asks.
- Inspect only files directly related to the requested task.
- Prefer minimal diffs.
- Keep responses concise and implementation-focused.
- Do not deploy unless the user asks.

## Important Docs

- `backend.md`
  - Full backend infrastructure audit.
  - Read this before creating a Firebase dev project or changing backend deployment.

- `readme2.md`
  - This handoff file.
  - Keep it updated when major flows change.

## Current Backend Overview

Firebase services currently used:

- Firestore
- Firebase Storage
- Cloud Functions v2
- Firebase Auth SDK exists, but OTP login uses Twilio Verify, not Firebase Phone Auth.

Other backend services:

- Twilio Verify for OTP.
- Algolia for item indexing/search.
- Cloud Run media processor for image/video processing.
- FFmpeg is installed inside the Cloud Run Docker image, not inside Firebase Functions.
- Cloud Scheduler is used through the scheduled Firebase function for expired item cleanup.

Important backend file:

- `functions/index.js`

Important backend audit:

- `backend.md`

## Cloud Functions

Known functions in `functions/index.js`:

- `sendOtp`
- `verifyOtp`
- `getFeedItems`
- `markFeedItemsSeen`
- `getItemViewCounts`
- `renewLiveItem`
- `deleteItemCompletely`
- `deleteSellerAccount`
- `processNewItemMedia`
- `ensureNewItemSellerStatus`
- `processUpdatedItemMedia`
- `syncItemToAlgolia`
- `createItemInAlgolia`
- `deleteItemFromAlgolia`
- `syncSellerStatusToItems`
- `backfillAlgoliaItems`
- `backfillSellerStatuses`
- `cleanupExpiredItems`

Runtime:

- Node.js 22

Region:

- `us-central1`

## OTP Login Flow

Current desired/login behavior:

1. User enters Oman phone number.
2. User clicks the OTP button.
3. App checks seller status before sending OTP.
4. If seller is banned/suspended/blocked, show blocked account popup and do not send OTP.
5. If seller is active, app calls Firebase Function `sendOtp`.
6. Flutter gets Android SMS app hash using `sms_autofill` and sends it to `sendOtp`.
7. `sendOtp` calls Twilio Verify and passes the app hash.
8. Twilio sends 4-digit OTP SMS with Android app hash.
9. Android SMS Retriever detects the SMS.
10. OTP popup fields fill automatically.
11. When the 4th digit is filled, login verifies automatically.
12. User does not need to press the login button after all 4 digits are entered.

OTP details:

- OTP length is 4 digits.
- Android autofill is working.
- SMS Retriever works without SMS permission.
- iOS does not use Android SMS Retriever hash. iOS may show system OTP suggestion above keyboard if SMS format is compatible.

Important files:

- `lib/seller_home_page.dart`
- `functions/index.js`
- `pubspec.yaml`

Package:

- `sms_autofill`

Notes:

- `Get OTP` text was removed from the button. The button now keeps only the icon/logo.
- Do not change OTP UI unless requested.
- Keep OTP status validation before sending OTP to avoid wasting Twilio OTP sends.

Deploy commands if OTP function changes:

```powershell
firebase.cmd deploy --only functions:sendOtp,functions:verifyOtp --project souqali-42fd9
```

## Seller Ban/Login Validation

Current intended behavior:

- Seller status is checked before sending OTP.
- If seller is banned/blocked/suspended, OTP flow must not open/send.
- Blocked account popup appears immediately after clicking the OTP button.

Main file:

- `lib/seller_home_page.dart`

Backend file:

- `functions/index.js`

## Item Seen / View Count Logic

Current behavior:

- Feed/live item seen logic records views in Firestore.
- Seen records are stored under item/viewer style collections.
- Listing page shows item view count as text like:
  - `0 Views`
  - `1 View`
  - `50 Views`

Important files:

- `lib/seller_tabs/seller_listings_tab.dart`
- `lib/widgets/item_card.dart`
- `functions/index.js`

Backend function:

- `getItemViewCounts`

Current UI:

- View count appears aligned left.
- It appears directly above item information.
- It uses styling similar to item expiry/info badge.
- It was moved into the item info area to remove the unwanted vertical gap when optional seller info is missing.

Current performance note:

- View count currently loads separately from item documents through `getItemViewCounts`.
- This can cause a short delay where `0 Views` appears first, then updates.
- Faster/instant future approach would be adding a denormalized `view_count` field on `items` and updating it when a new unique view is recorded.
- Do not implement this unless the user asks.

Deploy command if view count function changes:

```powershell
firebase.cmd deploy --only functions:getItemViewCounts --project souqali-42fd9
```

## Live Item Renew Logic

Current behavior:

- A live item can be renewed maximum 4 times.
- Renew count is stored on the existing `items` document.
- Fields:
  - `renew_count`
  - `last_renewed_at`
- Default old items are treated as `renew_count = 0`.

Backend function:

- `renewLiveItem`

Important files:

- `functions/index.js`
- `lib/seller_tabs/seller_listings_tab.dart`

Rules:

- Only live items can be renewed.
- Item must belong to the seller.
- Seller must not be blocked/suspended.
- Maximum renew count is 4.
- Renew updates expiry to the current live renew duration.

UI behavior:

- Renew button text shows remaining count:
  - `Renew (4)`
  - `Renew (3)`
  - `Renew (2)`
  - `Renew (1)`
  - `Renew (0)`
- When remaining count is `0`, button becomes grey and disabled.

Deploy command if renew function changes:

```powershell
firebase.cmd deploy --only functions:renewLiveItem --project souqali-42fd9
```

## Media Processing / FFmpeg

FFmpeg is not inside Firebase Functions.

Media processor:

- Folder: `media_processor`
- Dockerfile installs FFmpeg using apt.
- Service runs on Cloud Run.
- Functions call the Cloud Run media processor URL.

Important files:

- `media_processor/Dockerfile`
- `media_processor/index.js`
- `media_processor/package.json`
- `functions/index.js`

Deploy Cloud Run media processor from terminal:

```powershell
cd D:\souqaliv1\media_processor
gcloud run deploy <SERVICE_NAME> --source . --region us-central1 --project <PROJECT_ID>
```

Important:

- `firebase deploy` does not deploy this Cloud Run media processor.
- For a dev Firebase/GCP project, deploy a separate dev Cloud Run service and update the function config/code URL to point to dev.

## Auto Delete / Scheduled Cleanup

Scheduled cleanup function:

- `cleanupExpiredItems`

Behavior:

- Runs every 1 hour.
- Timezone: `Asia/Muscat`
- Deletes/cleans expired listings.

Deployment:

```powershell
firebase.cmd deploy --only functions:cleanupExpiredItems --project souqali-42fd9
```

Notes:

- Cloud Scheduler setup is created by Firebase deploy after billing/APIs are enabled.
- No separate manual scheduler creation should be needed in normal deploy flow.

## Firebase Development Project Migration

User plans to create a separate Firebase Development project.

User will manually handle:

- Create Firebase dev project.
- Enable billing.
- Create Firestore.
- Enable Storage.
- Add Android app.
- Add iOS app.
- Download new Firebase config files.
- Create/choose Twilio Verify service.
- Create/choose Algolia dev app/index/API key.
- Provide secret values.

Codex can handle from terminal:

- Replace Firebase config files in the project.
- Set Firebase Function secrets.
- Deploy Firestore rules/indexes.
- Deploy Cloud Functions.
- Deploy Cloud Run media processor.
- Set Cloud Run env vars.
- Update dev URLs/config.
- Inspect logs.
- Debug deployment errors.

Read `backend.md` before doing migration work.

## Common Commands

Analyze Flutter:

```powershell
flutter analyze --no-fatal-infos
```

Deploy all functions:

```powershell
firebase.cmd deploy --only functions --project souqali-42fd9
```

Deploy Firestore rules/indexes:

```powershell
firebase.cmd deploy --only firestore --project souqali-42fd9
```

Play Console release build with Android Studio JBR:

```powershell
$env:JAVA_HOME='D:\AndroidStudio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
flutter clean
flutter pub get
flutter build appbundle --release
```

Expected output:

- `build\app\outputs\bundle\release\app-release.aab`

## Recent Validation Notes

- OTP Android autofill was tested by the user and works.
- User confirmed 4-digit OTP messages arrive.
- User confirmed manual OTP login worked before autofill was fixed.
- View count UI was adjusted to remove unwanted spacing.
- Renew limit UI and backend were implemented and analyzed successfully.
- iOS-related changes were pulled from GitHub after MacinCloud work.
- Android side was considered low risk after the iOS pull.

## Caution

- Do not print secret values.
- Do not hardcode new production credentials into docs.
- Do not change backend project IDs casually.
- Do not deploy production functions unless user explicitly asks.
- Do not run broad repo scans unless the user asks for a full audit.

