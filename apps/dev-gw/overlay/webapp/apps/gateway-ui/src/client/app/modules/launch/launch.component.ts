import {
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  ElementRef,
  OnDestroy,
  OnInit,
  Renderer2,
  ViewChild,
} from '@angular/core';
import { ActivatedRoute } from '@angular/router';
import { init as rdpWasmInit } from '@devolutions/iron-remote-desktop-rdp';
import { DVL_RDP_ICON } from '@gateway/app.constants';
import { RdpToolbarWrapperComponent } from '@gateway/modules/web-client/rdp/rdp-toolbar-wrapper.component';
import { WebClientRdpComponent } from '@gateway/modules/web-client/rdp/web-client-rdp.component';
import { AnalyticService } from '@gateway/shared/services/analytic.service';
import { ToolbarSessionInfo } from '@shared/components/floating-session-toolbar/models/session-info.model';
import { GatewayAlertMessageService } from '@shared/components/gateway-alert-message/gateway-alert-message.service';
import { IronRDPConnectionParameters } from '@shared/interfaces/connection-params.interfaces';
import { DesktopSize } from '@shared/models/desktop-size';
import { Session } from '@shared/models/session';
import { ComponentResizeObserverService } from '@shared/services/component-resize-observer.service';
import { NavigationService } from '@shared/services/navigation.service';
import { UtilsService } from '@shared/services/utils.service';
import { WebClientService } from '@shared/services/web-client.service';
import { WebSessionService } from '@shared/services/web-session.service';
import { MessageService } from 'primeng/api';
import '@devolutions/iron-remote-desktop/iron-remote-desktop.js';

// LaunchComponent — programmatic token login ("our coder.js, but in-source").
//
// This is a THIN patch over the stock gateway RDP tab. It extends Devolutions'
// own WebClientRdpComponent and changes EXACTLY ONE thing: authentication.
// Instead of a login form + /jet/webapp/app-token fetch, the coderd authority
// (coderdp) has already — server-side — minted the association token, generated
// a synthetic per-session proxy credential, injected the REAL credential into the
// gateway via /jet/preflight, and (for domain targets) minted a KDC token, then
// redirected the browser here with the descriptor in the URL FRAGMENT.
//
// Everything else — the player, the floating toolbar, dynamic resize, clipboard,
// fullscreen, cursor, the whole session lifecycle AND their configBuilder
// (callConnect) — is INHERITED and runs unmodified. We only:
//   1. read the descriptor + seed the webapp session (auth),
//   2. assemble IronRDPConnectionParameters and hand them to their callConnect,
//   3. surface our DVLS-parity session-info rows (buildSessionInfo),
//   4. wire the 'ready' listener programmatically (a measured race on this route).
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
  // Display-only extras for the session-info popover (parity with DVLS). Optional:
  // absent ⇒ the row is hidden, exactly like DVLS's hidden:!value.
  gateway_name?: string;
  display_username?: string; // the REAL login name (e.g. "ceo") — name only, never the password
  display_domain?: string; // e.g. "astrateam.net"
}

@Component({
  standalone: true,
  selector: 'gw-launch',
  templateUrl: './launch.component.html',
  styleUrls: ['./launch.component.scss'],
  imports: [RdpToolbarWrapperComponent],
  // WebClientRdpComponent provides MessageService at the component level; mirror it
  // so any inherited toast path resolves identically.
  providers: [MessageService],
  // The template hosts the <iron-remote-desktop> custom element; standalone
  // components do not inherit AppModule's schemas.
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
})
export class LaunchComponent extends WebClientRdpComponent implements OnInit, OnDestroy {
  @ViewChild('sessionContainer', { static: true }) private containerRef!: ElementRef<HTMLElement>;

  private descriptor?: LaunchDescriptor;
  // The stock route loads the RDP WASM module via WasmInitResolver before activation;
  // this route has no resolver, so the component owns it. connect() waits on this.
  private wasmReady?: Promise<void>;
  // The programmatically created <iron-remote-desktop> (see initiateRemoteClientListener).
  private playerElement?: HTMLElement;

  constructor(
    renderer: Renderer2,
    utils: UtilsService,
    activatedRoute: ActivatedRoute,
    navigation: NavigationService,
    gatewayAlertMessageService: GatewayAlertMessageService,
    webSessionService: WebSessionService,
    webClientService: WebClientService,
    componentResizeService: ComponentResizeObserverService,
    analyticService: AnalyticService,
  ) {
    super(
      renderer,
      utils,
      activatedRoute,
      navigation,
      gatewayAlertMessageService,
      webSessionService,
      webClientService,
      componentResizeService,
      analyticService,
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  // We deliberately do NOT call super.ngOnInit(): the stock ngOnInit drives the
  // form/route/navigation path (setRdpConfig + navigateToNewSession) that we
  // replace with the descriptor. The inherited connection flow needs only a stable
  // webSessionId (icon updates no-op for unknown ids) and the WASM module.
  override ngOnInit(): void {
    let descriptor: LaunchDescriptor;
    try {
      descriptor = this.readDescriptor();
    } catch (err) {
      this.handleError(this.describeError(err));
      return;
    }
    this.descriptor = descriptor;
    // devget: name the browser tab after the RDP host so multiple gateway tabs
    // are distinguishable (favicon untouched). descriptor.target is host-only;
    // strip any explicit :port defensively.
    document.title = descriptor.target.replace(/:\d+$/, '');
    this.webSessionId = this.extractAssociationId(descriptor.association_token) ?? 'launch';
    this.webSessionIcon = DVL_RDP_ICON;
    this.seedWebAppSession(descriptor);
    this.wasmReady = rdpWasmInit('INFO');
    this.refreshSessionInfo();
  }

  override ngOnDestroy(): void {
    this.playerElement?.remove();
    this.playerElement = undefined;
    super.ngOnDestroy();
  }

  // Build the player element by hand so the 'ready' listener is attached BEFORE
  // the svelte custom element's mount microtask can dispatch (measured live on
  // this route: 'ready' at ~220ms vs ngAfterViewInit at ~237ms → a
  // template-declared element loses the race and `module` is undefined at mount).
  // Only the wiring is ours; the handler itself is the inherited base one.
  protected override initiateRemoteClientListener(): void {
    if (!this.descriptor) {
      return;
    }
    // The inherited fullscreen + dynamic-resize helpers operate on this element.
    this.sessionsContainerElement = this.containerRef;

    const element = document.createElement('iron-remote-desktop');
    element.setAttribute('targetplatform', 'web');
    element.setAttribute('verbose', 'true');
    element.setAttribute('scale', 'fit');
    element.setAttribute('flexcenter', 'true');
    // Property, not attribute: Backend is an object (the RDP WASM module facade).
    (element as HTMLElement & { module: unknown }).module = this.backendRef;
    const onReady = (event: Event): void => this.readyRemoteClientEventListener(event);
    element.addEventListener('ready', onReady);

    // First child: the status overlays (siblings) must stay on top.
    const container = this.containerRef.nativeElement;
    container.insertBefore(element, container.firstChild);
    this.playerElement = element;
    // base.removeRemoteClientListener() invokes this on destroy.
    this.unlistenRemoteClient = () => element.removeEventListener('ready', onReady);
  }

  // ── Connection (the only logic that differs: credential injection) ─────────────

  // Called by the inherited readyRemoteClientEventListener once the player is ready.
  // We assemble the injected parameters and hand them to the stock callConnect —
  // their configBuilder, connect, handleSessionStarted and run() are untouched.
  protected override startConnectionProcess(): void {
    const descriptor = this.descriptor;
    if (!descriptor) {
      return;
    }

    const connect = (): void => {
      const params: IronRDPConnectionParameters = {
        username: descriptor.proxy_username, // synthetic proxy cred — unlocks only this session
        password: descriptor.proxy_password,
        host: descriptor.target,
        gatewayAddress: descriptor.gateway_url, // already wss
        token: descriptor.association_token, // authority is coderd, not the webapp
        screenSize: this.measureDesktopSize(),
        enableDisplayControl: true,
        kdcProxyUrl: descriptor.kdc_proxy_url, // present only for domain/Kerberos targets
        // No domain: the proxy credential is synthetic, exactly like DVLS's
        // injected-credential path, which drops the domain when proxy creds are used.
      };
      this.callConnect(params);
    };

    if (this.wasmReady) {
      this.wasmReady.then(connect).catch((err) => this.handleError(this.describeError(err)));
    } else {
      connect();
    }
  }

  // ── Session info (DVLS parity — explicitly requested) ─────────────────────────

  // The DVLS session-info panel, row for row (its client builds exactly these,
  // hiding empty ones). Injection is always Active here — the descriptor always
  // carries proxy creds; recording is Inactive until jet_rec is wired.
  protected override buildSessionInfo(): ToolbarSessionInfo {
    const d = this.descriptor;
    const sessionId = this.extractAssociationId(d?.association_token);
    return {
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

  // ── Sizing ────────────────────────────────────────────────────────────────────

  // Initial desktop size = the viewport (this route is a full-window player).
  // Stock/DVLS always send a measured size; without one ironrdp-web falls back to
  // a hardcoded 1280×720. Width/height floored to even — RDP surfaces dislike odd.
  private measureDesktopSize(): DesktopSize {
    const width = Math.max(640, document.documentElement.clientWidth) & ~1;
    const height = Math.max(480, document.documentElement.clientHeight) & ~1;
    return new DesktopSize(width, height);
  }

  // ── Webapp session seeding (auth) ─────────────────────────────────────────────

  // DVLS hands the browser a WEBAPP token (SignAppToken) and the web client stores it as the login
  // session. We do the same: persist coderd's webapp_token into the stock AuthService session, using
  // the same storage key + Session model storeToken() uses. Without it the standalone gateway-webapp's
  // AuthService.startExpirationCheck() (app.component.ts, 60s interval) sees an empty session and
  // handleTokenExpiration() tears this player down after ~1 minute. Only AUTH; no other behaviour.
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

  // ── Descriptor ────────────────────────────────────────────────────────────────

  // Descriptor = base64url(JSON(LaunchResult)) in the URL fragment (INTEGRATION.md §4).
  // The fragment is client-only; it is never sent to the gateway server. It carries the
  // one-time token + synthetic creds, so strip it from history immediately after reading.
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

  // Gateway session ID == the association id (jet_aid claim) — the same UUID DVLS shows. The token
  // is already client-side; its payload is plain base64url JSON.
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

  // base64url (Go base64.RawURLEncoding — no padding) → UTF-8 string.
  private base64UrlDecode(input: string): string {
    const base64 = input.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(base64);
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
    return new TextDecoder().decode(bytes);
  }

  // IronError carries the useful detail in backtrace().
  private describeError(err: unknown): string {
    if (err && typeof (err as { backtrace?: unknown }).backtrace === 'function') {
      return (err as { backtrace(): string }).backtrace();
    }
    return err instanceof Error ? err.message : String(err);
  }
}
