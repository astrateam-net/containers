package coderd

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/astrateam-net/dev-kit/jetbroker"
	"github.com/google/uuid"
	"golang.org/x/xerrors"

	"github.com/coder/coder/v2/coderd/database"
	"github.com/coder/coder/v2/coderd/database/dbauthz"
	"github.com/coder/coder/v2/coderd/workspaceapps/appurl"
)

// rdp_adapters.go backs the four jetbroker seams (ports.go) with Coder data,
// all keyed by workspace id and read server-side. The HTTP endpoint
// (rdp_launch.go) owner-gates the request first; these reads then run as the
// system actor so the broker can read the workspace's own params/metadata
// regardless of the caller's fine-grained RBAC.

// rdpIdentity resolves the AD login: the rdp_username build parameter if set,
// else the workspace owner's Coder username (the AD sAMAccountName synced via
// Authentik). The down-level DOMAIN\user form is built by the jetbroker core
// from Config.Realm.
type rdpIdentity struct {
	db            database.Store
	usernameParam string
}

func (a rdpIdentity) Resolve(ctx context.Context, req jetbroker.LaunchRequest) (jetbroker.Identity, error) {
	wsID, err := uuid.Parse(req.WorkspaceID)
	if err != nil {
		return jetbroker.Identity{}, xerrors.Errorf("parse workspace id: %w", err)
	}
	sctx := dbauthz.AsSystemRestricted(ctx)

	ws, err := a.db.GetWorkspaceByID(sctx, wsID)
	if err != nil {
		return jetbroker.Identity{}, xerrors.Errorf("get workspace: %w", err)
	}

	params, err := latestBuildParams(sctx, a.db, wsID)
	if err != nil {
		return jetbroker.Identity{}, err
	}

	username := params[a.usernameParam]
	if username == "" {
		owner, err := a.db.GetUserByID(sctx, ws.OwnerID)
		if err != nil {
			return jetbroker.Identity{}, xerrors.Errorf("get workspace owner: %w", err)
		}
		username = owner.Username
	}

	return jetbroker.Identity{UserID: ws.OwnerID.String(), Username: username}, nil
}

// rdpTarget resolves the RDP target host from the coder.rdp.target resource
// metadata key. Host only; the jetbroker core defaults the port to 3389.
type rdpTarget struct {
	db  database.Store
	key string
}

func (a rdpTarget) Resolve(ctx context.Context, workspaceID string) (string, error) {
	wsID, err := uuid.Parse(workspaceID)
	if err != nil {
		return "", xerrors.Errorf("parse workspace id: %w", err)
	}
	md, err := resourceMetadata(dbauthz.AsSystemRestricted(ctx), a.db, wsID)
	if err != nil {
		return "", err
	}
	target := md[a.key]
	if target == "" {
		return "", xerrors.Errorf("workspace declares no %q metadata", a.key)
	}
	return target, nil
}

// rdpGateways resolves the gateway farm from the coder.rdp.gateways resource
// metadata key, a JSON list of {url, weight, app}. Per member:
//   - url    INTERNAL gateway address: jetbroker uses it for /jet/heartbeat (selection)
//            and /jet/preflight (server-side injection). The gateway uuid is discovered
//            from /jet/heartbeat, never declared.
//   - weight DVLS-style load-balancing weight.
//   - app    the slug of a (hidden) subdomain coder_app pointing at this gateway. When set
//            and the deployment has a wildcard app host, the BROWSER is sent to that app's
//            Coder subdomain (slug--agent--workspace--owner.<wildcard>) instead of url, so a
//            remote browser reaches the internal gateway via the Coder subdomain proxy.
type rdpGateways struct {
	db          database.Store
	key         string
	appHostname string // the deployment wildcard app host, e.g. "*.example.com" ("" disables subdomains)
}

func (a rdpGateways) Resolve(ctx context.Context, workspaceID string) ([]jetbroker.Gateway, error) {
	wsID, err := uuid.Parse(workspaceID)
	if err != nil {
		return nil, xerrors.Errorf("parse workspace id: %w", err)
	}
	sctx := dbauthz.AsSystemRestricted(ctx)

	md, err := resourceMetadata(sctx, a.db, wsID)
	if err != nil {
		return nil, err
	}
	raw := md[a.key]
	if raw == "" {
		return nil, xerrors.Errorf("workspace declares no %q metadata", a.key)
	}

	var declared []struct {
		URL    string `json:"url"`
		Weight int    `json:"weight"`
		App    string `json:"app"`
	}
	if err := json.Unmarshal([]byte(raw), &declared); err != nil {
		return nil, xerrors.Errorf("parse %q metadata: %w", a.key, err)
	}

	// Resolve the subdomain context once (only when subdomains are usable and at least one
	// member declares an app). Without a wildcard host or an app slug the browser uses the
	// gateway's own url (the directly-reachable case, e.g. a single LAN gateway).
	var agentName, wsName, owner string
	if a.appHostname != "" {
		for _, g := range declared {
			if g.App != "" {
				agentName, wsName, owner, err = a.subdomainContext(sctx, wsID)
				if err != nil {
					return nil, err
				}
				break
			}
		}
	}

	gateways := make([]jetbroker.Gateway, 0, len(declared))
	for _, g := range declared {
		gw := jetbroker.Gateway{BaseURL: g.URL, Weight: g.Weight}
		if g.App != "" && agentName != "" {
			sub := appurl.ApplicationURL{
				AppSlugOrPort: g.App,
				AgentName:     agentName,
				WorkspaceName: wsName,
				Username:      owner,
			}.String()
			gw.BrowserURL = "https://" + strings.Replace(a.appHostname, "*", sub, 1)
		}
		gateways = append(gateways, gw)
	}
	return gateways, nil
}

// subdomainContext returns the agent/workspace/owner names used to build a subdomain app host
// (slug--agent--workspace--owner.<wildcard>) for this workspace. The caller supplies the
// authorization context.
func (a rdpGateways) subdomainContext(ctx context.Context, wsID uuid.UUID) (agentName, wsName, owner string, err error) {
	ws, err := a.db.GetWorkspaceByID(ctx, wsID)
	if err != nil {
		return "", "", "", xerrors.Errorf("get workspace: %w", err)
	}
	build, err := a.db.GetLatestWorkspaceBuildByWorkspaceID(ctx, wsID)
	if err != nil {
		return "", "", "", xerrors.Errorf("get latest build: %w", err)
	}
	resources, err := a.db.GetWorkspaceResourcesByJobID(ctx, build.JobID)
	if err != nil {
		return "", "", "", xerrors.Errorf("get build resources: %w", err)
	}
	ids := make([]uuid.UUID, 0, len(resources))
	for _, res := range resources {
		ids = append(ids, res.ID)
	}
	agents, err := a.db.GetWorkspaceAgentsByResourceIDs(ctx, ids)
	if err != nil {
		return "", "", "", xerrors.Errorf("get workspace agents: %w", err)
	}
	if len(agents) == 0 {
		return "", "", "", xerrors.New("workspace has no agent to host the gateway subdomain app")
	}
	return agents[0].Name, ws.Name, ws.OwnerUsername, nil
}

// rdpSecret reads the real RDP password from the workspace's rdp_password build
// parameter, keyed by workspace id (not by calling user).
type rdpSecret struct {
	db database.Store
}

func (a rdpSecret) Get(ctx context.Context, workspaceID, name string) (string, error) {
	wsID, err := uuid.Parse(workspaceID)
	if err != nil {
		return "", xerrors.Errorf("parse workspace id: %w", err)
	}
	params, err := latestBuildParams(dbauthz.AsSystemRestricted(ctx), a.db, wsID)
	if err != nil {
		return "", err
	}
	value, ok := params[name]
	if !ok {
		return "", xerrors.Errorf("workspace declares no %q parameter", name)
	}
	return value, nil
}

// latestBuildParams returns the latest build's parameters as name->value. The
// caller supplies the authorization context.
func latestBuildParams(ctx context.Context, db database.Store, wsID uuid.UUID) (map[string]string, error) {
	build, err := db.GetLatestWorkspaceBuildByWorkspaceID(ctx, wsID)
	if err != nil {
		return nil, xerrors.Errorf("get latest build: %w", err)
	}
	params, err := db.GetWorkspaceBuildParameters(ctx, build.ID)
	if err != nil {
		return nil, xerrors.Errorf("get build parameters: %w", err)
	}
	out := make(map[string]string, len(params))
	for _, p := range params {
		out[p.Name] = p.Value
	}
	return out, nil
}

// resourceMetadata returns the latest build's resource metadata as key->value,
// flattened across every resource in the build (coder_metadata may attach to
// any resource). The caller supplies the authorization context.
func resourceMetadata(ctx context.Context, db database.Store, wsID uuid.UUID) (map[string]string, error) {
	build, err := db.GetLatestWorkspaceBuildByWorkspaceID(ctx, wsID)
	if err != nil {
		return nil, xerrors.Errorf("get latest build: %w", err)
	}
	resources, err := db.GetWorkspaceResourcesByJobID(ctx, build.JobID)
	if err != nil {
		return nil, xerrors.Errorf("get build resources: %w", err)
	}
	ids := make([]uuid.UUID, 0, len(resources))
	for _, res := range resources {
		ids = append(ids, res.ID)
	}
	metadata, err := db.GetWorkspaceResourceMetadataByResourceIDs(ctx, ids)
	if err != nil {
		return nil, xerrors.Errorf("get resource metadata: %w", err)
	}
	out := make(map[string]string, len(metadata))
	for _, md := range metadata {
		if md.Value.Valid {
			out[md.Key] = md.Value.String
		}
	}
	return out, nil
}
