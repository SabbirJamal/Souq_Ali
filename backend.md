# Bizsooq Backend Infrastructure Audit

This audit documents the current backend infrastructure used by the Bizsooq app so a separate Firebase Development project can be recreated safely.

No secrets are printed in this file.

## 1. Firebase Services

### Firestore

Purpose:
- Main app database for sellers, items, item seen records, viewer seen records, and app configuration.

Files using it:
- `lib/**`
- `functions/index.js`
- `firestore.rules`
- `firestore.indexes.json`

Manual setup required in a new Firebase project:
- Enable Firestore.
- Deploy Firestore rules.
- Deploy Firestore indexes.
- Decide production vs development seed data.

### Firebase Storage

Purpose:
- Stores item media, thumbnails, optimized images, videos, and seller-uploaded item assets.

Files using it:
- Flutter upload/media code in `lib/**`
- Cleanup logic in `functions/index.js`
- Media processor logic in `media_processor/index.js`

Manual setup required:
- Enable Firebase Storage.
- Configure Storage rules manually or add a `storage.rules` file.
- Configure dev bucket name in Cloud Run environment.

### Cloud Functions

Purpose:
- OTP, feed loading, seen tracking, item cleanup, Algolia sync, media processing triggers, seller validation, renew logic.

Files:
- `functions/index.js`
- `functions/package.json`

Manual setup required:
- Enable Cloud Functions.
- Enable required Google Cloud APIs.
- Create required secrets before deploy.
- Deploy functions to the new project.

### Firebase Authentication

Purpose:
- Firebase Auth SDK is present and used for current-user fallback in app code.
- OTP login itself is handled through Twilio Verify, not Firebase Phone Auth.

Files:
- `pubspec.yaml`
- Flutter files using `firebase_auth`

Manual setup required:
- Enable Authentication only if the app still depends on Firebase Auth users.
- No Firebase Phone Auth setup is currently the main OTP flow.

### Hosting

Status:
- No active Firebase Hosting usage found.

Manual setup required:
- Not required unless a web frontend is added later.

### App Check

Status:
- No active App Check usage found.

Manual setup required:
- Not required currently.

### Cloud Messaging

Status:
- No active Firebase Cloud Messaging usage found in the inspected backend flow.

Manual setup required:
- Not required currently.

### Remote Config

Status:
- No active Remote Config usage found.

Manual setup required:
- Not required currently.

### Extensions

Status:
- No Firebase Extensions usage found.

Manual setup required:
- Not required currently.

## 2. Cloud Functions

Runtime:
- Node.js 22

Source:
- `functions/index.js`

Default region:
- `us-central1`

### `sendOtp`

Trigger:
- Callable HTTPS function

Memory:
- 256 MiB

Timeout:
- 30 seconds

Purpose:
- Sends OTP through Twilio Verify.
- Accepts optional Android SMS app hash for SMS Retriever autofill.

Dependencies:
- Twilio Verify
- Firestore seller status lookup
- Firebase Functions secrets

Secrets:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_VERIFY_SERVICE_SID`

Redeploy to new project:
- Yes, after secrets and Twilio service are configured.

### `verifyOtp`

Trigger:
- Callable HTTPS function

Memory:
- 256 MiB

Timeout:
- 30 seconds

Purpose:
- Verifies OTP through Twilio Verify.

Dependencies:
- Twilio Verify
- Firestore seller lookup/session flow

Secrets:
- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- `TWILIO_VERIFY_SERVICE_SID`

Redeploy to new project:
- Yes, after secrets and Twilio service are configured.

### `getFeedItems`

Trigger:
- Callable HTTPS function

Memory:
- 512 MiB

Timeout:
- 60 seconds

Purpose:
- Loads feed items from Firestore.

Dependencies:
- Firestore

Redeploy to new project:
- Yes.

### `markFeedItemsSeen`

Trigger:
- Callable HTTPS function

Memory:
- 256 MiB

Timeout:
- 30 seconds

Purpose:
- Writes item seen records.

Dependencies:
- Firestore

Collections:
- `item_seen/{itemId}/viewers/{viewerId}`
- `viewer_seen/{viewerId}/items/{itemId}`

Redeploy to new project:
- Yes.

### `getItemViewCounts`

Trigger:
- Callable HTTPS function

Memory:
- 256 MiB

Timeout:
- 30 seconds

Purpose:
- Returns item view counts using Firestore count aggregation.

Dependencies:
- Firestore

Redeploy to new project:
- Yes.

### `renewLiveItem`

Trigger:
- Callable HTTPS function

Memory:
- 256 MiB

Timeout:
- 30 seconds

Purpose:
- Renews live items.
- Enforces maximum renew count of 4.
- Updates `renew_count` and `last_renewed_at`.

Dependencies:
- Firestore transactions

Redeploy to new project:
- Yes.

### `deleteItemCompletely`

Trigger:
- Callable HTTPS function

Memory:
- 512 MiB

Timeout:
- 120 seconds

Purpose:
- Deletes item document and related media/storage references.

Dependencies:
- Firestore
- Firebase Storage
- Algolia cleanup if applicable

Redeploy to new project:
- Yes, after Storage and Algolia config are ready.

### `deleteSellerAccount`

Trigger:
- Callable HTTPS function

Memory:
- 512 MiB

Timeout:
- 540 seconds

Purpose:
- Deletes seller account data and related items/media.

Dependencies:
- Firestore
- Firebase Storage

Redeploy to new project:
- Yes.

### `processNewItemMedia`

Trigger:
- Firestore `onDocumentCreated("items/{itemId}")`

Memory:
- 512 MiB

Timeout:
- 540 seconds

Purpose:
- Sends newly created item media to the Cloud Run media processor.

Dependencies:
- Firestore
- Cloud Run media processor
- Firebase Storage

Redeploy to new project:
- Yes, but the Cloud Run media processor must also exist and the URL must point to the correct environment.

### `ensureNewItemSellerStatus`

Trigger:
- Firestore `onDocumentCreated("items/{itemId}")`

Memory:
- 256 MiB

Timeout:
- 60 seconds

Purpose:
- Ensures new item carries seller status metadata.

Dependencies:
- Firestore

Redeploy to new project:
- Yes.

### `processUpdatedItemMedia`

Trigger:
- Firestore `onDocumentUpdated("items/{itemId}")`

Memory:
- 512 MiB

Timeout:
- 540 seconds

Purpose:
- Sends updated item media to the Cloud Run media processor.

Dependencies:
- Firestore
- Cloud Run media processor
- Firebase Storage

Redeploy to new project:
- Yes, but Cloud Run URL must be configured for the new project.

### `syncItemToAlgolia`

Trigger:
- Firestore `onDocumentUpdated("items/{itemId}")`

Memory:
- 256 MiB

Timeout:
- 60 seconds

Purpose:
- Syncs updated items to Algolia.

Dependencies:
- Firestore
- Algolia

Secrets:
- `ALGOLIA_WRITE_API_KEY`

Redeploy to new project:
- Yes, after Algolia dev index/API key is ready.

### `createItemInAlgolia`

Trigger:
- Firestore `onDocumentCreated("items/{itemId}")`

Memory:
- 256 MiB

Timeout:
- 60 seconds

Purpose:
- Creates Algolia records for new items.

Dependencies:
- Firestore
- Algolia

Secrets:
- `ALGOLIA_WRITE_API_KEY`

Redeploy to new project:
- Yes, after Algolia dev index/API key is ready.

### `deleteItemFromAlgolia`

Trigger:
- Firestore `onDocumentDeleted("items/{itemId}")`

Memory:
- 256 MiB

Timeout:
- 60 seconds

Purpose:
- Deletes Algolia records for deleted items.

Dependencies:
- Algolia

Secrets:
- `ALGOLIA_WRITE_API_KEY`

Redeploy to new project:
- Yes, after Algolia dev index/API key is ready.

### `syncSellerStatusToItems`

Trigger:
- Firestore `onDocumentUpdated("sellers/{sellerId}")`

Memory:
- 512 MiB

Timeout:
- 300 seconds

Purpose:
- Syncs seller status changes to seller items.

Dependencies:
- Firestore

Redeploy to new project:
- Yes.

### `backfillAlgoliaItems`

Trigger:
- HTTP `onRequest`

Memory:
- 512 MiB

Timeout:
- 300 seconds

Purpose:
- Backfills item records into Algolia.

Dependencies:
- Firestore
- Algolia

Secrets:
- `ALGOLIA_WRITE_API_KEY`
- `ALGOLIA_BACKFILL_TOKEN`

Redeploy to new project:
- Yes, after Algolia dev index/API key is ready.

### `backfillSellerStatuses`

Trigger:
- HTTP `onRequest`

Memory:
- 512 MiB

Timeout:
- 300 seconds

Purpose:
- Backfills seller status metadata.

Dependencies:
- Firestore

Secrets:
- `ALGOLIA_BACKFILL_TOKEN`

Redeploy to new project:
- Yes.

### `cleanupExpiredItems`

Trigger:
- Scheduled function

Memory:
- 512 MiB

Timeout:
- 540 seconds

Schedule:
- Every 1 hour

Timezone:
- Asia/Muscat

Purpose:
- Deletes or cleans expired listings.

Dependencies:
- Cloud Scheduler
- Pub/Sub/Eventarc support services
- Firestore
- Firebase Storage

Redeploy to new project:
- Yes, after required scheduler APIs are enabled.

## 3. Scheduled Jobs

### `cleanupExpiredItems`

Frequency:
- Every 1 hour

Trigger:
- Firebase scheduled function / Cloud Scheduler

Dependency:
- Cloud Scheduler
- Pub/Sub
- Eventarc

Additional setup:
- Firebase deploy usually creates the scheduler job automatically once APIs and billing are enabled.
- New project must have billing and required APIs enabled.

## 4. FFmpeg

FFmpeg is not running inside Firebase Cloud Functions.

FFmpeg is used inside the separate Cloud Run media processor.

Files:
- `media_processor/Dockerfile`
- `media_processor/index.js`
- `media_processor/package.json`
- `media_processor/README.md`

How FFmpeg is installed:
- Docker image is based on `node:22-bookworm-slim`.
- `apt-get install -y ffmpeg` installs FFmpeg during Docker build.

How FFmpeg is executed:
- `media_processor/index.js` runs FFmpeg using Node child process `spawn("ffmpeg", args)`.

Is `ffmpeg-static` used:
- No.

Is a binary bundled:
- No.

Is Docker used:
- Yes, for the Cloud Run service.

Does Firebase deploy recreate FFmpeg:
- No.
- Cloud Run must be separately built and deployed for the new Firebase/GCP project.

## 5. Google Cloud Services

### Cloud Functions v2

Used for:
- All Firebase functions.

Manual setup:
- Enable API.
- Deploy functions.

### Cloud Run

Used for:
- Media processor service.

Manual setup:
- Build and deploy `media_processor`.
- Configure environment variables.
- Configure IAM/invoker permissions.
- Update function URL/config if using a new dev service URL.

### Cloud Scheduler

Used for:
- `cleanupExpiredItems`.

Manual setup:
- Enable API.
- Deploy scheduled function.

### Cloud Build

Used for:
- Firebase Functions deployment.
- Cloud Run image builds.

Manual setup:
- Enable API.

### Artifact Registry

Used for:
- Cloud Functions/Cloud Run build artifacts.

Manual setup:
- Enable API.
- Usually created automatically by deployments.

### Eventarc

Used for:
- Cloud Functions v2 triggers.

Manual setup:
- Enable API.
- Usually configured by Firebase deploy.

### Pub/Sub

Used for:
- Scheduled functions and Firebase internal triggers.

Manual setup:
- Enable API.
- Usually configured by Firebase deploy.

### Secret Manager

Used for:
- Twilio and Algolia secrets.

Manual setup:
- Create all required secrets in the dev project.

### Cloud Storage / Firebase Storage

Used for:
- Item media.
- Processed media.
- Cleanup flows.

Manual setup:
- Enable Storage.
- Configure bucket/rules.

### Cloud Logging

Used for:
- Function and Cloud Run logs.

Manual setup:
- Usually automatic.

## 6. Firestore

Rules file:
- `firestore.rules`

Current rules:
- Open read/write rule: `allow read, write: if true`.

Indexes file:
- `firestore.indexes.json`

Composite indexes:
- Collection: `items`
- Fields:
  - `seller_status` ascending
  - `status` ascending
  - `created_at` descending
  - `__name__` descending

Collections found:
- `items`
- `sellers`
- `item_seen`
- `item_seen/{itemId}/viewers`
- `viewer_seen`
- `viewer_seen/{viewerId}/items`
- `app_config`
- `app_config/ios`

Notes:
- Some docs mention older `stories` behavior, but active inspected source did not show current backend usage for `stories`.

Manual setup:
- Deploy rules and indexes.
- Seed required app config documents if needed.
- Create dev test data.

## 7. Firebase Storage

Current production bucket from config:
- Production bucket exists in Firebase config.
- Do not reuse production bucket for development.

Upload paths:
- `items/{sellerUid}/...`
- Item media files
- Thumbnails
- Edit thumbnails
- Optimized media paths under item media folders

Cleanup logic:
- `deleteItemCompletely`
- `deleteSellerAccount`
- `cleanupExpiredItems`

Storage rules:
- No `storage.rules` file found.
- `firebase.json` does not define Storage rules deployment.

Manual setup:
- Create/enable Storage bucket in dev project.
- Add or manually configure Storage rules.
- Ensure Cloud Run media processor points to dev bucket.

## 8. Authentication

Login methods:
- Seller phone number login.
- OTP sent and verified through Twilio Verify.

Twilio integration:
- `sendOtp` sends OTP through Twilio Verify.
- `verifyOtp` verifies code through Twilio Verify.
- Android OTP autofill uses app hash with Twilio Verify SMS message.

Firebase Auth usage:
- Firebase Auth SDK exists.
- OTP flow is not Firebase Phone Auth.
- Some app code may use `FirebaseAuth.instance.currentUser` as fallback.

Manual setup:
- Configure Twilio Verify service for dev.
- Configure SMS template/hash behavior for Android OTP autofill.
- Enable Firebase Auth only if current app flows require it.

## 9. Environment Variables, Secrets, API Keys, Config

Secret values are intentionally not printed.

### Firebase Functions secrets

`TWILIO_ACCOUNT_SID`
- Purpose: Twilio account identifier.
- Used in: `functions/index.js`.

`TWILIO_AUTH_TOKEN`
- Purpose: Twilio API authentication.
- Used in: `functions/index.js`.

`TWILIO_VERIFY_SERVICE_SID`
- Purpose: Twilio Verify service identifier.
- Used in: `functions/index.js`.

`ALGOLIA_WRITE_API_KEY`
- Purpose: Write access for Algolia indexing.
- Used in: `functions/index.js`.

`ALGOLIA_BACKFILL_TOKEN`
- Purpose: Protects HTTP backfill endpoints.
- Used in: `functions/index.js`.

### Hardcoded/backend config values

`ALGOLIA_APPLICATION_ID`
- Purpose: Algolia app ID.
- Used in: `functions/index.js`.

`ALGOLIA_INDEX_NAME`
- Purpose: Algolia index name.
- Used in: `functions/index.js`.

`MEDIA_PROCESSOR_URL`
- Purpose: Cloud Run media processor endpoint.
- Used in: `functions/index.js`.
- Important: This must point to the dev Cloud Run service in a dev project.

### Cloud Run environment variables

`FIREBASE_STORAGE_BUCKET`
- Purpose: Storage bucket used by media processor.
- Used in: `media_processor/index.js`.

`GOOGLE_CLOUD_PROJECT`
- Purpose: Google Cloud project context.
- Used by Google Cloud SDK/admin clients.

`PORT`
- Purpose: Cloud Run HTTP server port.
- Used by media processor server.

### Firebase client config

Firebase client config files exist for Android and iOS.

Files:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- Flutter Firebase options file if present in source

Purpose:
- Connects mobile apps to the Firebase project.

Manual setup:
- Create Android and iOS apps in the new Firebase project.
- Replace configs with development project configs.
- Do not mix production app configs with dev backend.

## 10. Manual Console Configuration

The following likely require one-time manual setup in a new Firebase/GCP project:

- Create Firebase project.
- Enable billing.
- Enable Firestore.
- Enable Firebase Storage.
- Enable Cloud Functions.
- Enable Cloud Build.
- Enable Artifact Registry.
- Enable Cloud Run.
- Enable Eventarc.
- Enable Pub/Sub.
- Enable Cloud Scheduler.
- Enable Secret Manager.
- Create Firebase Android app.
- Create Firebase iOS app.
- Download and replace Firebase config files.
- Create all required Firebase Function secrets.
- Configure Twilio Verify service.
- Configure Twilio SMS template/app hash behavior for Android autofill.
- Configure Algolia dev app/index/API key or intentionally reuse production Algolia.
- Deploy Cloud Run media processor.
- Configure Cloud Run IAM invoker permissions.
- Configure Storage rules.
- Seed required Firestore documents.

## 11. Deployment Commands

Use the development project ID in place of `<DEV_PROJECT_ID>`.

Set Firebase project:

```powershell
firebase.cmd use <DEV_PROJECT_ID>
```

Deploy Firestore rules and indexes:

```powershell
firebase.cmd deploy --only firestore --project <DEV_PROJECT_ID>
```

Deploy all functions:

```powershell
firebase.cmd deploy --only functions --project <DEV_PROJECT_ID>
```

Deploy a specific function:

```powershell
firebase.cmd deploy --only functions:sendOtp --project <DEV_PROJECT_ID>
```

Set function secrets:

```powershell
firebase.cmd functions:secrets:set TWILIO_ACCOUNT_SID --project <DEV_PROJECT_ID>
firebase.cmd functions:secrets:set TWILIO_AUTH_TOKEN --project <DEV_PROJECT_ID>
firebase.cmd functions:secrets:set TWILIO_VERIFY_SERVICE_SID --project <DEV_PROJECT_ID>
firebase.cmd functions:secrets:set ALGOLIA_WRITE_API_KEY --project <DEV_PROJECT_ID>
firebase.cmd functions:secrets:set ALGOLIA_BACKFILL_TOKEN --project <DEV_PROJECT_ID>
```

Deploy Cloud Run media processor from `media_processor`:

```powershell
gcloud run deploy <DEV_MEDIA_PROCESSOR_SERVICE_NAME> --source . --region us-central1 --project <DEV_PROJECT_ID>
```

Set Cloud Run environment variables:

```powershell
gcloud run services update <DEV_MEDIA_PROCESSOR_SERVICE_NAME> --region us-central1 --project <DEV_PROJECT_ID> --set-env-vars FIREBASE_STORAGE_BUCKET=<DEV_BUCKET_NAME>
```

Important:
- Cloud Run deployment is separate from Firebase deployment.
- `MEDIA_PROCESSOR_URL` in functions must point to the dev Cloud Run URL.
- Firebase client config files must point to the dev Firebase project before testing dev builds.

## 12. Development Migration Plan

### Automatically recreated by deployment

- Cloud Functions after secrets/APIs are ready.
- Firestore rules from `firestore.rules`.
- Firestore indexes from `firestore.indexes.json`.
- Scheduled function definition for `cleanupExpiredItems`.
- Cloud Functions v2 trigger wiring.
- Artifact Registry/build artifacts used by Firebase deploy.

### Requires one-time manual configuration

- Firebase development project creation.
- Billing enablement.
- Required Google Cloud APIs.
- Firestore database creation.
- Firebase Storage bucket creation.
- Firebase Android app creation.
- Firebase iOS app creation.
- Replacing Android/iOS Firebase config files.
- Firebase Functions secrets.
- Twilio Verify service.
- Twilio Android SMS Retriever app hash/template setup.
- Algolia dev app/index/API key decision.
- Cloud Run media processor service deployment.
- Cloud Run IAM/invoker permissions.
- Cloud Run environment variables.
- Storage rules.
- Required Firestore seed/config documents.

### Must be recreated manually or carefully changed

- Production Firebase config references in mobile app files.
- Hardcoded `MEDIA_PROCESSOR_URL`.
- Algolia application/index configuration if dev should be isolated.
- Any production data needed in development.
- Storage security rules, because no deployable `storage.rules` file currently exists.
- Twilio console configuration.
- Cloud Run service and FFmpeg Docker environment.

## Key Warning

A plain Firebase deploy to a new project is not enough.

Before using a development project safely:
- Replace mobile Firebase config files.
- Create secrets.
- Deploy Firestore rules/indexes.
- Deploy functions.
- Deploy Cloud Run media processor.
- Point functions to the dev Cloud Run URL.
- Configure dev Storage.
- Configure Twilio and Algolia for development.

