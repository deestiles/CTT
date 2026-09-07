/* app.js — Catch the Thief web map builder (2D top-down). */
(function () {
  const { GRID_SIZE, LANE_WIDTH, SCHEMA_VERSION, CATEGORY_ORDER, createCatalog } = window.CTT;
  const R = window.CTT.rules;
  const { rotateDirs, rotatedFootprint, coveredCells, buildIndex, canPlace, validate } = R;

  const catalog = createCatalog();
  const byId = Object.fromEntries(catalog.map((d) => [d.id, d]));
  const LAYER_RANK = { surface: 0, structure: 1, prop: 2, vehicle: 3, character: 4 };

  const state = {
    items: [],                 // { id, cell:{x,y}, turns }
    name: "new_map",
    author: "",
    roles: new Set(["police"]),
    bounds: { cols: 24, rows: 24 },
    tool: "place",
    selectedId: "one_way_street",
    turns: 0,
    view: { ox: 60, oy: 60, scale: 30 },
    hover: null,               // {x,y}
    selectedItem: null,
    showArrows: true,
    showSpawns: false,
    undo: [], redo: [],
    lastValidation: null,
    bridge: false,
  };

  // ---------- DOM ----------
  const $ = (id) => document.getElementById(id);
  const canvas = $("grid"), ctx = canvas.getContext("2d");
  const wrap = $("canvasWrap");

  function resizeCanvas() {
    canvas.width = wrap.clientWidth; canvas.height = wrap.clientHeight; draw();
  }
  window.addEventListener("resize", resizeCanvas);

  // ---------- coordinate transforms ----------
  const cellToPx = (cx, cy) => ({ x: cx * state.view.scale + state.view.ox, y: cy * state.view.scale + state.view.oy });
  const pxToCell = (mx, my) => ({
    x: Math.floor((mx - state.view.ox) / state.view.scale),
    y: Math.floor((my - state.view.oy) / state.view.scale),
  });

  // ================= GLYPH DRAWING =================
  function arrow(g, cx, cy, dir, len, col) {
    const v = window.CTT.DIRECTIONS[dir];
    const ex = cx + v.x * len, ey = cy + v.y * len;
    const sx = cx - v.x * len, sy = cy - v.y * len;
    g.strokeStyle = col; g.lineWidth = Math.max(1.5, len * 0.16); g.lineCap = "round";
    g.beginPath(); g.moveTo(sx, sy); g.lineTo(ex, ey); g.stroke();
    const a = len * 0.5, perp = { x: -v.y, y: v.x };
    g.beginPath(); g.moveTo(ex, ey);
    g.lineTo(ex - v.x * a + perp.x * a * 0.7, ey - v.y * a + perp.y * a * 0.7);
    g.moveTo(ex, ey);
    g.lineTo(ex - v.x * a - perp.x * a * 0.7, ey - v.y * a - perp.y * a * 0.7);
    g.stroke();
  }

  function drawStraightRoad(g, def, turns, px, py, W, H, s, showArrows) {
    g.fillStyle = "#3a4048"; g.fillRect(px, py, W, H);
    const ports = rotateDirs(def.connectors, turns);
    const vertical = ports.includes("N") || ports.includes("S");
    const traffic = rotateDirs(def.traffic_directions, turns);
    const fwd = def.module_rules.lanes_forward, rev = def.module_rules.lanes_reverse;
    const lanes = fwd + rev;
    const laneSpanPx = (vertical ? W : H) / lanes;
    // per-lane arrows + dashed same-direction dividers
    for (let i = 0; i < lanes; i++) {
      const isForward = i < fwd;                 // first group forward, second reverse
      const dir = traffic.length === 1 ? traffic[0] : (isForward ? traffic[0] : traffic[1]);
      const laneCenter = (i + 0.5) * laneSpanPx;
      const cx = vertical ? px + laneCenter : px + W / 2;
      const cy = vertical ? py + H / 2 : py + laneCenter;
      if (showArrows && dir) arrow(g, cx, cy, dir, Math.min(s, W, H) * 0.26, "#e9edf1");
    }
    // center divider (solid yellow) between forward and reverse groups
    g.strokeStyle = "#e7c14a"; g.lineWidth = Math.max(1.4, s * 0.05);
    if (rev > 0 && fwd > 0) {
      const d = fwd * laneSpanPx;
      g.beginPath();
      if (vertical) { g.moveTo(px + d, py); g.lineTo(px + d, py + H); }
      else { g.moveTo(px, py + d); g.lineTo(px + W, py + d); }
      g.stroke();
    }
    // dashed dividers between same-direction lanes
    g.strokeStyle = "rgba(230,235,240,.5)"; g.setLineDash([s * 0.18, s * 0.16]); g.lineWidth = 1;
    for (let i = 1; i < lanes; i++) {
      if (i === fwd) continue; // that's the solid center
      const d = i * laneSpanPx;
      g.beginPath();
      if (vertical) { g.moveTo(px + d, py); g.lineTo(px + d, py + H); }
      else { g.moveTo(px, py + d); g.lineTo(px + W, py + d); }
      g.stroke();
    }
    g.setLineDash([]);
  }

  function drawCurveRoad(g, def, turns, px, py, W, H, s, showArrows) {
    g.fillStyle = "#3a4048"; g.fillRect(px, py, W, H);
    const conns = rotateDirs(def.connectors, turns); // two adjacent dirs
    const edgeMid = (dir) => {
      const v = window.CTT.DIRECTIONS[dir];
      return { x: px + W / 2 + v.x * W / 2, y: py + H / 2 + v.y * H / 2 };
    };
    if (conns.length >= 2) {
      const a = edgeMid(conns[0]), b = edgeMid(conns[1]);
      // pivot at the corner shared by the two edges
      const va = window.CTT.DIRECTIONS[conns[0]], vb = window.CTT.DIRECTIONS[conns[1]];
      const corner = { x: px + W / 2 + (va.x + vb.x) * W / 2, y: py + H / 2 + (va.y + vb.y) * H / 2 };
      g.strokeStyle = "#e9edf1"; g.lineWidth = Math.max(1.6, s * 0.08); g.setLineDash([s * 0.2, s * 0.16]);
      g.beginPath(); g.moveTo(a.x, a.y); g.quadraticCurveTo(corner.x, corner.y, b.x, b.y); g.stroke();
      g.setLineDash([]);
      if (showArrows) { const t = 0.5, mx = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * corner.x + t * t * b.x,
        my = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * corner.y + t * t * b.y;
        g.fillStyle = "#e9edf1"; g.beginPath(); g.arc(mx, my, Math.max(2, s * 0.09), 0, 7); g.fill(); }
    }
  }

  function drawIntersection(g, def, turns, px, py, W, H, s) {
    g.fillStyle = "#3a4048"; g.fillRect(px, py, W, H);
    g.strokeStyle = "rgba(230,235,240,.55)"; g.setLineDash([s * 0.16, s * 0.14]); g.lineWidth = 1;
    g.beginPath(); g.moveTo(px + W / 2, py); g.lineTo(px + W / 2, py + H);
    g.moveTo(px, py + H / 2); g.lineTo(px + W, py + H / 2); g.stroke(); g.setLineDash([]);
    g.fillStyle = "rgba(233,193,74,.9)"; g.beginPath(); g.arc(px + W / 2, py + H / 2, Math.max(2, s * 0.08), 0, 7); g.fill();
  }

  function drawItem(g, def, turns, px, py, s, showArrows) {
    const fp = rotatedFootprint(def, turns);
    const W = fp.w * s, H = fp.h * s;
    if (def.category === "Roads") {
      const kind = def.module_rules.kind;
      if (kind === "straight") drawStraightRoad(g, def, turns, px, py, W, H, s, showArrows);
      else if (kind === "curve_90") drawCurveRoad(g, def, turns, px, py, W, H, s, showArrows);
      else drawIntersection(g, def, turns, px, py, W, H, s);
    } else if (def.category === "Sidewalks") {
      g.fillStyle = "#8d8577"; g.fillRect(px, py, W, H);
      g.strokeStyle = "rgba(0,0,0,.25)"; g.lineWidth = 1; g.strokeRect(px + 1, py + 1, W - 2, H - 2);
      if (def.id !== "sidewalk") { // corner: darken the inner quadrant per rotation
        const q = [[0.5, 0.5], [0, 0.5], [0, 0], [0.5, 0]][((turns % 4) + 4) % 4];
        g.fillStyle = "rgba(0,0,0,.18)"; g.fillRect(px + q[0] * W, py + q[1] * H, W / 2, H / 2);
      }
    } else if (def.category === "Buildings") {
      g.fillStyle = "#6d5a86"; g.fillRect(px, py, W, H);
      g.fillStyle = "rgba(255,255,255,.10)"; g.fillRect(px + W * .12, py + H * .12, W * .76, H * .76);
      g.strokeStyle = "#2a2140"; g.lineWidth = 2; g.strokeRect(px + 1, py + 1, W - 2, H - 2);
      // windows
      g.fillStyle = "rgba(255,220,120,.55)";
      for (let a = 0.25; a < 0.9; a += 0.25) for (let b = 0.25; b < 0.9; b += 0.25)
        g.fillRect(px + a * W - s * .05, py + b * H - s * .05, s * .1, s * .1);
    } else if (def.category === "Street Fixtures") {
      const cx = px + W / 2, cy = py + H / 2;
      if (def.id === "street_lamp") {
        g.strokeStyle = "#cbd3dd"; g.lineWidth = Math.max(1.4, s * .06);
        g.beginPath(); g.moveTo(cx, cy + s * .3); g.lineTo(cx, cy - s * .1); g.stroke();
        g.fillStyle = "#ffd66b"; g.beginPath(); g.arc(cx, cy - s * .15, s * .16, 0, 7); g.fill();
      } else {
        g.fillStyle = "#26343b"; g.fillRect(cx - s * .07, cy - s * .3, s * .14, s * .6);
        const cols = ["#ff5a52", "#ffb648", "#57d38c"];
        cols.forEach((c, i) => { g.fillStyle = c; g.beginPath(); g.arc(cx, cy - s * .18 + i * s * .18, s * .07, 0, 7); g.fill(); });
      }
    } else if (def.category === "Vehicles") {
      const cx = px + W / 2, cy = py + H / 2;
      g.save(); g.translate(cx, cy); g.rotate((turns * Math.PI) / 2);
      g.fillStyle = def.id === "police_car" ? "#4aa3ff" : "#c8ccd2";
      g.fillRect(-s * .28, -s * .42, s * .56, s * .84);
      g.fillStyle = "#1a1d22"; g.fillRect(-s * .2, -s * .3, s * .4, s * .22); // windshield
      if (def.id === "police_car") { g.fillStyle = "#ff5a52"; g.fillRect(-s * .18, -s * .04, s * .16, s * .1);
        g.fillStyle = "#4aa3ff"; g.fillRect(s * .02, -s * .04, s * .16, s * .1); }
      g.restore();
    } else if (def.category === "Pedestrians") {
      const cx = px + W / 2, cy = py + H / 2;
      g.fillStyle = "#7ce0b0"; g.beginPath(); g.arc(cx, cy, s * .18, 0, 7); g.fill();
    }
  }

  // ================= MAIN DRAW =================
  function draw() {
    const { scale, ox, oy } = state.view;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#0f1216"; ctx.fillRect(0, 0, canvas.width, canvas.height);

    // play-area guide
    const p0 = cellToPx(0, 0), p1 = cellToPx(state.bounds.cols, state.bounds.rows);
    ctx.fillStyle = "rgba(74,163,255,.05)"; ctx.fillRect(p0.x, p0.y, p1.x - p0.x, p1.y - p0.y);

    // grid lines (visible range)
    const c0 = pxToCell(0, 0), c1 = pxToCell(canvas.width, canvas.height);
    ctx.lineWidth = 1;
    for (let cx = c0.x - 1; cx <= c1.x + 1; cx++) {
      const x = cellToPx(cx, 0).x;
      ctx.strokeStyle = cx === 0 || cx === state.bounds.cols ? "rgba(74,163,255,.45)" : (cx % 5 === 0 ? "rgba(255,255,255,.12)" : "rgba(255,255,255,.05)");
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke();
    }
    for (let cy = c0.y - 1; cy <= c1.y + 1; cy++) {
      const y = cellToPx(0, cy).y;
      ctx.strokeStyle = cy === 0 || cy === state.bounds.rows ? "rgba(74,163,255,.45)" : (cy % 5 === 0 ? "rgba(255,255,255,.12)" : "rgba(255,255,255,.05)");
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke();
    }

    // items sorted by layer
    const sorted = [...state.items].sort((a, b) => LAYER_RANK[byId[a.id].placement_layer] - LAYER_RANK[byId[b.id].placement_layer]);
    for (const it of sorted) {
      const def = byId[it.id]; if (!def) continue;
      const p = cellToPx(it.cell.x, it.cell.y);
      drawItem(ctx, def, it.turns, p.x, p.y, scale, state.showArrows);
    }

    // validation marks
    if (state.lastValidation) {
      for (const [k, m] of state.lastValidation.marks) {
        const [cx, cy] = k.split(",").map(Number); const p = cellToPx(cx, cy);
        ctx.strokeStyle = m.severe ? "rgba(255,90,82,.95)" : "rgba(255,182,72,.95)";
        ctx.lineWidth = 2; ctx.strokeRect(p.x + 1.5, p.y + 1.5, scale - 3, scale - 3);
      }
    }

    // spawn overlays
    if (state.showSpawns && state.lastValidation) {
      const sp = state.lastValidation.spawns;
      ctx.fillStyle = "rgba(74,163,255,.35)";
      for (const v of sp.vehicles) { const p = cellToPx(v.cell[0], v.cell[1]); ctx.fillRect(p.x + scale * .3, p.y + scale * .3, scale * .4, scale * .4); }
      ctx.fillStyle = "rgba(124,224,176,.5)";
      for (const pd of sp.pedestrians) { const p = cellToPx(pd.cell[0], pd.cell[1]); ctx.beginPath(); ctx.arc(p.x + scale / 2, p.y + scale / 2, scale * .12, 0, 7); ctx.fill(); }
    }

    // hover preview
    if (state.hover && state.tool === "place") {
      const def = byId[state.selectedId];
      const ok = canPlace(state.hover, def, state.turns, buildIndex(state.items, byId));
      const fp = rotatedFootprint(def, state.turns);
      const p = cellToPx(state.hover.x, state.hover.y);
      ctx.globalAlpha = 0.6; drawItem(ctx, def, state.turns, p.x, p.y, scale, state.showArrows); ctx.globalAlpha = 1;
      ctx.strokeStyle = ok ? "rgba(87,211,140,.95)" : "rgba(255,90,82,.95)";
      ctx.lineWidth = 2.5; ctx.strokeRect(p.x + 1, p.y + 1, fp.w * scale - 2, fp.h * scale - 2);
    }
    if (state.selectedItem) {
      const it = state.selectedItem, def = byId[it.id], fp = rotatedFootprint(def, it.turns);
      const p = cellToPx(it.cell.x, it.cell.y);
      ctx.strokeStyle = "rgba(74,163,255,.95)"; ctx.lineWidth = 2.5;
      ctx.strokeRect(p.x + 1, p.y + 1, fp.w * scale - 2, fp.h * scale - 2);
    }
  }

  // ================= MUTATION =================
  function pushUndo() { state.undo.push(JSON.stringify(state.items)); if (state.undo.length > 100) state.undo.shift(); state.redo.length = 0; }
  function refreshValidation() {
    state.lastValidation = validate(state.items, byId);
    renderValidation();
  }
  function itemAt(cell) {
    // topmost by layer
    const hits = state.items.filter((it) => coveredCells(it.cell, byId[it.id], it.turns).some((c) => c.x === cell.x && c.y === cell.y));
    hits.sort((a, b) => LAYER_RANK[byId[b.id].placement_layer] - LAYER_RANK[byId[a.id].placement_layer]);
    return hits[0] || null;
  }
  function placeAt(cell) {
    const def = byId[state.selectedId];
    if (!canPlace(cell, def, state.turns, buildIndex(state.items, byId))) { setStatus("Cannot place there (occupied / needs road edge).", "warn"); return false; }
    pushUndo();
    state.items.push({ id: def.id, cell: { x: cell.x, y: cell.y }, turns: state.turns });
    refreshValidation(); return true;
  }
  function eraseAt(cell) {
    const it = itemAt(cell); if (!it) return;
    pushUndo();
    state.items = state.items.filter((x) => x !== it);
    if (state.selectedItem === it) state.selectedItem = null;
    refreshValidation();
  }

  // ================= INTERACTION =================
  let panning = false, painting = false, rightErasing = false, panStart = null, lastPaintCell = null;
  canvas.addEventListener("mousedown", (e) => {
    if (e.button === 1 || (e.button === 0 && e.altKey)) { panning = true; panStart = { x: e.offsetX, y: e.offsetY, ox: state.view.ox, oy: state.view.oy }; e.preventDefault(); return; }
    const cell = pxToCell(e.offsetX, e.offsetY);
    if (e.button === 2) { // right-click deletes, in any tool; hold and drag to erase a run
      rightErasing = true; eraseAt(cell); lastPaintCell = cell; draw(); return;
    }
    if (e.button === 0) {
      if (state.tool === "place") { painting = true; lastPaintCell = null; placeAt(cell); lastPaintCell = cell; }
      else if (state.tool === "erase") { painting = true; eraseAt(cell); lastPaintCell = cell; }
      else { state.selectedItem = itemAt(cell); if (state.selectedItem) { setStatus(`Selected ${byId[state.selectedItem.id].display_name} @ (${state.selectedItem.cell.x},${state.selectedItem.cell.y})`); } }
      draw();
    }
  });
  canvas.addEventListener("mousemove", (e) => {
    const cell = pxToCell(e.offsetX, e.offsetY);
    state.hover = cell;
    $("coords").textContent = `cell (${cell.x}, ${cell.y})  ·  ${(cell.x * 5)}m, ${(cell.y * 5)}m`;
    if (panning) { state.view.ox = panStart.ox + (e.offsetX - panStart.x); state.view.oy = panStart.oy + (e.offsetY - panStart.y); draw(); return; }
    if ((painting || rightErasing) && (!lastPaintCell || lastPaintCell.x !== cell.x || lastPaintCell.y !== cell.y)) {
      if (rightErasing || state.tool === "erase") eraseAt(cell); else if (state.tool === "place") placeAt(cell);
      lastPaintCell = cell;
    }
    draw();
  });
  window.addEventListener("mouseup", () => { panning = false; painting = false; rightErasing = false; });
  canvas.addEventListener("mouseleave", () => { state.hover = null; draw(); });
  canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    const before = pxToCell(e.offsetX, e.offsetY);
    const factor = e.deltaY < 0 ? 1.12 : 1 / 1.12;
    state.view.scale = Math.min(90, Math.max(10, state.view.scale * factor));
    // keep cursor anchored
    const after = cellToPx(before.x, before.y);
    state.view.ox += e.offsetX - after.x; state.view.oy += e.offsetY - after.y;
    draw();
  }, { passive: false });

  // keyboard
  window.addEventListener("keydown", (e) => {
    if (e.target.tagName === "INPUT") return;
    // Arrow keys pan the view around the map (bigger steps with Shift).
    const panStep = (e.shiftKey ? 3 : 1) * Math.max(40, state.view.scale * 1.5);
    if (e.key === "ArrowRight") { state.view.ox -= panStep; e.preventDefault(); draw(); return; }
    if (e.key === "ArrowLeft") { state.view.ox += panStep; e.preventDefault(); draw(); return; }
    if (e.key === "ArrowDown") { state.view.oy -= panStep; e.preventDefault(); draw(); return; }
    if (e.key === "ArrowUp") { state.view.oy += panStep; e.preventDefault(); draw(); return; }
    if (e.key === "r" || e.key === "R") { state.turns = (state.turns + 1) % 4; $("rotdeg").textContent = state.turns * 90 + "°"; draw(); }
    else if (e.key === "1") setTool("place"); else if (e.key === "2") setTool("select"); else if (e.key === "3") setTool("erase");
    else if ((e.ctrlKey || e.metaKey) && e.key === "z") { doUndo(); }
    else if ((e.ctrlKey || e.metaKey) && (e.key === "y" || (e.shiftKey && e.key === "Z"))) { doRedo(); }
    else if ((e.key === "Delete" || e.key === "Backspace") && state.selectedItem) { pushUndo(); state.items = state.items.filter((x) => x !== state.selectedItem); state.selectedItem = null; refreshValidation(); draw(); }
  });

  function doUndo() { if (!state.undo.length) return; state.redo.push(JSON.stringify(state.items)); state.items = JSON.parse(state.undo.pop()); state.selectedItem = null; refreshValidation(); draw(); }
  function doRedo() { if (!state.redo.length) return; state.undo.push(JSON.stringify(state.items)); state.items = JSON.parse(state.redo.pop()); refreshValidation(); draw(); }

  function setTool(t) { state.tool = t; document.querySelectorAll("#tools button").forEach((b) => b.classList.toggle("active", b.dataset.tool === t)); }

  // ================= PALETTE =================
  function buildPalette() {
    const pal = $("palette"); pal.innerHTML = "";
    for (const cat of CATEGORY_ORDER) {
      const defs = catalog.filter((d) => d.category === cat);
      if (!defs.length) continue;
      const group = document.createElement("div"); group.className = "group";
      const h = document.createElement("h4"); h.innerHTML = `<span>${cat}</span><span>▾</span>`;
      const grid = document.createElement("div"); grid.className = "assets";
      h.onclick = () => { grid.style.display = grid.style.display === "none" ? "grid" : "none"; };
      group.appendChild(h); group.appendChild(grid);
      for (const def of defs) {
        const card = document.createElement("div"); card.className = "asset"; card.dataset.id = def.id;
        const c = document.createElement("canvas"); const cellPx = 22;
        const fp = def.footprint; c.width = Math.min(4, fp[0]) * cellPx; c.height = Math.min(4, fp[1]) * cellPx;
        const g = c.getContext("2d"); g.fillStyle = "#0f1216"; g.fillRect(0, 0, c.width, c.height);
        drawItem(g, def, 0, 0, 0, c.width / fp[0], true);
        const nm = document.createElement("div"); nm.className = "nm"; nm.textContent = def.display_name;
        const sz = document.createElement("div"); sz.className = "sz"; sz.textContent = `${fp[0]}×${fp[1]} · ${def.placement_layer}`;
        card.appendChild(c); card.appendChild(nm); card.appendChild(sz);
        card.onclick = () => selectAsset(def.id);
        group.querySelector(".assets").appendChild(card);
      }
      pal.appendChild(group);
    }
    highlightSelectedAsset();
  }
  function selectAsset(id) { state.selectedId = id; state.tool = "place"; setTool("place"); highlightSelectedAsset(); setStatus(`Selected: ${byId[id].display_name}`); draw(); }
  function highlightSelectedAsset() { document.querySelectorAll(".asset").forEach((a) => a.classList.toggle("sel", a.dataset.id === state.selectedId)); }

  // ================= VALIDATION PANEL =================
  function renderValidation() {
    const r = state.lastValidation.result;
    const rows = [
      ["Vehicle spawns", r.vehicle_spawn_candidates, r.vehicle_spawn_candidates < 2],
      ["Pedestrian spawns", r.pedestrian_spawn_candidates, false],
      ["Open road ends", r.dangling_ports, r.dangling_ports > 0],
      ["Lane mismatches", r.lane_mismatches, r.lane_mismatches > 0],
      ["Direction conflicts", r.direction_conflicts, r.direction_conflicts > 0],
      ["Disconnected roads", r.disconnected_roads, r.disconnected_roads > 0],
      ["Misoriented fixtures", r.misoriented_fixtures, r.misoriented_fixtures > 0],
    ];
    $("vstats").innerHTML = rows.map(([n, v, bad]) => `<div>${n}</div><div class="n ${bad ? "bad" : "ok"}">${v}</div>`).join("");
    const pill = $("validPill");
    if (r.valid) { pill.className = "pill ok"; pill.textContent = "VALID MAP"; }
    else { pill.className = "pill bad"; pill.textContent = `${r.issues} ISSUE${r.issues === 1 ? "" : "S"}`; }
    // issue list
    const counts = {};
    for (const [, m] of state.lastValidation.marks) counts[m.reason] = (counts[m.reason] || 0) + 1;
    $("issues").innerHTML = Object.keys(counts).length
      ? Object.entries(counts).map(([k, v]) => `<div class="row">${k} <b>×${v}</b></div>`).join("")
      : `<div class="hint">No placement problems.</div>`;
  }

  function setStatus(msg, kind) { const el = $("statusMsg"); el.textContent = msg; el.style.color = kind === "warn" ? "var(--warn)" : kind === "bad" ? "var(--bad)" : kind === "ok" ? "var(--ok)" : "var(--dim)"; }

  // ================= SERIALIZATION =================
  function computeCamera() {
    const cx = (canvas.width / 2 - state.view.ox) / state.view.scale;
    const cy = (canvas.height / 2 - state.view.oy) / state.view.scale;
    return { x: cx * GRID_SIZE, z: cy * GRID_SIZE, size: (canvas.height / state.view.scale) * GRID_SIZE };
  }
  function buildPayload() {
    const v = validate(state.items, byId);
    return {
      version: SCHEMA_VERSION,
      grid_size: GRID_SIZE,
      lane_width: LANE_WIDTH,
      items: state.items.map((it) => ({ id: it.id, cell: [it.cell.x, it.cell.y], turns: it.turns })),
      camera: computeCamera(),
      spawn_candidates: v.spawns,
      validation: v.result,
      // ---- builder metadata (ignored by the current game loader) ----
      roles: [...state.roles],
      name: state.name,
      author: state.author,
      created: new Date().toISOString(),
      play_area: { cols: state.bounds.cols, rows: state.bounds.rows },
      builder: "web_map_builder",
    };
  }
  function loadPayload(obj) {
    if (!obj || !Array.isArray(obj.items)) { setStatus("Invalid map file.", "bad"); return; }
    pushUndo();
    state.items = obj.items.filter((it) => it && byId[it.id] && Array.isArray(it.cell))
      .map((it) => ({ id: it.id, cell: { x: it.cell[0] | 0, y: it.cell[1] | 0 }, turns: ((it.turns | 0) % 4 + 4) % 4 }));
    if (obj.name) { state.name = obj.name; $("mapName").value = obj.name; }
    if (obj.author) { state.author = obj.author; $("mapAuthor").value = obj.author; }
    if (Array.isArray(obj.roles)) { state.roles = new Set(obj.roles); syncRoleButtons(); }
    if (obj.play_area) { state.bounds = { cols: obj.play_area.cols | 0 || 24, rows: obj.play_area.rows | 0 || 24 }; }
    state.selectedItem = null; refreshValidation(); fitView(); draw();
    setStatus(`Loaded ${state.items.length} objects.`, "ok");
  }
  function fitView() {
    if (!state.items.length) { state.view = { ox: 60, oy: 60, scale: 30 }; return; }
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const it of state.items) for (const c of coveredCells(it.cell, byId[it.id], it.turns)) { minX = Math.min(minX, c.x); minY = Math.min(minY, c.y); maxX = Math.max(maxX, c.x + 1); maxY = Math.max(maxY, c.y + 1); }
    const scale = Math.max(12, Math.min(60, Math.min(canvas.width / (maxX - minX + 4), canvas.height / (maxY - minY + 4))));
    state.view = { scale, ox: canvas.width / 2 - ((minX + maxX) / 2) * scale, oy: canvas.height / 2 - ((minY + maxY) / 2) * scale };
  }

  // ================= BRIDGE / IO =================
  const BRIDGE = (window.CTT_BRIDGE || "").replace(/\/$/, "");
  async function api(path, opts) { return fetch(`${BRIDGE}/api/${path}`, opts); }
  async function probeBridge() {
    try { const r = await api("ping"); if (r.ok) { state.bridge = true; $("bridge").className = "bridge on"; $("bridge").textContent = "● bridge online"; return; } } catch (e) {}
    state.bridge = false; $("bridge").className = "bridge off"; $("bridge").textContent = "● bridge offline (Export/Import)";
  }
  async function saveMap() {
    state.name = $("mapName").value.trim() || "new_map";
    const payload = buildPayload();
    if (!payload.validation.valid && !confirm(`This map has ${payload.validation.issues} validation issue(s). Save anyway?`)) return;
    if (state.bridge) {
      try {
        const r = await api("save", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name: state.name, map: payload }) });
        const j = await r.json();
        if (j.ok) { setStatus(`Saved to ${j.written.join(" & ")}`, "ok"); return; }
        setStatus("Save failed: " + (j.error || "unknown"), "bad"); return;
      } catch (e) { setStatus("Bridge save error; falling back to download.", "warn"); }
    }
    downloadJSON(state.name + ".json", payload);
    setStatus("Downloaded JSON (bridge offline). Copy into maps/ and user://maps/.", "warn");
  }
  function downloadJSON(filename, obj) {
    const blob = new Blob([JSON.stringify(obj, null, "\t")], { type: "application/json" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = filename; a.click(); URL.revokeObjectURL(a.href);
  }

  // ================= DIALOGS =================
  function openNew() { $("nmName").value = state.name; $("nmCols").value = state.bounds.cols; $("nmRows").value = state.bounds.rows; $("newDialog").showModal(); }
  $("new").onclick = openNew;
  $("nmCancel").onclick = () => $("newDialog").close();
  $("nmCreate").onclick = () => {
    state.name = $("nmName").value.trim() || "new_map"; $("mapName").value = state.name;
    state.bounds = { cols: Math.max(4, +$("nmCols").value | 0), rows: Math.max(4, +$("nmRows").value | 0) };
    state.items = []; state.selectedItem = null; state.undo = []; state.redo = [];
    fitViewToBounds(); refreshValidation(); $("newDialog").close(); draw();
    setStatus(`New ${state.bounds.cols}×${state.bounds.rows} map.`, "ok");
  };
  function fitViewToBounds() {
    const scale = Math.max(12, Math.min(50, Math.min(canvas.width / (state.bounds.cols + 4), canvas.height / (state.bounds.rows + 4))));
    state.view = { scale, ox: canvas.width / 2 - (state.bounds.cols / 2) * scale, oy: canvas.height / 2 - (state.bounds.rows / 2) * scale };
  }

  $("load").onclick = async () => {
    const dlg = $("loadDialog"); const list = $("mapList");
    dlg.showModal();
    if (!state.bridge) { list.innerHTML = `<div class="hint" style="padding:10px">Bridge offline. Use <b>Import</b> to open a .json file instead.</div>`; return; }
    list.innerHTML = `<div class="hint" style="padding:10px">Loading…</div>`;
    try {
      const r = await api("maps"); const j = await r.json();
      if (!j.maps || !j.maps.length) { list.innerHTML = `<div class="hint" style="padding:10px">No maps found.</div>`; return; }
      list.innerHTML = "";
      for (const m of j.maps) {
        const row = document.createElement("div"); row.className = "m";
        row.innerHTML = `<span>${m.name}</span><span class="hint">${m.items} objs${m.roles ? " · " + m.roles.join("/") : ""}</span>`;
        row.onclick = async () => { const rr = await api("map?name=" + encodeURIComponent(m.name)); const mj = await rr.json(); if (mj.ok) { loadPayload(mj.map); dlg.close(); } };
        list.appendChild(row);
      }
    } catch (e) { list.innerHTML = `<div class="hint" style="padding:10px">Error: ${e}</div>`; }
  };
  $("loadCancel").onclick = () => $("loadDialog").close();

  $("save").onclick = saveMap;
  $("export").onclick = () => { state.name = $("mapName").value.trim() || "new_map"; downloadJSON(state.name + ".json", buildPayload()); };
  $("import").onclick = () => $("fileInput").click();
  $("fileInput").onchange = (e) => { const f = e.target.files[0]; if (!f) return; const rd = new FileReader(); rd.onload = () => { try { loadPayload(JSON.parse(rd.result)); } catch (err) { setStatus("Bad JSON: " + err, "bad"); } }; rd.readAsText(f); e.target.value = ""; };

  $("rotate").onclick = () => { state.turns = (state.turns + 1) % 4; $("rotdeg").textContent = state.turns * 90 + "°"; draw(); };
  $("undo").onclick = doUndo; $("redo").onclick = doRedo;
  document.querySelectorAll("#tools button").forEach((b) => b.onclick = () => setTool(b.dataset.tool));
  $("showArrows").onchange = (e) => { state.showArrows = e.target.checked; buildPalette(); draw(); };
  $("showSpawns").onchange = (e) => { state.showSpawns = e.target.checked; draw(); };
  $("mapName").oninput = (e) => state.name = e.target.value;
  $("mapAuthor").oninput = (e) => state.author = e.target.value;
  function syncRoleButtons() { document.querySelectorAll(".roles button").forEach((b) => b.classList.toggle("active", state.roles.has(b.dataset.role))); }
  document.querySelectorAll(".roles button").forEach((b) => b.onclick = () => {
    const role = b.dataset.role;
    if (state.roles.has(role)) { if (state.roles.size > 1) state.roles.delete(role); } else state.roles.add(role);
    syncRoleButtons();
  });

  // ================= INIT =================
  buildPalette();
  resizeCanvas();
  fitViewToBounds();
  refreshValidation();
  probeBridge();
  setStatus("Define a map with New, then drag assets from the left. Press R to rotate.");
  draw();
})();
