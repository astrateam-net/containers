# AstraIDE — patch-over-upstream build

Orca runtime server (`orca serve`) plus one patch that adds **trusted-proxy web-session
mode**, so Orca's browser client works behind Coder / a reverse proxy that already
enforces auth — no pairing token in the URL.

## Build model (patch-file, à la `build/openclaw`)

Same shape as `apps/dev` (Coder). The image is **upstream + patches**, not a fork checkout:

1. Dockerfile clones the pristine upstream release `stablyai/orca @ ${VERSION}` (shallow).
2. Applies `patches/*.patch` in order with `git apply --verbose` (plain `git diff` files;
   fails the build loudly on version drift — same as `apps/dev`).
3. Builds the Electron desktop bundle and packages an unpacked Linux app (`orca-ide`).

The build depends only on **upstream** — never on our fork. The change is reviewable
here, next to the Dockerfile. If an upstream bump moves code a patch touches, `git am`
fails the build **loudly** — that's the signal to refresh the patch (below).

`VERSION` is Renovate-tracked against `stablyai/orca` stable releases (rc tags filtered).
Bumping `VERSION` rebuilds on the newer upstream; a bump is **not** auto-mergeable until
the patch is confirmed to still apply.

## The fork is the authoring polygon, not a build input

`github.com/mrkhachaturov/orcaide` is where patches are *written and tested* (real working
tree, `pnpm dev`, upstream-PR candidate). It has two remotes: `origin` (the fork) and
`upstream` (`stablyai/orca`, fetch-only for tags). Branch convention:

| Prefix | Purpose | Commits |
|--------|---------|---------|
| `feat/<feature>`  | dev history / upstream PR | many, messy OK |
| `patch/<feature>` | production patch source   | **exactly one** squashed commit on the upstream tag |

One `patch/` branch → one `.patch` file (the combined feature diff), even if it was
developed across many `feat/` commits.

Current: `patch/trusted-proxy` = `v1.4.154` + one commit → `patches/0001-*.patch`.

## Regenerate a patch (from any machine — you always have the fork)

```bash
git clone git@github.com:mrkhachaturov/orcaide.git && cd orcaide
git remote add upstream https://github.com/stablyai/orca.git   # once
git fetch upstream --tags
git checkout patch/trusted-proxy
git diff v1.4.154 patch/trusted-proxy \
  > <containers>/apps/astraide/patches/0001-serve-trusted-proxy-web-session.patch
```

## Bump upstream

```bash
cd orcaide && git fetch upstream --tags
git checkout patch/trusted-proxy
git rebase v<new>            # resolve conflicts if upstream moved our code
git push -f origin patch/trusted-proxy
git diff v<new> patch/trusted-proxy \
  > <containers>/apps/astraide/patches/0001-serve-trusted-proxy-web-session.patch
# then set VERSION="v<new>" in docker-bake.hcl
```

## The patch, in one line

`orca serve --trusted-proxy`: binds loopback only + serves the runtime pairing offer at
loopback-gated `GET /trusted-session`; the web client auto-fetches it when there's no URL
offer and no stored env. Mirrors code-server's `bind 127.0.0.1` + `--auth none` trust
model — but Orca's channel is E2EE, so it *issues* the credential instead of skipping auth.

Runtime env: `ORCA_PORT` (6768), `ORCA_TRUSTED_PROXY` (true), `ORCA_PAIRING_ADDRESS`
(the Coder-reachable URL — required, else reconnects dial 127.0.0.1), `ORCA_NO_SANDBOX`
(true; Chromium's sandbox can't init in most containers).
