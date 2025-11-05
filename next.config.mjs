import withBundleAnalyzer from '@next/bundle-analyzer';

// Enable bundle analyzer if ANALYZE env variable is set
const bundleAnalyzer = withBundleAnalyzer({
  enabled: process.env.ANALYZE === 'true',
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  trailingSlash: true,
  images: { unoptimized: true }, // Required for static export

  reactStrictMode: true,
  productionBrowserSourceMaps: true,

  webpack: (config, { isServer }) => {
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        net: false,
        tls: false,
        fs: false,
        http: false,
        stream: false,
      };
      config.externals.push({ ws: 'ws', 'utf-8-validate': 'utf-8-validate' });
    }
    return config;
  },
};

export default bundleAnalyzer(nextConfig);