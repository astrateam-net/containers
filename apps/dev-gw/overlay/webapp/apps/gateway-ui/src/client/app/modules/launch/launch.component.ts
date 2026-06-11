import {
  AfterViewInit,
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  ElementRef,
  HostListener,
  NgZone,
  OnDestroy,
  OnInit,
  ViewChild,
} from '@angular/core';
import type { SessionTerminationInfo, UserInteraction } from '@devolutions/iron-remote-desktop';
import { Backend, displayControl, init as rdpWasmInit, kdcProxyUrl } from '@devolutions/iron-remote-desktop-rdp';
import { RdpToolbarWrapperComponent } from '@gateway/modules/web-client/rdp/rdp-toolbar-wrapper.component';
import { ToolbarAction } from '@shared/components/floating-session-toolbar/models/floating-session-toolbar-action.model';
import { ScreenMode } from '@shared/components/floating-session-toolbar/models/floating-session-toolbar-config.model';
import { ToolbarSessionInfo } from '@shared/components/floating-session-toolbar/models/session-info.model';
import { ScreenScale } from '@shared/enums/screen-scale.enum';
import { Session } from '@shared/models/session';
import { UAParser } from 'ua-parser-js';
import '@devolutions/iron-remote-desktop/iron-remote-desktop.js';

// LaunchComponent — programmatic token login ("our coder.js, but in-source").
//
// The coderd authority (coderdp) has already, server-side: minted the association
// token, generated a synthetic per-session proxy credential, injected the REAL
// credential into the gateway via /jet/preflight, and (for domain targets) minted
// a KDC token. It then redirects the browser here with the descriptor in the URL
// FRAGMENT, which never reaches a server.
//
// Only the AUTHENTICATION differs from the stock RDP tab: no login form, no
// /jet/webapp/app-token flow, no auth guard — the token comes from coderd.
// Everything else mirrors the native gateway session UX: the same
// <iron-remote-desktop> handle + configBuilder chain, the same floating
// session toolbar (Windows key, Ctrl+Alt+Del, screen modes, clipboard actions,
// dynamic resize, unicode keyboard, crosshair cursor, session info), measured
// desktop size + display control like the DVLS web client.
//
// Contract: coderdp/INTEGRATION.md §2,§4. The real password is NEVER in the
// descriptor — only the association token + the synthetic proxy GUIDs.

// LaunchDescriptor == coderdp LaunchResult (json keys, INTEGRATION.md §2).
interface LaunchDescriptor {
  gateway_url: string; // wss base + /jet/rdp (scheme already rewritten by coderd)
  association_token: string; // signed JWT, carried in the RDCleanPath PDU
  proxy_username: string; // synthetic GUID — NOT the real user
  proxy_password: string; // synthetic GUID
  target: string; // host:3389
  kdc_proxy_url?: string; // present only for domain (Kerberos) targets
  // WEBAPP login token (cty=WEBAPP) coderd mints exactly like DVLS's SignAppToken. Stored as the
  // stock webapp session so AuthService.startExpirationCheck (app.component.ts, 60s) sees a valid
  // login and does NOT tear the player down after ~1 min. Not a credential.
  webapp_token?: string;
  // Display-only extras for the session-info popover (parity with DVLS, whose
  // server sends gateway.Name / resolvedCredentials.UserName the same way —
  // RemoteSessionService.cs). Optional: absent ⇒ the rows are hidden, exactly
  // like DVLS's hidden:!value. To be filled by coderdp (INTEGRATION.md TODO).
  gateway_name?: string;
  display_username?: string; // the REAL login name (e.g. "ceo") — name only, never the password
  display_domain?: string; // e.g. "astrateam.net"
}

type LaunchStatus = 'connecting' | 'connected' | 'terminated' | 'error';

// Same debounce the stock toolbar resize path uses (web-client-rdp RESIZE_DEBOUNCE_TIME).
const RESIZE_DEBOUNCE_MS = 100;

@Component({
  standalone: true,
  selector: 'gw-launch',
  templateUrl: './launch.component.html',
  styleUrls: ['./launch.component.scss'],
  imports: [RdpToolbarWrapperComponent],
  // The template hosts the <iron-remote-desktop> custom element; standalone
  // components do not inherit AppModule's schemas.
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
})
export class LaunchComponent implements OnInit, AfterViewInit, OnDestroy {
  backendRef = Backend;

  status: LaunchStatus = 'connecting';
  message: string | null = null;

  remoteClient?: UserInteraction;
  sessionInfo: ToolbarSessionInfo = { rows: [], emptyValueText: 'N/A' };
  clipboardActionButtons: ToolbarAction[] = [];
  dynamicResizeSupported = false;

  @ViewChild('sessionContainer', { static: true }) containerRef!: ElementRef<HTMLElement>;

  private descriptor?: LaunchDescriptor;
  // Loading the RDP WASM module is normally done by WasmInitResolver before the
  // web-client routes activate; this route has no resolver, so the component
  // owns it. connect() must wait for both this promise AND the 'ready' event.
  private wasmReady?: Promise<void>;
  // The programmatically created <iron-remote-desktop> (see ngAfterViewInit).
  private playerElement?: HTMLElement;
  private readyListener?: (event: Event) => void;
  private resizeListener?: () => void;
  private resizeDebounce?: ReturnType<typeof setTimeout>;
  private saveRemoteClipboardButtonEnabled = false;
  private cursorOverrideActive = false;
  private isFullScreenMode = false;

  constructor(private zone: NgZone) {}

  ngOnInit(): void {
    try {
      this.descriptor = this.readDescriptor();
    } catch (e) {
      this.fail(e);
      return;
    }

    this.seedWebAppSession(this.descriptor);
    this.wasmReady = rdpWasmInit('INFO');
    this.refreshSessionInfo();
  }

  // DVLS hands the browser a WEBAPP token (SignAppToken) and the web client stores it as the login
  // session. We do the same: persist coderd's webapp_token into the stock AuthService session, using
  // the same storage key + Session model the stock storeToken() uses. Without it the standalone
  // gateway-webapp's AuthService.startExpirationCheck() (app.component.ts, 60s interval) sees an
  // empty session — isAuthenticated() false — and handleTokenExpiration() cleans up the web session,
  // tearing this player down after ~1 minute. Only AUTH changes; we touch no other webapp behaviour.
  private seedWebAppSession(d: LaunchDescriptor): void {
    if (!d.webapp_token) {
      return;
    }
    // Mirror AuthService.storeToken: SESSION_STORAGE_KEY = 'session', expires = now + TOKEN_LIFESPAN.
    const TOKEN_LIFESPAN = 8 * 60 * 60 * 1000;
    const expires = new Date(Date.now() + TOKEN_LIFESPAN).toISOString();
    const session = new Session(d.display_username ?? '', d.webapp_token, expires);
    sessionStorage.setItem('session', JSON.stringify(session));
  }

  // Build the player element by hand. The svelte custom element captures its
  // `module` prop ONCE at mount and dispatches 'ready' ONCE, from a microtask
  // queued at DOM connection. On this route Angular's template phases (node
  // creation → property bindings → hooks) are split across tasks, so a
  // template-declared element loses both races (verified live: 'ready' at
  // 220ms vs ngAfterViewInit at 237ms; `module` undefined at mount →
  // "Cannot read properties of undefined (reading 'SessionBuilder')").
  // Setting the prop and the listener BEFORE appendChild makes the ordering
  // deterministic: the mount microtask cannot run before the element is
  // connected.
  ngAfterViewInit(): void {
    if (!this.descriptor) {
      return;
    }

    const element = document.createElement('iron-remote-desktop');
    element.setAttribute('targetplatform', 'web');
    element.setAttribute('verbose', 'true');
    element.setAttribute('scale', 'fit');
    element.setAttribute('flexcenter', 'true');
    // Property, not attribute: Backend is an object (the RDP WASM module facade).
    (element as HTMLElement & { module: unknown }).module = this.backendRef;
    this.readyListener = (event: Event) => this.onReady(event);
    element.addEventListener('ready', this.readyListener);

    // First child: the status overlays (siblings) must stay on top.
    const container = this.containerRef.nativeElement;
    container.insertBefore(element, container.firstChild);
    this.playerElement = element;
  }

  ngOnDestroy(): void {
    if (this.playerElement) {
      if (this.readyListener) {
        this.playerElement.removeEventListener('ready', this.readyListener);
      }
      this.playerElement.remove();
      this.playerElement = undefined;
    }
    this.unfollowWindowSize();
    // Break the reference cycle (handle → callbacks → component), as the stock base does.
    this.remoteClient = undefined;
  }

  // Mirrors the stock base: leaving browser fullscreen (e.g. via Esc) re-fits the session.
  @HostListener('document:fullscreenchange')
  onFullScreenChange(): void {
    if (!document.fullscreenElement && this.isFullScreenMode) {
      this.isFullScreenMode = false;
      this.remoteClient?.setScale(ScreenScale.Fit.valueOf());
    }
  }

  // ── Toolbar handlers — same behavior as the stock RDP tab ──────────────────

  handleScreenModeChange(mode: ScreenMode): void {
    if (!this.remoteClient) {
      return;
    }
    switch (mode) {
      case 'fullscreen':
        this.toggleFullscreen();
        break;
      case 'fit':
        this.remoteClient.setScale(ScreenScale.Fit.valueOf());
        break;
      case 'minimize':
        this.remoteClient.setScale(ScreenScale.Real.valueOf());
        break;
    }
  }

  onDynamicResizeChange(enabled: boolean): void {
    if (!this.remoteClient) {
      return;
    }
    if (enabled) {
      this.followWindowSize(this.remoteClient);
      const { width, height } = this.measureDesktopSize();
      this.remoteClient.resize(width, height);
    } else {
      this.unfollowWindowSize();
    }
  }

  onCursorCrosshairChange(active: boolean): void {
    this.cursorOverrideActive = active;
    this.remoteClient?.setCursorStyleOverride(
      active ? 'url("assets/images/crosshair.png") 7 7, default' : null,
    );
  }

  startTerminationProcess(): void {
    // run() resolves with the termination info afterwards → status 'terminated'.
    this.remoteClient?.shutdown();
  }

  // ── Connection flow ─────────────────────────────────────────────────────────

  /** 'ready' handler — the listener is attached before the element is connected
   *  (ngAfterViewInit), so the one-shot mount dispatch cannot be missed. */
  private onReady(event: Event): void {
    if (!this.descriptor || this.remoteClient) {
      return;
    }
    const remoteClient = (event as CustomEvent).detail.irgUserInteraction as UserInteraction;
    this.remoteClient = remoteClient;

    // Warnings the WASM client raises mid-session (stock shows a toast; this
    // page has no toast service — log them).
    remoteClient.onWarningCallback((data: string) => console.warn('[devget/launch]', data));

    // DVLS turns unicode keyboard mode ON for web sessions
    // (initializeKeyboardInteraction → setKeyboardUnicodeMode(true)).
    remoteClient.setKeyboardUnicodeMode(true);

    // Clipboard — the stock heuristic: auto on Blink, manual save/send actions
    // elsewhere (setupClipboardHandling in the desktop base).
    const autoClipboard = window.isSecureContext && new UAParser().getEngine().name === 'Blink';
    remoteClient.setEnableAutoClipboard(autoClipboard);
    remoteClient.onClipboardRemoteUpdateCallback(() => {
      this.saveRemoteClipboardButtonEnabled = true;
    });
    this.setupClipboardActions(remoteClient, autoClipboard);

    void this.wasmReady
      ?.then(() => this.connect(remoteClient, this.descriptor as LaunchDescriptor))
      .catch((err) => this.fail(err));
  }

  private connect(remoteClient: UserInteraction, d: LaunchDescriptor): Promise<void> {
    const desktopSize = this.measureDesktopSize();

    const builder = remoteClient
      .configBuilder()
      .withUsername(d.proxy_username) // synthetic proxy cred — unlocks only this session's fake KDC
      .withPassword(d.proxy_password)
      .withDestination(d.target)
      .withProxyAddress(d.gateway_url) // already wss
      .withAuthToken(d.association_token) // authority is coderd, not the webapp
      .withDesktopSize(desktopSize)
      // Same as the stock tab and DVLS: Display Control is what lets the session
      // follow the browser window instead of staying at the initial size.
      .withExtension(displayControl(true));

    // No withServerDomain: the proxy credential is synthetic (no domain), exactly
    // like DVLS's injected-credential path, which drops the domain when proxy
    // credentials are in play.

    if (d.kdc_proxy_url) {
      // Domain/Kerberos targets: the browser-side CredSSP needs the gateway's KKDCP
      // endpoint for the synthetic realm. Absent ⇒ NTLM target ⇒ not needed.
      builder.withExtension(kdcProxyUrl(d.kdc_proxy_url));
    }

    let connectPromise: Promise<unknown>;
    try {
      connectPromise = remoteClient.connect(builder.build());
    } catch (syncErr) {
      // The WASM client can throw synchronously before returning the promise.
      this.fail(syncErr);
      return Promise.resolve();
    }

    return connectPromise
      .then((session) => {
        // The canvas is hidden until told otherwise — the stock base flips it
        // in handleSessionStarted.
        remoteClient.setVisibility(true);
        this.dynamicResizeSupported = true;
        this.zone.run(() => {
          this.status = 'connected';
        });
        // Toolbar's Dynamic resize starts ON (initialState) — engage the follower.
        this.followWindowSize(remoteClient);
        return (session as { run(): Promise<SessionTerminationInfo> }).run();
      })
      .then((info) => {
        this.zone.run(() => {
          this.status = 'terminated';
          this.message = typeof info?.reason === 'function' ? info.reason() : null;
        });
      })
      .catch((err) => this.fail(err));
  }

  // ── Toolbar plumbing (mirrors the stock desktop base) ───────────────────────

  /** Manual clipboard actions for non-Blink engines — same as setupClipboardHandling. */
  private setupClipboardActions(remoteClient: UserInteraction, autoClipboard: boolean): void {
    if (!window.isSecureContext || autoClipboard) {
      this.clipboardActionButtons = [];
      return;
    }

    const actions: ToolbarAction[] = [
      {
        id: 'save-clipboard',
        label: 'Save Clipboard',
        tooltip: 'Copy received clipboard content to your local clipboard.',
        icon: 'dvl-icon dvl-icon-save',
        action: () => void this.saveRemoteClipboard(remoteClient),
        enabled: () => this.saveRemoteClipboardButtonEnabled,
      },
    ];

    if (typeof navigator.clipboard?.readText === 'function') {
      actions.push({
        id: 'send-clipboard',
        label: 'Send Clipboard',
        tooltip: 'Send your local clipboard content to the remote server.',
        icon: 'dvl-icon dvl-icon-send',
        action: () => void remoteClient.sendClipboardData(),
        enabled: () => true,
      });
    }

    this.clipboardActionButtons = actions;
  }

  private async saveRemoteClipboard(remoteClient: UserInteraction): Promise<void> {
    try {
      await remoteClient.saveRemoteClipboardData();
      this.saveRemoteClipboardButtonEnabled = false;
    } catch (err) {
      console.warn('[devget/launch] clipboard save failed:', this.toMessage(err));
    }
  }

  private toggleFullscreen(): void {
    if (!document.fullscreenElement) {
      this.isFullScreenMode = true;
      this.containerRef.nativeElement.requestFullscreen().catch((err: Error) => {
        this.isFullScreenMode = false;
        console.error(`Error attempting to enable fullscreen mode: ${err.message}`);
      });
      this.remoteClient?.setScale(ScreenScale.Full.valueOf());
    } else {
      this.isFullScreenMode = false;
      document.exitFullscreen().catch((err) => console.error(`Error attempting to exit fullscreen: ${err}`));
    }
  }

  /** The DVLS session-info panel, row for row (its client builds exactly these:
   *  credentialInjection / gatewayName / gatewaySessionId / gatewayUrl /
   *  recordingServer / username / domain, hiding empty ones). Injection is
   *  always Active here — the descriptor always carries proxy creds; recording
   *  is Inactive until jet_rec is wired. */
  private refreshSessionInfo(): void {
    const d = this.descriptor;
    const sessionId = this.extractAssociationId(d?.association_token);
    this.sessionInfo = {
      rows: [
        { id: 'credentialInjection', label: 'Credential injection', value: 'Active', tone: 'success', order: 1 },
        { id: 'gatewayName', label: 'Gateway name', value: d?.gateway_name, hidden: !d?.gateway_name, order: 2 },
        { id: 'gatewaySessionId', label: 'Gateway session ID', value: sessionId, hidden: !sessionId, order: 3 },
        { id: 'gatewayUrl', label: 'Gateway URL', value: this.toUserFacingUrl(d?.gateway_url), order: 4 },
        { id: 'recordingServer', label: 'Recording server', value: 'Inactive', order: 5 },
        { id: 'username', label: 'Username', value: d?.display_username, hidden: !d?.display_username, order: 6 },
        { id: 'domain', label: 'Domain', value: d?.display_domain, hidden: !d?.display_domain, order: 7 },
        // DVLS shows no host row; we add it (host only — the port lives in the gateway's dst_hst).
        { id: 'host', label: 'Host', value: d?.target, hidden: !d?.target, order: 8 },
      ],
      emptyValueText: 'N/A',
    };
  }

  /** Gateway session ID == the association id (jet_aid claim) — the same UUID
   *  DVLS shows (its RemoteSessionEntity.ID is the gatewaySessionId). The token
   *  is already client-side; its payload is plain base64url JSON. */
  private extractAssociationId(token: string | undefined): string | undefined {
    if (!token) {
      return undefined;
    }
    try {
      const payload = JSON.parse(this.base64UrlDecode(token.split('.')[1])) as { jet_aid?: string };
      return payload.jet_aid;
    } catch {
      return undefined;
    }
  }

  /** wss URL → clean https URL for display (same idea as the stock toUserFacingUrl). */
  private toUserFacingUrl(url: string | undefined): string | null {
    if (!url) {
      return null;
    }
    try {
      const normalized = new URL(url, window.location.href);
      normalized.protocol = normalized.protocol === 'wss:' ? 'https:' : 'http:';
      normalized.search = '';
      normalized.hash = '';
      return normalized.toString();
    } catch {
      return url;
    }
  }

  // ── Sizing ──────────────────────────────────────────────────────────────────

  /** Initial desktop size = the viewport (this route is a full-window player).
   *  Stock/DVLS always send a measured size; without one ironrdp-web falls back
   *  to a hardcoded 1280×720. Width is floored to even — RDP surfaces dislike
   *  odd widths. */
  private measureDesktopSize(): { width: number; height: number } {
    const width = Math.max(640, document.documentElement.clientWidth) & ~1;
    const height = Math.max(480, document.documentElement.clientHeight) & ~1;
    return { width, height };
  }

  /** Dynamic resize: the session follows the window (DVLS observes its session
   *  container the same way). Requires displayControl; toggled from the toolbar. */
  private followWindowSize(remoteClient: UserInteraction): void {
    if (this.resizeListener) {
      return;
    }
    // Outside the zone: resize events are high-frequency and touch no bindings.
    this.zone.runOutsideAngular(() => {
      this.resizeListener = () => {
        if (this.resizeDebounce) {
          clearTimeout(this.resizeDebounce);
        }
        this.resizeDebounce = setTimeout(() => {
          const { width, height } = this.measureDesktopSize();
          remoteClient.resize(width, height);
        }, RESIZE_DEBOUNCE_MS);
      };
      window.addEventListener('resize', this.resizeListener);
    });
  }

  private unfollowWindowSize(): void {
    if (this.resizeListener) {
      window.removeEventListener('resize', this.resizeListener);
      this.resizeListener = undefined;
    }
    if (this.resizeDebounce) {
      clearTimeout(this.resizeDebounce);
      this.resizeDebounce = undefined;
    }
  }

  // ── Descriptor ──────────────────────────────────────────────────────────────

  /** Descriptor = base64url(JSON(LaunchResult)) in the URL fragment (INTEGRATION.md §4).
   *  The fragment is client-only; it is never sent to the gateway server. It carries the
   *  one-time token + synthetic creds, so strip it from history immediately after reading. */
  private readDescriptor(): LaunchDescriptor {
    const raw = window.location.hash.replace(/^#/, '');
    if (!raw) {
      throw new Error('launch: empty URL fragment');
    }

    // Remove the one-time token + synthetic creds from the address bar / history.
    history.replaceState(null, '', window.location.pathname + window.location.search);

    let json: string;
    try {
      json = this.base64UrlDecode(raw);
    } catch {
      throw new Error('launch: fragment is not valid base64url');
    }

    let d: LaunchDescriptor;
    try {
      d = JSON.parse(json) as LaunchDescriptor;
    } catch {
      throw new Error('launch: fragment is not valid JSON');
    }

    if (!d.association_token || !d.target || !d.proxy_username || !d.proxy_password || !d.gateway_url) {
      throw new Error('launch: descriptor missing required fields');
    }
    return d;
  }

  /** base64url (Go base64.RawURLEncoding — no padding) → UTF-8 string. */
  private base64UrlDecode(input: string): string {
    const base64 = input.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(base64);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  }

  private fail(err: unknown): void {
    this.zone.run(() => {
      this.status = 'error';
      this.message = this.toMessage(err);
    });
  }

  private toMessage(err: unknown): string {
    // IronError carries the useful detail in backtrace().
    if (err && typeof (err as { backtrace?: unknown }).backtrace === 'function') {
      return (err as { backtrace(): string }).backtrace();
    }
    return err instanceof Error ? err.message : String(err);
  }
}
