"use strict";
// MCP OAuth broker for Docmost (astrawiki).
//
// Stock Docmost gates its MCP endpoint (root /mcp) behind a personal API key
// passed as a static `Authorization: Bearer` header — there is NO OAuth flow,
// so native web MCP connectors (Claude, ChatGPT) that speak the MCP OAuth
// discovery handshake cannot connect. This module adds that handshake by
// turning Docmost into its own OAuth 2.1 Authorization Server + Resource Server
// (a broker), while delegating the human-login step to the workspace's already
// configured Authentik OIDC provider.
//
// Flow (MCP spec 2025-11-25):
//   client --/mcp (no token)-->            401 + WWW-Authenticate: resource_metadata=...
//   client --GET /.well-known/oauth-protected-resource--> { authorization_servers:[base] }
//   client --GET /.well-known/oauth-authorization-server--> { *_endpoint under /mcp-oauth }
//   client --POST /mcp-oauth/register-->   Dynamic Client Registration (RFC 7591)
//   client --GET  /mcp-oauth/authorize-->  (PKCE S256) --302--> Authentik /authorize
//   Authentik --302--> /mcp-oauth/callback (we exchange code, resolve Docmost user)
//   client --POST /mcp-oauth/token-->      verify client PKCE -> MINT Docmost API_KEY token
//   client --/mcp (Bearer <API_KEY>)-->    stock JwtStrategy validates type:api_key
//
// Key difference from a pass-through proxy: Docmost's /mcp only accepts tokens
// IT minted (app-secret HS256 + api_keys row), so on /callback we discard
// Authentik's token and mint our own API_KEY-type token via the same primitive
// the API-keys feature uses. Because we mint our own token, RFC 8707 audience
// binding is satisfied by construction and Authentik needs no audience config —
// the ONLY Authentik change required is whitelisting this broker's callback URL
// (<base>/mcp-oauth/callback) in the existing provider's redirect URIs.
//
// State (DCR clients, pending authorize states, broker codes, refresh tokens)
// is kept in the SAME Redis/Valkey that Docmost already uses (via its
// RedisService), so registrations survive restarts and are shared across all
// replicas. Falls back to an in-memory store only when Redis is unavailable
// (single-instance dev). See registerMcpOauth().

const crypto = require("node:crypto");
const oidc = require("openid-client");

// Compiled Docmost internals (paths relative to dist/mcp-oauth/broker.js).
const { SsoService } = require("../ee/sso/services/sso.service");
const { TokenService } = require("../core/auth/services/token.service");
const { UserRepo } = require("../database/repos/user/user.repo");
const { WorkspaceRepo } = require("../database/repos/workspace/workspace.repo");
const { formatOidcProfile } = require("../ee/sso/sso.utils");
const { v7: uuidv7 } = require("uuid");

const LOG = "[mcp-oauth]";
const OIDC = "oidc";

// Verbose per-request traces (authorize/token/callback/register/issued) are
// gated behind debug: env MCP_OAUTH_DEBUG=true or LOG_LEVEL=debug. Security
// events ([sec]) and errors always log regardless of this flag.
const DEBUG = process.env.MCP_OAUTH_DEBUG === "true" || ["debug", "trace"].includes((process.env.LOG_LEVEL || "").toLowerCase());

// Lifetimes.
const AUTHZ_STATE_TTL_MS = 10 * 60 * 1000; // pending Authentik round-trip
const BROKER_CODE_TTL_MS = 5 * 60 * 1000; // our authorization code
const API_KEY_TTL_MS = 8 * 60 * 60 * 1000; // short-lived access token; refresh_token extends sessions (spec: short-lived tokens)
const REFRESH_TTL_MS = 180 * 24 * 60 * 60 * 1000; // broker refresh token
const CLIENT_TTL_MS = REFRESH_TTL_MS; // DCR client registration retention

// ---- shared TTL store ------------------------------------------------------
// Redis-backed when available (survives restarts, shared across replicas);
// in-memory Map fallback otherwise. Uniform async interface: set/get/take.
function makeStore(redis, ns) {
  if (redis) {
    const k = (id) => `mcp-oauth:${ns}:${id}`;
    return {
      async set(id, v, ttlMs) {
        await redis.set(k(id), JSON.stringify(v), "PX", ttlMs);
      },
      async get(id) {
        const s = await redis.get(k(id));
        return s ? JSON.parse(s) : undefined;
      },
      async take(id) {
        const key = k(id);
        const s = await redis.get(key);
        if (s != null) await redis.del(key);
        return s ? JSON.parse(s) : undefined;
      },
    };
  }
  const m = new Map();
  return {
    async set(id, v, ttlMs) {
      m.set(id, { v, exp: Date.now() + ttlMs });
    },
    async get(id) {
      const e = m.get(id);
      if (!e) return undefined;
      if (e.exp < Date.now()) {
        m.delete(id);
        return undefined;
      }
      return e.v;
    },
    async take(id) {
      const v = await this.get(id);
      if (v !== undefined) m.delete(id);
      return v;
    },
  };
}

// ---- helpers ----------------------------------------------------------------
function rand(bytes = 32) {
  return crypto.randomBytes(bytes).toString("base64url");
}

function baseUrl(req) {
  // trustProxy is on; req.hostname excludes the port, req.protocol is scheme.
  const proto = req.protocol || "https";
  const host = req.headers["x-forwarded-host"] || req.headers.host || req.hostname;
  return `${proto}://${host}`;
}

function cors(reply) {
  reply.header("Access-Control-Allow-Origin", "*");
  reply.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  reply.header("Access-Control-Allow-Headers", "Content-Type, Authorization, mcp-protocol-version");
}

function sendJson(reply, status, obj, withCors) {
  if (withCors) cors(reply);
  reply.header("Cache-Control", "no-store");
  reply.code(status).header("Content-Type", "application/json").send(JSON.stringify(obj));
}

function oauthErr(reply, status, error, description) {
  sendJson(reply, status, { error, error_description: description }, true);
}

// PKCE S256 verify: base64url(sha256(verifier)) === challenge.
function verifyPkceS256(verifier, challenge) {
  if (typeof verifier !== "string" || typeof challenge !== "string") return false;
  const computed = crypto.createHash("sha256").update(verifier).digest("base64url");
  const a = Buffer.from(computed);
  const b = Buffer.from(challenge);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function isLoopbackHost(h) {
  return h === "localhost" || h === "127.0.0.1" || h === "[::1]" || h === "::1";
}

// RFC 8252 §7.3: native apps (e.g. the VS Code Claude Code extension) catch the
// OAuth redirect on http://localhost:<port> with an OS-assigned ephemeral port
// that can differ between DCR and /authorize. So for loopback redirect URIs we
// match on scheme+host+path and IGNORE the port; non-loopback URIs must still
// match exactly. This is why Claude Desktop (stable claude:// redirect) worked
// while Claude Code (ephemeral localhost port) hit "redirect_uri not registered".
function redirectUriAllowed(registered, requested) {
  if (!requested) return false;
  if (registered.includes(requested)) return true;
  let rq;
  try {
    rq = new URL(requested);
  } catch (_) {
    return false;
  }
  if (!isLoopbackHost(rq.hostname)) return false;
  return registered.some((r) => {
    let ru;
    try {
      ru = new URL(r);
    } catch (_) {
      return false;
    }
    return isLoopbackHost(ru.hostname) && ru.protocol === rq.protocol && ru.hostname === rq.hostname && ru.pathname === rq.pathname;
  });
}

// Spec (OAuth 2.1 §1.5): all redirect URIs MUST be either loopback or HTTPS.
function isValidRedirectUri(uri) {
  let u;
  try {
    u = new URL(uri);
  } catch (_) {
    return false;
  }
  if (u.protocol === "https:") return true;
  if (u.protocol === "http:" && isLoopbackHost(u.hostname)) return true;
  return false;
}

// Per-IP, per-minute rate limit on the abuse-prone endpoints (/register,/token).
// Redis-backed so the limit is shared across replicas; in-memory fallback for a
// single-instance dev run. Returns {allowed, limit, remaining, reset}.
const RL_FALLBACK = new Map();
async function rateLimit(services, req, endpoint, maxPerMin) {
  const ip = (req.ip || req.headers["x-forwarded-for"] || "unknown").toString().split(",")[0].trim();
  const key = `mcp-oauth:rl:${endpoint}:${ip}`;
  let count = 0;
  let reset = 60;
  if (services.redis) {
    try {
      count = await services.redis.incr(key);
      if (count === 1) await services.redis.expire(key, 60);
      const ttl = await services.redis.ttl(key);
      reset = ttl > 0 ? ttl : 60;
    } catch (_) {
      return { allowed: true, limit: maxPerMin, remaining: maxPerMin, reset: 60 };
    }
  } else {
    const now = Date.now();
    let e = RL_FALLBACK.get(key);
    if (!e || e.exp < now) {
      e = { n: 0, exp: now + 60000 };
      RL_FALLBACK.set(key, e);
    }
    e.n += 1;
    count = e.n;
    reset = Math.max(1, Math.ceil((e.exp - now) / 1000));
  }
  return { allowed: count <= maxPerMin, limit: maxPerMin, remaining: Math.max(0, maxPerMin - count), reset };
}

function applyRateHeaders(reply, rl) {
  reply.header("RateLimit-Limit", String(rl.limit));
  reply.header("RateLimit-Remaining", String(rl.remaining));
  reply.header("RateLimit-Reset", String(rl.reset));
}

// Metadata documents ----------------------------------------------------------
function protectedResourceDoc(base) {
  return {
    resource: `${base}/mcp`,
    authorization_servers: [base],
    bearer_methods_supported: ["header"],
    resource_documentation: `${base}/mcp`,
  };
}

function authServerDoc(base) {
  return {
    issuer: base,
    authorization_endpoint: `${base}/mcp-oauth/authorize`,
    token_endpoint: `${base}/mcp-oauth/token`,
    registration_endpoint: `${base}/mcp-oauth/register`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none"],
    scopes_supported: ["mcp"],
  };
}

// ---- per-request Docmost context -------------------------------------------
async function resolveContext(services, req) {
  const { workspaceRepo, ssoService } = services;
  const host = (req.headers["x-forwarded-host"] || req.headers.host || req.hostname || "")
    .toString()
    .split(":")[0];
  let workspace = null;
  try {
    if (host) workspace = await workspaceRepo.findByHostname(host);
  } catch (_) {}
  if (!workspace) workspace = await workspaceRepo.findFirst();
  if (!workspace) throw new Error("no workspace");

  const provider = await ssoService.db
    .selectFrom("authProviders")
    .selectAll()
    .where("workspaceId", "=", workspace.id)
    .where("type", "=", OIDC)
    .where("isEnabled", "=", true)
    .executeTakeFirst();
  if (!provider) throw new Error("no enabled OIDC provider");
  return { workspace, provider };
}

// Build an openid-client config for the broker<->Authentik leg. Unlike
// oidc.service.getClient (which bakes Docmost's own SSO callback), we register
// the broker callback so Authentik accepts the redirect and the code exchange.
async function authentikConfig(provider, redirectUri) {
  return oidc.discovery(
    new URL(provider.oidcIssuer),
    provider.oidcClientId?.trim(),
    {
      client_secret: provider.oidcClientSecret?.trim(),
      redirect_uris: [redirectUri],
      response_types: ["code"],
    },
    undefined,
    { execute: [oidc.allowInsecureRequests] }
  );
}

// Mint a Docmost API_KEY-type token (same shape the API-keys feature issues, so
// the stock JwtStrategy -> ApiKeyService.validateApiKey path accepts it). Done
// inline (TokenService + apiKeys insert) to avoid the audit/CLS coupling in
// ApiKeyService.createApiKey — validation only needs the row to exist.
async function mintApiKeyToken(services, user, workspaceId, name) {
  const { tokenService, ssoService } = services;
  const apiKeyId = uuidv7();
  const expiresIn = Math.floor(API_KEY_TTL_MS / 1000);
  const token = await tokenService.generateApiToken({ apiKeyId, user, workspaceId, expiresIn });
  await ssoService.db
    .insertInto("apiKeys")
    .values({
      id: apiKeyId,
      name: (name || "MCP client").slice(0, 255),
      creatorId: user.id,
      workspaceId,
      expiresAt: new Date(Date.now() + API_KEY_TTL_MS),
    })
    .execute();
  return { token, expiresIn, apiKeyId };
}

async function revokeApiKeyById(services, apiKeyId) {
  try {
    await services.ssoService.db.deleteFrom("apiKeys").where("id", "=", apiKeyId).execute();
  } catch (e) {
    services.log(`${LOG} failed to revoke api key ${apiKeyId}: ${e.message}`);
  }
}

// Housekeeping: delete broker-minted API keys (name prefixed "MCP: ") that are
// past their expiry, so abandoned or rotated connections don't leave a graveyard
// of api_keys rows. Only touches rows we created (name prefix) and only expired
// ones — user-created keys and live MCP keys are untouched.
async function sweepExpiredMcpKeys(services) {
  try {
    await services.ssoService.db
      .deleteFrom("apiKeys")
      .where("name", "like", "MCP: %")
      .where("expiresAt", "<", new Date())
      .execute();
  } catch (e) {
    services.log(`${LOG} expired-key sweep failed: ${e.message}`);
  }
}

// ---- route handlers ---------------------------------------------------------
async function handleRegister(services, req, reply) {
  const rl = await rateLimit(services, req, "register", 20);
  applyRateHeaders(reply, rl);
  if (!rl.allowed) {
    services.log(`${LOG}[sec] rate-limit /register from ${req.ip}`);
    return oauthErr(reply, 429, "temporarily_unavailable", "Rate limit exceeded");
  }
  const body = typeof req.body === "object" && req.body ? req.body : {};
  const redirectUris = Array.isArray(body.redirect_uris) ? body.redirect_uris.filter((u) => typeof u === "string") : [];
  if (redirectUris.length === 0) {
    return oauthErr(reply, 400, "invalid_redirect_uri", "redirect_uris is required");
  }
  if (!redirectUris.every(isValidRedirectUri)) {
    services.log(`${LOG}[sec] rejected DCR (redirect not loopback/HTTPS) from ${req.ip}: ${redirectUris.join(",")}`);
    return oauthErr(reply, 400, "invalid_redirect_uri", "redirect_uris must be https:// or http://localhost");
  }
  const clientId = `mcp_${rand(16)}`;
  const name = (body.client_name || "MCP client").toString().slice(0, 120);
  await services.stores.clients.set(clientId, { redirectUris, name }, CLIENT_TTL_MS);
  services.debug(`${LOG} registered client ${clientId} (${name}) redirect=${redirectUris.join(",")}`);
  return sendJson(
    reply,
    201,
    {
      client_id: clientId,
      client_id_issued_at: Math.floor(Date.now() / 1000),
      redirect_uris: redirectUris,
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
      client_name: name,
    },
    true
  );
}

async function handleAuthorize(services, req, reply) {
  const base = baseUrl(req);
  const q = req.query || {};
  services.debug(`${LOG} authorize client=${q.client_id} redirect=${q.redirect_uri}`);
  if (q.response_type !== "code") {
    return oauthErr(reply, 400, "unsupported_response_type", "response_type must be 'code'");
  }
  const client = await services.stores.clients.get(q.client_id);
  if (!client) {
    services.log(`${LOG}[sec] authorize with unknown client_id ${q.client_id} from ${req.ip}`);
    return oauthErr(reply, 400, "invalid_client", "Unknown client_id — register first");
  }
  if (!q.redirect_uri || !redirectUriAllowed(client.redirectUris, q.redirect_uri)) {
    services.log(`${LOG}[sec] redirect_uri not registered for client ${q.client_id} from ${req.ip}`);
    return oauthErr(reply, 400, "invalid_request", "redirect_uri not registered for this client");
  }
  if (!q.code_challenge || q.code_challenge_method !== "S256") {
    return oauthErr(reply, 400, "invalid_request", "PKCE with code_challenge_method=S256 is required");
  }

  let ctx;
  try {
    ctx = await resolveContext(services, req);
  } catch (e) {
    services.log(`${LOG} authorize: context error: ${e.message}`);
    return oauthErr(reply, 500, "server_error", "OIDC provider not configured");
  }

  const brokerCallback = `${base}/mcp-oauth/callback`;
  let config;
  try {
    config = await authentikConfig(ctx.provider, brokerCallback);
  } catch (e) {
    services.log(`${LOG} authorize: discovery failed: ${e.message}`);
    return oauthErr(reply, 500, "server_error", "Failed to reach identity provider");
  }

  const brokerState = rand(24);
  const legVerifier = oidc.randomPKCECodeVerifier();
  const legChallenge = await oidc.calculatePKCECodeChallenge(legVerifier);

  await services.stores.authzStates.set(
    brokerState,
    {
      clientId: q.client_id,
      clientRedirectUri: q.redirect_uri,
      clientState: q.state,
      clientCodeChallenge: q.code_challenge,
      providerId: ctx.provider.id,
      workspaceId: ctx.workspace.id,
      legVerifier,
      brokerCallback,
    },
    AUTHZ_STATE_TTL_MS
  );

  const authUrl = oidc.buildAuthorizationUrl(config, {
    redirect_uri: brokerCallback,
    scope: "openid email profile",
    state: brokerState,
    code_challenge: legChallenge,
    code_challenge_method: "S256",
  });
  reply.header("Cache-Control", "no-store");
  return reply.redirect(authUrl.href);
}

async function handleCallback(services, req, reply) {
  const base = baseUrl(req);
  const q = req.query || {};
  if (q.error) {
    return sendJson(reply, 400, { error: q.error, error_description: q.error_description || "IdP error" }, false);
  }
  const st = await services.stores.authzStates.take(q.state);
  if (!st) return sendJson(reply, 400, { error: "invalid_state", error_description: "Unknown or expired state" }, false);

  try {
    const provider = await services.ssoService.getProviderById({
      providerId: st.providerId,
      workspaceId: st.workspaceId,
      type: OIDC,
    });
    const workspace = await services.workspaceRepo.findById(st.workspaceId);
    if (!provider || !workspace) throw new Error("provider/workspace vanished");

    const config = await authentikConfig(provider, st.brokerCallback);
    const currentUrl = new URL(req.raw.url, base);
    const tokens = await oidc.authorizationCodeGrant(config, currentUrl, {
      expectedState: q.state,
      pkceCodeVerifier: st.legVerifier,
    });
    const claims = tokens.claims();
    let userInfo = await oidc.fetchUserInfo(config, tokens.access_token, claims?.sub ?? oidc.skipSubjectCheck);
    if (!userInfo?.email && claims?.email) userInfo = { ...userInfo, email: claims.email };
    if (!userInfo?.groups && claims?.groups) userInfo = { ...userInfo, groups: claims.groups };
    if (!userInfo?.email) throw new Error("IdP returned no email");

    const profile = formatOidcProfile(userInfo);
    const user = await services.ssoService.handleAuthentication({
      workspace,
      providerId: provider.id,
      providerType: OIDC,
      profile,
    });

    const clientRec = await services.stores.clients.get(st.clientId);
    const brokerCode = rand(24);
    await services.stores.brokerCodes.set(
      brokerCode,
      {
        userId: user.id,
        workspaceId: workspace.id,
        clientId: st.clientId,
        clientRedirectUri: st.clientRedirectUri,
        clientCodeChallenge: st.clientCodeChallenge,
        clientName: clientRec?.name,
      },
      BROKER_CODE_TTL_MS
    );

    const back = new URL(st.clientRedirectUri);
    back.searchParams.set("code", brokerCode);
    if (st.clientState) back.searchParams.set("state", st.clientState);
    services.debug(`${LOG} callback ok: brokerCode issued for client ${st.clientId} user ${user.id} -> ${st.clientRedirectUri}`);
    reply.header("Cache-Control", "no-store");
    return reply.redirect(back.href);
  } catch (e) {
    services.log(`${LOG} callback failed: ${e.message}`);
    return sendJson(reply, 400, { error: "authentication_failed", error_description: e.message }, false);
  }
}

async function handleToken(services, req, reply) {
  const rl = await rateLimit(services, req, "token", 60);
  applyRateHeaders(reply, rl);
  if (!rl.allowed) {
    services.log(`${LOG}[sec] rate-limit /token from ${req.ip}`);
    return oauthErr(reply, 429, "temporarily_unavailable", "Rate limit exceeded");
  }
  const body = typeof req.body === "object" && req.body ? req.body : {};
  const grantType = body.grant_type;
  services.debug(`${LOG} token grant=${grantType} client=${body.client_id} redirect=${body.redirect_uri} code=${body.code ? "yes" : "no"}`);

  if (grantType === "authorization_code") {
    const bc = await services.stores.brokerCodes.take(body.code);
    if (!bc) {
      services.log(`${LOG}[sec] token: invalid/expired code from ${req.ip} client=${body.client_id}`);
      return oauthErr(reply, 400, "invalid_grant", "Invalid or expired code");
    }
    if (bc.clientId !== body.client_id) {
      services.log(`${LOG}[sec] token: client_id mismatch (authz=${bc.clientId} token=${body.client_id})`);
      return oauthErr(reply, 400, "invalid_grant", "client_id mismatch");
    }
    if (!body.redirect_uri || !redirectUriAllowed([bc.clientRedirectUri], body.redirect_uri)) {
      services.log(`${LOG}[sec] token: redirect mismatch (authz=${bc.clientRedirectUri} token=${body.redirect_uri})`);
      return oauthErr(reply, 400, "invalid_grant", "redirect_uri mismatch");
    }
    if (!verifyPkceS256(body.code_verifier, bc.clientCodeChallenge)) {
      services.log(`${LOG}[sec] PKCE verification failed for client ${body.client_id} from ${req.ip}`);
      return oauthErr(reply, 400, "invalid_grant", "PKCE verification failed");
    }
    const user = await services.userRepo.findById(bc.userId, bc.workspaceId);
    if (!user) return oauthErr(reply, 400, "invalid_grant", "User no longer exists");

    const { token, expiresIn, apiKeyId } = await mintApiKeyToken(services, user, bc.workspaceId, `MCP: ${bc.clientName || "client"}`);
    const refresh = rand(32);
    await services.stores.refreshTokens.set(
      refresh,
      { userId: bc.userId, workspaceId: bc.workspaceId, clientId: bc.clientId, clientName: bc.clientName, apiKeyId },
      REFRESH_TTL_MS
    );
    services.debug(`${LOG} issued token for user ${bc.userId} client ${bc.clientId}`);
    return sendJson(
      reply,
      200,
      { access_token: token, token_type: "Bearer", expires_in: expiresIn, refresh_token: refresh, scope: "mcp" },
      true
    );
  }

  if (grantType === "refresh_token") {
    const rt = await services.stores.refreshTokens.take(body.refresh_token);
    if (!rt) return oauthErr(reply, 400, "invalid_grant", "Invalid or expired refresh_token");
    if (body.client_id && rt.clientId !== body.client_id) {
      return oauthErr(reply, 400, "invalid_grant", "client_id mismatch");
    }
    const user = await services.userRepo.findById(rt.userId, rt.workspaceId);
    if (!user) return oauthErr(reply, 400, "invalid_grant", "User no longer exists");

    // One live key per refresh chain: drop the key the previous grant minted
    // before minting a new one, so refreshes don't pile up api_keys rows.
    if (rt.apiKeyId) await revokeApiKeyById(services, rt.apiKeyId);
    const { token, expiresIn, apiKeyId } = await mintApiKeyToken(services, user, rt.workspaceId, `MCP: ${rt.clientName || rt.clientId}`);
    const newRefresh = rand(32);
    await services.stores.refreshTokens.set(newRefresh, { ...rt, apiKeyId }, REFRESH_TTL_MS);
    return sendJson(
      reply,
      200,
      { access_token: token, token_type: "Bearer", expires_in: expiresIn, refresh_token: newRefresh, scope: "mcp" },
      true
    );
  }

  return oauthErr(reply, 400, "unsupported_grant_type", "grant_type must be authorization_code or refresh_token");
}

// ---- registration on the Fastify instance ----------------------------------
function registerMcpOauth(app) {
  const log = (m) => {
    try {
      console.log(m);
    } catch (_) {}
  };

  let services;
  try {
    services = {
      log,
      ssoService: app.get(SsoService, { strict: false }),
      tokenService: app.get(TokenService, { strict: false }),
      userRepo: app.get(UserRepo, { strict: false }),
      workspaceRepo: app.get(WorkspaceRepo, { strict: false }),
    };
  } catch (e) {
    log(`${LOG} DISABLED — could not resolve Docmost services: ${e.message}`);
    return;
  }

  // Shared state in Docmost's own Redis/Valkey (survives restarts, shared across
  // replicas). Fall back to in-memory only if Redis can't be resolved.
  let redis = null;
  try {
    const { RedisService } = require("@nestjs-labs/nestjs-ioredis");
    redis = app.get(RedisService, { strict: false }).getOrThrow();
    log(`${LOG} state store: Redis (shared, restart-safe)`);
  } catch (e) {
    log(`${LOG} state store: in-memory fallback (single-instance only) — Redis unavailable: ${e.message}`);
  }
  services.redis = redis;
  services.debug = DEBUG ? log : () => {};
  if (DEBUG) log(`${LOG} debug logging ON`);
  services.stores = {
    clients: makeStore(redis, "client"),
    authzStates: makeStore(redis, "authz"),
    brokerCodes: makeStore(redis, "code"),
    refreshTokens: makeStore(redis, "refresh"),
  };

  const fastify = app.getHttpAdapter().getInstance();

  const wrap = (h) => async (req, reply) => {
    try {
      await h(services, req, reply);
    } catch (e) {
      services.log(`${LOG} unhandled error on ${req.raw.url}: ${e && e.stack ? e.stack : e}`);
      if (!reply.sent) oauthErr(reply, 500, "server_error", "Internal error");
    }
  };

  // Discovery (root well-known). Path-aware PRM variant for the /mcp resource.
  const prm = async (req, reply) => sendJson(reply, 200, protectedResourceDoc(baseUrl(req)), true);
  const asm = async (req, reply) => sendJson(reply, 200, authServerDoc(baseUrl(req)), true);
  fastify.get("/.well-known/oauth-protected-resource", prm);
  fastify.get("/.well-known/oauth-protected-resource/mcp", prm);
  fastify.get("/.well-known/oauth-authorization-server", asm);
  fastify.get("/.well-known/oauth-authorization-server/mcp", asm);
  fastify.get("/.well-known/openid-configuration", asm);

  // Broker endpoints.
  fastify.options("/mcp-oauth/*", async (_req, reply) => {
    cors(reply);
    reply.code(204).send();
  });
  fastify.post("/mcp-oauth/register", wrap(handleRegister));
  fastify.get("/mcp-oauth/authorize", wrap(handleAuthorize));
  fastify.get("/mcp-oauth/callback", wrap(handleCallback));
  fastify.post("/mcp-oauth/token", wrap(handleToken));

  // 401 challenge on the MCP endpoint so clients start the OAuth dance.
  fastify.addHook("onSend", (req, reply, payload, done) => {
    try {
      const url = req.raw.url || "";
      const isMcp = url === "/mcp" || url.startsWith("/mcp?") || url.startsWith("/mcp/");
      if (isMcp && reply.statusCode === 401 && !reply.getHeader("WWW-Authenticate")) {
        reply.header(
          "WWW-Authenticate",
          `Bearer resource_metadata="${baseUrl(req)}/.well-known/oauth-protected-resource"`
        );
      }
    } catch (_) {}
    done(null, payload);
  });

  // Periodic cleanup of expired broker-minted API keys (every 6h). Redis TTL
  // handles OAuth-flow state; this handles the api_keys rows we insert. Safe to
  // run on every replica (idempotent DELETE of already-expired MCP-prefixed rows).
  const keySweep = setInterval(() => sweepExpiredMcpKeys(services), 6 * 60 * 60 * 1000);
  if (keySweep.unref) keySweep.unref();
  sweepExpiredMcpKeys(services);

  log(`${LOG} broker mounted: /.well-known/* + /mcp-oauth/{register,authorize,callback,token}`);
}

module.exports = { registerMcpOauth };
