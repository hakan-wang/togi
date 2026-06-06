/**
 * MonsterMascot — a line-art terminal creature for the waitlist.
 *
 * Deliberately non-conventional / "coded" look to match the editorial-terminal
 * aesthetic (Instrument Serif + JetBrains Mono, monochrome on cream, one orange
 * accent). Hand-drawn SVG strokes — no emojis. It floats, blinks, and chomps
 * while little code tokens (</> { } ;) fly in for it to eat. Honours
 * prefers-reduced-motion (animations disabled in CSS).
 */

type MonsterMascotProps = {
  /** Rendered width in pixels. Height scales to keep the aspect ratio. */
  size?: number;
  className?: string;
};

export function MonsterMascot({ size = 200, className }: MonsterMascotProps) {
  const stroke = "var(--foreground)";
  return (
    <svg
      viewBox="0 0 240 200"
      width={size}
      height={(size * 200) / 240}
      className={className}
      role="img"
      aria-label="A line-art terminal creature munching code"
      fill="none"
      stroke={stroke}
      strokeWidth="3"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <g className="monster-float">
        {/* faint ground shadow */}
        <ellipse cx="120" cy="156" rx="44" ry="5" fill="var(--foreground)" stroke="none" opacity="0.07" />

        {/* antennae / feelers */}
        <path d="M96 60 L86 41" />
        <circle cx="85" cy="38" r="3.5" fill="var(--foreground)" stroke="none" />
        <path d="M144 60 L154 41" />
        <circle cx="155" cy="38" r="3.5" fill="var(--foreground)" stroke="none" />

        {/* head panel */}
        <rect x="74" y="58" width="92" height="86" rx="13" fill="var(--card)" />
        {/* corner bolts */}
        <circle cx="84" cy="68" r="1.7" fill="var(--foreground)" stroke="none" />
        <circle cx="156" cy="68" r="1.7" fill="var(--foreground)" stroke="none" />
        <circle cx="84" cy="134" r="1.7" fill="var(--foreground)" stroke="none" />
        <circle cx="156" cy="134" r="1.7" fill="var(--foreground)" stroke="none" />

        {/* eyes (blink as a group) */}
        <g className="monster-eyes">
          <circle cx="104" cy="92" r="5.5" fill="var(--foreground)" stroke="none" />
          <circle cx="136" cy="92" r="5.5" fill="var(--foreground)" stroke="none" />
        </g>

        {/* little triangle nose */}
        <path d="M114 103 L126 103 L120 111 Z" strokeWidth="2.5" />

        {/* mouth — outlined slot that chomps open/closed */}
        <g className="monster-mouth">
          <rect
            x="98"
            y="120"
            width="44"
            height="16"
            rx="7"
            fill="var(--card)"
            vectorEffect="non-scaling-stroke"
          />
        </g>

        {/* code tokens flying into the mouth — anchored at the eat point */}
        <g transform="translate(120,128)">
          <text
            className="morsel morsel-1"
            textAnchor="middle"
            dominantBaseline="central"
            stroke="none"
            fill="var(--primary)"
            style={{ fontFamily: "var(--font-mono)", fontSize: "17px", fontWeight: 600 }}
          >
            {"</>"}
          </text>
        </g>
        <g transform="translate(120,128)">
          <text
            className="morsel morsel-2"
            textAnchor="middle"
            dominantBaseline="central"
            stroke="none"
            fill="var(--foreground)"
            style={{ fontFamily: "var(--font-mono)", fontSize: "17px", fontWeight: 600 }}
          >
            {"{ }"}
          </text>
        </g>
        <g transform="translate(120,128)">
          <text
            className="morsel morsel-3"
            textAnchor="middle"
            dominantBaseline="central"
            stroke="none"
            fill="var(--foreground)"
            style={{ fontFamily: "var(--font-mono)", fontSize: "18px", fontWeight: 600 }}
          >
            {";"}
          </text>
        </g>
      </g>
    </svg>
  );
}

export default MonsterMascot;
