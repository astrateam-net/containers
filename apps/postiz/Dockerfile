# syntax=docker/dockerfile:1
# check=skip=InvalidDefaultArgInFrom

# Postiz overlay — adds generic S3 (MinIO) storage support on top of the stock image.
#
# Stock Postiz ships only two storage backends: `local` and `cloudflare`, and the
# "cloudflare" provider hardcodes the S3 endpoint to <accountID>.r2.cloudflarestorage.com,
# uses virtual-hosted addressing, and writes objects to the bucket root. This overlay
# patches the COMPILED provider (no source rebuild needed — the dist is per-file,
# unminified JS) in both the backend and orchestrator bundles to add:
#   - CLOUDFLARE_ENDPOINT          → point the S3 client at MinIO (s3.astrateam.net)
#   - CLOUDFLARE_FORCE_PATH_STYLE  → path-style addressing (required by MinIO)
#   - CLOUDFLARE_BUCKET_PREFIX     → write under a key prefix (subfolder) instead of root
#
# The patch is anchor-based and idempotent, and is a no-op when the new env vars are
# unset (default endpoint = R2, empty prefix = identical keys/URLs). STORAGE_PROVIDER
# stays "cloudflare" so the frontend upload path is unchanged (no frontend rebuild).
ARG VERSION
FROM ghcr.io/gitroomhq/postiz-app:${VERSION}

COPY <<'PATCH' /tmp/patch.js
const fs = require('fs');
const { execSync } = require('child_process');

const files = execSync("find /app/apps -path '*upload/cloudflare.storage.js'", {
  encoding: 'utf8',
}).split('\n').filter(Boolean);
if (files.length === 0) throw new Error('cloudflare.storage.js not found');

const HELPER =
  'function __postizKey(id, extension) {\n' +
  "    const p = (process.env.CLOUDFLARE_BUCKET_PREFIX || '').replace(/^\\/+|\\/+$/g, '');\n" +
  "    return p ? p + '/' + id + '.' + extension : id + '.' + extension;\n" +
  '}\n';

for (const f of files) {
  let s = fs.readFileSync(f, 'utf8');
  if (s.includes('__postizKey')) { console.log('already patched:', f); continue; }

  // 1) bucket key prefix helper, injected before the class
  const classAnchor = 'class CloudflareStorage {';
  if (!s.includes(classAnchor)) throw new Error('class anchor missing: ' + f);
  s = s.replace(classAnchor, HELPER + classAnchor);

  // 2) configurable endpoint (MinIO) + path-style addressing
  const epAnchor = 'endpoint: `https://${accountID}.r2.cloudflarestorage.com`,';
  if (!s.includes(epAnchor)) throw new Error('endpoint anchor missing: ' + f);
  s = s.replace(epAnchor,
    'endpoint: process.env.CLOUDFLARE_ENDPOINT || `https://${accountID}.r2.cloudflarestorage.com`,\n' +
    "            forcePathStyle: process.env.CLOUDFLARE_FORCE_PATH_STYLE === 'true',");

  // 3) apply the prefix to the object key and the returned public URLs
  s = s.split('Key: `${id}.${extension}`,').join('Key: `${__postizKey(id, extension)}`,');
  s = s.split('`${this._uploadUrl}/${id}.${extension}`')
       .join('`${this._uploadUrl}/${__postizKey(id, extension)}`');

  fs.writeFileSync(f, s);
  console.log('patched:', f);
}
console.log('done');
PATCH

RUN node /tmp/patch.js && rm -f /tmp/patch.js && rm -rf /app/node-compile-cache/* 2>/dev/null || true
