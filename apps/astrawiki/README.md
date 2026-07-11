# astrawiki — deployment guide

`astrawiki` is a thin overlay on the upstream [`docmost/docmost`](https://github.com/docmost/docmost)
image with the Enterprise edition unlocked at build time (see [`agent`](./agent) and
[`Dockerfile`](./Dockerfile)). Functionally it **is** Docmost — same runtime, same env vars, same
database schema — so upstream's [self-hosting docs](https://docmost.com/docs/self-hosting/environment-variables)
apply verbatim. This guide only covers what a prod operator must provision **outside** the image:
the **PostgreSQL extensions**, and the optional **search** and **AI** backends.

> No license key is required. The image reports the Enterprise tier and every feature on its own.

---

## 0. Secrets (Docker / Swarm)

Upstream Docmost reads every secret as a **plaintext environment variable** — it has no
`*_FILE` convention. `astrawiki` adds one via a small entrypoint: for any env var named
`<NAME>_FILE`, it reads the referenced file and exports its contents as `<NAME>` before the app
starts. This lets every secret be delivered through `docker secret` (mounted under `/run/secrets`)
instead of a plaintext value. Plain `<NAME>` still works, so it's fully opt-in.

Applies to all secret-bearing vars: `APP_SECRET`, `DATABASE_URL`, `REDIS_URL`, `OPENAI_API_KEY`,
`GEMINI_API_KEY`, `TYPESENSE_API_KEY`, `SMTP_PASSWORD`, `AWS_S3_ACCESS_KEY_ID`,
`AWS_S3_SECRET_ACCESS_KEY`, `AZURE_STORAGE_ACCOUNT_KEY`.

```yaml
# docker-compose.yml (Swarm)
services:
  astrawiki:
    image: ghcr.io/astrateam-net/astrawiki:rolling
    environment:
      APP_URL: 'https://wiki.example.com'
      # non-secret config as plain env …
      APP_SECRET_FILE:     /run/secrets/astrawiki_app_secret
      DATABASE_URL_FILE:   /run/secrets/astrawiki_database_url
      REDIS_URL_FILE:      /run/secrets/astrawiki_redis_url
      OPENAI_API_KEY_FILE: /run/secrets/astrawiki_openai_api_key
    secrets:
      - astrawiki_app_secret
      - astrawiki_database_url
      - astrawiki_redis_url
      - astrawiki_openai_api_key

secrets:
  astrawiki_app_secret:   { external: true }
  astrawiki_database_url: { external: true }
  astrawiki_redis_url:    { external: true }
  astrawiki_openai_api_key: { external: true }
```

If a `<NAME>_FILE` points at an unreadable path, the container exits with an error rather than
starting half-configured. Put the full connection string (e.g. `DATABASE_URL`) in the secret,
not just the password.

---

## 1. PostgreSQL extensions (the important part)

Docmost creates its schema through migrations that run automatically on boot, as the role in
`DATABASE_URL`. Several migrations issue `CREATE EXTENSION IF NOT EXISTS …`. **The extension binaries
must already be installed on every Postgres node** (for a Patroni cluster: on all members, since a
replica can be promoted at any time). The `CREATE EXTENSION` call only enables an extension that is
already available on the server — it cannot install one that isn't.

| Extension | Required for | When | Notes |
|-----------|--------------|------|-------|
| **`pg_trgm`** | Core full-text search (default `database` search driver) | **Always** | Ships with the `postgresql-contrib` package. Trigram matching. |
| **`unaccent`** | Core full-text search (accent-insensitive matching) | **Always** | Ships with `postgresql-contrib`. |
| **`vector`** (pgvector) | AI-powered / semantic search + AI embeddings | **Only if AI features are enabled** | **Not** in `contrib` — must be installed separately. Requires **pgvector ≥ 0.7.0** (the schema uses the `halfvec` type and an `hnsw … halfvec_cosine_ops` index; both were introduced in 0.7.0). |

There is **no** dependency on `pgcrypto`, `uuid-ossp`, or `gen_random_uuid`. Docmost defines its own
`gen_uuid_v7()` as a pure `plpgsql` function (using only `random()` / built-ins), so no extension is
needed for primary keys.

### Privileges / Patroni notes

- Creating an extension requires the DB role to be a **superuser** or to have been granted the right
  to create that specific extension. Managed / Patroni clusters usually run the app with a
  non-superuser role. Two options:
  1. **Pre-create the extensions once** as a superuser in the target database, before first boot:
     ```sql
     CREATE EXTENSION IF NOT EXISTS pg_trgm;
     CREATE EXTENSION IF NOT EXISTS unaccent;
     CREATE EXTENSION IF NOT EXISTS vector;   -- only if using AI
     ```
     The idempotent `CREATE EXTENSION IF NOT EXISTS` in the migrations then becomes a no-op.
  2. Grant the app role permission to create them (less preferred on shared clusters).
- **pgvector must be present on the OS/package level on every Patroni node.** If it is missing, the
  embeddings migration does **not** fail the boot — it logs a warning and **silently skips** creating
  the `page_embeddings` table:
  > *Postgres pgvector extension is not available. Skipping embeddings table creation.*
  The app runs fine, but AI semantic search will never work until pgvector is installed and the app
  is restarted (so the migration re-runs and creates the table). Verify availability with:
  ```sql
  SELECT * FROM pg_available_extensions WHERE name IN ('vector','pg_trgm','unaccent');
  ```

---

## 2. Search driver (optional, Enterprise)

`SEARCH_DRIVER` selects how full-text search is served:

| `SEARCH_DRIVER` | Backend | Requirements |
|-----------------|---------|--------------|
| `database` (**default**) | PostgreSQL full-text search | `pg_trgm` + `unaccent` extensions (section 1). Nothing else. |
| `typesense` (Enterprise) | An external **Typesense** server | A separately-run Typesense instance. **The astrawiki image does not include a Typesense server** — only the client. You must deploy `typesense/typesense` yourself and point the app at it. |

Typesense gives typo-tolerant, faster search at scale. If you don't need that, stay on `database` —
it needs no extra service.

Typesense env vars (only when `SEARCH_DRIVER=typesense`):

| Variable | Example | Description |
|----------|---------|-------------|
| `SEARCH_DRIVER` | `typesense` | Switch the driver. |
| `TYPESENSE_URL` | `http://typesense:8108` | URL of your Typesense server. |
| `TYPESENSE_API_KEY` | `…` | API key with read/write permission. |
| `TYPESENSE_LOCALE` | `en` | Locale for text analysis (default `en`). |

---

## 3. AI features (optional, Enterprise) — using OpenAI

The AI settings (AI-powered/semantic search "AI Answers", Ask AI, AI Chat) need **two** things:

1. **pgvector** in PostgreSQL — see section 1 (the `vector` extension). Without it, embeddings are
   never stored and semantic search stays inert even though the toggles appear in the UI.
2. **An embedding + completion provider.** For OpenAI, set:

| Variable | Example | Description |
|----------|---------|-------------|
| `AI_DRIVER` | `openai` | Provider. (`openai` / `openai-compatible` / `ollama` / `google` are supported; use `openai`.) |
| `OPENAI_API_KEY` | `sk-…` | OpenAI API key. |
| `OPENAI_API_URL` | *(optional)* | Override base URL — only for OpenAI-compatible gateways/proxies. |
| `AI_EMBEDDING_MODEL` | `text-embedding-3-small` | Embedding model for vector search. `text-embedding-3-small` = 1536 dims. |
| `AI_EMBEDDING_DIMENSION` | *(optional)* | Override dimensions; defaults to the model preset (or 1536). The vector column caps at **1536** dimensions. |
| `AI_COMPLETION_MODEL` | `gpt-4o-mini` | Model for editor AI actions (improve, summarize, translate, …). |
| `AI_CHAT_MODEL` | `gpt-4o-mini` | Model for AI Chat; falls back to `AI_COMPLETION_MODEL` if unset. |

### How semantic search works (for reference)

- On page create/update, a background job chunks the page text, calls the embedding model, and stores
  each chunk's `halfvec` embedding in `page_embeddings` (scoped per space/workspace), indexed with
  HNSW (`halfvec_cosine_ops`, `m=16`, `ef_construction=64`).
- At query time the search embeds the query and ranks chunks by cosine distance
  (`embedding <=> query`, keeping matches with distance `< 0.9`), returning `similarity = 1 − distance`.
- Changing the embedding model or its dimension triggers an automatic reset + global re-embedding.

---

## Minimum vs full setup

| Goal | PostgreSQL | Extra services | Env |
|------|-----------|----------------|-----|
| Basic wiki, default search | `pg_trgm`, `unaccent` | — | standard `APP_URL` / `APP_SECRET` / `DATABASE_URL` / `REDIS_URL` |
| + AI semantic search / Ask AI (OpenAI) | `pg_trgm`, `unaccent`, **`vector` (pgvector ≥ 0.7.0)** | — | + `AI_DRIVER`, `OPENAI_API_KEY`, `AI_EMBEDDING_MODEL`, `AI_COMPLETION_MODEL` |
| + Typesense search | `pg_trgm`, `unaccent` (+ `vector` if also using AI) | **Typesense server** | + `SEARCH_DRIVER=typesense`, `TYPESENSE_URL`, `TYPESENSE_API_KEY` |
