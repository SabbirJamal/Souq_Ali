const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { FieldPath, FieldValue, getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const db = getFirestore();
const bucket = getStorage().bucket();
const ALGOLIA_WRITE_API_KEY = defineSecret("ALGOLIA_WRITE_API_KEY");
const ALGOLIA_BACKFILL_TOKEN = defineSecret("ALGOLIA_BACKFILL_TOKEN");
const ALGOLIA_APPLICATION_ID = "ZI4NULCVNS";
const ALGOLIA_INDEX_NAME = "bizsooq";
const DEFAULT_FEED_LIMIT = 16;
const MAX_FEED_LIMIT = 32;
const FEED_FETCH_BATCH_SIZE = 100;
const FEED_MAX_SCANNED_DOCS = 400;
const FEED_SEEN_LOOKBACK_LIMIT = 1500;
const SELLER_STATUS_ACTIVE = "active";
const SELLER_STATUS_SUSPENDED = "suspended";
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
  "seller_status",
  "seller_uid",
  "share_code",
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

    const startedAt = Date.now();
    let seenLoadMs = 0;
    let itemQueryMs = 0;
    let filteringMs = 0;
    let batches = 0;

    try {
      const seenStartedAt = Date.now();
      const seenIds = await loadViewerSeenIds(viewerId);
      seenLoadMs = Date.now() - seenStartedAt;
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
          .where("seller_status", "==", SELLER_STATUS_ACTIVE)
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

        const queryStartedAt = Date.now();
        const snapshot = await query.get();
        itemQueryMs += Date.now() - queryStartedAt;
        batches += 1;
        hasMore = snapshot.size === FEED_FETCH_BATCH_SIZE;

        const filteringStartedAt = Date.now();
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
        filteringMs += Date.now() - filteringStartedAt;

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

      const totalMs = Date.now() - startedAt;
      logger.info("getFeedItems timing", {
        viewerId,
        status,
        limit,
        returned: selectedItems.length,
        scanned,
        batches,
        seenCount: seenIds.size,
        seenLoadMs,
        itemQueryMs,
        filteringMs,
        totalMs,
      });

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

exports.deleteItemCompletely = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request) => {
    const itemId = stringValue(request.data && request.data.itemId);
    const sellerUid = stringValue(request.data && request.data.sellerUid);

    try {
      if (!itemId) {
        throw new HttpsError("invalid-argument", "itemId is required.");
      }

      const itemRef = db.collection("items").doc(itemId);
      const itemDoc = await itemRef.get();
      if (!itemDoc.exists) {
        return { deleted: false, reason: "not_found" };
      }

      const item = itemDoc.data() || {};
      if (sellerUid && stringValue(item.seller_uid) && stringValue(item.seller_uid) !== sellerUid) {
        throw new HttpsError("permission-denied", "sellerUid does not match item owner.");
      }

      await cleanupItem(itemDoc);
      return { deleted: true };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("deleteItemCompletely failed", {
        itemId,
        sellerUid,
        error,
      });
      throw new HttpsError(
        "internal",
        error && error.message ? error.message : "Item delete failed.",
      );
    }
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

exports.syncItemToAlgolia = onDocumentUpdated(
  {
    document: "items/{itemId}",
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [ALGOLIA_WRITE_API_KEY],
  },
  async (event) => {
    const itemId = event.params.itemId;
    const item = event.data && event.data.after ? event.data.after.data() : {};
    await upsertAlgoliaItem(itemId, item);
  },
);

exports.createItemInAlgolia = onDocumentCreated(
  {
    document: "items/{itemId}",
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [ALGOLIA_WRITE_API_KEY],
  },
  async (event) => {
    const itemId = event.params.itemId;
    const item = event.data && event.data.data ? event.data.data() : {};
    await upsertAlgoliaItem(itemId, item);
  },
);

exports.deleteItemFromAlgolia = onDocumentDeleted(
  {
    document: "items/{itemId}",
    region: "us-central1",
    timeoutSeconds: 60,
    memory: "256MiB",
    secrets: [ALGOLIA_WRITE_API_KEY],
  },
  async (event) => {
    await deleteAlgoliaItem(event.params.itemId);
  },
);

exports.syncSellerStatusToItems = onDocumentUpdated(
  {
    document: "sellers/{sellerId}",
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async (event) => {
    const sellerId = event.params.sellerId;
    const before = event.data && event.data.before ? event.data.before.data() : {};
    const after = event.data && event.data.after ? event.data.after.data() : {};
    const beforeStatus = normalizeSellerStatus(before.status);
    const afterStatus = normalizeSellerStatus(after.status);

    if (beforeStatus === afterStatus) {
      return;
    }

    let updated = 0;
    let lastDoc = null;
    while (true) {
      let query = db
        .collection("items")
        .where("seller_uid", "==", sellerId)
        .orderBy(FieldPath.documentId())
        .limit(400);
      if (lastDoc) {
        query = query.startAfter(lastDoc);
      }

      const snapshot = await query.get();

      if (snapshot.empty) {
        break;
      }
      lastDoc = snapshot.docs[snapshot.docs.length - 1];

      const batch = db.batch();
      let batchUpdates = 0;
      for (const doc of snapshot.docs) {
        if (stringValue(doc.get("seller_status")) === afterStatus) {
          continue;
        }
        batch.update(doc.ref, {
          seller_status: afterStatus,
          updated_at: FieldValue.serverTimestamp(),
        });
        batchUpdates += 1;
      }
      if (batchUpdates > 0) {
        await batch.commit();
        updated += batchUpdates;
      }
    }

    logger.info("Seller status synced to items.", {
      sellerId,
      beforeStatus,
      afterStatus,
      updated,
    });
  },
);

exports.backfillAlgoliaItems = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
    secrets: [ALGOLIA_WRITE_API_KEY, ALGOLIA_BACKFILL_TOKEN],
  },
  async (request, response) => {
    const token = stringValue(request.body && request.body.token);
    const cursor = stringValue(request.body && request.body.cursor);
    const expectedToken = ALGOLIA_BACKFILL_TOKEN.value();

    if (!expectedToken || token !== expectedToken) {
      response.status(403).json({ ok: false, error: "forbidden" });
      return;
    }

    let query = db
      .collection("items")
      .orderBy(FieldPath.documentId())
      .limit(300);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    let indexed = 0;
    let skipped = 0;
    let lastId = cursor || "";

    for (const doc of snapshot.docs) {
      lastId = doc.id;
      const item = doc.data();
      if (shouldIndexAlgoliaItem(item)) {
        await upsertAlgoliaItem(doc.id, item);
        indexed += 1;
      } else {
        await deleteAlgoliaItem(doc.id);
        skipped += 1;
      }
    }

    response.json({
      ok: true,
      indexed,
      skipped,
      nextCursor: snapshot.size === 300 ? lastId : null,
    });
  },
);

exports.backfillSellerStatuses = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 300,
    memory: "512MiB",
    secrets: [ALGOLIA_BACKFILL_TOKEN],
  },
  async (request, response) => {
    const token = stringValue(request.body && request.body.token);
    const cursor = stringValue(request.body && request.body.cursor);
    const mode = stringValue(request.body && request.body.mode) || "sellers";
    const expectedToken = ALGOLIA_BACKFILL_TOKEN.value();

    if (!expectedToken || token !== expectedToken) {
      response.status(403).json({ ok: false, error: "forbidden" });
      return;
    }
    if (mode !== "sellers" && mode !== "items") {
      response.status(400).json({ ok: false, error: "mode must be sellers or items" });
      return;
    }

    const collection = mode === "sellers" ? "sellers" : "items";
    let query = db.collection(collection).orderBy(FieldPath.documentId()).limit(300);
    if (cursor) {
      query = query.startAfter(cursor);
    }

    const snapshot = await query.get();
    const batch = db.batch();
    let updated = 0;
    let skipped = 0;
    let lastId = cursor || "";

    for (const doc of snapshot.docs) {
      lastId = doc.id;
      const data = doc.data() || {};
      if (mode === "sellers") {
        if (!stringValue(data.status)) {
          batch.set(doc.ref, {
            status: SELLER_STATUS_ACTIVE,
            updatedAt: Timestamp.now(),
          }, { merge: true });
          updated += 1;
        } else {
          skipped += 1;
        }
      } else if (!stringValue(data.seller_status)) {
        batch.set(doc.ref, {
          seller_status: SELLER_STATUS_ACTIVE,
          updated_at: Timestamp.now(),
        }, { merge: true });
        updated += 1;
      } else {
        skipped += 1;
      }
    }

    if (updated > 0) {
      await batch.commit();
    }

    response.json({
      ok: true,
      mode,
      updated,
      skipped,
      nextCursor: snapshot.size === 300 ? lastId : null,
    });
  },
);

exports.cleanupExpiredItems = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "Asia/Muscat",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const now = Timestamp.now();
    let cleaned = 0;

    while (true) {
      const expiredItems = await db
        .collection("items")
        .where("expires_at", "<=", now)
        .limit(50)
        .get();

      if (expiredItems.empty) {
        if (cleaned === 0) {
          logger.info("No expired items found.");
        } else {
          logger.info(`Expired cleanup completed. Deleted ${cleaned} item(s).`);
        }
        return;
      }

      logger.info(`Cleaning ${expiredItems.size} expired item(s) in current batch.`);

      for (const itemDoc of expiredItems.docs) {
        if (isItemExpired(itemDoc.data(), now)) {
          await cleanupItem(itemDoc);
          cleaned += 1;
        } else {
          logger.info(`Skipping item ${itemDoc.id}; selected time period is still active.`);
        }
      }
    }
  },
);

async function upsertAlgoliaItem(itemId, item) {
  if (!shouldIndexAlgoliaItem(item)) {
    await deleteAlgoliaItem(itemId);
    return;
  }

  const record = algoliaRecordFromItem(itemId, item);
  const response = await fetch(algoliaObjectUrl(itemId), {
    method: "PUT",
    headers: algoliaHeaders(),
    body: JSON.stringify(record),
  });

  if (!response.ok) {
    const body = await response.text();
    logger.error("Algolia item sync failed.", {
      itemId,
      status: response.status,
      body,
    });
    throw new Error(`Algolia sync failed ${response.status}: ${body}`);
  }

  logger.info("Algolia item synced.", { itemId });
}

async function deleteAlgoliaItem(itemId) {
  if (!itemId) return;
  const response = await fetch(algoliaObjectUrl(itemId), {
    method: "DELETE",
    headers: algoliaHeaders(),
  });

  if (!response.ok && response.status !== 404) {
    const body = await response.text();
    logger.error("Algolia item delete failed.", {
      itemId,
      status: response.status,
      body,
    });
    throw new Error(`Algolia delete failed ${response.status}: ${body}`);
  }

  logger.info("Algolia item deleted.", { itemId });
}

function shouldIndexAlgoliaItem(item) {
  const status = stringValue(item.status);
  if (status !== "post" && status !== "live") return false;
  const sellerStatus = stringValue(item.seller_status);
  if (sellerStatus && sellerStatus !== SELLER_STATUS_ACTIVE) return false;
  if (!isItemVisible(item, Timestamp.now())) return false;
  return hasUsableMedia(item);
}

function normalizeSellerStatus(value) {
  const status = stringValue(value);
  return status === SELLER_STATUS_SUSPENDED ? SELLER_STATUS_SUSPENDED : SELLER_STATUS_ACTIVE;
}

function algoliaRecordFromItem(itemId, item) {
  const createdAtMs = timestampMillis(item.created_at);
  const expiresAtMs = timestampMillis(item.expires_at);
  return {
    objectID: itemId,
    created_at_ms: createdAtMs,
    expires_at_ms: expiresAtMs,
    created_at: createdAtMs ? { __timestampMs: createdAtMs } : null,
    expires_at: expiresAtMs ? { __timestampMs: expiresAtMs } : null,
    image_urls: Array.isArray(item.image_urls) ? item.image_urls : [],
    is_transit: item.is_transit === true,
    item_name: stringValue(item.item_name),
    item_price: stringValue(item.item_price),
    location: stringValue(item.location),
    media_files: Array.isArray(item.media_files) ? item.media_files : [],
    media_processing_status: stringValue(item.media_processing_status),
    price_number: Number(item.price_number) || 0,
    price_unit: stringValue(item.price_unit),
    seller_name: stringValue(item.seller_name),
    seller_phone: stringValue(item.seller_phone),
    seller_status: stringValue(item.seller_status) || SELLER_STATUS_ACTIVE,
    seller_uid: stringValue(item.seller_uid),
    share_code: stringValue(item.share_code),
    status: stringValue(item.status),
  };
}

function algoliaObjectUrl(itemId) {
  return `https://${ALGOLIA_APPLICATION_ID}.algolia.net/1/indexes/${ALGOLIA_INDEX_NAME}/${encodeURIComponent(itemId)}`;
}

function algoliaHeaders() {
  return {
    "Content-Type": "application/json",
    "X-Algolia-Application-Id": ALGOLIA_APPLICATION_ID,
    "X-Algolia-API-Key": ALGOLIA_WRITE_API_KEY.value(),
  };
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === "function") {
    return value.toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return 0;
}

function isItemExpired(item, now) {
  const effectiveExpiresAt = effectiveExpiryTimestamp(item);
  if (!effectiveExpiresAt) {
    return false;
  }
  return effectiveExpiresAt.toMillis() <= now.toMillis();
}

function effectiveExpiryTimestamp(item) {
  const expiresAt = item.expires_at;
  if (expiresAt && typeof expiresAt.toMillis === "function") {
    return expiresAt;
  }

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

  return null;
}

async function cleanupItem(itemDoc) {
  const itemId = itemDoc.id;
  const item = itemDoc.data();

  logger.info(`Cleaning expired item ${itemId}.`);

  const mediaRefs = collectMediaStorageRefs(itemId, item);
  await deleteStorageFiles(mediaRefs);
  await removeItemSeenRecords(itemId);

  await itemDoc.ref.delete();
  logger.info(`Deleted expired item ${itemId}.`);
}

function collectMediaStorageRefs(itemId, item) {
  const urls = new Set();
  const paths = new Set();
  const prefixes = new Set();

  if (Array.isArray(item.image_urls)) {
    for (const url of item.image_urls) {
      if (typeof url === "string" && url.trim()) {
        urls.add(url);
      }
    }
  }

  if (Array.isArray(item.media_files)) {
    for (let index = 0; index < item.media_files.length; index += 1) {
      const media = item.media_files[index];
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

      for (const key of ["path", "raw_path", "optimized_path", "thumbnail_path"]) {
        if (media && typeof media[key] === "string" && media[key].trim()) {
          paths.add(media[key].trim());
        }
      }

      const rawPath =
        media && typeof media.raw_path === "string" && media.raw_path.trim()
          ? media.raw_path.trim()
          : media && typeof media.path === "string" && media.path.trim()
            ? media.path.trim()
            : "";
      const optimizedPrefix = optimizedStoragePrefix(itemId, index, rawPath);
      if (optimizedPrefix) {
        prefixes.add(optimizedPrefix);
      }
    }
  }

  return {
    urls: [...urls],
    paths: [...paths],
    prefixes: [...prefixes],
  };
}

function optimizedStoragePrefix(itemId, index, rawPath) {
  if (!rawPath) {
    return `items/${itemId}/optimized/${itemId}_${index}`;
  }

  const lastSlash = rawPath.lastIndexOf("/");
  const rawDir = lastSlash === -1 ? `items/${itemId}` : rawPath.slice(0, lastSlash);
  return `${rawDir}/optimized/${itemId}_${index}`;
}

async function deleteStorageFiles({ urls, paths, prefixes }) {
  for (const url of urls) {
    const filePath = storagePathFromUrl(url);
    if (!filePath) {
      logger.warn(`Could not read storage path from URL: ${url}`);
      continue;
    }

    await deleteStoragePath(filePath);
  }

  for (const filePath of paths) {
    await deleteStoragePath(filePath);
  }

  for (const prefix of prefixes) {
    await deleteStoragePrefix(prefix);
  }
}

async function deleteStoragePath(filePath) {
  if (!filePath) {
    return;
  }

  try {
    await bucket.file(filePath).delete({ ignoreNotFound: true });
    logger.info(`Deleted storage file: ${filePath}`);
  } catch (error) {
    logger.error(`Failed deleting storage file: ${filePath}`, error);
  }
}

async function deleteStoragePrefix(prefix) {
  if (!prefix) {
    return;
  }

  try {
    const [files] = await bucket.getFiles({ prefix });
    if (!files.length) {
      return;
    }

    for (const file of files) {
      try {
        await file.delete({ ignoreNotFound: true });
        logger.info(`Deleted storage file via prefix ${prefix}: ${file.name}`);
      } catch (error) {
        logger.error(`Failed deleting storage file via prefix ${prefix}: ${file.name}`, error);
      }
    }
  } catch (error) {
    logger.error(`Failed listing storage prefix: ${prefix}`, error);
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
  let deletedViewers = 0;

  while (true) {
    const viewers = await seenDocRef.collection("viewers").limit(400).get();
    if (viewers.empty) {
      break;
    }

    const batch = db.batch();
    for (const viewer of viewers.docs) {
      batch.delete(viewer.ref);
      batch.delete(
        db.collection("viewer_seen").doc(viewer.id).collection("items").doc(itemId),
      );
    }
    await batch.commit();
    deletedViewers += viewers.size;
  }

  if (deletedViewers > 0) {
    logger.info(`Deleted ${deletedViewers} seen viewer document(s) for item ${itemId}.`);
  }

  await seenDocRef.delete();

  try {
    let deletedMirrored = 0;
    while (true) {
      const mirrored = await db
        .collectionGroup("items")
        .where("item_id", "==", itemId)
        .limit(400)
        .get();

      if (mirrored.empty) {
        break;
      }

      const batch = db.batch();
      for (const doc of mirrored.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
      deletedMirrored += mirrored.size;
    }

    if (deletedMirrored > 0) {
      logger.info(`Deleted ${deletedMirrored} mirrored seen document(s) for item ${itemId}.`);
    }
  } catch (error) {
    logger.error(`Failed mirrored seen cleanup for item ${itemId}.`, error);
  }
}

async function loadViewerSeenIds(viewerId) {
  const seenIds = new Set();
  const seen = await db
    .collection("viewer_seen")
    .doc(viewerId)
    .collection("items")
    .orderBy("seen_at", "desc")
    .limit(FEED_SEEN_LOOKBACK_LIMIT)
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
  const sellerStatus = stringValue(item.seller_status);
  if (sellerStatus && sellerStatus !== SELLER_STATUS_ACTIVE) {
    return false;
  }
  if (isItemExpired(item, now)) {
    return false;
  }
  const hasMedia = hasUsableMedia(item);
  if (stringValue(item.media_processing_status) === "pending" && !hasMedia) {
    return false;
  }
  return hasMedia;
}

function hasUsableMedia(item) {
  const mediaFiles = Array.isArray(item.media_files) ? item.media_files : [];
  if (mediaFiles.some((media) => media && typeof media === "object" && stringValue(media.url))) {
    return true;
  }

  const imageUrls = Array.isArray(item.image_urls) ? item.image_urls : [];
  return imageUrls.some((url) => stringValue(url));
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
