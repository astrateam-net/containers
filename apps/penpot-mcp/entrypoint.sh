#!/bin/sh

# Default ports (can be overridden via environment variables)
MCP_PORT=${MCP_PORT:-4401}
PLUGIN_PORT=${PLUGIN_PORT:-4400}

# Function to handle shutdown
cleanup() {
    echo "Shutting down..."
    [ -n "$MCP_PID" ] && kill -TERM "$MCP_PID" 2>/dev/null || true
    [ -n "$PLUGIN_PID" ] && kill -TERM "$PLUGIN_PID" 2>/dev/null || true
    wait "$MCP_PID" 2>/dev/null || true
    wait "$PLUGIN_PID" 2>/dev/null || true
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT

# Start MCP server in background with unbuffered output
cd /app/mcp-server
NODE_ENV=production node --no-warnings dist/index.js --port "$MCP_PORT" 2>&1 | sed 's/^/[MCP] /' &
MCP_PID=$!

# Start plugin preview server in background with unbuffered output  
cd /app/penpot-plugin
NODE_ENV=production vite preview --host 0.0.0.0 --port "$PLUGIN_PORT" 2>&1 | sed 's/^/[PLUGIN] /' &
PLUGIN_PID=$!

# Wait for both processes (exit if either dies)
wait $MCP_PID $PLUGIN_PID

