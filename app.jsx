// Metadater — main app (v2).
// Implements: theme switching, batch-edit master/scope model, append/replace caption,
// date/time/TZ editing, auto-save on selection change, fit/1:1 keyboard shortcuts.

const { useState, useMemo, useRef, useEffect, useCallback } = React;

// ── Tweak defaults ──────────────────────────────────────────────────────────
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "appState": "browsing",
  "thumbDensity": "m",
  "browserMode": "grid",
  "mapStyle": "topo"
}/*EDITMODE-END*/;

// ── Date parsing / formatting ───────────────────────────────────────────────
function parseDate(str) {
  const m = String(str || "").match(/(\d{4})\s*\/\s*(\d{2})\s*\/\s*(\d{2}).*?(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return { y: 2026, mo: 1, d: 1, h: 0, i: 0, s: 0 };
  return { y: +m[1], mo: +m[2], d: +m[3], h: +m[4], i: +m[5], s: +(m[6] || 0) };
}
function pad2(n) { return String(n).padStart(2, "0"); }
function fmtDate(d) {
  return `${d.y}/${pad2(d.mo)}/${pad2(d.d)} ${pad2(d.h)}:${pad2(d.i)}:${pad2(d.s)}`;
}
function shiftDate(d, deltaHours, deltaMinutes) {
  const js = new Date(Date.UTC(d.y, d.mo - 1, d.d, d.h, d.i, d.s));
  js.setUTCMinutes(js.getUTCMinutes() + deltaHours * 60 + deltaMinutes);
  return {
    y: js.getUTCFullYear(), mo: js.getUTCMonth() + 1, d: js.getUTCDate(),
    h: js.getUTCHours(), i: js.getUTCMinutes(), s: js.getUTCSeconds(),
  };
}

const TZ_OPTIONS = [
  "UTC+00:00 · Auto",
  "UTC+00:00 · Iceland",
  "UTC+00:00 · UK",
  "UTC+01:00 · CET",
  "UTC-05:00 · EST",
  "UTC-08:00 · PST",
  "UTC+05:30 · IST",
  "UTC+09:00 · JST",
];

function makeInitial(photos) {
  return Object.fromEntries(photos.map(p => [p.id, {
    headline: p.headline,
    caption: p.caption,
    keywords: [...p.keywords],
    date: parseDate(p.date),
    tz: "UTC+00:00 · Auto",
    lat: p.lat,
    lon: p.lon,
  }]));
}

// Parse a single coordinate (decimal or DMS) — used by paste parser.
// Returns array of {val, hem?} tokens for whatever it finds in the string.
function tokenizeCoords(s) {
  const dms = /([+-]?\d+(?:\.\d+)?)\s*(?:°|d|deg)\s*(?:(\d+(?:\.\d+)?)\s*(?:'|′|m\b))?\s*(?:(\d+(?:\.\d+)?)\s*(?:"|″|s\b))?\s*([NSEW])?/gi;
  const hasDmsMarkers = /[°'"′″NSEW]/i.test(s);
  if (hasDmsMarkers) {
    const tokens = [];
    let m;
    while ((m = dms.exec(s)) !== null) {
      const deg = parseFloat(m[1]);
      const min = parseFloat(m[2] || "0");
      const sec = parseFloat(m[3] || "0");
      const hem = m[4]?.toUpperCase();
      let val = Math.abs(deg) + min / 60 + sec / 3600;
      if (deg < 0) val = -val;
      if (hem === "S" || hem === "W") val = -Math.abs(val);
      else if (hem === "N" || hem === "E") val = Math.abs(val);
      if (!isNaN(val)) tokens.push({ val, hem });
    }
    return tokens;
  }
  // Decimal: split on commas / whitespace / semicolons
  return s.split(/[,;\s]+/)
    .map(x => parseFloat(x))
    .filter(n => !isNaN(n))
    .map(val => ({ val }));
}

// Parse a pasted string into { lat, lon } if a pair is detectable,
// or { single } if only one value is present.
function parseLatLonPair(s) {
  s = s.trim();
  if (!s) return null;
  const tokens = tokenizeCoords(s);
  if (!tokens.length) return null;
  if (tokens.length === 1) return { single: tokens[0].val };

  const [a, b] = tokens;
  const isLat = (t) => t.hem === "N" || t.hem === "S";
  const isLon = (t) => t.hem === "E" || t.hem === "W";
  let lat, lon;
  if (isLat(a) && isLon(b))      { lat = a.val; lon = b.val; }
  else if (isLat(b) && isLon(a)) { lat = b.val; lon = a.val; }
  else if (isLat(a))             { lat = a.val; lon = b.val; }
  else if (isLon(a))             { lon = a.val; lat = b.val; }
  else                           { lat = a.val; lon = b.val; }

  // Sanity swap if obviously reversed (lat > 90 means swapped)
  if (Math.abs(lat) > 90 && Math.abs(lon) <= 90) {
    const t = lat; lat = lon; lon = t;
  }
  return { lat, lon };
}

// ── Tiny inline icons ───────────────────────────────────────────────────────
const Icon = ({ name, size = 14 }) => {
  const s = size;
  const stroke = { stroke: "currentColor", strokeWidth: 1.5, fill: "none", strokeLinecap: "round", strokeLinejoin: "round" };
  switch (name) {
    case "folder":   return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M2 5 V12 a1 1 0 0 0 1 1 H13 a1 1 0 0 0 1 -1 V6 a1 1 0 0 0 -1 -1 H8 L6.5 3.5 H3 a1 1 0 0 0 -1 1 Z"/></svg>;
    case "search":   return <svg width={s} height={s} viewBox="0 0 16 16"><circle {...stroke} cx="7" cy="7" r="4.5"/><path {...stroke} d="M10.5 10.5 L14 14"/></svg>;
    case "grid":     return <svg width={s} height={s} viewBox="0 0 16 16"><rect {...stroke} x="2.5" y="2.5" width="4.5" height="4.5"/><rect {...stroke} x="9" y="2.5" width="4.5" height="4.5"/><rect {...stroke} x="2.5" y="9" width="4.5" height="4.5"/><rect {...stroke} x="9" y="9" width="4.5" height="4.5"/></svg>;
    case "list":     return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M3 4 H13 M3 8 H13 M3 12 H13"/></svg>;
    case "sort":     return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M4 4 L4 13 M4 13 L2 11 M4 13 L6 11 M9 5 H13 M9 9 H12 M9 13 H10.5"/></svg>;
    case "more":     return <svg width={s} height={s} viewBox="0 0 16 16"><circle fill="currentColor" cx="3.5" cy="8" r="1.1"/><circle fill="currentColor" cx="8" cy="8" r="1.1"/><circle fill="currentColor" cx="12.5" cy="8" r="1.1"/></svg>;
    case "save":     return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M3 3 H10 L13 6 V13 a0.5 0.5 0 0 1 -0.5 0.5 H3.5 a0.5 0.5 0 0 1 -0.5 -0.5 Z M5 3 V6 H10 V3 M5 10 H11 V13.5 H5 Z"/></svg>;
    case "stack":    return <svg width={s} height={s} viewBox="0 0 16 16"><rect {...stroke} x="2.5" y="6" width="11" height="7.5" rx="1"/><path {...stroke} d="M4 4.5 H12 M5 3 H11"/></svg>;
    case "wifi":     return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M2 6 Q8 1 14 6 M4 9 Q8 5 12 9"/><circle fill="currentColor" cx="8" cy="12" r="1"/></svg>;
    case "battery":  return <svg width={s} height={s} viewBox="0 0 22 12"><rect {...stroke} x="0.5" y="1.5" width="18" height="9" rx="2"/><rect x="3" y="3" width="13" height="6" fill="currentColor"/><rect x="19.5" y="4" width="2" height="4" rx="1" fill="currentColor"/></svg>;
    case "spot":     return <svg width={s} height={s} viewBox="0 0 16 16"><circle {...stroke} cx="7" cy="7" r="4.5"/><path {...stroke} d="M10.5 10.5 L14 14"/></svg>;
    case "control":  return <svg width={s} height={s} viewBox="0 0 16 16"><rect {...stroke} x="2" y="3" width="5" height="10" rx="1"/><rect {...stroke} x="9" y="3" width="5" height="10" rx="1"/><circle fill="currentColor" cx="4.5" cy="9" r="1.2"/><circle fill="currentColor" cx="11.5" cy="6" r="1.2"/></svg>;
    case "check":    return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M3 8 L7 12 L13 4"/></svg>;
    case "moon":     return <svg width={s} height={s} viewBox="0 0 16 16"><path {...stroke} d="M13 9.5 A5 5 0 1 1 6.5 3 A4 4 0 0 0 13 9.5 Z"/></svg>;
    case "sun":      return <svg width={s} height={s} viewBox="0 0 16 16"><circle {...stroke} cx="8" cy="8" r="3"/><path {...stroke} d="M8 1.5 V3 M8 13 V14.5 M1.5 8 H3 M13 8 H14.5 M3.5 3.5 L4.5 4.5 M11.5 11.5 L12.5 12.5 M3.5 12.5 L4.5 11.5 M11.5 4.5 L12.5 3.5"/></svg>;
    default: return null;
  }
};

// ── Menubar ─────────────────────────────────────────────────────────────────
function Menubar() {
  return (
    <div className="menubar">
      <span className="mb-app">⌘ Metadater</span>
      {["File","Edit","View","Image","Window","Help"].map(m => (
        <span key={m} className="mb-item">{m}</span>
      ))}
      <span className="mb-spacer"></span>
      <div className="mb-right">
        <span className="mb-glyph"><Icon name="control" size={14} /></span>
        <span className="mb-glyph"><Icon name="battery" size={20} /></span>
        <span className="mb-glyph"><Icon name="wifi" size={14} /></span>
        <span className="mb-glyph"><Icon name="spot" size={13} /></span>
        <span>Wed 8 May  ·  10:42</span>
      </div>
    </div>
  );
}

// ── Titlebar ────────────────────────────────────────────────────────────────
function Titlebar({ folder, browserMode, setBrowserMode }) {
  return (
    <div className="titlebar">
      <div className="tl-group">
        <span className="tl-dot r"></span>
        <span className="tl-dot y"></span>
        <span className="tl-dot g"></span>
      </div>
      <div className="tb-divider"></div>
      <div className="tb-btn" title={folder?.path || "Open folder… (⌘O)"}>
        <Icon name="folder" size={13} />
        <span>{folder?.name || "Choose folder…"}</span>
        <span className="caret">▾</span>
      </div>
      <div className="tb-btn icon" title="Sort"><Icon name="sort" /></div>
      <div className="tb-segment" title="View mode">
        <button className={browserMode === "grid" ? "on" : ""} onClick={() => setBrowserMode("grid")}><Icon name="grid" size={12}/></button>
        <button className={browserMode === "list" ? "on" : ""} onClick={() => setBrowserMode("list")}><Icon name="list" size={12}/></button>
      </div>

      <span className="spacer"></span>

      <div className="tb-search">
        <Icon name="search" size={12} />
        <input placeholder="Filter keywords, caption…" defaultValue="" />
      </div>
    </div>
  );
}

// ── Browser ─────────────────────────────────────────────────────────────────
function Browser({ photos, selectedId, batchOrder, onSelect, onToggleBatch, mode, density, batchMode }) {
  const batchSet = useMemo(() => new Set(batchOrder), [batchOrder]);
  const masterId = batchOrder[0];

  if (mode === "list") {
    return (
      <div className="list-wrap">
        {photos.map(p => {
          const isSel = batchMode ? batchSet.has(p.id) : selectedId === p.id;
          const isMaster = batchMode && masterId === p.id;
          return (
            <div key={p.id} className={"list-row " + (isSel ? "selected" : "")}
                 onClick={(e) => batchMode || e.metaKey ? onToggleBatch(p.id) : onSelect(p.id)}>
              <div className="lthumb"><PhotoSVG photo={p}/></div>
              <div>
                <div className="lname">{p.file}{isMaster ? "  ⏵ master" : ""}</div>
                <div className="lmeta mono">{p.dim} · {p.size} · {p.iso} ISO</div>
              </div>
              <div className="lmeta mono">{p.aperture}</div>
            </div>
          );
        })}
      </div>
    );
  }
  return (
    <div className={"grid-wrap density-" + density}>
      {photos.map(p => {
        const isSel = batchMode ? batchSet.has(p.id) : selectedId === p.id;
        const inBatch = batchMode && batchSet.has(p.id);
        const isMaster = batchMode && masterId === p.id;
        const orderNum = batchMode && inBatch ? batchOrder.indexOf(p.id) + 1 : null;
        return (
          <div key={p.id}
               className={"thumb density-" + density + (isSel ? " selected" : "") + (inBatch ? " batch" : "")}
               onClick={(e) => batchMode || e.metaKey ? onToggleBatch(p.id) : onSelect(p.id)}>
            <PhotoSVG photo={p}/>
            {p.flag === "pick" && !batchMode && (
              <span className="badge flag" title="Flagged">✓</span>
            )}
            {batchMode && (
              <span className="badge flag" style={{ background: inBatch ? "var(--accent)" : "rgba(0,0,0,.55)", color: inBatch ? "var(--accent-fg)" : "rgba(255,255,255,.85)" }}>
                {orderNum != null ? (isMaster ? "M" : orderNum) : "+"}
              </span>
            )}
            {density !== "s" && (
              <span className="stamp mono">{p.id}</span>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Preview pane ────────────────────────────────────────────────────────────
function PreviewPane({ photo, zoom }) {
  return (
    <div className="preview-wrap">
      <div className="preview-frame">
        <PhotoSVG photo={photo} big />
        <div className="preview-corners">
          <div className="c tl"></div><div className="c tr"></div>
          <div className="c bl"></div><div className="c br"></div>
        </div>
      </div>
      <div className="preview-toolbar">
        <button title="Fit (,)">⤢</button>
        <button title="1:1 (.)">1:1</button>
        <button title="Rotate left">↺</button>
      </div>
      <div className="preview-zoom mono">{zoom === "fit" ? "Fit · 38%" : "1:1 · 100%"}</div>
    </div>
  );
}

// ── Caption block (single) ──────────────────────────────────────────────────
function CaptionBlock({ headline, setHeadline, caption, setCaption }) {
  const hLen = headline.length;
  const cLen = caption.length;
  const hClass = hLen > 40 ? "over" : hLen >= 36 ? "warn" : "";
  return (
    <div className="caption-block">
      <div className="headline-row">
        <span className="field-label">Headline</span>
        <input
          className="headline-input"
          value={headline}
          onChange={(e) => setHeadline(e.target.value)}
        />
        <span className={"glyph-count " + hClass}>{hLen}/40</span>
      </div>
      <div className="caption-input-row">
        <span className="field-label" style={{ paddingTop: 3 }}>Caption</span>
        <textarea
          className="caption-input"
          value={caption}
          onChange={(e) => setCaption(e.target.value)}
        />
        <div className="caption-meta">
          <span>{cLen}</span>
          <span>chars</span>
        </div>
      </div>
    </div>
  );
}

// ── Date editor ─────────────────────────────────────────────────────────────
function DateEditor({ value, tz, onChange, onTzChange, locked }) {
  const upd = (k) => (e) => {
    const v = e.target.value.replace(/\D/g, "");
    if (locked) return;
    onChange({ ...value, [k]: +v || 0 });
  };
  return (
    <div className="date-editor">
      <input className="date-seg y" value={value.y} onChange={upd("y")} disabled={locked} maxLength={4} inputMode="numeric" />
      <span className="date-sep">/</span>
      <input className="date-seg m" value={pad2(value.mo)} onChange={upd("mo")} disabled={locked} maxLength={2} inputMode="numeric" />
      <span className="date-sep">/</span>
      <input className="date-seg d" value={pad2(value.d)} onChange={upd("d")} disabled={locked} maxLength={2} inputMode="numeric" />
      <span className="date-pad"></span>
      <input className="date-seg h" value={pad2(value.h)} onChange={upd("h")} disabled={locked} maxLength={2} inputMode="numeric" />
      <span className="date-sep">:</span>
      <input className="date-seg i" value={pad2(value.i)} onChange={upd("i")} disabled={locked} maxLength={2} inputMode="numeric" />
      <span className="date-sep">:</span>
      <input className="date-seg s" value={pad2(value.s)} onChange={upd("s")} disabled={locked} maxLength={2} inputMode="numeric" />
      <select className="date-tz" value={tz} onChange={(e) => !locked && onTzChange(e.target.value)} disabled={locked}>
        {TZ_OPTIONS.map(o => <option key={o} value={o}>{o}</option>)}
      </select>
    </div>
  );
}

function DateShift({ delta, setDelta }) {
  return (
    <div className="date-shift">
      <span>Shift all by</span>
      <input value={delta.hours} onChange={(e) => setDelta({ ...delta, hours: +e.target.value || 0 })} inputMode="numeric" />
      <span>h</span>
      <input value={delta.minutes} onChange={(e) => setDelta({ ...delta, minutes: +e.target.value || 0 })} inputMode="numeric" />
      <span>m</span>
      <span className="spacer" style={{ flex: 1 }}></span>
      <span className="faint mono" style={{ fontSize: 10 }}>preserves order</span>
    </div>
  );
}

// ── Keyword chips (single) ──────────────────────────────────────────────────
function KeywordChips({ keywords, setKeywords }) {
  const [draft, setDraft] = useState("");
  const inputRef = useRef(null);

  const commit = (raw) => {
    const parts = raw.split(",").map(s => s.trim()).filter(Boolean);
    if (!parts.length) return;
    const next = [...keywords];
    parts.forEach(p => { if (!next.includes(p.toLowerCase())) next.push(p.toLowerCase()); });
    setKeywords(next);
    setDraft("");
  };

  return (
    <div className="chips" onClick={() => inputRef.current?.focus()}>
      {keywords.map((k, i) => (
        <span key={k + i} className="chip">
          <span className="scope-dot"></span>
          {k}
          <span className="x" onClick={(e) => { e.stopPropagation(); setKeywords(keywords.filter((_, j) => j !== i)); }}>×</span>
        </span>
      ))}
      <input
        ref={inputRef}
        className="chip-input"
        value={draft}
        placeholder={keywords.length ? "Add…" : "Type a keyword, press , to add"}
        onChange={(e) => {
          const v = e.target.value;
          if (v.endsWith(",")) commit(v);
          else setDraft(v);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") { e.preventDefault(); commit(draft); }
          if (e.key === "Backspace" && !draft && keywords.length) {
            setKeywords(keywords.slice(0, -1));
          }
        }}
      />
    </div>
  );
}

// ── Keyword chips (batch) ───────────────────────────────────────────────────
// Renders union of all selected images' keywords. Solid = in every image;
// dashed/faded = in some. X removes from all. Right-click context menu
// offers Add-to-all (for "some" chips) or Remove-from-all.
function BatchKeywordChips({ commonKeywords, someKeywords, onAddAll, onRemoveAll, onPromoteToAll }) {
  const [draft, setDraft] = useState("");
  const [menu, setMenu] = useState(null); // { x, y, key, scope }
  const inputRef = useRef(null);

  const commit = (raw) => {
    const parts = raw.split(",").map(s => s.trim().toLowerCase()).filter(Boolean);
    if (!parts.length) return;
    parts.forEach(p => onAddAll(p));
    setDraft("");
  };

  useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(null);
    window.addEventListener("click", close);
    return () => window.removeEventListener("click", close);
  }, [menu]);

  const renderChip = (k, scope) => (
    <span key={scope + "-" + k} className={"chip" + (scope === "some" ? " some" : "")}
          onContextMenu={(e) => { e.preventDefault(); setMenu({ x: e.clientX, y: e.clientY, key: k, scope }); }}>
      <span className="scope-dot"></span>
      {k}
      <span className="x" onClick={(e) => { e.stopPropagation(); onRemoveAll(k); }}>×</span>
    </span>
  );

  return (
    <>
      <div className="chips" onClick={() => inputRef.current?.focus()}>
        {commonKeywords.map(k => renderChip(k, "all"))}
        {someKeywords.map(k => renderChip(k, "some"))}
        <input
          ref={inputRef}
          className="chip-input"
          value={draft}
          placeholder={(commonKeywords.length + someKeywords.length) ? "Add to all…" : "Add a keyword, press , to add to all"}
          onChange={(e) => {
            const v = e.target.value;
            if (v.endsWith(",")) commit(v);
            else setDraft(v);
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter") { e.preventDefault(); commit(draft); }
          }}
        />
      </div>
      {menu && (
        <div className="chip-menu" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()}>
          {menu.scope === "some" && (
            <div className="item" onClick={() => { onPromoteToAll(menu.key); setMenu(null); }}>
              <Icon name="check" size={11}/> Add "{menu.key}" to all
            </div>
          )}
          <div className="item danger" onClick={() => { onRemoveAll(menu.key); setMenu(null); }}>
            Remove "{menu.key}" from all
          </div>
        </div>
      )}
    </>
  );
}

// ── Geo cells (lat + lon with inline hemisphere) ────────────────────────────
function formatCoord(v) {
  if (v == null || isNaN(v)) return "";
  return Math.abs(v).toFixed(4) + "°";
}

function GeoCells({ lat, lon, onChange }) {
  const [latStr, setLatStr] = useState(formatCoord(lat));
  const [lonStr, setLonStr] = useState(formatCoord(lon));
  useEffect(() => { setLatStr(formatCoord(lat)); }, [lat]);
  useEffect(() => { setLonStr(formatCoord(lon)); }, [lon]);

  const onPaste = (which) => (e) => {
    const text = e.clipboardData.getData("text");
    const parsed = parseLatLonPair(text);
    if (!parsed) return;
    e.preventDefault();
    if (parsed.lat != null && parsed.lon != null) {
      onChange({ lat: parsed.lat, lon: parsed.lon });
    } else if (parsed.single != null) {
      if (which === "lat") onChange({ lat: parsed.single, lon });
      else                 onChange({ lat, lon: parsed.single });
    }
  };

  const commit = (which) => () => {
    const str = which === "lat" ? latStr : lonStr;
    const cur = which === "lat" ? lat : lon;
    const v = parseFloat(str);
    if (isNaN(v)) {
      // reset display
      if (which === "lat") setLatStr(formatCoord(lat));
      else                 setLonStr(formatCoord(lon));
      return;
    }
    const signed = cur < 0 ? -Math.abs(v) : Math.abs(v);
    if (signed !== cur) {
      if (which === "lat") onChange({ lat: signed, lon });
      else                 onChange({ lat, lon: signed });
    } else {
      if (which === "lat") setLatStr(formatCoord(signed));
      else                 setLonStr(formatCoord(signed));
    }
  };

  const toggleSign = (which) => () => {
    // intentionally a no-op — hemisphere is a read-only label derived
    // from the value's sign. To flip hemisphere, type a leading "-".
  };

  return (
    <div className="geo-row">
      <div className="geo-cell">
        <input
          className="geo-input"
          value={latStr}
          onChange={(e) => setLatStr(e.target.value)}
          onPaste={onPaste("lat")}
          onBlur={commit("lat")}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); commit("lat")(); e.target.blur(); } }}
          spellCheck={false}
        />
        <span className="hemi" title="Hemisphere — derived from sign">
          {lat >= 0 ? "N" : "S"}
        </span>
      </div>
      <div className="geo-cell">
        <input
          className="geo-input"
          value={lonStr}
          onChange={(e) => setLonStr(e.target.value)}
          onPaste={onPaste("lon")}
          onBlur={commit("lon")}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); commit("lon")(); e.target.blur(); } }}
          spellCheck={false}
        />
        <span className="hemi" title="Hemisphere — derived from sign">
          {lon >= 0 ? "E" : "W"}
        </span>
      </div>
    </div>
  );
}

// ── Map pin with optional direction cone + altitude readout ────────────────
function MapPin({ dir }) {
  return (
    <div className="map-pin">
      {dir != null && (
        <svg className="pin-cone" viewBox="0 0 56 56"
             style={{ transform: `rotate(${dir}deg)` }} aria-hidden="true">
          <defs>
            <radialGradient id="cone-grad" cx="50%" cy="50%" r="55%">
              <stop offset="0"    stopColor="currentColor" stopOpacity="0.6" />
              <stop offset="0.55" stopColor="currentColor" stopOpacity="0.22" />
              <stop offset="1"    stopColor="currentColor" stopOpacity="0" />
            </radialGradient>
          </defs>
          <path d="M 28 28 L 12 0 A 32 32 0 0 1 44 0 Z" fill="url(#cone-grad)"/>
        </svg>
      )}
      <div className="pin-pulse"></div>
      <div className="pin-dot"></div>
    </div>
  );
}

function PlaceLine({ place, alt }) {
  return (
    <div className="place-line">
      <span>{place}</span>
      {alt != null && (
        <>
          <span className="dim-sep">·</span>
          <span className="alt" title={`Altitude ${alt} m`}>
            <svg width="9" height="9" viewBox="0 0 9 9" fill="none" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M 4.5 1 L 4.5 8 M 2 3 L 4.5 1 L 7 3"/>
            </svg>
            {alt} m
          </span>
        </>
      )}
    </div>
  );
}
function MetaPanelSingle({ photo, image, update, mapStyle }) {
  return (
    <div className="meta-panel">
      <div className="meta-scroll">
        <div className="section">
          <div className="section-title"><span>Camera</span></div>
          <dl className="kv-list">
            <dt>Camera</dt>     <dd>{photo.cam}</dd>
            <dt>Lens</dt>       <dd>{photo.lens}</dd>
            <dt>Exposure</dt>   <dd>{photo.shutter} · {photo.aperture}</dd>
            <dt>ISO</dt>        <dd>{photo.iso}</dd>
            <dt>Focal length</dt><dd>{photo.focal}</dd>
          </dl>
        </div>

        <div className="section">
          <div className="section-title"><span>Captured</span></div>
          <DateEditor
            value={image.date}
            tz={image.tz}
            onChange={(d) => update({ date: d })}
            onTzChange={(tz) => update({ tz })}
          />
        </div>

        <div className="section">
          <div className="section-title"><span>File</span></div>
          <dl className="kv-list">
            <dt>Format</dt>     <dd>{photo.fmt}</dd>
            <dt>Dimensions</dt> <dd>{photo.dim}</dd>
            <dt>Size</dt>       <dd>{photo.size}</dd>
            <dt>Color</dt>      <dd>{photo.profile}</dd>
          </dl>
        </div>

        <div className="section">
          <div className="section-title"><span>Location</span><span className="edit">Drag pin</span></div>
          <div className="map">
            <MapView photo={photo} style={mapStyle} />
            <MapPin dir={photo.dir} />
          </div>
          <GeoCells lat={image.lat} lon={image.lon} onChange={({lat, lon}) => update({ lat, lon })} />
          <PlaceLine place={photo.place} alt={photo.alt} />
        </div>

        <div className="section">
          <div className="section-title"><span>Keywords</span><span className="edit">{image.keywords.length}</span></div>
          <KeywordChips keywords={image.keywords} setKeywords={(v) => update({ keywords: v })} />
        </div>
      </div>
    </div>
  );
}

// ── Meta panel (batch) ──────────────────────────────────────────────────────
function MetaPanelBatch({ batchPhotos, batchImages, masterId, batchDraft, setBatchDraft, mapStyle, commonKeywords, someKeywords, onAddAll, onRemoveAll, onPromoteToAll }) {
  const master = batchImages[masterId];
  if (!master) return null;
  const dateCount = new Set(batchPhotos.map(p => `${batchImages[p.id].date.y}-${batchImages[p.id].date.mo}-${batchImages[p.id].date.d}`)).size;
  const locCount = new Set(batchPhotos.map(p => `${p.lat.toFixed(2)},${p.lon.toFixed(2)}`)).size;

  return (
    <div className="meta-panel">
      <div className="meta-scroll">
        <div className="section">
          <div className="section-title"><span>Selection</span><span className="edit">{batchPhotos.length}</span></div>
          <dl className="kv-list">
            <dt>Master</dt>     <dd>{batchPhotos[0]?.id}</dd>
            <dt>Date span</dt>  <dd>{dateCount === 1 ? "same day" : `${dateCount} dates`}</dd>
            <dt>Locations</dt>  <dd>{locCount} distinct</dd>
            <dt>Total size</dt> <dd>{batchPhotos.reduce((s, p) => s + parseFloat(p.size), 0).toFixed(1)} MB</dd>
          </dl>
        </div>

        <div className="section">
          <div className="section-title"><span>Captured (master)</span></div>
          <DateEditor
            value={master.date}
            tz={master.tz}
            onChange={(d) => setBatchDraft({ ...batchDraft, masterDate: d })}
            onTzChange={(tz) => setBatchDraft({ ...batchDraft, masterTz: tz })}
          />
          <DateShift delta={batchDraft.dateShift} setDelta={(d) => setBatchDraft({ ...batchDraft, dateShift: d })} />
        </div>

        <div className="section">
          <div className="section-title"><span>Location (master)</span></div>
          <div className="map">
            <MapView photo={batchPhotos[0]} style={mapStyle} />
            <MapPin dir={batchPhotos[0].dir} />
          </div>
          <GeoCells
            lat={batchImages[masterId].lat}
            lon={batchImages[masterId].lon}
            onChange={({lat, lon}) => setBatchDraft({ ...batchDraft, masterLat: lat, masterLon: lon })}
          />
          <PlaceLine place={locCount > 1 ? `${locCount - 1} other location${locCount > 2 ? "s" : ""} in selection` : batchPhotos[0].place} alt={batchPhotos[0].alt} />
        </div>

        <div className="section">
          <div className="section-title">
            <span>Keywords</span>
            <span className="edit mono">{commonKeywords.length} all · {someKeywords.length} some</span>
          </div>
          <BatchKeywordChips
            commonKeywords={commonKeywords}
            someKeywords={someKeywords}
            onAddAll={onAddAll}
            onRemoveAll={onRemoveAll}
            onPromoteToAll={onPromoteToAll}
          />
          <div className="dim" style={{ fontSize: 10.5 }}>
            <span className="scope-dot" style={{ display: "inline-block", marginRight: 4, background: "var(--accent)" }}></span>
            in all · <span style={{ opacity: 0.55 }}>◌</span> in some
          </div>
        </div>
      </div>
    </div>
  );
}

// ── Status bar ──────────────────────────────────────────────────────────────
function StatusBar({ total, selected, batch, savedFlash, mode }) {
  return (
    <div className="statusbar">
      <span>{total} items</span>
      <span className="sep">·</span>
      <span>
        {mode === "batch"
          ? `${batch} selected · master = first selected`
          : selected ? `${selected.file}  ·  ${selected.size}` : "no selection"}
      </span>
      <span className="sep">·</span>
      <span className={"saved-flash" + (savedFlash ? " flash" : "")}>
        <span className="check"><Icon name="check" size={8}/></span>
        {savedFlash ? `Auto-saved${savedFlash.count > 1 ? ` to ${savedFlash.count}` : ""}` : "All changes saved"}
      </span>
      <span className="right">
        <span title="All edits go to a sidecar; RAW files are never modified">.xmp sidecar</span>
        <span className="sep">·</span>
        <span>P3 · Display</span>
        <span className="sep">·</span>
        <span>v2.4</span>
      </span>
    </div>
  );
}

// ── Empty state ─────────────────────────────────────────────────────────────
function EmptyState() {
  return (
    <div className="empty">
      <div className="empty-card">
        <div className="empty-icon">
          <svg width="32" height="32" viewBox="0 0 32 32" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 9 V25 a2 2 0 0 0 2 2 H27 a2 2 0 0 0 2 -2 V11 a2 2 0 0 0 -2 -2 H16 L13 6 H5 a2 2 0 0 0 -2 2 Z"/>
            <path d="M11 18 L14.5 21.5 L21 15"/>
          </svg>
        </div>
        <div>
          <div className="empty-title">Point Metadater at a folder of images</div>
          <div className="empty-sub">
            Drag any folder onto the window, or use ⌘O to choose one. Metadater reads EXIF, IPTC and XMP from each image and writes your edits to a <b>.xmp sidecar</b> alongside the original — RAW files are never modified.
          </div>
        </div>
        <div className="empty-actions">
          <div className="tb-btn primary"><Icon name="folder" size={13}/><span>Choose folder…</span></div>
          <div className="tb-btn"><span>Open recent</span><span className="caret">▾</span></div>
        </div>
      </div>
    </div>
  );
}

// ── Batch center (preview area) ─────────────────────────────────────────────
function BatchCenter({ batchPhotos }) {
  // Render master on top of the stack (last in DOM order).
  const sample = batchPhotos.slice(0, 3).reverse();
  return (
    <div className="batch-overlay">
      <div>
        <div className="batch-stack">
          {sample.map((p) => (
            <div key={p.id} className="card"><PhotoSVG photo={p}/></div>
          ))}
        </div>
        <div className="batch-label">
          <b>{batchPhotos.length} images</b> · master is <b className="mono">{batchPhotos[0]?.id}</b> — its values prefill the editors below.
        </div>
      </div>
    </div>
  );
}

// ── Batch caption block ─────────────────────────────────────────────────────
function BatchCaptionBlock({ master, batchDraft, setBatchDraft }) {
  const hLen = batchDraft.headline.length;
  const cLen = batchDraft.captionMode === "replace" ? batchDraft.captionReplace.length : batchDraft.captionAppend.length;
  return (
    <div className="caption-block">
      <div className="headline-row">
        <span className="field-label">Headline</span>
        <input
          className="headline-input"
          value={batchDraft.headline}
          onChange={(e) => setBatchDraft({ ...batchDraft, headline: e.target.value })}
        />
        <span className={"glyph-count " + (hLen > 40 ? "over" : hLen >= 36 ? "warn" : "")}>{hLen}/40</span>
      </div>
      <div className="caption-input-row">
        <span className="field-label" style={{ paddingTop: 3, display: "flex", flexDirection: "column", gap: 4 }}>
          <span>Caption</span>
          <div className="mode-pill" style={{ marginTop: 2 }}>
            <button className={batchDraft.captionMode === "replace" ? "on" : ""}
                    onClick={() => setBatchDraft({ ...batchDraft, captionMode: "replace" })}>Replace</button>
            <button className={batchDraft.captionMode === "append" ? "on" : ""}
                    onClick={() => setBatchDraft({ ...batchDraft, captionMode: "append" })}>Append</button>
          </div>
        </span>
        {batchDraft.captionMode === "replace" ? (
          <textarea
            className="caption-input"
            value={batchDraft.captionReplace}
            onChange={(e) => setBatchDraft({ ...batchDraft, captionReplace: e.target.value })}
          />
        ) : (
          <div className="caption-stack">
            <div className="caption-master" title="Master caption (locked in append mode)">
              {master.caption}
            </div>
            <textarea
              className="caption-append-input"
              placeholder="Text to append to every caption…"
              value={batchDraft.captionAppend}
              onChange={(e) => setBatchDraft({ ...batchDraft, captionAppend: e.target.value })}
            />
          </div>
        )}
        <div className="caption-meta">
          <span>{cLen}</span>
          <span>chars</span>
        </div>
      </div>
    </div>
  );
}

// ── Root ────────────────────────────────────────────────────────────────────
function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const photos = window.PHOTOS;
  const folder = window.FOLDER;

  // Expose tweak setter for screenshots / verification.
  useEffect(() => { window.__setTweak = setTweak; }, [setTweak]);

  // Theme onto root
  useEffect(() => {
    document.documentElement.setAttribute("data-theme", t.theme || "dark");
  }, [t.theme]);

  // Image edit state (single source of truth)
  const initial = useMemo(() => makeInitial(photos), [photos]);
  const [images, setImages] = useState(initial);

  // Selection
  const [selectedId, setSelectedId] = useState("DSC_0421");
  // Order matters: batchOrder[0] is the master.
  const [batchOrder, setBatchOrder] = useState(["DSC_0421", "DSC_0312", "DSC_0244"]);
  const batchSet = useMemo(() => new Set(batchOrder), [batchOrder]);
  const masterId = batchOrder[0];

  const batchMode = t.appState === "batch";
  const emptyMode = t.appState === "empty";

  // Saved flash
  const [savedFlash, setSavedFlash] = useState(null);
  const flashTimer = useRef(null);
  const flashSaved = (count) => {
    if (flashTimer.current) clearTimeout(flashTimer.current);
    setSavedFlash({ count });
    flashTimer.current = setTimeout(() => setSavedFlash(null), 1100);
  };

  // Track dirty per id (for selection-change auto-save)
  const [dirty, setDirty] = useState(new Set());

  // Zoom (fit / 1:1)
  const [zoom, setZoom] = useState("fit");

  // Single-image update
  const updateImage = (id, patch) => {
    setImages(prev => ({ ...prev, [id]: { ...prev[id], ...patch } }));
    setDirty(prev => new Set([...prev, id]));
  };

  // Auto-save on selection change
  const prevSel = useRef(selectedId);
  useEffect(() => {
    if (prevSel.current !== selectedId) {
      if (dirty.has(prevSel.current)) {
        flashSaved(1);
        setDirty(prev => { const n = new Set(prev); n.delete(prevSel.current); return n; });
      }
      prevSel.current = selectedId;
    }
  }, [selectedId]); // eslint-disable-line react-hooks/exhaustive-deps

  // Auto-save on tab hide (proxy for program exit)
  useEffect(() => {
    const onHide = () => {
      if (dirty.size > 0) {
        flashSaved(dirty.size);
        setDirty(new Set());
      }
    };
    document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") onHide(); });
    return () => document.removeEventListener("visibilitychange", onHide);
  }, [dirty]);

  // Keyboard shortcuts: , = fit, . = 1:1
  useEffect(() => {
    const onKey = (e) => {
      const target = e.target;
      if (target && (target.matches?.("input, textarea, select, [contenteditable=true]"))) return;
      if (e.key === ",") { e.preventDefault(); setZoom("fit"); }
      else if (e.key === ".") { e.preventDefault(); setZoom("1:1"); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // ── Batch state ──
  const [batchDraft, setBatchDraft] = useState({
    headline: "",
    captionMode: "replace",
    captionReplace: "",
    captionAppend: "",
    dateShift: { hours: 0, minutes: 0 },
    masterDate: null,
    masterTz: null,
  });

  // Reset batchDraft from master when entering batch mode or master changes
  const prevMasterIdRef = useRef(null);
  useEffect(() => {
    if (!batchMode || !masterId) { prevMasterIdRef.current = null; return; }
    if (prevMasterIdRef.current === masterId) return;
    const m = images[masterId];
    setBatchDraft({
      headline: m.headline,
      captionMode: "replace",
      captionReplace: m.caption,
      captionAppend: "",
      dateShift: { hours: 0, minutes: 0 },
      masterDate: m.date,
      masterTz: m.tz,
    });
    prevMasterIdRef.current = masterId;
  }, [batchMode, masterId, images]);

  const batchPhotos = useMemo(
    () => batchOrder.map(id => photos.find(p => p.id === id)).filter(Boolean),
    [photos, batchOrder]
  );

  // Common / some keyword scope (union vs intersection)
  const { commonKeywords, someKeywords } = useMemo(() => {
    if (!batchMode || batchPhotos.length === 0) return { commonKeywords: [], someKeywords: [] };
    const ids = batchOrder;
    const all = new Set();
    ids.forEach(id => images[id]?.keywords.forEach(k => all.add(k)));
    const common = [];
    const some = [];
    [...all].forEach(k => {
      const cnt = ids.reduce((s, id) => s + (images[id]?.keywords.includes(k) ? 1 : 0), 0);
      if (cnt === ids.length) common.push(k);
      else some.push(k);
    });
    return { commonKeywords: common.sort(), someKeywords: some.sort() };
  }, [batchMode, batchPhotos, batchOrder, images]);

  const addKeywordToAll = (k) => {
    const next = { ...images };
    let changed = 0;
    batchOrder.forEach(id => {
      if (!next[id].keywords.includes(k)) {
        next[id] = { ...next[id], keywords: [...next[id].keywords, k] };
        changed++;
      }
    });
    if (!changed) return;
    setImages(next);
    flashSaved(changed);
  };
  const removeKeywordFromAll = (k) => {
    const next = { ...images };
    let changed = 0;
    batchOrder.forEach(id => {
      if (next[id].keywords.includes(k)) {
        next[id] = { ...next[id], keywords: next[id].keywords.filter(x => x !== k) };
        changed++;
      }
    });
    if (!changed) return;
    setImages(next);
    flashSaved(changed);
  };
  const promoteKeywordToAll = (k) => addKeywordToAll(k);

  // Apply batch caption / headline / date — auto-fires when batchDraft changes
  // semantically (e.g. headline edit). For the mockup we apply when the user
  // toggles back to single mode (or on explicit Apply via Save click).
  const applyBatchDraft = useCallback(() => {
    const m = images[masterId];
    if (!m) return;
    const next = { ...images };
    let changed = 0;
    const { dateShift } = batchDraft;

    batchOrder.forEach(id => {
      const cur = next[id];
      const patch = {};
      if (batchDraft.headline !== m.headline || batchDraft.headline !== cur.headline) {
        if (cur.headline !== batchDraft.headline) patch.headline = batchDraft.headline;
      }
      if (batchDraft.captionMode === "replace") {
        if (cur.caption !== batchDraft.captionReplace) patch.caption = batchDraft.captionReplace;
      } else if (batchDraft.captionAppend) {
        patch.caption = (cur.caption || "") + batchDraft.captionAppend;
      }
      if (dateShift.hours || dateShift.minutes) {
        patch.date = shiftDate(cur.date, dateShift.hours, dateShift.minutes);
      }
      if (Object.keys(patch).length) {
        next[id] = { ...cur, ...patch };
        changed++;
      }
    });
    if (!changed) return;
    setImages(next);
    flashSaved(changed);
    setBatchDraft(d => ({ ...d, captionAppend: "", dateShift: { hours: 0, minutes: 0 } }));
  }, [batchDraft, batchOrder, images, masterId]);

  // Selection handlers
  const onSelect = (id) => setSelectedId(id);
  const onToggleBatch = (id) => {
    setBatchOrder(prev => {
      if (prev.includes(id)) return prev.filter(x => x !== id);
      return [...prev, id];
    });
  };

  const photo = photos.find(p => p.id === selectedId);
  const image = images[selectedId];

  return (
    <div className="scene-wrap">
      <SceneScaler>
        <div className="scene">
          <Menubar />

          <div className="window">
            <Titlebar
              folder={emptyMode ? null : folder}
              browserMode={t.browserMode}
              setBrowserMode={(v) => setTweak("browserMode", v)}
            />

            <div className="body">
              {/* LEFT */}
              <div className="col col-left">
                <div className="browser-head">
                  <span>{emptyMode ? "Browser" : (folder.name)}</span>
                  <span className="count mono">
                    {emptyMode ? "—" : (batchMode ? `${batchOrder.length} / ${photos.length}` : photos.length)}
                  </span>
                </div>
                <div className="browser-scroll">
                  {emptyMode ? (
                    <div style={{ padding: "40px 8px", textAlign: "center", color: "var(--fg-faint)", fontSize: 11 }}>
                      No folder open
                    </div>
                  ) : (
                    <Browser
                      photos={photos}
                      selectedId={selectedId}
                      batchOrder={batchOrder}
                      onSelect={onSelect}
                      onToggleBatch={onToggleBatch}
                      mode={t.browserMode}
                      density={t.thumbDensity}
                      batchMode={batchMode}
                    />
                  )}
                </div>
              </div>

              {/* CENTER */}
              <div className="col center">
                {emptyMode ? (
                  <EmptyState />
                ) : batchMode ? (
                  <>
                    <BatchCenter batchPhotos={batchPhotos} />
                    <BatchCaptionBlock master={images[masterId]} batchDraft={batchDraft} setBatchDraft={setBatchDraft} />
                  </>
                ) : (
                  <>
                    <PreviewPane photo={photo} zoom={zoom} />
                    <CaptionBlock
                      headline={image?.headline || ""}
                      setHeadline={(v) => updateImage(selectedId, { headline: v })}
                      caption={image?.caption || ""}
                      setCaption={(v) => updateImage(selectedId, { caption: v })}
                    />
                  </>
                )}
              </div>

              {/* RIGHT */}
              <div className="col col-right">
                {emptyMode ? (
                  <div style={{ padding: 20, color: "var(--fg-faint)", fontSize: 11, lineHeight: 1.6 }}>
                    Select an image to inspect its metadata.
                  </div>
                ) : batchMode ? (
                  <MetaPanelBatch
                    batchPhotos={batchPhotos}
                    batchImages={images}
                    masterId={masterId}
                    batchDraft={batchDraft}
                    setBatchDraft={setBatchDraft}
                    mapStyle={t.mapStyle}
                    commonKeywords={commonKeywords}
                    someKeywords={someKeywords}
                    onAddAll={addKeywordToAll}
                    onRemoveAll={removeKeywordFromAll}
                    onPromoteToAll={promoteKeywordToAll}
                  />
                ) : (
                  <MetaPanelSingle
                    photo={photo}
                    image={image}
                    update={(patch) => updateImage(selectedId, patch)}
                    mapStyle={t.mapStyle}
                  />
                )}
              </div>
            </div>

            <StatusBar
              total={emptyMode ? 0 : photos.length}
              selected={emptyMode ? null : photo}
              batch={batchOrder.length}
              savedFlash={savedFlash}
              mode={batchMode ? "batch" : "single"}
            />
          </div>

          <DockHint />
        </div>
      </SceneScaler>

      <GrainDefs />

      <TweaksPanel title="Tweaks">
        <TweakSection label="Theme" />
        <TweakRadio
          label="Appearance"
          value={t.theme}
          options={[
            { value: "dark",  label: "Dark" },
            { value: "light", label: "Light" },
          ]}
          onChange={(v) => setTweak("theme", v)}
        />
        <TweakSection label="State" />
        <TweakRadio
          label="App state"
          value={t.appState}
          options={[
            { value: "empty",    label: "Empty" },
            { value: "browsing", label: "Single" },
            { value: "batch",    label: "Multi" },
          ]}
          onChange={(v) => setTweak("appState", v)}
        />
        <TweakSection label="Browser" />
        <TweakRadio
          label="Mode"
          value={t.browserMode}
          options={[
            { value: "grid", label: "Grid" },
            { value: "list", label: "List" },
          ]}
          onChange={(v) => setTweak("browserMode", v)}
        />
        <TweakRadio
          label="Density"
          value={t.thumbDensity}
          options={[
            { value: "s", label: "S" },
            { value: "m", label: "M" },
            { value: "l", label: "L" },
          ]}
          onChange={(v) => setTweak("thumbDensity", v)}
        />
        <TweakSection label="Map" />
        <TweakSelect
          label="Style"
          value={t.mapStyle}
          options={[
            { value: "topo",      label: "Topo / contours" },
            { value: "minimal",   label: "Minimal grey" },
            { value: "satellite", label: "Satellite (dark)" },
            { value: "pin",       label: "Pin on tint" },
          ]}
          onChange={(v) => setTweak("mapStyle", v)}
        />
        {batchMode && (
          <>
            <TweakSection label="Batch" />
            <TweakButton label="Apply batch edits" onClick={applyBatchDraft} />
          </>
        )}
      </TweaksPanel>
    </div>
  );
}

// ── Dock hint ───────────────────────────────────────────────────────────────
function DockHint() {
  return (
    <div className="dock-hint">
      <div className="di"></div>
      <div className="di"></div>
      <div className="di"></div>
      <div className="di app"></div>
      <div className="di"></div>
      <div className="di"></div>
      <div className="di"></div>
    </div>
  );
}

// ── Scene scaler ────────────────────────────────────────────────────────────
function SceneScaler({ children }) {
  const ref = useRef(null);
  useEffect(() => {
    const fit = () => {
      const el = ref.current;
      if (!el) return;
      const vw = window.innerWidth, vh = window.innerHeight;
      const scale = Math.min(vw / 1280, vh / 800);
      el.style.transform = `translate(-50%, -50%) scale(${scale})`;
      document.documentElement.style.setProperty("--dc-inv-zoom", 1 / scale);
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);
  return (
    <div ref={ref} style={{ position: "absolute", left: "50%", top: "50%", transformOrigin: "center center" }}>
      {children}
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
