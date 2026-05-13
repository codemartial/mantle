// Map rendering variants — purely decorative, no real tile service.

function MapView({ photo, style }) {
  // style: "topo" | "minimal" | "satellite" | "pin"
  const s = style || "topo";

  if (s === "minimal") {
    return (
      <svg viewBox="0 0 300 110" preserveAspectRatio="xMidYMid slice">
        <rect width="300" height="110" fill="#222629" />
        {/* coast */}
        <path d="M 0 70 Q 60 50 120 65 T 220 70 T 300 60 L 300 110 L 0 110 Z" fill="#1a1e21" />
        {/* roads */}
        <path d="M -10 84 Q 80 72 160 86 T 320 80" stroke="#3a3f44" strokeWidth="3" fill="none" />
        <path d="M 40 110 Q 70 80 110 70 T 200 60" stroke="#3a3f44" strokeWidth="2" fill="none" />
        <path d="M 220 110 L 220 60" stroke="#3a3f44" strokeWidth="1.5" fill="none" />
        {/* grid */}
        {[...Array(12)].map((_, i) => (
          <line key={i} x1={i * 25} y1="0" x2={i * 25} y2="110" stroke="#2a2e31" strokeWidth="0.5" />
        ))}
      </svg>
    );
  }

  if (s === "satellite") {
    return (
      <svg viewBox="0 0 300 110" preserveAspectRatio="xMidYMid slice">
        <defs>
          <radialGradient id="vig">
            <stop offset="0" stopColor="#1c2026" stopOpacity="0" />
            <stop offset="1" stopColor="#000" stopOpacity="0.55" />
          </radialGradient>
        </defs>
        <rect width="300" height="110" fill="#0a141f" />
        {/* land mass */}
        <path d="M 0 60 Q 50 30 110 50 Q 160 28 220 56 Q 270 38 300 50 L 300 110 L 0 110 Z" fill="#1c2a1e" />
        <path d="M 0 78 Q 60 60 130 72 Q 200 88 280 74 L 280 110 L 0 110 Z" fill="#23351f" />
        {/* clouds */}
        <ellipse cx="80"  cy="22" rx="40" ry="6" fill="#cad4dc" opacity="0.18" />
        <ellipse cx="220" cy="14" rx="60" ry="5" fill="#cad4dc" opacity="0.14" />
        <ellipse cx="160" cy="40" rx="30" ry="4" fill="#cad4dc" opacity="0.12" />
        {/* snow patches */}
        <ellipse cx="180" cy="58" rx="14" ry="3" fill="#aebac4" opacity="0.6" />
        <ellipse cx="40"  cy="68" rx="10" ry="2" fill="#aebac4" opacity="0.5" />
        <rect width="300" height="110" fill="url(#vig)" />
      </svg>
    );
  }

  if (s === "pin") {
    return (
      <svg viewBox="0 0 300 110" preserveAspectRatio="xMidYMid slice">
        <rect width="300" height="110" fill="#26303a" />
        {/* simple horizon split */}
        <rect width="300" height="42" y="58" fill="#1c2530" />
        <line x1="0" y1="58" x2="300" y2="58" stroke="#3a4654" strokeWidth="0.5" />
        {/* dotted lat/lon */}
        {[18, 36, 76, 94].map((y, i) => (
          <line key={i} x1="0" y1={y} x2="300" y2={y} stroke="#2a3540" strokeWidth="0.5" strokeDasharray="3 4" />
        ))}
        {[40, 100, 160, 220, 260].map((x, i) => (
          <line key={i} x1={x} y1="0" x2={x} y2="110" stroke="#2a3540" strokeWidth="0.5" strokeDasharray="3 4" />
        ))}
      </svg>
    );
  }

  // topo (default) — contour rings around the pin
  return (
    <svg viewBox="0 0 300 110" preserveAspectRatio="xMidYMid slice">
      <defs>
        <radialGradient id="topo-bg">
          <stop offset="0" stopColor="#283038" />
          <stop offset="1" stopColor="#1a1f25" />
        </radialGradient>
      </defs>
      <rect width="300" height="110" fill="url(#topo-bg)" />
      {/* coast */}
      <path d="M 0 86 Q 70 70 140 78 T 260 72 T 320 80 L 320 110 L 0 110 Z"
            fill="#1e2a30" stroke="#3a5366" strokeWidth="0.6" />
      {/* contours concentric around the pin (150, 55) */}
      {[8, 16, 26, 38, 52, 70].map((r, i) => (
        <ellipse key={i} cx="150" cy="55" rx={r * 1.6} ry={r}
                 fill="none" stroke="#3a4a55" strokeWidth="0.6" opacity={0.7 - i * 0.08} />
      ))}
      {/* small rivers / lines */}
      <path d="M 20 30 Q 80 50 140 40 T 280 50" stroke="#3a667a" strokeWidth="0.8" fill="none" opacity="0.7" />
      <path d="M 60 92 Q 110 80 160 90 T 250 86" stroke="#3a667a" strokeWidth="0.8" fill="none" opacity="0.6" />
    </svg>
  );
}

window.MapView = MapView;
