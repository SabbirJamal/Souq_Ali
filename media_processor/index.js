import express from 'express';
import { Firestore } from '@google-cloud/firestore';
import { Storage } from '@google-cloud/storage';
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { lookup as lookupMime } from 'mime-types';
import { v4 as uuidv4 } from 'uuid';

const app = express();
app.use(express.json({ limit: '1mb' }));

const firestore = new Firestore();
const storage = new Storage();
const bucketName =
  process.env.FIREBASE_STORAGE_BUCKET || `${process.env.GOOGLE_CLOUD_PROJECT}.firebasestorage.app`;

const imageTypes = new Set(['image', 'photo']);
const videoTypes = new Set(['video']);
const optimizedThumbWidth = 520;

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'bizsooq-media-processor' });
});

app.post('/process', async (req, res) => {
  const { itemId } = req.body || {};
  if (!itemId || typeof itemId !== 'string') {
    res.status(400).json({ ok: false, error: 'itemId is required' });
    return;
  }

  try {
    console.log('[media-processor] start item', itemId);
    const result = await processItem(itemId);
    console.log('[media-processor] done item', itemId, result);
    res.json({ ok: true, ...result });
  } catch (error) {
    console.error('process failed', error);
    res.status(500).json({ ok: false, error: error.message || 'process failed' });
  }
});

async function processItem(itemId) {
  const itemRef = firestore.collection('items').doc(itemId);
  const itemSnap = await itemRef.get();
  if (!itemSnap.exists) {
    throw new Error(`items/${itemId} does not exist`);
  }

  const item = itemSnap.data() || {};
  const mediaFiles = Array.isArray(item.media_files) ? item.media_files : [];
  if (mediaFiles.length === 0) {
    await itemRef.update({ media_processing_status: 'skipped_empty' });
    return { processed: 0, skipped: 0 };
  }

  await itemRef.update({ media_processing_status: 'processing' });

  const updatedMedia = [];
  let processed = 0;
  let skipped = 0;

  for (let index = 0; index < mediaFiles.length; index += 1) {
    const media = mediaFiles[index] || {};
    const type = `${media.type || ''}`.toLowerCase();
    const url = media.url || media.optimized_url;

    if (!url || media.processing_status === 'done') {
      updatedMedia.push(media);
      skipped += 1;
      continue;
    }

    if (!imageTypes.has(type) && !videoTypes.has(type)) {
      updatedMedia.push(media);
      skipped += 1;
      continue;
    }

    try {
      console.log('[media-processor] processing media', { itemId, index, type });
      const optimized = await processMedia({
        itemId,
        index,
        media,
        type,
        sourceUrl: url,
      });
      console.log('[media-processor] media done', {
        itemId,
        index,
        type,
        path: optimized.path,
      });
      updatedMedia.push({
        ...media,
        raw_url: media.raw_url || url,
        raw_thumbnail_url: media.raw_thumbnail_url || media.thumbnail_url,
        url: optimized.downloadUrl,
        optimized_path: optimized.path,
        thumbnail_url: optimized.thumbnailDownloadUrl || media.thumbnail_url,
        thumbnail_path: optimized.thumbnailPath || media.thumbnail_path,
        processing_status: 'done',
      });
      processed += 1;
    } catch (error) {
      console.error(`media ${index} failed`, error);
      updatedMedia.push({
        ...media,
        processing_status: 'failed',
        processing_error: error.message || 'compression failed',
      });
    }
  }

  await itemRef.update({
    media_files: updatedMedia,
    media_processing_status: processed > 0 ? 'done' : 'skipped',
    media_processed_at: Firestore.Timestamp.now(),
  });

  return { processed, skipped };
}

async function processMedia({ itemId, index, media, type, sourceUrl }) {
  const sourcePath = storagePathFromUrl(sourceUrl);
  const isVideo = videoTypes.has(type);
  const extension = isVideo ? 'mp4' : 'jpg';
  const tempDir = await mkdtemp(path.join(tmpdir(), 'bizsooq-media-'));
  const inputPath = path.join(tempDir, `input-${index}`);
  const outputPath = path.join(tempDir, `output-${index}.${extension}`);
  const thumbnailPath = path.join(tempDir, `thumb-${index}.jpg`);

  try {
    const bucket = storage.bucket(bucketName);
    await bucket.file(sourcePath).download({ destination: inputPath });

    if (isVideo) {
      await runFfmpeg([
        '-y',
        '-i',
        inputPath,
        '-vf',
        "scale='if(gt(iw,ih),min(720,iw),-2)':'if(gt(iw,ih),-2,min(720,ih))'",
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '28',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        outputPath,
      ]);
      await runFfmpeg([
        '-y',
        '-ss',
        '00:00:00.4',
        '-i',
        outputPath,
        '-frames:v',
        '1',
        '-vf',
        `scale='if(gt(iw,ih),min(${optimizedThumbWidth},iw),-2)':'if(gt(iw,ih),-2,min(${optimizedThumbWidth},ih))'`,
        '-q:v',
        '5',
        thumbnailPath,
      ]);
    } else {
      await runFfmpeg([
        '-y',
        '-i',
        inputPath,
        '-vf',
        "scale='if(gt(iw,ih),min(1280,iw),-2)':'if(gt(iw,ih),-2,min(1280,ih))'",
        '-q:v',
        '5',
        outputPath,
      ]);
      await runFfmpeg([
        '-y',
        '-i',
        outputPath,
        '-vf',
        `scale='if(gt(iw,ih),min(${optimizedThumbWidth},iw),-2)':'if(gt(iw,ih),-2,min(${optimizedThumbWidth},ih))'`,
        '-q:v',
        '6',
        thumbnailPath,
      ]);
    }

    const destination = optimizedPathFor({ itemId, index, media, extension });
    const uploaded = await uploadProcessedFile(bucket, outputPath, destination, extension);
    const thumbDestination = optimizedPathFor({
      itemId,
      index,
      media,
      extension: 'jpg',
      suffix: 'thumb',
    });
    const uploadedThumb = await uploadProcessedFile(bucket, thumbnailPath, thumbDestination, 'jpg');

    return {
      path: destination,
      downloadUrl: uploaded.downloadUrl,
      thumbnailPath: thumbDestination,
      thumbnailDownloadUrl: uploadedThumb.downloadUrl,
    };
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

async function uploadProcessedFile(bucket, filePath, destination, extension) {
  const downloadToken = uuidv4();
  await bucket.upload(filePath, {
    destination,
    metadata: {
      contentType: lookupMime(extension) || 'application/octet-stream',
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
      cacheControl: 'public,max-age=31536000,immutable',
    },
  });
  return {
    downloadUrl: firebaseDownloadUrl(bucketName, destination, downloadToken),
  };
}

function optimizedPathFor({ itemId, index, media, extension, suffix = '' }) {
  const rawPath = media.raw_path || media.path || '';
  const rawDir = rawPath.includes('/') ? rawPath.slice(0, rawPath.lastIndexOf('/')) : `items/${itemId}`;
  const suffixText = suffix ? `_${suffix}` : '';
  return `${rawDir}/optimized/${itemId}_${index}${suffixText}_${Date.now()}.${extension}`;
}

function storagePathFromUrl(url) {
  if (url.startsWith('gs://')) {
    const withoutScheme = url.slice(5);
    const firstSlash = withoutScheme.indexOf('/');
    return withoutScheme.slice(firstSlash + 1);
  }

  const marker = '/o/';
  const markerIndex = url.indexOf(marker);
  if (markerIndex === -1) {
    throw new Error('Unsupported Storage URL');
  }

  const encodedPath = url.slice(markerIndex + marker.length).split('?')[0];
  return decodeURIComponent(encodedPath);
}

function firebaseDownloadUrl(bucket, objectPath, token) {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(
    objectPath,
  )}?alt=media&token=${token}`;
}

function runFfmpeg(args) {
  return new Promise((resolve, reject) => {
    const child = spawn('ffmpeg', args);
    let stderr = '';

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr || `ffmpeg exited with code ${code}`));
      }
    });
  });
}

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`media processor listening on ${port}`);
});
