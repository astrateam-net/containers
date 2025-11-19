# Penpot MCP Container

A containerized deployment of the [Penpot MCP Server](https://github.com/penpot/penpot-mcp) that enables LLMs to interact directly with Penpot design projects using the Model Context Protocol (MCP).

## 📦 Container Image

**Container Registry:** `ghcr.io/astrateam-net/penpot-mcp:0.0.1`

```bash
docker pull ghcr.io/astrateam-net/penpot-mcp:0.0.1
```

**Source Code:** [View the build configuration and Dockerfile](https://github.com/astrateam-net/containers/tree/main/apps/penpot-mcp)

## 🚀 Features

✅ **HTTPS-ready** - Works with all modern browsers via secure reverse proxy  
✅ **No local Node.js required** - Everything runs in the container  
✅ **Production-ready** - Multi-platform builds (amd64 + arm64)  
✅ **Easy deployment** - Works with Docker Compose, Kubernetes, or any container orchestrator  
✅ **Automatic WebSocket patching** - Plugin automatically connects via HTTPS

## 📋 Quick Start

### Using Docker Compose with Traefik

```yaml
services:
  penpot-mcp:
    image: ghcr.io/astrateam-net/penpot-mcp:0.0.1
    networks:
      - trf_proxy
      - penpot_internal
    environment:
      - MCP_PORT=4401
      - PLUGIN_PORT=4400
      - ALLOWED_HOSTS=penpot-mcp.${DOMAIN}
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=trf_proxy"
        
        # Plugin router (port 4400) - lowest priority
        - "traefik.http.routers.penpot-mcp-plugin.entrypoints=websecure"
        - "traefik.http.routers.penpot-mcp-plugin.rule=Host(`penpot-mcp.${DOMAIN}`)"
        - "traefik.http.routers.penpot-mcp-plugin.service=penpot-mcp-plugin-svc"
        - "traefik.http.routers.penpot-mcp-plugin.tls=true"
        - "traefik.http.routers.penpot-mcp-plugin.priority=1"
        - "traefik.http.services.penpot-mcp-plugin-svc.loadbalancer.server.port=4400"
        
        # MCP router for /mcp and /sse (port 4401)
        - "traefik.http.routers.penpot-mcp-mcp.entrypoints=websecure"
        - "traefik.http.routers.penpot-mcp-mcp.rule=Host(`penpot-mcp.${DOMAIN}`) && (PathPrefix(`/mcp`) || PathPrefix(`/sse`))"
        - "traefik.http.routers.penpot-mcp-mcp.service=penpot-mcp-mcp-svc"
        - "traefik.http.routers.penpot-mcp-mcp.tls=true"
        - "traefik.http.routers.penpot-mcp-mcp.priority=10"
        - "traefik.http.services.penpot-mcp-mcp-svc.loadbalancer.server.port=4401"
        
        # WebSocket router (port 4402) - highest priority
        - "traefik.http.routers.penpot-mcp-ws.entrypoints=websecure"
        - "traefik.http.routers.penpot-mcp-ws.rule=Host(`penpot-mcp.${DOMAIN}`) && PathPrefix(`/ws`)"
        - "traefik.http.routers.penpot-mcp-ws.service=penpot-mcp-ws-svc"
        - "traefik.http.routers.penpot-mcp-ws.tls=true"
        - "traefik.http.routers.penpot-mcp-ws.priority=15"
        - "traefik.http.services.penpot-mcp-ws-svc.loadbalancer.server.port=4402"
```

### Using Docker Run

```bash
docker run -d \
  --name penpot-mcp \
  -p 4400:4400 \
  -p 4401:4401 \
  -p 4402:4402 \
  -e MCP_PORT=4401 \
  -e PLUGIN_PORT=4400 \
  ghcr.io/astrateam-net/penpot-mcp:0.0.1
```

## 🔧 Configuration

### Environment Variables

- `MCP_PORT` - Port for MCP server (default: `4401`)
- `PLUGIN_PORT` - Port for plugin server (default: `4400`)
- `ALLOWED_HOSTS` - Comma-separated list of allowed hosts for vite preview (default: all hosts)

**Note:** The plugin's WebSocket URL is automatically patched at container startup to use `wss://${window.location.host}/ws`, enabling secure connections through your reverse proxy.

### Endpoints

Once deployed behind Traefik with HTTPS:

- **MCP Server (Modern HTTP)**: `https://penpot-mcp.yourdomain.com/mcp`
- **MCP Server (Legacy SSE)**: `https://penpot-mcp.yourdomain.com/sse`
- **Plugin Manifest**: `https://penpot-mcp.yourdomain.com/manifest.json`
- **WebSocket**: `wss://penpot-mcp.yourdomain.com/ws`

## 📖 Usage

### 1. Load the Plugin in Penpot

1. Open Penpot in your browser
2. Navigate to a design file
3. Open the Plugins menu
4. Load the plugin using your HTTPS URL: `https://penpot-mcp.yourdomain.com/manifest.json`
5. Open the plugin UI and click "Connect to MCP server"

### 2. Connect an MCP Client

#### For HTTP-capable clients (Claude Code, etc.):

```bash
claude mcp add penpot -t http https://penpot-mcp.yourdomain.com/mcp
```

#### For stdio-only clients (Claude Desktop):

```json
{
    "mcpServers": {
        "penpot": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://penpot-mcp.yourdomain.com/sse"]
        }
    }
}
```

## 🏗️ Architecture

The container runs three services:

1. **MCP Server** (port 4401) - Provides MCP tools to LLMs
   - `/mcp` - Modern Streamable HTTP endpoint
   - `/sse` - Legacy SSE endpoint

2. **WebSocket Server** (port 4402) - Handles plugin connections
   - Routes through `/ws` path when behind reverse proxy

3. **Plugin Server** (port 4400) - Serves the Penpot plugin
   - `/manifest.json` - Plugin manifest
   - Plugin UI and assets

All services run in the same container and are routed via Traefik based on path prefixes.

## 🔄 Updating

The container builds from the upstream repository. To update:

1. Update the `GIT_REF` in `docker-bake.hcl` to point to a specific commit or branch
2. Rebuild the container
3. Deploy the new version

## 🐛 Troubleshooting

- **Check Traefik routing** - Verify all ports (4400, 4401, 4402) are properly routed
- **Check container logs** - `docker logs penpot-mcp` to see service status
- **Verify HTTPS** - Ensure the plugin URL uses HTTPS, not HTTP
- **Browser console** - Check for WebSocket connection errors

## 🔗 Links

- **Container Image**: `ghcr.io/astrateam-net/penpot-mcp:0.0.1`
- **Source Code**: [GitHub Repository](https://github.com/astrateam-net/containers/tree/main/apps/penpot-mcp)
- **Upstream Project**: [penpot/penpot-mcp](https://github.com/penpot/penpot-mcp)

## 📄 License

This container follows the same license as the upstream project (MPL-2.0).
