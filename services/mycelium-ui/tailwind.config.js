/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        mycelium: {
          50: '#f5f7fa',
          100: '#ebeef5',
          200: '#dce2ef',
          300: '#c2cde4',
          400: '#9fb1d5',
          500: '#7a91c4',
          600: '#5e75b1',
          700: '#4e5f9a',
          800: '#43507f',
          900: '#3a446a',
          950: '#252b41',
        },
      },
    },
  },
  plugins: [],
}
