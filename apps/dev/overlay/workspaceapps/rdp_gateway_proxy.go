package workspaceapps

import (
	"crypto/tls"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"

	"cdr.dev/slog/v3"

	"github.com/coder/coder/v2/site"
)

// rdp_gateway_proxy.go is part of the in-house browser-RDP system. The launch
// authority (coderd/rdp_launch.go) selects a live, least-loaded Devolutions
// Gateway from the swarm farm and sends the browser to a subdomain coder_app
// whose URL is that chosen gateway. A normal workspace app would be proxied
// through the workspace agent's tailnet (and rewritten to the agent host's
// localhost), which is wrong here: the farm runs on the swarm, not on the
// workspace host. proxyWorkspaceApp branches to rdpGatewayDirectProxy for these
// apps (gated by ServerOptions.RDPGatewayAppPrefix).

// rdpGatewayDirectProxy builds a reverse proxy that forwards straight to an
// external Devolutions Gateway (target), dialing its published port directly
// over the network. It does NOT route through the workspace agent and does NOT
// rewrite the host to the agent IP. WebSocket (/jet/rdp) and the webapp launch
// page both flow through this proxy, so HTTP/2 is disabled to keep the Upgrade
// handshake on HTTP/1.1.
func rdpGatewayDirectProxy(target, dashboardURL *url.URL, tlsInsecure bool, logger slog.Logger) *httputil.ReverseProxy {
	proxy := httputil.NewSingleHostReverseProxy(target)

	// NewSingleHostReverseProxy preserves the inbound Host; the gateway is
	// addressed by its own hostname, so set Host to the target.
	baseDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		baseDirector(req)
		req.Host = target.Host
	}

	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.ForceAttemptHTTP2 = false
	transport.TLSClientConfig = &tls.Config{
		MinVersion: tls.VersionTLS12,
		// http/1.1 only: a negotiated h2 connection breaks the WebSocket Upgrade.
		NextProtos:         []string{"http/1.1"},
		InsecureSkipVerify: tlsInsecure, //nolint:gosec // private-CA test stand opt-in
	}
	proxy.Transport = transport

	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		logger.Warn(r.Context(), "rdp gateway proxy error",
			slog.F("target", target.String()), slog.Error(err))
		site.RenderStaticErrorPage(w, r, site.ErrorPageData{
			Status:      http.StatusBadGateway,
			Title:       "Bad Gateway",
			Description: fmt.Sprintf("Failed to reach the RDP gateway: %s", err.Error()),
			Actions: []site.Action{
				{URL: dashboardURL.String(), Text: "Back to site"},
			},
		})
	}

	return proxy
}
