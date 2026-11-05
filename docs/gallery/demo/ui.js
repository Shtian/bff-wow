// The addon's frames in HTML, drawn from S. Metrics follow UI/*.lua.
const S = {
  tab: "roster", order: "online", expanded: {}, members: initialMembers(), feed: initialFeed(),
  reacted: { joined: true }, goals: initialGoals(), spares: initialSpares(), feedSeen: false,
  whenMember: null, profSort: null, picked: [], togX: 0, showAlts: false, feedScroll: 0, toasts: [],
};
const esc = (s) => s;
const pic = (kind, size, own) => `<div class="pic" style="width:${size}px;height:${size}px;background:${EDGES[kind] || "#d1ccdb"}8c"><img src="${icon(own || PICTURES[kind])}" style="width:100%;height:100%;clip-path:inset(7%);transform:scale(1.16)" alt=""></div>`;
const reactBtn = (key, reaction) => {
  const done = S.reacted[key];
  return `<div class="react${done ? " done" : ""}" data-hover data-act="react:${key}:${reaction}" data-tip="react:${done ? "done" : reaction}" data-key="${key}"><img src="${icon(REACTIONS[reaction].icon)}" alt=""></div>`;
};
const memberOf = (id) => S.members.find((m) => m.id === id);
const canPlay = (c) => Math.abs(c.level - YOU_LEVEL) <= 3;
const onlineCount = () => S.members.filter((m) => !m.own && m.online).length;
const unseen = () => (S.feedSeen ? 0 : S.feed.filter((e) => e.unseen).length);

const TABS = [["roster", "Roster"], ["feed", "Feed"], ["goals", "Goals"], ["when", "When"], ["spares", "Spares"], ["professions", "Professions"], ["together", "Together"]];
function shell(view) {
  const counts = { feed: S.tab === "feed" ? 0 : unseen(), spares: S.tab === "spares" ? 0 : (S.sparesUnseen || 0) };
  const tabs = TABS.map(([id, label]) => `<div class="tab${S.tab === id ? " on" : ""}" data-hover data-act="tab:${id}"><span>${label}</span>${counts[id] ? `<span class="count">${counts[id]}</span>` : ""}</div>`).join("");
  return `<div class="head"><div class="title">Best Friends in Forever</div><div class="status"><i></i>${onlineCount()} of 3 online</div><div class="close" data-hover data-act="close">✕</div></div>
  <div class="body"><div class="nav">${tabs}<div class="grow"></div><div class="tab" data-hover><span>Settings</span></div></div><div class="view">${view}</div></div>`;
}

// Roster
function rosterRow(m) {
  const c = m.chars.find((x) => x.playing) || m.chars[0];
  const alts = m.chars.filter((x) => x !== c);
  const open = S.expanded[m.id];
  const altsCanPlay = alts.some(canPlay);
  const tags = [m.own ? "you" : m.display, !m.own && canPlay(c) ? `<span class="gold">can play</span>` : ""].filter(Boolean).map((t) => `<span>${t}</span>`).join("");
  const row = `<div class="row${m.own ? " own" : ""}${m.online ? "" : " offline"}" data-hover data-tip="char:${m.id}:${m.chars.indexOf(c)}" data-tip-at="beside" ${alts.length ? `data-act="alts:${m.id}"` : ""} data-row="${m.id}">
    <img class="cls icon" src="${icon(`classicon_${c.cls.toLowerCase()}`)}" alt=""><i class="dot${m.online ? "" : " off"}"></i>
    <div class="line1"><span class="name" style="color:${CLASS[c.cls]}">${c.name}</span><span class="badge">${c.level}</span>${tags}</div>
    <div class="zone">${c.zone}</div>
    ${m.own ? "" : `<div class="seen${m.online ? " on" : ""}">${m.online ? "online" : c.seen}</div>`}
    ${alts.length ? `<div class="more${altsCanPlay ? " gold" : ""}">${open ? "- " : "+ "}${alts.length} more</div>` : ""}
    ${c.xp ? `<div class="xp"><i style="width:${c.xp * 100}%"></i></div>` : ""}
  </div>`;
  const altRows = open ? alts.map((a) => `<div class="alt" data-hover data-tip="char:${m.id}:${m.chars.indexOf(a)}" data-tip-at="beside"><span class="name" style="color:${CLASS[a.cls]}">${a.name}</span><span class="badge">${a.level}</span>${a.main ? "<span>main</span>" : ""}${canPlay(a) ? `<span class="gold">can play</span>` : ""}<span class="right">${a.zone} · ${a.seen || "online"}</span></div>`).join("") : "";
  return row + altRows;
}
function drawRoster() {
  const others = S.members.filter((m) => !m.own);
  const level = (m) => Math.max(...m.chars.map((c) => c.level));
  const sorted = [...others].sort(S.order === "level" ? (a, b) => level(b) - level(a)
    : S.order === "name" ? (a, b) => a.display.localeCompare(b.display)
      : (a, b) => (b.online - a.online) || a.display.localeCompare(b.display));
  const label = { online: "Online first", level: "Level", name: "Name" }[S.order];
  return `<div class="scroll"><div class="inner">${rosterRow(memberOf("you"))}
    <div class="crewhead"><span class="label">CREW</span><hr>${S.sparesForYou ? `<span class="gold" style="font-size:12px">${S.sparesForYou} Spare for you</span>` : ""}<div class="btn small" id="sort" data-hover data-act="menu:sort">Sort: ${label}</div></div>
    ${sorted.map(rosterRow).join("")}</div></div>
    <div class="footer"><span>Crew code</span><div class="code"><span>RJZX-2X4S</span></div><span class="right">Hidden: 1 (unseen 30d)</span></div>`;
}

// Feed
function feedEntry(e) {
  if (e.day) return `<div class="day"><span class="label">${e.day}</span><hr></div>`;
  const given = S.reacted[e.key];
  const names = [...(e.reactors || []), ...(given ? ["<b>You</b>"] : [])];
  const meta = names.length && e.reaction ? `<span><img src="${icon(REACTIONS[e.reaction].icon)}" alt="">${names.join(", ")}</span>` : "";
  const fresh = e.unseen && !S.feedAcked;
  return `<div class="entry${e.own ? " own" : ""}" data-entry="${e.key}">${pic(e.kind, 26, e.icon)}
    <div class="text${e.gold ? " gold" : ""}">${e.text}${fresh ? `<span class="new">NEW</span>` : ""}</div>
    <div class="meta"><span>${e.time}</span>${meta}</div>
    ${e.reaction && !e.noButton && !e.own ? reactBtn(e.key, e.reaction) : ""}</div>`;
}
function drawFeed() {
  return `<div class="scroll" id="feedscroll"><div class="inner" id="feedinner" style="padding-top:12px;transform:translateY(${-S.feedScroll}px)"><div class="feedline"></div>${S.feed.map(feedEntry).join("")}</div><div class="thumb" id="thumb"></div></div>`;
}

// Goals
function medal(m, i) {
  return `<div class="medal" data-hover data-tip="medal:${i}" id="medal${i}"><div class="m" style="border-color:${TIERS[m.tier]}"><img src="${icon(m.icon)}" alt=""><i style="background:${TIERS[m.tier]}"></i></div><div class="v${m.fresh ? " gold" : ""}">${m.value}</div><div class="d">${m.date}</div></div>`;
}
const grouped = (n) => n.toLocaleString("en-US");
function tile(t) {
  return `<div class="gtile" data-tile="${t.id}"><div class="pic" style="background:${t.hue}8c"><img src="${icon(t.icon)}" alt=""></div><h4>${t.title}</h4>
    <div class="nums">${grouped(t.value)} <span>/ ${grouped(t.goal)}</span></div>
    <div class="bar"><i style="width:${(t.shown ?? t.value / t.goal) * 100}%;background:${t.hue}bf"></i></div><div class="cap">${t.cap}</div></div>`;
}
function drawGoals() {
  const g = S.goals;
  return `<div class="plate" id="plate"><div class="pic" style="background:#ffd14a8c"><img src="${icon(g.latest.icon)}" alt=""></div><div><h3>${g.latest.text}</h3><p>${g.latest.sub}</p></div></div>
    <div class="goalhead"><span class="label">TROPHY SHELF</span><hr><span class="count">${g.total}</span></div>
    <div class="shelf">${g.medals.slice(0, 7).map(medal).join("")}<div class="medal" data-hover><div class="m more">+${g.total - 7}</div><div class="v">See all</div><div class="d">${g.total} trophies</div></div></div>
    <div class="goalhead"><span class="label">WORKING ON</span><hr></div>
    <div class="tiles">${g.tiles.map(tile).join("")}</div>`;
}

// When
function shade(value, max) {
  return value <= 0 || max <= 0 ? "rgba(255,255,255,.05)" : `rgba(255,209,74,${0.2 + 0.8 * Math.min(value / max, 1)})`;
}
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
function whenData() {
  const id = S.whenMember;
  if (!id) return { grid: crewGrid(), max: 4, title: "The Crew", intro: "How many of the 4 Members usually play each hour: in 2 of the last 4 weeks. Your local time.", low: "None", high: "Everyone" };
  const name = id === "you" ? "You" : memberOf(id).display;
  return { grid: PLAY[id], max: 4, title: name, member: name, intro: `How many of the last 4 weeks ${id === "you" ? "you" : name} played each hour. Your local time.`, low: "0", high: "4 weeks" };
}
function drawWhen() {
  const v = whenData();
  const hours = Array.from({ length: 24 }, (_, h) => `<span>${h % 3 === 0 ? String(h).padStart(2, "0") : ""}</span>`).join("");
  const rows = v.grid.map((row, d) => `<div class="dayname">${DAYS[d]}</div>` + row.map((value, h) => `<div class="cell" data-hover data-tip="cell:${d}:${h}" data-cell="${d}-${h}" style="background:${shade(value, v.max)}"></div>`).join("")).join("");
  const legend = [0, 1, 2, 3].map((i) => `<i style="background:${shade(i, 3)}"></i>`).join("");
  return `<div class="when"><div><div class="btn small" id="whenpick" data-hover data-act="menu:when" style="display:inline-flex">Show: ${v.title}</div></div>
    <div class="intro">${v.intro}</div><div class="hours"><span></span>${hours}</div><div class="grid">${rows}</div>
    <div class="legend"><span>${v.low}</span>${legend}<span>${v.high}</span></div></div>`;
}

// Spares
function spareRow(s, yours) {
  const buttons = yours
    ? (s.given ? "" : `<div class="btn spare${s.winner ? " primary" : " disabled"}" ${s.winner ? `data-hover data-act="give:${s.id}"` : ""} id="give-${s.id}">Give</div><div class="btn spare" data-hover>Withdraw</div>`)
    : (s.claimed ? `<div class="btn spare" data-hover data-act="unclaim:${s.id}">Withdraw</div>` : `<div class="btn spare primary" data-hover data-act="claim:${s.id}" id="claim-${s.id}">Claim</div>`);
  const info = yours ? s.info : `${s.owner} · ${s.state}`;
  const gold = yours ? s.winner && !s.given : s.claimed;
  return `<div class="srow${s.given ? " dim" : ""}" data-hover data-spare="${s.id}"><img class="icon" src="${icon(s.icon)}" alt="">
    <div class="item"><span style="color:${s.color}">[${s.item}]</span>${s.level ? `<span class="badge">${s.level}</span>` : ""}</div>
    <div class="info${gold ? " gold" : ""}">${info}</div><div class="btns">${buttons}</div></div>`;
}
function drawSpares() {
  const { crew, yours } = S.spares;
  const open = yours.filter((s) => !s.given).length;
  const claims = crew.filter((s) => s.claimed).length;
  return `<div class="scroll"><div class="inner" style="padding-top:4px">
    <div class="section" style="height:28px"><span class="label">FROM THE CREW</span><hr><span class="count">${claims} of 20 Claims</span></div>
    ${crew.map((s) => spareRow(s, false)).join("")}
    <div style="height:6px"></div>
    <div class="section" style="height:28px"><span class="label">YOURS</span><hr><span class="count">${open} of 20 up</span></div>
    <div class="drop" id="drop" data-hover data-act="drop"><div class="slot">+</div><p>Drop an item from your bags here to offer it to your Crew.</p></div>
    ${yours.map((s) => spareRow(s, true)).join("")}
    <div class="note">Offer an item: drop it on the slot above, or type /bff spares add and shift-click it into the chat box. Mail it to the winner, then Give it.</div>
  </div></div>`;
}

// Professions
const rankOf = (skill) => (skill < 75 ? ["Apprentice", 75, 0.11] : skill < 150 ? ["Journeyman", 150, 0.19] : skill < 225 ? ["Expert", 225, 0.29] : ["Artisan", 300, 0.41]);
function drawProfessions() {
  const heads = PROFESSIONS.map(([name, ic], i) => `${i === 9 ? "<span></span>" : ""}<div class="ph${S.profSort === i ? " on" : ""}" data-hover data-tip="proficon:${i}" data-act="profsort:${i}" id="ph${i}"><img src="${icon(ic)}" alt=""></div>`).join("");
  let names = Object.keys(SKILLS);
  if (S.profSort !== null) {
    const p = PROFESSIONS[S.profSort][0];
    names = [...names].sort((a, b) => ((SKILLS[b] || {})[p] || 0) - ((SKILLS[a] || {})[p] || 0));
  }
  const rows = names.map((name) => {
    const skills = SKILLS[name];
    if (!skills) return `<div class="prow"><div class="pn">${name}</div><div class="none">Not shared yet</div></div>`;
    const tiles = PROFESSIONS.map(([p], i) => {
      const skill = skills[p];
      const gap = i === 9 ? "<span></span>" : "";
      if (!skill) return `${gap}<div class="tile" style="background:rgba(255,255,255,.035)"></div>`;
      const [, max, wash] = rankOf(skill);
      return `${gap}<div class="tile" data-hover data-tip="prof:${name}:${i}" data-tile="${name}-${i}" style="background:rgba(255,255,255,${wash})">${skill}<i style="width:${(skill / max) * 100}%"></i></div>`;
    }).join("");
    return `<div class="prow"><div class="pn">${name}</div>${tiles}</div>`;
  }).join("");
  return `<div class="ptable"><div class="phead"><span></span>${heads}</div>${rows}</div>`;
}

// Together: 24px a level, 16px before 1 (Core.TOGETHER_LAYOUT).
const lx = (level) => 16 + (level - 1) * 24;
const closest = (m) => [...m.chars].sort((a, b) => Math.abs(a.level - YOU_LEVEL) - Math.abs(b.level - YOU_LEVEL));
function fits(m, d) { return m.chars.some((c) => c.level >= d.from && c.level <= d.to); }
function drawTogether() {
  const friends = S.members.filter((m) => !m.own);
  const groups = [{ you: true, level: YOU_LEVEL, label: "You", on: true, cls: "MAGE" }];
  for (const m of friends) {
    m.chars.forEach((c) => {
      if (c.main || c.playing || S.showAlts) groups.push({ id: m.id, level: c.level, label: m.display, alt: !c.main, on: m.online && c.playing, cls: c.cls });
    });
  }
  // Each label in the first row where it keeps clear of its neighbours.
  const rowsUsed = [[], [], [], []];
  const placed = groups.sort((a, b) => (b.you ? 1 : 0) - (a.you ? 1 : 0) || b.on - a.on || Math.abs(a.level - YOU_LEVEL) - Math.abs(b.level - YOU_LEVEL)).map((g) => {
    const left = lx(g.level) - 12, right = left + 62 + (g.alt ? 18 : 0);
    const row = rowsUsed.findIndex((used) => used.every(([l, r]) => right + 6 < l || left - 6 > r));
    if (row >= 0) rowsUsed[row].push([left, right]);
    return { ...g, row: Math.max(row, 0), left };
  });
  const ROWS_TOP = 20, ROW = 21, rail = ROWS_TOP + 4 * ROW + 6, axis = rail + 14;
  const labels = placed.map((g) => {
    const y = ROWS_TOP + (3 - g.row) * ROW;
    const faded = S.picked.length && !g.you && !S.picked.includes(g.id);
    return `<div class="stem${faded ? " faded" : ""}" style="left:${lx(g.level)}px;top:${y + 19}px;height:${rail - y - 19}px"></div>
      <div class="fdot${g.on ? " on" : ""}${g.you ? " you" : ""}${faded ? " faded" : ""}" style="left:${lx(g.level)}px;top:${rail}px;background:${CLASS[g.cls]}"></div>
      <div class="fr${faded ? " faded" : ""}" style="left:${g.left}px;top:${y}px" ${g.id ? `data-hover data-act="pick:${g.id}" data-tip="group:${g.id}:${g.level}" data-friend="${g.id}${g.alt ? "-alt" : ""}"` : ""}>${g.on && !g.you ? `<i class="on"></i>` : ""}${g.label}${g.alt ? "<small> alt</small>" : ""} <small>${g.level}</small></div>`;
  }).join("");
  const ticks = [];
  for (let l = 5; l <= 60; l += 5) ticks.push(`<div class="tick" style="left:${lx(l)}px;top:${axis + 3}px">${l}</div>`);
  // Lanes: the bars nearest your level first, each in the first lane with room.
  const lanes = [];
  const order = [...DUNGEONS].sort((a, b) => Math.abs((a.from + a.to) / 2 - YOU_LEVEL) - Math.abs((b.from + b.to) / 2 - YOU_LEVEL));
  const bars = order.map((d) => {
    const who = friends.filter((m) => fits(m, d));
    const width = Math.max((d.to - d.from) * 24, d.name.length * 6.1 + (d.forever ? 30 : 0) + who.length * 7 + 18);
    const left = lx(d.from);
    let lane = lanes.findIndex((end) => end + 6 < left);
    if (lane < 0) { lanes.push(0); lane = lanes.length - 1; }
    lanes[lane] = left + width;
    const youFit = YOU_LEVEL >= d.from && YOU_LEVEL <= d.to;
    const shared = youFit && S.picked.every((id) => fits(memberOf(id), d));
    const faded = S.picked.length && !shared;
    const dots = who.map((m) => { const c = closest(m).find((x) => x.level >= d.from && x.level <= d.to); return `<i style="background:${CLASS[c.cls]}"></i>`; }).join("");
    return `<div class="dbar${youFit ? " fit" : ""}${faded ? " faded" : ""}" data-hover data-tip="bar:${d.name}" data-bar="${d.name}" style="left:${left}px;top:${axis + 26 + lane * 23}px;width:${width}px">${d.name}${d.forever ? `<span class="np">NEW</span>` : ""}<span class="ds">${dots}</span></div>`;
  }).join("");
  const hidden = S.showAlts ? "" : "3 alts hidden";
  const viewW = 515;
  const total = lx(60) + 90;
  const marks = groups.map((g) => `<div class="mk" style="left:${(lx(g.level) / total) * 100}%;background:${CLASS[g.cls]}"></div>`).join("");
  return `<div class="toolbar"><span>As <span style="color:${CLASS.MAGE}">Gahzuria</span> ${YOU_LEVEL}</span>${S.picked.length ? `<div class="btn small" data-hover data-act="unpick">Clear</div>` : ""}<span class="right" style="font-size:14px">${hidden}</span><div class="btn small" id="togshow" data-hover data-act="menu:together">Show</div></div>
    <div class="line"><div class="track" id="track" style="transform:translateX(${-S.togX}px)">
      <div class="band" style="left:${lx(YOU_LEVEL - 3)}px;width:${6 * 24}px"><span>can play</span></div>
      ${labels}<div class="axis" style="top:${axis}px;width:${total}px"></div>${ticks.join("")}${bars}</div></div>
    <div class="overview"><div class="ov">${marks}<div class="win" id="win" style="left:${(S.togX / total) * 100}%;width:${(viewW / total) * 100}%"></div></div></div>`;
}

const VIEWS = { roster: drawRoster, feed: drawFeed, goals: drawGoals, when: drawWhen, spares: drawSpares, professions: drawProfessions, together: drawTogether };
function render() {
  $("#panel").innerHTML = shell(VIEWS[S.tab]());
  placeThumb();
  refreshHover();
}
function placeThumb() {
  const thumb = $("#thumb");
  if (!thumb) return;
  const view = $("#feedscroll").clientHeight, inner = $("#feedinner").scrollHeight + 12;
  const height = view * (view / inner);
  thumb.style.height = `${height}px`;
  thumb.style.top = `${(S.feedScroll / (inner - view)) * (view - height)}px`;
}

// While you were away
function drawAway() {
  const noticed = AWAY.noticed.map((n) => `<div class="nline"><img src="${icon(REACTIONS[n.reaction].icon)}" alt="">${n.text}</div>`).join("");
  const rows = AWAY.rows.map((r) => {
    const tall = r.member && r.character;
    const who = r.member ? `<div class="who"><img src="${icon(`classicon_${r.cls.toLowerCase()}`)}" alt=""><span style="color:${CLASS[r.cls]}">${r.member}</span></div>` : "";
    const ch = r.character || r.label;
    const scale = 90 / 60;
    return `<div class="arow${tall ? " tall" : ""}${r.member ? " first" : ""}">${who}${ch ? `<div class="ch">${ch}</div>` : ""}
      <div class="lv">${r.level}${r.star ? `<svg width="12" height="12" viewBox="0 0 24 24"><path d="M12 1.5l3 7.6 8.2.5-6.3 5.2 2 7.9L12 18.4l-6.9 4.3 2-7.9L.8 9.6 9 9.1z" fill="#ffd93b" stroke="#7a5a00" stroke-width="1.2"/></svg>` : ""}</div>
      <div class="tr"><i style="width:${r.from * scale}px"></i><b style="left:${r.from * scale}px;width:${Math.max(2, (r.level - r.from) * scale)}px"></b></div>
      <div class="gn">${r.gained}</div><div class="dt">${r.deaths || ""}</div>
      <div class="rs">${r.cheer ? reactBtn(r.cheer, "cheer") : `<span class="gap"></span>`}${r.respects ? reactBtn(r.respects, "respects") : `<span class="gap"></span>`}</div></div>`;
  }).join("");
  $("#away").innerHTML = `<div class="head"><div class="title">While you were away</div><div class="close" data-hover data-act="dismiss">✕</div></div>
    <div class="inner"><div class="sec"><span class="label">YOUR CREW NOTICED</span>${noticed}</div>
    <div class="intro">${AWAY.intro}</div>
    <div class="heads"><span class="label" style="left:136px">LEVEL</span><span class="label" style="right:78px">GAINED</span><img src="${icon("inv_misc_bone_humanskull_01")}" alt=""></div>
    ${rows}<div class="btns"><div class="btn" data-hover data-act="dismiss">Dismiss</div><div class="btn primary" id="openfeed" data-hover data-act="openfeed">Open Feed</div></div></div>`;
  refreshHover();
}

// Toasts: 10s each, the clock stops while hovered, and a 0.6s fade at the end.
const TOAST_MS = 10000, TOAST_FADE = 600;
let toastId = 0;
function toast(t) {
  const item = { id: ++toastId, left: t.ms || TOAST_MS, total: t.ms || TOAST_MS, ...t };
  S.toasts.push(item);
  drawToasts();
  return item;
}
function drawToasts() {
  $("#toasts").innerHTML = S.toasts.map((t) => `<div class="toast" data-hover data-toast="${t.id}">${pic(t.kind, 24, t.icon)}<div class="text${t.gold ? " gold" : ""}">${t.text}</div>${t.reaction ? reactBtn(t.key, t.reaction) : ""}<div class="timer"></div></div>`).join("");
  refreshHover();
}
Clock.updates.push((dt) => {
  let gone = false;
  for (const t of S.toasts) {
    const el = $(`[data-toast="${t.id}"]`);
    const hovered = el && el.classList.contains("hover");
    if (!hovered) t.left -= dt;
    if (t.left <= 0) { gone = true; continue; }
    if (el) {
      el.querySelector(".timer").style.width = `${Math.max(1, 300 * (t.left / t.total))}px`;
      el.style.opacity = hovered ? 1 : Math.min(1, t.left / TOAST_FADE);
    }
  }
  if (gone) { S.toasts = S.toasts.filter((t) => t.left > 0); drawToasts(); }
});

function chat(html) {
  const line = document.createElement("div");
  line.innerHTML = `<b>BFF:</b> ${html}`;
  $("#chat").append(line);
}

// Tooltips, by what the hovered thing's data-tip names.
function tipHtml(tip) {
  const [kind, a, b] = tip.split(":");
  const line = (cls, text) => `<div class="${cls}">${text}</div>`;
  if (kind === "mm") {
    return line("h", "Best Friends in Forever") + line("w", `${onlineCount()} of 3 online · 2 can play with you now`)
      + (unseen() ? line("g", `${unseen()} new in Feed`) : "") + line("m", "Click: open BFF. Right-click: options.");
  }
  if (kind === "react") return `<div class="w">${a === "done" ? "You reacted" : REACTIONS[a].name}</div>`;
  if (kind === "char") {
    const m = memberOf(a), c = m.chars[Number(b)];
    const profs = m.own || !SKILLS[m.display] ? "" : Object.entries(SKILLS[m.display]).filter(() => c.main).slice(0, 2).map(([p, s]) => {
      const [rank, max] = rankOf(s);
      const ic = PROFESSIONS.find(([n]) => n === p)[1];
      return `<div class="d"><span><img src="${icon(ic)}" alt="">${p} <span style="color:var(--dim)">${rank}</span></span><span class="m">${s}/${max}</span></div>`;
    }).join("");
    return `<div class="h" style="color:${CLASS[c.cls]}">${c.name}</div>` + line("w", `Level ${c.level} ${CLASS_NAME[c.cls]} ${c.main ? "(Main)" : "(Alt)"}`)
      + line("w", m.own ? "Your Character" : `${m.display}'s Character`) + `<div>${c.zone}</div>` + (c.xp ? line("m", `XP ${Math.floor(c.xp * 100)}%`) : "")
      + line("m", `Deaths: ${c.deaths}`) + (c.gold ? line("m", c.gold) : "") + profs
      + (c.playing ? line("o", m.own ? "Playing now" : "Online now") : line("m", `Last seen ${c.seen}`))
      + (!m.own && canPlay(c) ? line("g", "Within 3 levels of you: can play together") : "");
  }
  if (kind === "cell") {
    const v = whenData(), value = v.grid[a][b], h = Number(b);
    const time = `${DAYS[a]} ${String(h).padStart(2, "0")}:00-${String((h + 1) % 24).padStart(2, "0")}:00`;
    return line("h", time) + line("m", v.member ? `${v.member} played ${value} of the last 4 weeks` : `${value} of 4 Members usually play`);
  }
  if (kind === "prof") {
    const name = a, [p] = PROFESSIONS[b], skill = SKILLS[name][p], [rank, max] = rankOf(skill);
    return line("h", p) + `<div class="d"><span>${name}</span><span class="w">${rank} ${skill}/${max}</span></div>`;
  }
  if (kind === "proficon") return line("h", PROFESSIONS[a][0]) + line("m", "Click to sort by this profession");
  if (kind === "medal") {
    const [title, ...rest] = S.goals.medals[a].tip;
    return line("h", title) + rest.map((t) => line("m", t)).join("");
  }
  if (kind === "bar") {
    const d = DUNGEONS.find((x) => x.name === a);
    const you = YOU_LEVEL < d.from ? `You need ${d.from - YOU_LEVEL} more levels` : YOU_LEVEL > d.to ? "You've outlevelled it" : "You fit";
    const who = S.members.filter((m) => !m.own && fits(m, d)).map((m) => {
      const c = closest(m).find((x) => x.level >= d.from && x.level <= d.to);
      const near = canPlay(c);
      return `<div class="d"><span style="color:${CLASS[c.cls]}">${m.display}${c.main ? "" : " (alt)"}</span><span class="${near ? "g" : "m"}">${near ? "can play" : `fits, ${Math.abs(c.level - YOU_LEVEL)} levels from you`}</span></div>`;
    }).join("");
    return line("h", d.name) + line("m", `Dungeon · Levels ${d.from}-${d.to}`) + (d.forever ? line("g", "New in WoW: Forever") : "") + line("w", you) + who;
  }
  if (kind === "group") {
    const m = memberOf(a), c = m.chars.find((x) => x.level === Number(b));
    const diff = c.level - YOU_LEVEL;
    return `<div class="h">${m.display}</div><div style="color:${CLASS[c.cls]}">${c.name} · ${c.level}${c.main ? "" : " alt"}</div>` + (m.online && c.playing ? line("o", "Online") : "")
      + (canPlay(c) ? line("g", "can play") : line("m", diff > 0 ? `${diff} ahead` : `${-diff} behind`));
  }
  return "";
}
const UI = {
  tooltip(owner) {
    const el = $("#tooltip");
    if (!owner) { el.hidden = true; UI.tipFor = null; return; }
    if (UI.tipFor === owner.dataset.tip) return;
    UI.tipFor = owner.dataset.tip;
    el.innerHTML = tipHtml(owner.dataset.tip);
    el.hidden = false;
    const r = owner.getBoundingClientRect();
    const [ox, oy] = stageOrigin();
    const zoom = 1.5 * fit;
    let x = (r.right - ox) / zoom + 4, y = (r.top - oy) / zoom;
    if (owner.dataset.tipAt === "beside") x = 90 + 640 + 4;
    if (owner.id === "mm") { x = (r.left - ox) / zoom - el.offsetWidth - 8; y += 4; }
    x = Math.min(x, 1280 - el.offsetWidth - 6);
    el.style.left = `${x}px`;
    el.style.top = `${Math.min(y, 720 - el.offsetHeight - 6)}px`;
  },
  closeMenuUnless(action) {
    if (!action || (!action.startsWith("pickmenu") && !action.startsWith("menu"))) $("#menu").hidden = true;
  },
  menu(owner, title, items) {
    const el = $("#menu");
    el.innerHTML = (title ? `<div class="t">${title}</div>` : "") + items.map(([label, act, on]) => `<div class="i${on ? " on" : ""}" data-hover data-act="pickmenu:${act}" data-item="${label}">${label}</div>`).join("");
    el.hidden = false;
    const r = $(owner).getBoundingClientRect();
    const [ox, oy] = stageOrigin();
    const zoom = 1.5 * fit;
    el.style.left = `${(r.left - ox) / zoom}px`;
    el.style.top = `${(r.bottom - oy) / zoom + 2}px`;
  },
  act(action) {
    const [verb, a, b] = action.split(":");
    const ACT = {
      tab() {
        const leavingFeed = S.tab === "feed";
        S.tab = a;
        if (leavingFeed) { S.feedSeen = true; S.feedAcked = true; }
        if (a === "feed") { S.feedScroll = 0; }
        if (a === "spares") S.sparesUnseen = 0;
        if (a === "together" && !S.togInit) { S.togInit = true; S.togX = lx(YOU_LEVEL) - 250; }
        render();
      },
      close() { $("#panel").hidden = true; refreshHover(); },
      mm() {
        const panel = $("#panel");
        panel.hidden = !panel.hidden;
        if (!panel.hidden) render();
        refreshHover();
      },
      alts() { S.expanded[a] = !S.expanded[a]; render(); },
      react() {
        if (S.reacted[a]) return;
        S.reacted[a] = true;
        document.querySelectorAll(`[data-key="${a}"]`).forEach((el) => { el.classList.add("done"); el.dataset.tip = "react:done"; });
        UI.tipFor = null;
        if (!$("#panel").hidden) render();
        if (!$("#away").hidden) drawAway();
        drawToasts();
      },
      dismiss() { $("#away").hidden = true; refreshHover(); },
      openfeed() {
        $("#away").hidden = true;
        $("#panel").hidden = false;
        S.tab = "feed";
        render();
      },
      menu() {
        if (a === "sort") UI.menu("#sort", null, [["Online first", "sort:online", S.order === "online"], ["Level", "sort:level", S.order === "level"], ["Name", "sort:name", S.order === "name"]]);
        if (a === "when") UI.menu("#whenpick", "Show", [["The Crew", "when:", !S.whenMember], ["Simba", "when:simba", S.whenMember === "simba"], ["Simbad", "when:simbad", S.whenMember === "simbad"], ["Simone", "when:simone", S.whenMember === "simone"], ["You", "when:you", S.whenMember === "you"]]);
        if (a === "together") UI.menu("#togshow", "Friends", [["Alts", "alts", S.showAlts]]);
        refreshHover();
      },
      pickmenu() {
        $("#menu").hidden = true;
        if (a === "sort") S.order = b;
        if (a === "when") S.whenMember = b || null;
        if (a === "alts") S.showAlts = !S.showAlts;
        render();
      },
      profsort() { S.profSort = S.profSort === Number(a) ? null : Number(a); render(); },
      pick() { S.picked = S.picked.length === 1 && S.picked[0] === a ? [] : [a]; render(); },
      unpick() { S.picked = []; render(); },
      claim() {
        const s = S.spares.crew.find((x) => x.id === a);
        s.claimed = true; s.state = "You claimed it for Gahzuria";
        render();
      },
      unclaim() {
        const s = S.spares.crew.find((x) => x.id === a);
        s.claimed = false; s.state = "No claims yet";
        render();
      },
      give() {
        const s = S.spares.yours.find((x) => x.id === a);
        const el = $("#popup");
        el.innerHTML = `Give <span style="color:${s.color}">[${s.item}]</span> to ${s.winner}? Do this once you've mailed it: BFF only tells the Crew.<div class="bs"><div class="b" id="yes" data-hover data-act="given:${a}">Yes</div><div class="b" data-hover data-act="nogive">No</div></div>`;
        el.hidden = false;
        refreshHover();
      },
      given() {
        const s = S.spares.yours.find((x) => x.id === a);
        s.given = true; s.info = `Given to ${s.winner} (${s.winner})`;
        $("#popup").hidden = true;
        render();
      },
      nogive() { $("#popup").hidden = true; refreshHover(); },
      drop() {
        if (!UI.dropping) return;
        S.spares.yours.push(UI.dropping);
        chat(`<i>[${UI.dropping.item}]</i> is up for your Crew. See /bff spares.`);
        UI.dropping = null;
        holdItem(null);
        render();
      },
    };
    if (ACT[verb]) ACT[verb]();
  },
};
