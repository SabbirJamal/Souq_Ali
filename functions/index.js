const { onSchedule } = require("firebase-functions/v2/scheduler");
const { logger } = require("firebase-functions");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");

initializeApp();

const db = getFirestore();
const bucket = getStorage().bucket();

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
  await removeItemStories(itemId);

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
    }
  }

  if (
    typeof item.audio_description_url === "string" &&
    item.audio_description_url.trim()
  ) {
    urls.add(item.audio_description_url);
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

async function removeItemStories(itemId) {
  const stories = await db
    .collection("stories")
    .where("item_id", "==", itemId)
    .get();

  if (stories.empty) {
    return;
  }

  const batch = db.batch();
  for (const story of stories.docs) {
    batch.delete(story.ref);
  }
  await batch.commit();
  logger.info(`Deleted ${stories.size} story document(s) for item ${itemId}.`);
}
