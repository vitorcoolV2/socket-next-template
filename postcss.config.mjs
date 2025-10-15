// postcss.config.mjs
export default {
  plugins: [
    '@tailwindcss/postcss', // Tailwind CSS PostCSS plugin
    'autoprefixer', // Automatically add vendor prefixes
    [
      'postcss-preset-env', // Use modern CSS features
      {
        stage: 0,
      },
    ],
  ],
};
