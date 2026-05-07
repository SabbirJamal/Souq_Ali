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
    schedule: "every 24 hours",
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
      await cleanupItem(itemDoc);
    }
  },
);

async function cleanupItem(itemDoc) {
  const itemId = itemDoc.id;
  const item = itemDoc.data();
  const sellerId = item.seller_uid || "";

  logger.info(`Cleaning expired item ${itemId}.`);

  const mediaUrls = collectMediaUrls(item);
  await deleteStorageFiles(mediaUrls);

  if (sellerId) {
    await removeItemVideosFromStory(sellerId, itemId);
  }

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

async function removeItemVideosFromStory(sellerId, itemId) {
  const storyRef = db.collection("stories").doc(sellerId);
  const storyDoc = await storyRef.get();
  if (!storyDoc.exists) {
    return;
  }

  const story = storyDoc.data() || {};
  const videos = Array.isArray(story.videos) ? story.videos : [];
  const remainingVideos = videos.filter((video) => video.item_id !== itemId);

  if (remainingVideos.length === videos.length) {
    return;
  }

  if (remainingVideos.length === 0) {
    await storyRef.delete();
    logger.info(`Deleted empty story document for seller ${sellerId}.`);
    return;
  }

  await storyRef.update({
    videos: remainingVideos,
    latest_created_at: latestCreatedAt(remainingVideos),
  });
  logger.info(`Removed expired item videos from seller ${sellerId} story.`);
}

function latestCreatedAt(videos) {
  return videos.reduce((latest, video) => {
    const createdAt = video.created_at;
    if (!latest) {
      return createdAt || Timestamp.now();
    }
    if (createdAt && createdAt.toMillis && createdAt.toMillis() > latest.toMillis()) {
      return createdAt;
    }
    return latest;
  }, null) || Timestamp.now();
}
