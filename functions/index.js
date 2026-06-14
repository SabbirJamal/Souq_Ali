const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { FieldPath, getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const db = getFirestore();
const bucket = getStorage().bucket();
const DEFAULT_FEED_LIMIT = 16;
const MAX_FEED_LIMIT = 32;
const FEED_FETCH_BATCH_SIZE = 100;
const FEED_MAX_SCANNED_DOCS = 600;
const MEDIA_PROCESSOR_URL =
  "https://bizsooq-media-processor-r7y3ppqj6q-uc.a.run.app";
const FEED_ITEM_FIELDS = [
  "created_at",
  "expires_at",
  "image_urls",
  "is_transit",
  "item_name",
  "item_price",
  "location",
  "media_files",
  "media_processing_status",
  "price_number",
  "price_unit",
  "seller_name",
  "seller_phone",
  "seller_uid",
  "status",
  "time_period_hours",
];

exports.getFeedItems = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    const viewerId = stringValue(request.data && request.data.viewerId);
    const status = stringValue(request.data && request.data.status);
    const cursor = request.data && request.data.cursor ? request.data.cursor : null;
    const limit = normalizedLimit(request.data && request.data.limit);

    if (!viewerId) {
      throw new HttpsError("invalid-argument", "viewerId is required.");
    }
    if (status !== "post" && status !== "live") {
      throw new HttpsError("invalid-argument", "status must be post or live.");
    }

    try {
      const seenIds = await loadViewerSeenIds(viewerId);
      const now = Timestamp.now();
      const unseen = [];
      const seenFallback = [];
      let queryCursor = normalizeCursor(cursor);
      let scanned = 0;
      let hasMore = true;
      let lastCursor = queryCursor;
      let filledPageBeforeBatchEnd = false;

      while (unseen.length < limit && scanned < FEED_MAX_SCANNED_DOCS && hasMore) {
        let query = db
          .collection("items")
          .where("status", "==", status)
          .orderBy("created_at", "desc")
          .orderBy(FieldPath.documentId(), "desc")
          .select(...FEED_ITEM_FIELDS)
          .limit(FEED_FETCH_BATCH_SIZE);

        if (queryCursor) {
          query = query.startAfter(
            Timestamp.fromMillis(queryCursor.createdAtMs),
            queryCursor.docId,
          );
        }

        const snapshot = await query.get();
        hasMore = snapshot.size === FEED_FETCH_BATCH_SIZE;

        for (let index = 0; index < snapshot.docs.length; index += 1) {
          const doc = snapshot.docs[index];
          scanned += 1;
          const item = doc.data();
          lastCursor = cursorFromDoc(doc);

          if (!isItemVisible(item, now)) {
            continue;
          }

          const entry = { id: doc.id, data: serializeFeedItem(item), cursor: lastCursor };
          if (seenIds.has(doc.id)) {
            if (seenFallback.length < limit) {
              seenFallback.push(entry);
            }
          } else {
            unseen.push(entry);
            if (unseen.length >= limit) {
              filledPageBeforeBatchEnd =
                index < snapshot.docs.length - 1 || snapshot.size === FEED_FETCH_BATCH_SIZE;
              break;
            }
          }
        }

        if (!lastCursor) {
          hasMore = false;
        }
        queryCursor = lastCursor;
        if (snapshot.empty) {
          hasMore = false;
        }
      }

      const remainingSlots = Math.max(limit - unseen.length, 0);
      const selectedItems = unseen
        .slice(0, limit)
        .concat(seenFallback.slice(0, remainingSlots));
      const responseCursor =
        selectedItems.length > 0
          ? selectedItems[selectedItems.length - 1].cursor
          : lastCursor;

      return {
        items: selectedItems.map((item) => ({ id: item.id, data: item.data })),
        cursor: responseCursor,
        hasMore: Boolean(hasMore || filledPageBeforeBatchEnd || scanned >= FEED_MAX_SCANNED_DOCS),
      };
    } catch (error) {
      logger.error("getFeedItems failed", { viewerId, status, error });
      throw new HttpsError("internal", error && error.message ? error.message : "Feed loading failed.");
    }
  },
);

exports.markFeedItemsSeen = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (request) => {
    const viewerId = stringValue(request.data && request.data.viewerId);
    const viewerType = stringValue(request.data && request.data.viewerType) || "anonymous";
    const rawItemIds = Array.isArray(request.data && request.data.itemIds)
      ? request.data.itemIds
      : [];
    const itemIds = [...new Set(rawItemIds.map(stringValue).filter(Boolean))].slice(0, 120);

    if (!viewerId) {
      throw new HttpsError("invalid-argument", "viewerId is required.");
    }
    if (itemIds.length === 0) {
      return { written: 0 };
    }

    const batch = db.batch();
    const seenAt = Timestamp.now();

    for (const itemId of itemIds) {
      const seenData = {
        item_id: itemId,
        viewer_id: viewerId,
        viewer_type: viewerType,
        seen_at: seenAt,
      };
      if (viewerType === "seller") {
        seenData.seller_id = viewerId;
      }

      batch.set(
        db.collection("item_seen").doc(itemId).collection("viewers").doc(viewerId),
        seenData,
        { merge: true },
      );
      batch.set(
        db.collection("viewer_seen").doc(viewerId).collection("items").doc(itemId),
        seenData,
        { merge: true },
      );
    }

    await batch.commit();
    return { written: itemIds.length };
  },
);

exports.processNewItemMedia = onDocumentCreated(
  {
    document: "items/{itemId}",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (event) => {
    const itemId = event.params.itemId;
    const item = event.data && event.data.data ? event.data.data() : {};
    const mediaFiles = Array.isArray(item.media_files) ? item.media_files : [];

    if (mediaFiles.length === 0) {
      logger.info("Skipping media processor; item has no media.", { itemId });
      return;
    }

    try {
      logger.info("Calling media processor.", {
        itemId,
        mediaCount: mediaFiles.length,
        url: MEDIA_PROCESSOR_URL,
      });

      const response = await fetch(`${MEDIA_PROCESSOR_URL}/process`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ itemId }),
      });

      if (!response.ok) {
        const body = await response.text();
        throw new Error(`Media processor failed ${response.status}: ${body}`);
      }

      const body = await response.text();
      logger.info("Media processor completed.", { itemId, response: body });
    } catch (error) {
      logger.error("Failed calling media processor.", { itemId, error });
      throw error;
    }
  },
);

exports.processUpdatedItemMedia = onDocumentUpdated(
  {
    document: "items/{itemId}",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (event) => {
    const itemId = event.params.itemId;
    const before = event.data && event.data.before ? event.data.before.data() : {};
    const after = event.data && event.data.after ? event.data.after.data() : {};
    const mediaFiles = Array.isArray(after.media_files) ? after.media_files : [];

    if (mediaFiles.length === 0 || !hasMediaWaitingForProcessing(after, before)) {
      return;
    }

    try {
      logger.info("Calling media processor for updated item.", {
        itemId,
        mediaCount: mediaFiles.length,
        url: MEDIA_PROCESSOR_URL,
      });

      const response = await fetch(`${MEDIA_PROCESSOR_URL}/process`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ itemId }),
      });

      if (!response.ok) {
        const body = await response.text();
        throw new Error(`Media processor failed ${response.status}: ${body}`);
      }

      const body = await response.text();
      logger.info("Media processor completed for updated item.", { itemId, response: body });
    } catch (error) {
      logger.error("Failed calling media processor for updated item.", { itemId, error });
      throw error;
    }
  },
);

exports.cleanupExpiredItems = onSchedule(
  {
    schedule: "every 6 hours",
    timeZone: "Asia/Muscat",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const now = Timestamp.now();
    const expiredItems = await db
      .collection("items")
      .where("expires_at", "<=", now)
      .limit(50)
      .get();

    if (expiredItems.empty) {
      logger.info("No expired items found.");
      return;
    }

    logger.info(`Cleaning ${expiredItems.size} expired item(s).`);

    for (const itemDoc of expiredItems.docs) {
      if (isItemExpired(itemDoc.data(), now)) {
        await cleanupItem(itemDoc);
      } else {
        logger.info(`Skipping item ${itemDoc.id}; selected time period is still active.`);
      }
    }
  },
);

function isItemExpired(item, now) {
  const effectiveExpiresAt = effectiveExpiryTimestamp(item);
  if (!effectiveExpiresAt) {
    return false;
  }
  return effectiveExpiresAt.toMillis() <= now.toMillis();
}

function effectiveExpiryTimestamp(item) {
  const createdAt = item.created_at;
  const timePeriodHours = Number(item.time_period_hours);

  if (
    createdAt &&
    typeof createdAt.toMillis === "function" &&
    Number.isFinite(timePeriodHours) &&
    timePeriodHours > 0
  ) {
    return Timestamp.fromMillis(
      createdAt.toMillis() + (timePeriodHours * 60 * 60 * 1000),
    );
  }

  const expiresAt = item.expires_at;
  if (expiresAt && typeof expiresAt.toMillis === "function") {
    return expiresAt;
  }

  return null;
}

async function cleanupItem(itemDoc) {
  const itemId = itemDoc.id;
  const item = itemDoc.data();

  logger.info(`Cleaning expired item ${itemId}.`);

  const mediaUrls = collectMediaUrls(item);
  await deleteStorageFiles(mediaUrls);
  await removeItemSeenRecords(itemId);

  await itemDoc.ref.delete();
  logger.info(`Deleted expired item ${itemId}.`);
}

function collectMediaUrls(item) {
  const urls = new Set();

  if (Array.isArray(item.image_urls)) {
    for (const url of item.image_urls) {
      if (typeof url === "string" && url.trim()) {
        urls.add(url);
      }
    }
  }

  if (Array.isArray(item.media_files)) {
    for (const media of item.media_files) {
      if (media && typeof media.url === "string" && media.url.trim()) {
        urls.add(media.url);
      }
      if (
        media &&
        typeof media.thumbnail_url === "string" &&
        media.thumbnail_url.trim()
      ) {
        urls.add(media.thumbnail_url);
      }
      if (
        media &&
        typeof media.raw_url === "string" &&
        media.raw_url.trim()
      ) {
        urls.add(media.raw_url);
      }
      if (
        media &&
        typeof media.raw_thumbnail_url === "string" &&
        media.raw_thumbnail_url.trim()
      ) {
        urls.add(media.raw_thumbnail_url);
      }
    }
  }

  return [...urls];
}

async function deleteStorageFiles(urls) {
  for (const url of urls) {
    const filePath = storagePathFromUrl(url);
    if (!filePath) {
      logger.warn(`Could not read storage path from URL: ${url}`);
      continue;
    }

    try {
      await bucket.file(filePath).delete({ ignoreNotFound: true });
      logger.info(`Deleted storage file: ${filePath}`);
    } catch (error) {
      logger.error(`Failed deleting storage file: ${filePath}`, error);
    }
  }
}

function storagePathFromUrl(url) {
  if (url.startsWith("gs://")) {
    const withoutScheme = url.slice(5);
    const firstSlash = withoutScheme.indexOf("/");
    return firstSlash === -1 ? "" : withoutScheme.slice(firstSlash + 1);
  }

  try {
    const parsed = new URL(url);

    if (parsed.hostname === "firebasestorage.googleapis.com") {
      const match = parsed.pathname.match(/\/o\/(.+)$/);
      return match ? decodeURIComponent(match[1]) : "";
    }

    if (parsed.hostname === "storage.googleapis.com") {
      const parts = parsed.pathname.split("/").filter(Boolean);
      return parts.length > 1 ? decodeURIComponent(parts.slice(1).join("/")) : "";
    }
  } catch (error) {
    logger.warn(`Invalid media URL: ${url}`, error);
  }

  return "";
}

async function removeItemSeenRecords(itemId) {
  const seenDocRef = db.collection("item_seen").doc(itemId);
  const viewers = await seenDocRef.collection("viewers").get();

  if (!viewers.empty) {
    let batch = db.batch();
    let count = 0;
    for (const viewer of viewers.docs) {
      batch.delete(viewer.ref);
      count += 1;
      if (count % 450 === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    logger.info(`Deleted ${viewers.size} seen viewer document(s) for item ${itemId}.`);
  }

  await seenDocRef.delete();

  const mirrored = await db
    .collectionGroup("items")
    .where("item_id", "==", itemId)
    .limit(500)
    .get();

  if (!mirrored.empty) {
    let batch = db.batch();
    let count = 0;
    for (const doc of mirrored.docs) {
      batch.delete(doc.ref);
      count += 1;
      if (count % 450 === 0) {
        await batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    logger.info(`Deleted ${mirrored.size} mirrored seen document(s) for item ${itemId}.`);
  }
}

async function loadViewerSeenIds(viewerId) {
  const seenIds = new Set();
  const seen = await db
    .collection("viewer_seen")
    .doc(viewerId)
    .collection("items")
    .limit(5000)
    .get();

  for (const doc of seen.docs) {
    seenIds.add(doc.id);
  }

  return seenIds;
}

function stringValue(value) {
  return typeof value === "string" ? value.trim() : "";
}

function normalizedLimit(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_FEED_LIMIT;
  }
  return Math.min(Math.max(Math.floor(parsed), 1), MAX_FEED_LIMIT);
}

function normalizeCursor(cursor) {
  if (!cursor || typeof cursor !== "object") {
    return null;
  }
  const createdAtMs = Number(cursor.createdAtMs);
  const docId = stringValue(cursor.docId);
  if (!Number.isFinite(createdAtMs) || !docId) {
    return null;
  }
  return { createdAtMs, docId };
}

function cursorFromDoc(doc) {
  const createdAt = doc.get("created_at");
  if (!createdAt || typeof createdAt.toMillis !== "function") {
    return null;
  }
  return { createdAtMs: createdAt.toMillis(), docId: doc.id };
}

function isItemVisible(item, now) {
  const status = stringValue(item.status);
  if (status !== "post" && status !== "live") {
    return false;
  }
  if (stringValue(item.media_processing_status) === "pending") {
    return false;
  }
  return isItemExpired(item, now) === false;
}

function hasMediaWaitingForProcessing(after, before) {
  const status = stringValue(after.media_processing_status);
  if (status !== "pending") {
    return false;
  }
  if (stringValue(before.media_processing_status) === "processing") {
    return false;
  }
  return (Array.isArray(after.media_files) ? after.media_files : []).some((media) => {
    if (!media || typeof media !== "object") {
      return false;
    }
    const type = stringValue(media.type).toLowerCase();
    return (
      (type === "image" || type === "photo" || type === "video") &&
      stringValue(media.url) &&
      stringValue(media.processing_status) !== "done"
    );
  });
}

function serializeItem(item) {
  const serialized = {};
  for (const [key, value] of Object.entries(item)) {
    serialized[key] = serializeValue(value);
  }
  return serialized;
}

function serializeFeedItem(item) {
  const serialized = {};
  for (const key of FEED_ITEM_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(item, key)) {
      serialized[key] = serializeValue(item[key]);
    }
  }
  return serialized;
}

function serializeValue(value) {
  if (value && typeof value.toMillis === "function") {
    return { __timestampMs: value.toMillis() };
  }
  if (Array.isArray(value)) {
    return value.map(serializeValue);
  }
  if (value && typeof value === "object") {
    const output = {};
    for (const [key, child] of Object.entries(value)) {
      output[key] = serializeValue(child);
    }
    return output;
  }
  return value;
}
