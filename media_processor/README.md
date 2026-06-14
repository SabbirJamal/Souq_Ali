# Bizsooq Media Processor

Cloud Run service for backend media compression.

## What It Does

- Receives an `itemId`
- Reads `items/{itemId}` from Firestore
- Downloads each image/video from Firebase Storage
- Compresses media with FFmpeg
- Uploads optimized media back to Storage
- Updates `media_files` in Firestore

## Local Shape

```text
media_processor/
  Dockerfile
  package.json
  index.js
```

## Endpoints

```http
GET /health
POST /process
```

Body:

```json
{
  "itemId": "FIRESTORE_ITEM_ID"
}
```

## Environment

Cloud Run should use:

```text
FIREBASE_STORAGE_BUCKET=souqali-42fd9.firebasestorage.app
GOOGLE_CLOUD_PROJECT=souqali-42fd9
```

## Next Step

Connect this service from a Firestore trigger. The trigger should call `/process`
after a new `items/{itemId}` document is created.
