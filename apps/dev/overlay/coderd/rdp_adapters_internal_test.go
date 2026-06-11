package coderd

import (
	"context"
	"database/sql"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/require"

	"github.com/astrateam-net/dev-kit/jetbroker"
	"github.com/coder/coder/v2/coderd/database"
)

// fakeRDPStore implements only the handful of database.Store methods the RDP
// adapters call. The embedded nil interface satisfies the rest; any unexpected
// call panics, which is the behavior we want in a focused test.
type fakeRDPStore struct {
	database.Store

	ws        database.Workspace
	owner     database.User
	build     database.WorkspaceBuild
	params    []database.WorkspaceBuildParameter
	resources []database.WorkspaceResource
	agents    []database.WorkspaceAgent
	metadata  []database.WorkspaceResourceMetadatum
}

func (f *fakeRDPStore) GetWorkspaceAgentsByResourceIDs(_ context.Context, _ []uuid.UUID) ([]database.WorkspaceAgent, error) {
	return f.agents, nil
}

func (f *fakeRDPStore) GetWorkspaceByID(_ context.Context, id uuid.UUID) (database.Workspace, error) {
	require := f.ws.ID == id
	if !require {
		return database.Workspace{}, sql.ErrNoRows
	}
	return f.ws, nil
}

func (f *fakeRDPStore) GetUserByID(_ context.Context, id uuid.UUID) (database.User, error) {
	if f.owner.ID != id {
		return database.User{}, sql.ErrNoRows
	}
	return f.owner, nil
}

func (f *fakeRDPStore) GetLatestWorkspaceBuildByWorkspaceID(_ context.Context, wsID uuid.UUID) (database.WorkspaceBuild, error) {
	if f.build.WorkspaceID != wsID {
		return database.WorkspaceBuild{}, sql.ErrNoRows
	}
	return f.build, nil
}

func (f *fakeRDPStore) GetWorkspaceBuildParameters(_ context.Context, buildID uuid.UUID) ([]database.WorkspaceBuildParameter, error) {
	if f.build.ID != buildID {
		return nil, sql.ErrNoRows
	}
	return f.params, nil
}

func (f *fakeRDPStore) GetWorkspaceResourcesByJobID(_ context.Context, jobID uuid.UUID) ([]database.WorkspaceResource, error) {
	if f.build.JobID != jobID {
		return nil, sql.ErrNoRows
	}
	return f.resources, nil
}

func (f *fakeRDPStore) GetWorkspaceResourceMetadataByResourceIDs(_ context.Context, _ []uuid.UUID) ([]database.WorkspaceResourceMetadatum, error) {
	return f.metadata, nil
}

func meta(key, value string) database.WorkspaceResourceMetadatum {
	return database.WorkspaceResourceMetadatum{Key: key, Value: sql.NullString{String: value, Valid: true}}
}

func newFixture() *fakeRDPStore {
	wsID := uuid.New()
	ownerID := uuid.New()
	buildID := uuid.New()
	jobID := uuid.New()
	resID := uuid.New()
	return &fakeRDPStore{
		ws:    database.Workspace{ID: wsID, OwnerID: ownerID, Name: "myws", OwnerUsername: "ceo"},
		owner: database.User{ID: ownerID, Username: "ceo"},
		build: database.WorkspaceBuild{ID: buildID, WorkspaceID: wsID, JobID: jobID},
		params: []database.WorkspaceBuildParameter{
			{Name: "rdp_password", Value: "s3cr3t"},
		},
		resources: []database.WorkspaceResource{{ID: resID, JobID: jobID}},
		agents:    []database.WorkspaceAgent{{Name: "main", ResourceID: resID}},
		metadata: []database.WorkspaceResourceMetadatum{
			meta("coder.rdp.target", "win-host.example.com"),
			meta("coder.rdp.gateways", `[{"url":"https://gw01.example.com:7171","weight":100},{"url":"https://gw02.example.com:7171","weight":50}]`),
		},
	}
}

func TestRDPIdentity(t *testing.T) {
	t.Parallel()
	ctx := context.Background()

	t.Run("FallsBackToOwner", func(t *testing.T) {
		t.Parallel()
		f := newFixture()
		id, err := rdpIdentity{db: f, usernameParam: "rdp_username"}.Resolve(ctx, jetbroker.LaunchRequest{WorkspaceID: f.ws.ID.String()})
		require.NoError(t, err)
		require.Equal(t, "ceo", id.Username)
		require.Equal(t, f.owner.ID.String(), id.UserID)
	})

	t.Run("ParamWins", func(t *testing.T) {
		t.Parallel()
		f := newFixture()
		f.params = append(f.params, database.WorkspaceBuildParameter{Name: "rdp_username", Value: "svc_account"})
		id, err := rdpIdentity{db: f, usernameParam: "rdp_username"}.Resolve(ctx, jetbroker.LaunchRequest{WorkspaceID: f.ws.ID.String()})
		require.NoError(t, err)
		require.Equal(t, "svc_account", id.Username)
	})
}

func TestRDPTarget(t *testing.T) {
	t.Parallel()
	f := newFixture()
	host, err := rdpTarget{db: f, key: "coder.rdp.target"}.Resolve(context.Background(), f.ws.ID.String())
	require.NoError(t, err)
	require.Equal(t, "win-host.example.com", host)
}

// TestRDPGateways: no wildcard host + no app slug => the browser uses the gateway's own url
// (BrowserURL stays empty). This is the directly-reachable case (e.g. a single LAN gateway).
func TestRDPGateways(t *testing.T) {
	t.Parallel()
	f := newFixture()
	gws, err := rdpGateways{db: f, key: "coder.rdp.gateways"}.Resolve(context.Background(), f.ws.ID.String())
	require.NoError(t, err)
	require.Equal(t, []jetbroker.Gateway{
		{BaseURL: "https://gw01.example.com:7171", Weight: 100},
		{BaseURL: "https://gw02.example.com:7171", Weight: 50},
	}, gws)
}

// TestRDPGatewaysSubdomain: with a wildcard host + an app slug, the browser-facing URL becomes the
// gateway's Coder subdomain (slug--agent--workspace--owner.<wildcard>), while BaseURL (heartbeat/
// preflight) stays the internal gateway address.
func TestRDPGatewaysSubdomain(t *testing.T) {
	t.Parallel()
	f := newFixture()
	f.metadata = []database.WorkspaceResourceMetadatum{
		meta("coder.rdp.gateways", `[{"url":"https://gw01.example.com:7171","weight":100,"app":"rdp-gw01"}]`),
	}
	gws, err := rdpGateways{db: f, key: "coder.rdp.gateways", appHostname: "*.example.com"}.Resolve(context.Background(), f.ws.ID.String())
	require.NoError(t, err)
	require.Equal(t, []jetbroker.Gateway{
		{
			BaseURL:    "https://gw01.example.com:7171",
			Weight:     100,
			BrowserURL: "https://rdp-gw01--main--myws--ceo.example.com",
		},
	}, gws)
}

func TestRDPSecret(t *testing.T) {
	t.Parallel()
	f := newFixture()
	pw, err := rdpSecret{db: f}.Get(context.Background(), f.ws.ID.String(), "rdp_password")
	require.NoError(t, err)
	require.Equal(t, "s3cr3t", pw)

	_, err = rdpSecret{db: f}.Get(context.Background(), f.ws.ID.String(), "missing")
	require.Error(t, err)
}

func TestRDPTargetMissing(t *testing.T) {
	t.Parallel()
	f := newFixture()
	f.metadata = nil
	_, err := rdpTarget{db: f, key: "coder.rdp.target"}.Resolve(context.Background(), f.ws.ID.String())
	require.Error(t, err)
}
