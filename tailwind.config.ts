import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        ink: "#172026",
        paper: "#f7f4ef",
        line: "#d8d2c8",
        moss: "#4f6f52",
        clay: "#b45f43",
        steel: "#476579"
      }
    }
  },
  plugins: []
};

export default config;
