/** @type {import('tailwindcss').Config} */
const config = {
  content: ['./src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {

      // Colors
      colors: {
        // Base colors
        // Base colors
        red: {
          600: '#dc2626',
        },
        green: {
          200: '#bbf7d0', // Light green (used for authenticated badge)
          800: '#166534', // Dark green (text color for authenticated badge)
        },
        gray: {
          50: '#f9fafb',   // Very light gray (hover background in light mode)
          200: '#e5e7eb',  // Light gray (offline badge in light mode)
          600: '#4b5563',  // Medium gray (text color for offline badge)
          800: '#1f2937',  // Dark gray (background in dark mode)
          900: '#111827',  // Very dark gray (text in dark mode)
        },
        yellow: {
          200: '#fef3c7', // Light yellow (optional connected badge)
          800: '#92400e', // Dark yellow (text color for optional connected badge)
        },
        pink: {
          500: '#ec4899', // Default Tailwind pink-500
        },

        black: '#000000',
        white: '#ffffff',
        transparent: 'transparent',

        // ✅ Semantic state colors
        'user-authenticated': '#e6ffe6',     // Light green
        'user-offline': '#f9f9f9',           // Very light gray
        'user-connected': '#fff7e6',         // Light orange (optional)
        'user-disconnected': '#f9f9f9',      // Same as offline or use #f3f3f3
      },

      // Spacing
      spacing: {
        1: '0.25rem',
        2: '0.5rem',
        3: '0.75rem',
        4: '1rem',
        5: '1.25rem',
        6: '1.5rem',
        7: '1.75rem',
        8: '2rem',
        9: '2.25rem',
        10: '2.5rem',
        11: '2.75rem',
        12: '3rem',
        14: '3.5rem',
        16: '4rem',
        20: '5rem',
        24: '6rem',
        28: '7rem',
        32: '8rem',
        36: '9rem',
        40: '10rem',
        44: '11rem',
        48: '12rem',
        52: '13rem',
        56: '14rem',
        60: '15rem',
        64: '16rem',
        72: '18rem',
        80: '20rem',
        96: '24rem',
      },

      // Border Radius
      borderRadius: {
        DEFAULT: '0.25rem',
        md: '0.375rem',
        lg: '0.5rem',
        xl: '0.75rem',
        '2xl': '1rem',
        '3xl': '1.5rem',
        full: '9999px',
      },

      // Max Width
      maxWidth: {
        xs: '20rem',
        sm: '24rem',
        md: '28rem',
        lg: '32rem',
        xl: '36rem',
        '2xl': '42rem',
        '3xl': '48rem',
        '4xl': '56rem',
        '5xl': '64rem',
        '6xl': '72rem',
        '7xl': '80rem',
        full: '100%',
        min: 'min-content',
        max: 'max-content',
        fit: 'fit-content',
        prose: '65ch',
      },

      // Height
      height: {
        auto: 'auto',
        px: '1px',
        1: '0.25rem',
        2: '0.5rem',
        3: '0.75rem',
        4: '1rem',
        5: '1.25rem',
        6: '1.5rem',
        7: '1.75rem',
        8: '2rem',
        9: '2.25rem',
        10: '2.5rem',
        11: '2.75rem',
        12: '3rem',
        14: '3.5rem',
        16: '4rem',
        20: '5rem',
        24: '6rem',
        28: '7rem',
        32: '8rem',
        36: '9rem',
        40: '10rem',
        44: '11rem',
        48: '12rem',
        52: '13rem',
        56: '14rem',
        60: '15rem',
        64: '16rem',
        72: '18rem',
        80: '20rem',
        96: '24rem',
        screen: '100vh',
      },
      // Add to your existing tailwind.config.js theme.extend object
      position: {
        absolute: 'absolute',
        relative: 'relative',
      },
      zIndex: {
        10: '10',
      },
      minHeight: {
        '400px': '400px',
      },
      margin: {
        8: '2rem', // mt-8
        4: '1rem', // mt-4
        1: '0.25rem', // mb-1
      },
      transitionProperty: {
        colors:
          'color, background-color, border-color, outline-color, text-decoration-color, fill, stroke',
      },
    },
  },
  plugins: [],
};

export default config;
