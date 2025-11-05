// postcss.config.mjs
/* eslint-disable import/no-anonymous-default-export */
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
