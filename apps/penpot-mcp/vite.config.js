// Minimal vite config for preview server
// Allows all hosts and enables CORS for reverse proxy usage
// ALLOWED_HOSTS env var: comma-separated list of hosts, or leave empty to allow all
const allowedHosts = process.env.ALLOWED_HOSTS
  ? process.env.ALLOWED_HOSTS.split(',').map(h => h.trim())
  : [/.*/]; // Allow all hosts by default (regex matches everything)

export default {
  preview: {
    host: '0.0.0.0',
    port: 4400,
    cors: true,
    strictPort: false,
    allowedHosts: allowedHosts
  }
};

