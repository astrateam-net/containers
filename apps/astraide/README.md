# astraide

`ghcr.io/astrateam-net/astraide` — a custom build of [Orca](https://github.com/stablyai/orca)
(the AI-agent orchestrator/IDE), rebuilt from a pinned upstream tag with a local
patch series applied on top. It runs Orca in **server mode** (`orca serve`) so the
runtime — terminals, git worktrees, agents, orchestration — lives on a host and the
UI is reached from a browser, like `code-server`.

## The problem we're solving

Orca is open-source and self-hostable: `orca serve` starts the runtime headless and
ships a full web client. That's the piece we want — a workspace that lives on a
server (a Coder workspace, an LXC) and is reachable from any browser, with agents
running server-side instead of on a laptop.

But Orca's web client can't sit behind a reverse proxy the way `code-server` does.
Two things get in the way:

1. **Auth is a per-startup token in the URL fragment.** Orca mints a fresh pairing
   offer every time `serve` starts and hands it to the browser as
   `…/web-index.html#pairing=<token>`. code-server behind Coder just runs with
   `--auth none` and trusts the proxy — Orca has no equivalent, so the page refuses
   to do anything until it's handed that token.
2. **The token doesn't exist at provision time.** A Coder app tile's URL is fixed
   when the template is built, before any workspace (and any token) exists — so the
   tile literally cannot carry it. And a URL fragment never reaches the server, so
   it can't be injected proxy-side either.

The result: stock `orca serve` can't be a one-click Coder app the way `code-server`,
VS Code Web, or Jupyter are.

## What the patch does

`patches/0001` adds **`orca serve --trusted-proxy`** — the missing `--auth none`
equivalent, adapted to Orca's design:

- Binds the runtime listener to **loopback only**. Behind Coder, the only way a
  packet reaches the port is through Coder's agent, which already enforced TLS +
  owner-scoped auth. A connection on loopback is therefore proof it came through the
  trusted proxy — exactly how `code-server`'s `bind 127.0.0.1` + `--auth none` works.
- Serves the current pairing offer at loopback-gated **`GET /trusted-session`**. The
  web client auto-fetches it on load when there's no URL token and no saved server,
  and connects with nothing in the address bar.

The one way it *differs* from `--auth none`: Orca's browser channel is **end-to-end
encrypted**, so the token isn't a password you can skip — it carries the key. The
patch can't "return true"; it *issues* the credential over the loopback-gated
endpoint instead. Same trust boundary, encryption preserved.

Net effect: astraide is a normal Coder subdomain app. Open the tile → the page pairs
itself → you're in. Survives refresh and workspace restarts, no token in the URL.

## Why it matters here

This is the missing piece for running agents as server-side workspaces instead of on
a laptop: a Coder workspace boots `astraide`, agents run in the sandboxed container
(where `--dangerously-skip-permissions` is actually appropriate), reach secrets only
through the agent-vault MITM proxy, read context from the wiki/AstraRAG over MCP, and
you drive the whole thing from a browser tab — nothing installed locally.

## Build

Upstream + patches, same shape as [`apps/dev`](../dev/): the [`Dockerfile`](Dockerfile)
clones `stablyai/orca @ $VERSION`, applies `patches/` with `git apply` (fails loudly on
version drift), builds the Electron desktop bundle, and packages an unpacked Linux app.
The runtime stage mirrors upstream's headless deps (Chromium libs + Xvfb).

Patches are authored in the fork [`mrkhachaturov/orcaide`](https://github.com/mrkhachaturov/orcaide)
(the "polygon") and exported here as plain diffs. See [`CLAUDE.md`](CLAUDE.md) for the
authoring workflow and how to bump the upstream version.

### Runtime configuration

| Env | Default | Purpose |
|-----|---------|---------|
| `ORCA_PORT` | `6768` | Listener port. |
| `ORCA_TRUSTED_PROXY` | `true` | Loopback bind + `/trusted-session`. |
| `ORCA_PAIRING_ADDRESS` | — | The Coder-reachable URL clients advertise. **Required** — without it, reconnects dial `127.0.0.1`. |
| `ORCA_NO_SANDBOX` | `true` | Chromium's setuid sandbox can't initialize in most containers. |
| `ORCA_NO_PAIRING` | `false` | Disable pairing entirely. |

amd64 only — Orca is an Electron app; an arm64 build under emulation is impractical.
