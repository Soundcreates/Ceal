import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const jsQR = require('jsqr') as (
  data: Uint8ClampedArray,
  width: number,
  height: number,
  options?: { inversionAttempts?: 'dontInvert' | 'onlyInvert' | 'attemptBoth' | 'invertFirst' },
) => { data?: string } | null;

export interface DecodedQrPhoto {
  rawPayload: string;
}

export interface AadhaarQrExtracted {
  name: string | null;
  gender: string | null;
  state: string | null;
  dob: string | null;
  yob: string | null;
}

export function decodeQrFromRgba(
  width: number,
  height: number,
  rgba: Uint8ClampedArray,
): DecodedQrPhoto {
  const attempts = generateTransforms(width, height, rgba);
  for (const candidate of attempts) {
    const qr = jsQR(candidate.rgba, candidate.width, candidate.height, {
      inversionAttempts: 'attemptBoth',
    });
    if (qr?.data && qr.data.trim().length > 0) {
      return { rawPayload: qr.data.trim() };
    }
  }

  throw new Error('No QR code detected in image');
}

export async function parseAadhaarQrPayload(raw: string): Promise<AadhaarQrExtracted> {
  const fromSelf = await tryParseWithSelfSdk(raw);
  if (fromSelf) {
    return {
      name: normalizeField(fromSelf.name),
      gender: normalizeField(fromSelf.gender),
      state: normalizeField(fromSelf.state),
      dob: normalizeField(fromSelf.dob),
      yob: normalizeField(fromSelf.yob),
    };
  }
  return parseAadhaarQrXml(raw);
}

function generateTransforms(width: number, height: number, rgba: Uint8ClampedArray): Array<{
  width: number;
  height: number;
  rgba: Uint8ClampedArray;
}> {
  const variants = [{ width, height, rgba }];
  variants.push(rotate90(width, height, rgba));
  variants.push(rotate180(width, height, rgba));
  variants.push(rotate270(width, height, rgba));
  return variants;
}

function rotate90(width: number, height: number, rgba: Uint8ClampedArray) {
  const out = new Uint8ClampedArray(rgba.length);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const src = (y * width + x) * 4;
      const nx = height - 1 - y;
      const ny = x;
      const dst = (ny * height + nx) * 4;
      out[dst] = rgba[src];
      out[dst + 1] = rgba[src + 1];
      out[dst + 2] = rgba[src + 2];
      out[dst + 3] = rgba[src + 3];
    }
  }
  return { width: height, height: width, rgba: out };
}

function rotate180(width: number, height: number, rgba: Uint8ClampedArray) {
  const out = new Uint8ClampedArray(rgba.length);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const src = (y * width + x) * 4;
      const nx = width - 1 - x;
      const ny = height - 1 - y;
      const dst = (ny * width + nx) * 4;
      out[dst] = rgba[src];
      out[dst + 1] = rgba[src + 1];
      out[dst + 2] = rgba[src + 2];
      out[dst + 3] = rgba[src + 3];
    }
  }
  return { width, height, rgba: out };
}

function rotate270(width: number, height: number, rgba: Uint8ClampedArray) {
  const out = new Uint8ClampedArray(rgba.length);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const src = (y * width + x) * 4;
      const nx = y;
      const ny = width - 1 - x;
      const dst = (ny * height + nx) * 4;
      out[dst] = rgba[src];
      out[dst + 1] = rgba[src + 1];
      out[dst + 2] = rgba[src + 2];
      out[dst + 3] = rgba[src + 3];
    }
  }
  return { width: height, height: width, rgba: out };
}

async function tryParseWithSelfSdk(rawPayload: string): Promise<Partial<AadhaarQrExtracted> | null> {
  try {
    const sdk = require('@selfxyz/qrcode') as Record<string, unknown>;
    const maybeParser =
      sdk.parseAadhaarQr ??
      sdk.parseQRCode ??
      sdk.parse;

    if (typeof maybeParser !== 'function') {
      return null;
    }

    const result = await (maybeParser as (input: string) => Promise<unknown> | unknown)(rawPayload);
    if (!result || typeof result !== 'object') {
      return null;
    }
    const obj = result as Record<string, unknown>;
    return {
      name: asString(obj.name),
      gender: asString(obj.gender),
      state: asString(obj.state),
      dob: asString(obj.dob),
      yob: asString(obj.yob),
    };
  } catch {
    return null;
  }
}

function parseAadhaarQrXml(raw: string): AadhaarQrExtracted {
  const xml = extractXml(raw);
  const nodeMatch = xml.match(/<\s*PrintLetterBarcodeData\b([^>]*)\/?>/i);
  if (!nodeMatch || !nodeMatch[1]) {
    throw new Error('Aadhaar QR XML must contain PrintLetterBarcodeData');
  }

  const attrs = new Map<string, string>();
  const attrRegex = /([a-zA-Z_:][\w:.-]*)\s*=\s*"([^"]*)"/g;
  let m: RegExpExecArray | null;
  while ((m = attrRegex.exec(nodeMatch[1])) !== null) {
    const key = m[1];
    const value = m[2];
    if (!key) continue;
    attrs.set(key.toLowerCase(), decodeXmlEntities(value ?? ''));
  }

  return {
    name: normalizeField(attrs.get('name')),
    gender: normalizeField(attrs.get('gender')),
    state: normalizeField(attrs.get('state')),
    dob: normalizeField(attrs.get('dob')),
    yob: normalizeField(attrs.get('yob')),
  };
}

function extractXml(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith('<')) return trimmed;

  try {
    const decoded = decodeURIComponent(trimmed);
    if (decoded.includes('<')) return decoded;
  } catch {
    // Non URI-encoded payload; fall through.
  }

  const start = trimmed.indexOf('<');
  const end = trimmed.lastIndexOf('>');
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1);
  }

  throw new Error('No XML found in QR payload');
}

function decodeXmlEntities(value: string): string {
  return value
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

function normalizeField(value: string | undefined | null): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function asString(v: unknown): string | undefined {
  return typeof v === 'string' ? v : undefined;
}
