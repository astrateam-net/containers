// Generate an obsidian://setuplivesync URI for an Obsidian Self-hosted
// LiveSync vault. Adapted from the upstream generator at
// https://raw.githubusercontent.com/vrtmrz/obsidian-livesync/main/utils/flyio/generate_setupuri.ts
// with HTTP-Basic + JWT (ES256/ES512) support driven by env vars.
//
// Required env vars (both modes):
//   hostname   - public CouchDB URL, e.g. https://obsync.example.com
//   database   - target DB (userdb-<hex> for private, vault name for shared)
//   passphrase - E2EE passphrase used to encrypt vault content in CouchDB
//
// Auth mode selector:
//   auth_mode  - "basic" (default) or "jwt"
//
// Basic mode:
//   username, password
//
// JWT mode (LiveSync experimental, per docs/tips/jwt-on-couchdb.md):
//   jwt_algorithm     - ES256 | ES512 (default ES256)
//   jwt_key           - private key in PEM (PKCS#8) format
//   jwt_kid           - key id matching CouchDB's [jwt_keys] entry
//   jwt_sub           - subject == CouchDB username
//   jwt_exp_duration  - token lifetime in minutes (default 60)
//
// Optional:
//   uri_passphrase    - passphrase encrypting the URI itself; auto-generated
//                       as adjective-noun if unset

import { encrypt } from "npm:octagonal-wheels@0.1.30/encryption/encryption";

const NOUNS = [
    "waterfall", "river", "breeze", "moon", "rain", "wind", "sea", "morning",
    "snow", "lake", "sunset", "pine", "shadow", "leaf", "dawn", "glitter",
    "forest", "hill", "cloud", "meadow", "sun", "glade", "bird", "brook",
    "butterfly", "bush", "dew", "dust", "field", "fire", "flower", "firefly",
    "feather", "grass", "haze", "mountain", "night", "pond", "darkness",
    "snowflake", "silence", "sound", "sky", "shape", "surf", "thunder",
    "violet", "water", "wildflower", "wave", "resonance", "log", "dream",
    "cherry", "tree", "fog", "frost", "voice", "paper", "frog", "smoke", "star",
];
const ADJECTIVES = [
    "autumn", "hidden", "bitter", "misty", "silent", "empty", "dry", "dark",
    "summer", "icy", "delicate", "quiet", "white", "cool", "spring", "winter",
    "patient", "twilight", "dawn", "crimson", "wispy", "weathered", "blue",
    "billowing", "broken", "cold", "damp", "falling", "frosty", "green", "long",
    "late", "lingering", "bold", "little", "morning", "muddy", "old", "red",
    "rough", "still", "small", "sparkling", "thrumming", "shy", "wandering",
    "withered", "wild", "black", "young", "holy", "solitary", "fragrant", "aged",
    "snowy", "proud", "floral", "restless", "divine", "polished", "ancient",
    "purple", "lively", "nameless",
];

function friendlyString(): string {
    const a = ADJECTIVES[Math.floor(Math.random() * ADJECTIVES.length)];
    const n = NOUNS[Math.floor(Math.random() * NOUNS.length)];
    return `${a}-${n}`;
}

function require(name: string): string {
    const v = Deno.env.get(name);
    if (!v) {
        console.error(`ERROR: env var '${name}' is required`);
        Deno.exit(2);
    }
    return v;
}

const URIBASE = "obsidian://setuplivesync?settings=";

const uriPassphrase = Deno.env.get("uri_passphrase") || friendlyString();
const authMode = (Deno.env.get("auth_mode") || "basic").toLowerCase();

// Settings shape mirrors LiveSync's RemoteDBSettings. Field names below
// were verified against src/modules/features/SettingDialogue/PaneRemoteConfig.ts
// at the time of writing.
const base: Record<string, unknown> = {
    couchDB_URI: require("hostname"),
    couchDB_DBNAME: require("database"),
    syncOnStart: true,
    gcDelay: 0,
    periodicReplication: true,
    syncOnFileOpen: true,
    encrypt: true,
    passphrase: require("passphrase"),
    usePathObfuscation: true,
    batchSave: true,
    batch_size: 50,
    batches_limit: 50,
    useHistory: true,
    disableRequestURI: true,
    customChunkSize: 50,
    syncAfterMerge: false,
    concurrencyOfReadChunksOnline: 100,
    minimumIntervalOfReadChunksOnline: 100,
    handleFilenameCaseSensitive: false,
    doNotUseFixedRevisionForChunks: false,
    settingVersion: 10,
    notifyThresholdOfRemoteStorageSize: 800,
};

let conf: Record<string, unknown>;
if (authMode === "jwt") {
    conf = {
        ...base,
        couchDB_USER: "",
        couchDB_PASSWORD: "",
        useJWT: true,
        jwtAlgorithm: Deno.env.get("jwt_algorithm") || "ES256",
        jwtKey: require("jwt_key"),
        jwtKid: require("jwt_kid"),
        jwtSub: require("jwt_sub"),
        jwtExpDuration: parseInt(Deno.env.get("jwt_exp_duration") || "60", 10),
    };
} else if (authMode === "basic") {
    conf = {
        ...base,
        couchDB_USER: require("username"),
        couchDB_PASSWORD: require("password"),
        useJWT: false,
    };
} else {
    console.error(`ERROR: unknown auth_mode '${authMode}' (expected 'basic' or 'jwt')`);
    Deno.exit(2);
}

const encrypted = encodeURIComponent(
    await encrypt(JSON.stringify(conf), uriPassphrase, false),
);
console.log();
console.log(`Your passphrase of Setup-URI is:  ${uriPassphrase}`);
console.log("This passphrase is never shown again, so please note it in a safe place.");
console.log(`${URIBASE}${encrypted}`);
