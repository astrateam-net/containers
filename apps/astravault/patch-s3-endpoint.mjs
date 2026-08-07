// astravault — let PAM session-recording storage target an S3-compatible provider.
//
// Upstream builds its S3 client from the per-template recording config alone, which
// carries bucket/region/keyPrefix but no endpoint, so the SDK always resolves an
// amazonaws.com host. This rewrites buildClient() in
// dist/ee/services/pam-session-recording/aws-s3/aws-s3-provider-factory.mjs to honour
// PAM_RECORDING_S3_ENDPOINT, which is instance-wide: bucket, region, key prefix and the
// AWS connection stay per-template and keep using the stock UI and API.
//
// When the endpoint is set the signing region is overridden too (R2 wants "auto"), since
// the template's region field is a fixed AWS enum upstream. The template region is still
// what selects credentials from the app connection, which only matters for STS
// assume-role; a static access key ignores it.
//
//   PAM_RECORDING_S3_ENDPOINT          e.g. https://<account>.r2.cloudflarestorage.com
//   PAM_RECORDING_S3_REGION            signing region, default "auto"
//   PAM_RECORDING_S3_FORCE_PATH_STYLE  "false" to use virtual-host style, default path style
//
// Unset endpoint leaves the stock AWS behaviour byte-for-byte. Anchored on the S3Client
// construction; if upstream changes that shape the build FAILS rather than silently
// shipping an image that ignores the endpoint.
import { readFileSync, writeFileSync } from "node:fs";

const FILE = "/backend/dist/ee/services/pam-session-recording/aws-s3/aws-s3-provider-factory.mjs";

// buildClient()'s constructor call. `region: config.region` is the first key upstream sets
// and is what the endpoint path has to override.
const ANCHOR = /return new S3Client\(\{(\s*)region: config\.region,/;

const REPLACEMENT = `const astravaultS3Endpoint = process.env.PAM_RECORDING_S3_ENDPOINT;
  return new S3Client({$1...(astravaultS3Endpoint
      ? {
          endpoint: astravaultS3Endpoint,
          forcePathStyle: process.env.PAM_RECORDING_S3_FORCE_PATH_STYLE !== "false"
        }
      : {}),$1region: astravaultS3Endpoint ? process.env.PAM_RECORDING_S3_REGION || "auto" : config.region,`;

const src = readFileSync(FILE, "utf8");

const matches = src.match(new RegExp(ANCHOR.source, "g")) ?? [];
if (matches.length !== 1) {
  console.error(
    `astravault: expected exactly 1 S3Client construction in ${FILE}, found ${matches.length} — upstream shape changed; refusing to build`
  );
  process.exit(1);
}

const patched = src.replace(ANCHOR, REPLACEMENT);
if (patched === src) {
  console.error("astravault: S3 endpoint substitution did not apply — refusing to build");
  process.exit(1);
}

writeFileSync(FILE, patched);
console.log("astravault: PAM recording S3 endpoint override applied");
