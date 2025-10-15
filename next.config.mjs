import withBundleAnalyzer from '@next/bundle-analyzer';

// Enable bundle analyzer if ANALYZE env variable is set
const bundleAnalyzer = withBundleAnalyzer({
  enabled: process.env.ANALYZE === 'true',
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Next.js will use its optimized Babel setup

  productionBrowserSourceMaps: true,
  // Enable React strict mode for better error handling and performance
  reactStrictMode: true,

  // Enable SWC minification for faster builds
  // !working swcMinify: true,

  // Configure custom server (used in socket.io/server.ts)
  // No additional server settings needed, as custom server is handled externally
  experimental: {
    // Enable if you use experimental features (e.g., app router optimizations)
    // serverComponentsExternalPackages: ['socket.io'],
  },

  // Webpack configuration (optional)
  webpack: (config, { isServer }) => {
    // Ensure Webpack works with Socket.IO and custom server
    if (!isServer) {
      // Prevent Webpack from bundling Node.js-specific modules in client-side code
      config.resolve.fallback = {
        ...config.resolve.fallback,
        net: false,
        tls: false,
        fs: false,
        http: false,
        stream: false, // Add this if required        
      };

      config.externals.push({ ws: 'ws', 'utf-8-validate': 'utf-8-validate' });
    }
    return config;
  },
};

export default bundleAnalyzer(nextConfig);
