// astravault — entitle the full self-hosted feature set at image-build time.
//
// The backend derives its active plan from getDefaultOnPremFeatures() (in
// dist/ee/services/license/license-fns.mjs) whenever no license key is configured —
// the same single chokepoint the license server would otherwise populate. This
// rewrites that function's returned object so every capability flag is enabled and
// the numeric caps are effectively unlimited, leaving the actual on/off decision to
// deployment config (mirrors the entitle-all approach used for the dev image).
//
// The enforce* flags in this set are *entitlements* ("allowed to enforce"), not live
// switches — real enforcement lives in per-org settings that stay admin-controlled.
//
// No license key => the license service never contacts the license server, so the
// instance runs fully offline.
//
// Anchored on the function's stable name marker; if upstream changes the shape the
// anchors won't match and the build FAILS rather than silently shipping a locked image.
import { readFileSync, writeFileSync } from "node:fs";

const FILE = "/backend/dist/ee/services/license/license-fns.mjs";
const START = "var getDefaultOnPremFeatures =";
const END = '}), "getDefaultOnPremFeatures");';

// Numeric caps that gate usage (0 / small default -> effectively unlimited).
const CAPS = {
  auditLogsRetentionDays: 36500,
  auditLogStreamLimit: 100000,
  honeyTokenLimit: 100000
};

const src = readFileSync(FILE, "utf8");
const startIdx = src.indexOf(START);
const endIdx = startIdx === -1 ? -1 : src.indexOf(END, startIdx);
if (startIdx === -1 || endIdx === -1) {
  console.error(`astravault: getDefaultOnPremFeatures block not found in ${FILE} — upstream shape changed; refusing to build`);
  process.exit(1);
}
const endFull = endIdx + END.length;

const original = src.slice(startIdx, endFull);
let block = original.replace(/: false\b/g, ": true");
for (const [key, val] of Object.entries(CAPS)) {
  block = block.replace(new RegExp(`(\\b${key}:\\s*)\\d+`), `$1${val}`);
}

if (block === original) {
  console.error("astravault: no substitutions applied — refusing to build");
  process.exit(1);
}

writeFileSync(FILE, src.slice(0, startIdx) + block + src.slice(endFull));
console.log("astravault: on-prem feature set entitled");
