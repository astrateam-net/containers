# Build-only stubs for Devolutions' private npm packages

Five `@devolutions/*` dependencies of `gateway-ui` live on Devolutions' **private**
Artifactory registry (`devolutions.jfrog.io`, auth required — their CI injects
`ARTIFACTORY_NPM_TOKEN`, see upstream `.github/workflows/ci.yml`) and are not published
to npmjs:

- `@devolutions/terminal-shared`, `@devolutions/web-ssh-gui`, `@devolutions/web-telnet-gui`
  — the SSH/Telnet terminal components;
- `@devolutions/iron-remote-desktop-vnc` — the VNC/ARD backend;
- `@devolutions/icons` — the dvl-icon font + logos.

Without them a plain `pnpm install` of the webapp workspace 404s, so the stock webapp is
not buildable outside Devolutions at all. devget only ships the **RDP** launch path, whose
dependencies (`iron-remote-desktop`, `iron-remote-desktop-rdp`) ARE public — so these stubs
replace the private packages at build time via `overrides` in `pnpm-workspace.yaml`
(added by `patches/0002-stub-private-terminal-deps.patch`). Each stub exports exactly the
symbols/files gateway-ui imports, typed loosely, with inert runtime values.

Consequences in the devget image (all stock-UI-only; the `/launch` route is unaffected):

- **SSH, Telnet, VNC and ARD web sessions are non-functional** (custom elements/backends
  never materialize).

**Icons are the exception — they DO render.** The `@devolutions/icons` stub is repopulated at
build time from the official image of the same pinned version (`tools/harvest-icons.sh`, wired into
`mise run build` as `tasks.icons`): it copies the real font files and extracts the glyph map
(`.dvl-icon-*::before{content:…}`, ~1375 rules, mixed-case `entry-*` included) from the image's own
compiled stylesheet. So `dvl-icon` glyphs are the genuine font, byte-locked to the image version.

**RDP — the whole point of this edition — is fully functional.** If Devolutions ever
publishes these packages publicly, drop the stubs and the override patch.
