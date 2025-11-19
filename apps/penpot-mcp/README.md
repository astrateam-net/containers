# Penpot MCP Container

A containerized deployment of the [Penpot MCP Server](https://github.com/penpot/penpot-mcp) that enables LLMs to interact directly with Penpot design projects using the Model Context Protocol (MCP).

## 📦 Container Image

**Container Registry:** `ghcr.io/astrateam-net/penpot-mcp:0.0.1`

```bash
docker pull ghcr.io/astrateam-net/penpot-mcp:0.0.1
```

**Source Code:** [View the build configuration and Dockerfile](https://github.com/astrateam-net/containers/tree/main/apps/penpot-mcp)

## 🚀 Why Use This Container?

### Solves the HTTP/Private Network Access Problem

The upstream Penpot MCP project has a known limitation with modern Chromium browsers (v142+):

> **Browser Compatibility Issue**: Starting with Chromium version 142, Google has hardened the private network access (PNA) enforcement layer. This means that newer Chromium-based browsers (Chrome, Edge, Vivaldi, Opera, Brave, etc.) will not allow Penpot to connect to a local plugin server by default.

**The workaround suggested in the upstream README:**
- Use Firefox, or
- Use an older version of a Chromium-based browser (up to Chromium version 141)

**Our solution:** Deploy this container behind a reverse proxy (Traefik, nginx, Caddy, etc.) with HTTPS, and the browser will allow the connection! 🎉

When accessed via HTTPS through a reverse proxy, the browser treats it as a secure connection, bypassing the private network access restrictions entirely.

### Additional Benefits

✅ **No local Node.js installation required** - Everything runs in the container  
✅ **Consistent environment** - Same setup across all machines  
✅ **Easy deployment** - Works with Docker Compose, Kubernetes, or any container orchestrator  
✅ **Production-ready** - Multi-platform builds (amd64 + arm64)  
✅ **Automatic updates** - Rebuild when upstream updates  
✅ **Isolated** - No conflicts with other Node.js projects on your system  

## 📋 Quick Start

### Using Docker Compose with Traefik (Separate Domains)

```yaml
services:
  penpot-mcp:
    image: ghcr.io/astrateam-net/penpot-mcp:0.0.1
    container_name: penpot-mcp
    labels:
      - "traefik.enable=true"
      - "traefik.swarm.network=trf_proxy"
      
      # MCP router for /mcp and /sse (port 4401) - separate domain
      - "traefik.http.routers.penpot-mcp-mcp.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-mcp.rule=Host(`penpot-mcp.yourdomain.com`)"
      - "traefik.http.routers.penpot-mcp-mcp.service=penpot-mcp-mcp-svc"
      - "traefik.http.routers.penpot-mcp-mcp.tls=true"
      - "traefik.http.services.penpot-mcp-mcp-svc.loadbalancer.server.port=4401"
      
      # WebSocket router for plugin connection (port 4402) - same domain as MCP
      - "traefik.http.routers.penpot-mcp-ws.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-ws.rule=Host(`penpot-mcp.yourdomain.com`) && PathPrefix(`/ws`)"
      - "traefik.http.routers.penpot-mcp-ws.service=penpot-mcp-ws-svc"
      - "traefik.http.routers.penpot-mcp-ws.tls=true"
      - "traefik.http.services.penpot-mcp-ws-svc.loadbalancer.server.port=4402"
      
      # Plugin router (port 4400) - separate domain
      - "traefik.http.routers.penpot-mcp-plugin.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-plugin.rule=Host(`penpot-plugin.yourdomain.com`)"
      - "traefik.http.routers.penpot-mcp-plugin.service=penpot-mcp-plugin-svc"
      - "traefik.http.routers.penpot-mcp-plugin.tls=true"
      - "traefik.http.services.penpot-mcp-plugin-svc.loadbalancer.server.port=4400"
    networks:
      - trf_proxy
      - penpot_internal
    environment:
      - MCP_PORT=4401
      - PLUGIN_PORT=4400
      - ALLOWED_HOSTS=penpot-plugin.yourdomain.com,penpot-mcp.yourdomain.com
```

**⚠️ Important:** The plugin code is hardcoded to connect to `ws://localhost:4402/`. The container automatically patches this at startup to use `wss://${window.location.host}` (same origin). **Use the single domain approach below for best compatibility.**

### Using Docker Compose with Traefik (Single Domain) ⭐ Recommended

The container automatically patches the plugin to use `wss://${window.location.host}` instead of `ws://localhost:4402/`. Use a single domain so the plugin and WebSocket are on the same origin:

```yaml
services:
  penpot-mcp:
    image: ghcr.io/astrateam-net/penpot-mcp:0.0.1
    container_name: penpot-mcp
    labels:
      - "traefik.enable=true"
      
      # Plugin router (port 4400) - main domain
      - "traefik.http.routers.penpot-mcp-plugin.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-plugin.rule=Host(`penpot-api.yourdomain.com`)"
      - "traefik.http.routers.penpot-mcp-plugin.service=penpot-mcp-plugin-svc"
      - "traefik.http.routers.penpot-mcp-plugin.tls=true"
      - "traefik.http.services.penpot-mcp-plugin-svc.loadbalancer.server.port=4400"
      
      # MCP router for /mcp and /sse (port 4401) - higher priority
      - "traefik.http.routers.penpot-mcp-mcp.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-mcp.rule=Host(`penpot-api.yourdomain.com`) && (PathPrefix(`/mcp`) || PathPrefix(`/sse`))"
      - "traefik.http.routers.penpot-mcp-mcp.service=penpot-mcp-mcp-svc"
      - "traefik.http.routers.penpot-mcp-mcp.tls=true"
      - "traefik.http.routers.penpot-mcp-mcp.priority=10"
      - "traefik.http.services.penpot-mcp-mcp-svc.loadbalancer.server.port=4401"
      
      # WebSocket router (port 4402) - HTTP router with WebSocket upgrade
      # The plugin is patched to use wss://same-domain/ws, so we route /ws to port 4402
      # Note: WebSocket server accepts connections on any path, so /ws works fine
      - "traefik.http.routers.penpot-mcp-ws.entrypoints=websecure"
      - "traefik.http.routers.penpot-mcp-ws.rule=Host(`penpot-api.yourdomain.com`) && PathPrefix(`/ws`)"
      - "traefik.http.routers.penpot-mcp-ws.service=penpot-mcp-ws-svc"
      - "traefik.http.routers.penpot-mcp-ws.tls=true"
      - "traefik.http.routers.penpot-mcp-ws.priority=15"
      - "traefik.http.services.penpot-mcp-ws-svc.loadbalancer.server.port=4402"
      # Optional: Strip /ws path prefix when forwarding (if WebSocket server requires root path)
      # - "traefik.http.middlewares.penpot-mcp-ws-stripprefix.stripprefix.prefixes=/ws"
      # - "traefik.http.routers.penpot-mcp-ws.middlewares=penpot-mcp-ws-stripprefix"
    networks:
      - traefik
    environment:
      - MCP_PORT=4401
      - PLUGIN_PORT=4400
      - ALLOWED_HOSTS=penpot-api.yourdomain.com
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
  - Controls the `/mcp` and `/sse` endpoints
- `PLUGIN_PORT` - Port for plugin server (default: `4400`)
  - Controls where the plugin manifest is served
- `ALLOWED_HOSTS` - Comma-separated list of allowed hosts for vite preview (default: all hosts)
  - Example: `penpot-mcp.astrateam.net,penpot-api.example.com`
  - If not set, all hosts are allowed (useful when behind reverse proxy)

**Note:** The plugin's WebSocket URL (`ws://localhost:4402/`) is automatically patched at container startup to use `wss://${window.location.host}/ws` (same origin with `/ws` path). This allows the plugin to connect via HTTPS through Traefik, which routes `/ws` to the WebSocket server on port 4402.

### Endpoints

Once deployed behind Traefik with HTTPS:

- **MCP Server (Modern HTTP)**: `https://penpot-api.yourdomain.com/mcp`
- **MCP Server (Legacy SSE)**: `https://penpot-api.yourdomain.com/sse`
- **Plugin Manifest**: `https://penpot-api.yourdomain.com/manifest.json`

## 📖 Usage

### 1. Deploy the Container

Deploy the container behind your reverse proxy (Traefik, nginx, etc.) with HTTPS enabled.

### 2. Load the Plugin in Penpot

1. Open Penpot in your browser
2. Navigate to a design file
3. Open the Plugins menu
4. Load the plugin using your HTTPS URL: `https://penpot-api.yourdomain.com/manifest.json`
5. Open the plugin UI
6. Click "Connect to MCP server"

The connection will work because it's over HTTPS! ✅

### 3. Connect an MCP Client

#### For HTTP-capable clients (Claude Code, etc.):

```bash
claude mcp add penpot -t http https://penpot-api.yourdomain.com/mcp
```

#### For stdio-only clients (Claude Desktop):

Use `mcp-remote` with your HTTPS endpoint:

```json
{
    "mcpServers": {
        "penpot": {
            "command": "npx",
            "args": ["-y", "mcp-remote", "https://penpot-api.yourdomain.com/sse"]
        }
    }
}
```

Note: With HTTPS, you don't need the `--allow-http` flag!

## 🏗️ Architecture

The container runs two services:

1. **MCP Server** (port 4401) - Provides MCP tools to LLMs
   - `/mcp` - Modern Streamable HTTP endpoint
   - `/sse` - Legacy SSE endpoint
   - WebSocket server (port 4402) - For plugin connections

2. **Plugin Server** (port 4400) - Serves the Penpot plugin
   - `/manifest.json` - Plugin manifest
   - Plugin UI and assets

Both services run in the same container and can be routed via Traefik based on path prefixes or separate domains.

## 🔄 Updating

The container builds from the upstream repository. To update:

1. Update the `GIT_REF` in `docker-bake.hcl` to point to a specific commit or branch
2. Rebuild the container
3. Deploy the new version

## 🐛 Troubleshooting

### Connection Issues

- **Ensure HTTPS is enabled** - The browser restriction only applies to HTTP
- **Check Traefik routing** - Verify both ports (4400, 4401) are properly routed
- **Check container logs** - `docker logs penpot-mcp` to see both services

### Plugin Not Loading

- Verify the plugin server is accessible: `curl https://penpot-api.yourdomain.com/manifest.json`
- Check browser console for CORS or network errors
- Ensure the plugin URL uses HTTPS, not HTTP

## 📝 Comparison: Container vs Local Installation

| Feature | Container | Local npm install |
|---------|-----------|-------------------|
| **Browser Compatibility** | ✅ Works with all browsers via HTTPS | ❌ Requires Firefox or old Chromium |
| **Setup Complexity** | ✅ One command | ❌ Requires Node.js, npm, build steps |
| **Isolation** | ✅ Isolated environment | ❌ Can conflict with other projects |
| **Portability** | ✅ Same everywhere | ❌ Different per machine |
| **Production Ready** | ✅ Yes | ⚠️ Requires process management |
| **Updates** | ✅ Rebuild container | ❌ Manual npm update + rebuild |

## 🔗 Links

- **Container Image**: `ghcr.io/astrateam-net/penpot-mcp:0.0.1`
- **Source Code**: [GitHub Repository](https://github.com/astrateam-net/containers/tree/main/apps/penpot-mcp)
- **Upstream Project**: [penpot/penpot-mcp](https://github.com/penpot/penpot-mcp)

## 🤝 Contributing

This container is built from the upstream [penpot/penpot-mcp](https://github.com/penpot/penpot-mcp) repository. 

To contribute to the Penpot MCP project itself, please see the [upstream repository](https://github.com/penpot/penpot-mcp).

To contribute to this container build, see the [source repository](https://github.com/astrateam-net/containers).

## 📄 License

This container follows the same license as the upstream project (MPL-2.0).

## 🙏 Credits

- [Penpot MCP](https://github.com/penpot/penpot-mcp) - The upstream project
- [Penpot](https://penpot.app/) - The design tool

---

**Enjoy seamless Penpot MCP integration with any browser!** 🎨✨

