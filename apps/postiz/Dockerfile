# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Postiz overlay — adds generic S3 (MinIO) storage support on top of the stock image.
#
# Stock Postiz hardcodes the S3 endpoint to <accountID>.r2.cloudflarestorage.com and
# uses virtual-hosted addressing in BOTH upload paths:
#   - cloudflare.storage.js  (simple PutObject — public API / server uploads)
#   - r2.uploader.js         (multipart upload — the browser/UI upload flow)
# This overlay patches the COMPILED dist (per-file, unminified JS) in the backend and
# orchestrator bundles to add:
#   - CLOUDFLARE_ENDPOINT          → point the S3 client at MinIO (s3.astrateam.net)
#   - CLOUDFLARE_FORCE_PATH_STYLE  → path-style addressing (required by MinIO)
#   - CLOUDFLARE_BUCKET_PREFIX     → write under a key prefix (cloudflare.storage path)
#
# Anchor/regex-based and idempotent; a no-op when the env vars are unset (default
# endpoint = R2, empty prefix = identical keys). STORAGE_PROVIDER stays "cloudflare".
ARG VERSION
FROM ghcr.io/gitroomhq/postiz-app:${VERSION}

COPY <<'PATCH' /tmp/patch.js
const fs = require('fs');
const { execSync } = require('child_process');

const files = execSync(
  "find /app/apps \\( -path '*upload/cloudflare.storage.js' -o -path '*upload/r2.uploader.js' \\)",
  { encoding: 'utf8' }
).split('\n').filter(Boolean);
if (files.length === 0) throw new Error('no upload S3 files found');

const HELPER =
  'function __postizKey(id, extension) {\n' +
  "    const p = (process.env.CLOUDFLARE_BUCKET_PREFIX || '').replace(/^\\/+|\\/+$/g, '');\n" +
  "    return p ? p + '/' + id + '.' + extension : id + '.' + extension;\n" +
  '}\n';

// Matches both `${accountID}` (cloudflare.storage) and `${CLOUDFLARE_ACCOUNT_ID}` (r2.uploader),
// preserving the original indentation.
const epRe = /^(\s*)endpoint: (`https:\/\/\$\{[A-Za-z_0-9]+\}\.r2\.cloudflarestorage\.com`),/m;

for (const f of files) {
  let s = fs.readFileSync(f, 'utf8');
  let changed = false;

  // 1) configurable endpoint (MinIO) + path-style addressing — both files
  if (!s.includes('process.env.CLOUDFLARE_ENDPOINT')) {
    if (!epRe.test(s)) throw new Error('endpoint anchor missing: ' + f);
    s = s.replace(epRe, (m, indent, url) =>
      `${indent}endpoint: process.env.CLOUDFLARE_ENDPOINT || ${url},\n` +
      `${indent}forcePathStyle: process.env.CLOUDFLARE_FORCE_PATH_STYLE === 'true',`);
    changed = true;
  }

  // 2) bucket key prefix — only the simple-upload provider (class CloudflareStorage)
  if (s.includes('class CloudflareStorage {') && !s.includes('__postizKey')) {
    s = s.replace('class CloudflareStorage {', HELPER + 'class CloudflareStorage {');
    s = s.split('Key: `${id}.${extension}`,').join('Key: `${__postizKey(id, extension)}`,');
    s = s.split('`${this._uploadUrl}/${id}.${extension}`')
         .join('`${this._uploadUrl}/${__postizKey(id, extension)}`');
    changed = true;
  }

  if (changed) { fs.writeFileSync(f, s); console.log('patched:', f); }
  else console.log('already patched:', f);
}
console.log('done');
PATCH

RUN node /tmp/patch.js && rm -f /tmp/patch.js && rm -rf /app/node-compile-cache/* 2>/dev/null || true
