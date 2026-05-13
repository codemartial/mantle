// Procedural thumbnail / preview SVG generator.
// Renders a distinguishable "photograph" from a photo data object
// without pretending to be a real image. Each photo's `sky`, `land`,
// `accent` + scene flags drive what gets composed.

function PhotoSVG({ photo, big = false }) {
  const id = "g_" + photo.id + (big ? "_b" : "");
  const sky = photo.sky || { from: "#3a4a5a", to: "#1a2230" };
  const land = photo.land || "#0c1116";
  const horizon = big ? 62 : 64; // % from top
  return (
    <svg viewBox="0 0 300 200" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id={id + "_sky"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={sky.from} />
          <stop offset="1" stopColor={sky.to} />
        </linearGradient>
        <linearGradient id={id + "_land"} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={land} />
          <stop offset="1" stopColor="#000" stopOpacity="0.65" />
        </linearGradient>
        {photo.aurora && (
          <linearGradient id={id + "_aur"} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0"   stopColor="#2aff8c" stopOpacity="0" />
            <stop offset="0.3" stopColor="#3affa8" stopOpacity="0.85" />
            <stop offset="0.6" stopColor="#aaffd0" stopOpacity="0.7" />
            <stop offset="1"   stopColor="#2aaaff" stopOpacity="0" />
          </linearGradient>
        )}
      </defs>
      {/* sky */}
      <rect width="300" height="200" fill={`url(#${id}_sky)`} />

      {/* aurora ribbons */}
      {photo.aurora && (
        <g opacity="0.85">
          <path d="M -10 60 C 60 30, 120 90, 180 50 S 280 80, 320 40 L 320 78 C 280 110, 220 70, 150 100 S 60 70, -10 95 Z"
                fill={`url(#${id}_aur)`} />
          <path d="M -10 96 C 80 70, 140 130, 220 95 S 320 110, 320 100 L 320 124 C 240 150, 160 110, 80 138 S -10 120, -10 120 Z"
                fill={`url(#${id}_aur)`} opacity="0.6" />
        </g>
      )}

      {/* stars */}
      {photo.stars && (
        <g fill="#ffffff" opacity="0.85">
          {[[22,18],[44,32],[80,12],[120,28],[160,16],[200,38],[240,22],[270,46],[60,52],[180,8],[105,8],[230,8]].map(([x,y],i)=>(
            <circle key={i} cx={x} cy={y} r={0.7 + (i%3)*0.3} />
          ))}
        </g>
      )}

      {/* sun / moon disc */}
      {photo.sun && (
        <circle cx={photo.sun.x * 3} cy={photo.sun.y * 2} r={photo.sun.r} fill={photo.sun.color} opacity="0.85" />
      )}

      {/* land horizon */}
      <path d={`M 0 ${horizon * 2} L 18 ${horizon * 2 - 4} L 46 ${horizon * 2 + 2} L 74 ${horizon * 2 - 8} L 110 ${horizon * 2 + 4} L 150 ${horizon * 2 - 12} L 190 ${horizon * 2 + 6} L 232 ${horizon * 2 - 2} L 268 ${horizon * 2 + 8} L 300 ${horizon * 2 - 4} L 300 200 L 0 200 Z`}
            fill={`url(#${id}_land)`} />

      {/* basalt stacks for Reynisfjara-style scene */}
      {photo.id === "DSC_0421" && (
        <g fill="#0a0d12">
          <path d="M 180 132 L 188 86 L 196 132 Z" />
          <path d="M 198 132 L 212 70 L 226 132 Z" />
          <path d="M 240 132 L 248 96 L 258 132 Z" />
          <path d="M 90 138 L 102 110 L 114 138 Z" />
        </g>
      )}

      {/* waterfall */}
      {photo.fall && (
        <g>
          <rect x="120" y="40" width="60" height="100" fill="#cfd8e0" opacity="0.85" />
          <rect x="124" y="40" width="3" height="100" fill="#fff" opacity="0.5" />
          <rect x="148" y="40" width="2" height="100" fill="#fff" opacity="0.4" />
          <rect x="166" y="40" width="3" height="100" fill="#fff" opacity="0.5" />
          <ellipse cx="150" cy="142" rx="46" ry="6" fill="#fff" opacity="0.55" />
          <path d="M 110 60 Q 150 -10 190 60 L 110 60" fill="rgba(255,200,150,0.18)" />
        </g>
      )}

      {/* ice cave arch */}
      {photo.cave && (
        <g>
          <path d="M 0 200 L 0 70 Q 150 -20 300 70 L 300 200 Z" fill="#1a2a3a" />
          <path d="M 30 200 L 30 100 Q 150 30 270 100 L 270 200 Z" fill="#3a86b8" />
          <path d="M 60 200 L 60 130 Q 150 70 240 130 L 240 200 Z" fill="#7ccae8" opacity="0.85" />
          <path d="M 90 200 L 90 160 Q 150 110 210 160 L 210 200 Z" fill="#e0f4ff" opacity="0.55" />
        </g>
      )}

      {/* steam plumes */}
      {photo.steam && (
        <g fill="#e8dcc8" opacity="0.55">
          <ellipse cx="80"  cy="100" rx="28" ry="14" />
          <ellipse cx="150" cy="84"  rx="34" ry="18" />
          <ellipse cx="220" cy="98"  rx="26" ry="12" />
        </g>
      )}

      {/* puffin silhouette */}
      {photo.bird && (
        <g>
          <ellipse cx="180" cy="120" rx="36" ry="28" fill="#0c0c0c" />
          <ellipse cx="180" cy="130" rx="22" ry="14" fill="#f0eee8" />
          <circle cx="200" cy="98" r="14" fill="#0c0c0c" />
          <circle cx="206" cy="96" r="2.5" fill="#e8e8e8" />
          <path d="M 212 100 L 224 102 L 214 108 Z" fill={photo.accent || "#e8762a"} />
        </g>
      )}

      {/* road vanishing */}
      {photo.road && (
        <g>
          <path d="M 130 200 L 148 100 L 156 100 L 170 200 Z" fill="#8a7858" />
          <path d="M 150 200 L 152.5 100 L 154 100 L 158 200 Z" fill="#dccaa0" opacity="0.6" />
        </g>
      )}

      {/* pool surface */}
      {photo.pool && (
        <g>
          <rect x="0" y="120" width="300" height="80" fill="#9ed0e6" opacity="0.85" />
          <rect x="0" y="120" width="300" height="2" fill="#fff" opacity="0.4" />
          <ellipse cx="80"  cy="140" rx="50" ry="6" fill="#fff" opacity="0.25" />
          <ellipse cx="220" cy="160" rx="40" ry="4" fill="#fff" opacity="0.2" />
        </g>
      )}

      {/* moss field */}
      {photo.moss && (
        <g fill="#3a5a3a" opacity="0.85">
          {[...Array(40)].map((_, i) => (
            <ellipse key={i} cx={(i * 37) % 300 + 8} cy={130 + ((i * 23) % 60)} rx={6 + (i % 4)} ry={3 + (i % 2)} />
          ))}
        </g>
      )}

      {/* harbor boats */}
      {photo.harbor && (
        <g>
          <rect x="0"   y="130" width="300" height="70" fill="#1a2a36" />
          <path d="M 40 130 L 50 118 L 110 118 L 120 130 Z" fill="#c84a3a" />
          <rect x="60" y="100" width="6" height="20" fill="#c8c8c8" />
          <path d="M 150 130 L 158 116 L 218 116 L 226 130 Z" fill="#d8b440" />
          <rect x="172" y="98" width="6" height="20" fill="#c8c8c8" />
        </g>
      )}

      {/* crater rim */}
      {photo.crater && (
        <g>
          <ellipse cx="150" cy="170" rx="180" ry="30" fill="#2a1c1c" />
          <ellipse cx="150" cy="166" rx="160" ry="24" fill="#3a2828" />
          <ellipse cx="150" cy="162" rx="120" ry="16" fill="#1c1010" />
        </g>
      )}

      {/* small church */}
      {photo.church && (
        <g>
          <rect x="146" y="118" width="20" height="22" fill="#e8e2d8" />
          <path d="M 146 118 L 156 100 L 166 118 Z" fill="#a83a2a" />
          <rect x="158" y="92" width="2" height="14" fill="#a83a2a" />
          <rect x="156" y="84" width="6" height="2" fill="#a83a2a" />
          <rect x="158" y="84" width="2" height="6" fill="#a83a2a" />
        </g>
      )}

      {/* film-grain wash */}
      <rect width="300" height="200" fill="url(#grain)" opacity="0.06" />
    </svg>
  );
}

function GrainDefs() {
  // single shared filter defs node
  return (
    <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
      <defs>
        <pattern id="grain" width="3" height="3" patternUnits="userSpaceOnUse">
          <rect width="3" height="3" fill="#000" />
          <rect width="1" height="1" fill="#fff" opacity="0.5" />
        </pattern>
      </defs>
    </svg>
  );
}

window.PhotoSVG = PhotoSVG;
window.GrainDefs = GrainDefs;
