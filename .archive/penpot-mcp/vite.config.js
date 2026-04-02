// Minimal vite config for preview server
// Allows all hosts and enables CORS for reverse proxy usage
// ALLOWED_HOSTS env var: comma-separated list of hosts, or leave empty to allow all
const allowedHosts = process.env.ALLOWED_HOSTS
  ? process.env.ALLOWED_HOSTS.split(',').map(h => h.trim())
  : 'all'; // Allow all hosts by default

export default {
  server: {
    host: '0.0.0.0',
    port: 4400,
    cors: true,
    strictPort: false,
    allowedHosts: allowedHosts
  },
  preview: {
    host: '0.0.0.0',
    port: 4400,
    cors: true,
    strictPort: false,
    allowedHosts: allowedHosts
  }
};

