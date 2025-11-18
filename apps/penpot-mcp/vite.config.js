// Minimal vite config for preview server
// Allows all hosts and enables CORS for reverse proxy usage
export default {
  preview: {
    host: '0.0.0.0',
    port: 4400,
    cors: true,
    allowedHosts: 'all' // Allow all hosts when behind reverse proxy
  }
};

