/** @type {import('tailwindcss').Config} */
export default {
    darkMode: 'class',
    content: [
        "./index.html",
        "./src/**/*.{js,ts,jsx,tsx}",
    ],
    theme: {
        extend: {
            colors: {
                // === Stitch Color Palette (Indigo Vault) ===
                "dn-bg":       "#131318",   // Global canvas
                "dn-surface":  "#1f1f25",   // Section backgrounds
                "dn-surface-low": "#1b1b20", // Recessed sections
                "dn-surface-high": "#2a292f", // Hover states
                "dn-surface-highest": "#35343a", // Elevated cards
                "dn-surface-lowest": "#0e0e13", // Deepest sections/inputs
                "dn-primary":  "#c0c1ff",   // Highlight/Selection
                "dn-accent":   "#6366F1",   // Indigo Brand
                "dn-accent-container": "#8083ff", // CTA Background
                "dn-text":     "#e4e1e9",   // Primary text
                "dn-subtext":  "#c7c4d7",   // Secondary metadata
                "dn-muted":    "#908fa0",   // Outlines/disabled
                "dn-border":   "#464554",   // Structural lines (Ghost Border)
                "dn-success":  "#30D158",   // Green tunnel status
                "dn-error":    "#ffb4ab",   // Error state
            },
            fontFamily: {
                "sans": ["Inter", "system-ui", "sans-serif"],
            },
            boxShadow: {
                "dn-glow":    "0 0 80px -20px rgba(128, 131, 255, 0.15)",
                "dn-card":    "0 12px 40px rgba(0, 0, 0, 0.4)",
            },
            borderRadius: {
                "md":  "0.75rem",
                "lg":  "1rem",
                "xl":  "1.5rem",
                "2xl": "2rem",
                "3xl": "3.5rem",
            }
        },
    },
    plugins: [],
}
