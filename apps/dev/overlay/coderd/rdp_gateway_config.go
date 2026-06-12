package coderd

import "os"

// rdp_gateway_config.go feeds the workspace-app server the browser-RDP gateway
// proxy settings (see workspaceapps.ServerOptions.RDPGatewayAppPrefix). Kept as
// version-robust overlay so the coderd.go wiring patch stays a two-line diff.

// rdpGatewayAppPrefix is the slug prefix that marks a subdomain coder_app as a
// browser-RDP gateway app. The workspace-app proxy forwards such apps directly
// to the chosen swarm gateway instead of through the workspace agent. Empty (env
// unset) leaves every app on the stock agent-proxied path, so the feature is off
// unless explicitly configured (e.g. CODER_RDP_GATEWAY_APP_PREFIX=rdp-gw).
func rdpGatewayAppPrefix() string {
	return os.Getenv("CODER_RDP_GATEWAY_APP_PREFIX")
}

// rdpGatewayTLSInsecure mirrors CODER_RDP_TLS_INSECURE for the gateway proxy leg
// (the same opt-in the launch authority uses for a private-CA test stand).
func rdpGatewayTLSInsecure() bool {
	return truthy(os.Getenv("CODER_RDP_TLS_INSECURE"))
}
