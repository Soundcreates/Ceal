/**
 * AfterMath Backend — Image storage service (Cloudinary).
 *
 * Uploads disaster-report images to Cloudinary and returns the
 * secure CDN URL.  Falls back to a data-URI placeholder when
 * Cloudinary credentials are not configured (e.g. in tests).
 */

import crypto from 'node:crypto';
import { v2 as cloudinary } from 'cloudinary';
import { env } from '../config.js';
import { logger } from '../logger.js';

// ---------------------------------------------------------------------------
// Configure Cloudinary SDK (safe to call even when credentials are absent)
// ---------------------------------------------------------------------------
if (env.CLOUDINARY_CLOUD_NAME) {
  cloudinary.config({
    cloud_name: env.CLOUDINARY_CLOUD_NAME,
    api_key: env.CLOUDINARY_API_KEY,
    api_secret: env.CLOUDINARY_API_SECRET,
    secure: true,
  });
  logger.info('Cloudinary configured');
}

/**
 * Compute SHA-256 hash of image bytes (for dedup / replay detection).
 */
export function hashImage(buffer: Buffer): string {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

/**
 * Upload an image to Cloudinary and return the secure URL.
 *
 * Images are stored under the folder `aftermath/{userId}` with the
 * reportId as the public_id, making them easy to locate / delete.
 *
 * When Cloudinary is not configured the function returns a placeholder
 * path so the rest of the pipeline still works (useful in dev/test).
 */
export async function storeImage(
  buffer: Buffer,
  userId: string,
  reportId: string,
  mime: string,
): Promise<string> {
  if (!env.CLOUDINARY_CLOUD_NAME) {
    logger.warn('Cloudinary not configured — returning placeholder URL');
    return `https://placeholder.local/aftermath/${userId}/${reportId}`;
  }

  const result = await new Promise<{ secure_url: string }>((resolve, reject) => {
    const stream = cloudinary.uploader.upload_stream(
      {
        folder: `aftermath/${userId}`,
        public_id: reportId,
        resource_type: 'image',
        overwrite: false,
      },
      (err, uploadResult) => {
        if (err) return reject(err);
        resolve(uploadResult as { secure_url: string });
      },
    );
    stream.end(buffer);
  });

  logger.info(
    `Image uploaded to Cloudinary: ${result.secure_url} (${buffer.length} bytes)`,
  );
  return result.secure_url;
}

/**
 * Validate that the uploaded buffer is an allowed image type.
 * Checks magic bytes, not the declared MIME type.
 */
export function validateImageMagic(buffer: Buffer): string | null {
  if (buffer.length < 4) return null;

  // JPEG: FF D8 FF
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return 'image/png';
  }
  // WebP: RIFF....WEBP
  if (
    buffer.length >= 12 &&
    buffer[0] === 0x52 &&
    buffer[1] === 0x49 &&
    buffer[2] === 0x46 &&
    buffer[3] === 0x46 &&
    buffer[8] === 0x57 &&
    buffer[9] === 0x45 &&
    buffer[10] === 0x42 &&
    buffer[11] === 0x50
  ) {
    return 'image/webp';
  }

  return null;
}
