package coderd

import (
	"crypto/tls"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/astrateam-net/dev-kit/jetbroker"
	"golang.org/x/xerrors"

	"cdr.dev/slog/v3"

	"github.com/coder/coder/v2/coderd/database"
	"github.com/coder/coder/v2/coderd/httpapi"
	"github.com/coder/coder/v2/coderd/httpmw"
	"github.com/coder/coder/v2/codersdk"
)

// rdp_launch.go wires the in-house browser-RDP authority (the dev-kit jetbroker
// core) into coderd. The endpoint mints provisioner-signed Devolutions Gateway
// tokens, injects the real RDP credential into a farm gateway server-to-server
// via /jet/preflight, and 302s the browser to the chosen gateway's webapp
// launch page with a descriptor that NEVER carries the real password.
//
// The four jetbroker seams (identity, target, gateway farm, secret) are backed
// by Coder data read by workspace id (rdp_adapters.go). The endpoint is owner
// gated: only the workspace owner may launch (share=owner parity).

var (
	rdpBrokerOnce sync.Once
	rdpBroker     *jetbroker.Broker
	rdpBrokerErr  error
)

// rdpBrokerFor builds the jetbroker.Broker once from environment configuration,
// backed by the Coder database. A misconfigured deployment fails per request
// (the error is logged, the client gets a generic 502) rather than at boot, so
// a Coder server without RDP configured still starts normally.
func (api *API) rdpBrokerFor() (*jetbroker.Broker, error) {
	rdpBrokerOnce.Do(func() {
		// api.AppHostname is the deployment wildcard app host (e.g. "*.example.com"); it
		// lets the gateway resolver build the browser-facing subdomain for the chosen gateway.
		// Empty (no wildcard configured) => the browser uses the gateway's own url.
		rdpBroker, rdpBrokerErr = buildRDPBroker(api.Database, api.AppHostname)
	})
	return rdpBroker, rdpBrokerErr
}

func buildRDPBroker(db database.Store, appHostname string) (*jetbroker.Broker, error) {
	keyPath := os.Getenv("CODER_RDP_PROVISIONER_KEY")
	if keyPath == "" {
		return nil, xerrors.New("CODER_RDP_PROVISIONER_KEY is required (path to the provisioner private key PEM)")
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, xerrors.Errorf("read CODER_RDP_PROVISIONER_KEY: %w", err)
	}
	key, err := jetbroker.LoadProvisionerKey(keyPEM)
	if err != nil {
		return nil, err
	}

	usernameParam := envOr("CODER_RDP_USERNAME_PARAM", "rdp_username")
	cfg := jetbroker.Config{
		ProvisionerKey:   key,
		Realm:            os.Getenv("CODER_RDP_REALM"),
		SecretName:       envOr("CODER_RDP_SECRET_PARAM", "rdp_password"),
		RedirectMode:     true,
		PlayerLaunchPath: envOr("CODER_RDP_LAUNCH_PATH", "/jet/webapp/client/launch"),
	}
	if ttl := os.Getenv("CODER_RDP_CREDENTIAL_TTL"); ttl != "" {
		n, err := strconv.Atoi(ttl)
		if err != nil {
			return nil, xerrors.Errorf("CODER_RDP_CREDENTIAL_TTL must be an integer: %w", err)
		}
		cfg.CredentialTTL = n
	}
	// Farm gateways carry the publicly trusted wildcard cert, so TLS verifies by
	// default. Opt-in skip for a private-CA test stand only.
	if truthy(os.Getenv("CODER_RDP_TLS_INSECURE")) {
		cfg.HTTPClient = &http.Client{
			Timeout:   10 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, //nolint:gosec // test-stand opt-in
		}
	}

	return jetbroker.New(
		cfg,
		rdpIdentity{db: db, usernameParam: usernameParam},
		rdpTarget{db: db, key: envOr("CODER_RDP_TARGET_KEY", "coder.rdp.target")},
		rdpSecret{db: db},
		rdpGateways{db: db, key: envOr("CODER_RDP_GATEWAYS_KEY", "coder.rdp.gateways"), appHostname: appHostname},
	)
}

// workspaceRDP is the launch endpoint. It is registered behind apiKeyMiddleware
// and httpmw.ExtractWorkspaceParam, so the caller is authenticated and the
// workspace is loaded. It authorizes the owner (share=owner), then delegates to
// the jetbroker handler, which selects a gateway, injects the credential, and
// 302s to the gateway webapp launch page.
//
// @Summary Launch a browser RDP session
// @ID launch-a-browser-rdp-session
// @Security CoderSessionToken
// @Tags Workspaces
// @Param workspace path string true "Workspace ID" format(uuid)
// @Success 302
// @Router /workspaces/{workspace}/rdp [get]
// @x-apidocgen {"skip": true}
func (api *API) workspaceRDP(rw http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ws := httpmw.WorkspaceParam(r)

	// share=owner: only the workspace owner may launch RDP. The credential is
	// bound to the workspace, so this gate prevents a non-owner from connecting
	// under the configured account by guessing the workspace id.
	if httpmw.APIKey(r).UserID != ws.OwnerID {
		httpapi.Write(ctx, rw, http.StatusNotFound, codersdk.Response{
			Message: "Workspace not found.",
		})
		return
	}

	broker, err := api.rdpBrokerFor()
	if err != nil {
		api.Logger.Error(ctx, "rdp broker unavailable", slog.Error(err))
		httpapi.Write(ctx, rw, http.StatusBadGateway, codersdk.Response{
			Message: "RDP is not available.",
		})
		return
	}

	// The jetbroker handler reads the workspace id from the "ws" query param and
	// owns the redirect/descriptor encoding. Feed it the authorized workspace id
	// from the path so the adapters resolve the right workspace server-side.
	q := r.URL.Query()
	q.Set("ws", ws.ID.String())
	r.URL.RawQuery = q.Encode()
	broker.Handler().ServeHTTP(rw, r)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func truthy(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}
