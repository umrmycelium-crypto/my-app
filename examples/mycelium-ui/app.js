const state = {
  captures: JSON.parse(localStorage.getItem("mycelium-ui-captures") || "[]")
};

const views = {
  intake: "Intake and sorting",
  truth: "Main mushroom profile",
  projects: "Project focus",
  public: "Public output"
};

const sampleCaptures = [
  "I need the UI to keep my internal feelings visible while turning the wider ambition into projects other people can use.",
  "Create a public concept note about truth-to-output boundaries using fake examples and no private names.",
  "Rotate database credentials if the old environment file was ever pushed. Keep the template public only.",
  "The main mushroom should shape my public image without exposing the raw life profile."
];

const selectors = {
  captureText: document.querySelector("#captureText"),
  captureList: document.querySelector("#captureList"),
  captureTotal: document.querySelector("#captureTotal"),
  privateCount: document.querySelector("#privateCount"),
  publicCount: document.querySelector("#publicCount"),
  secretCount: document.querySelector("#secretCount"),
  relevanceList: document.querySelector("#relevanceList"),
  publicList: document.querySelector("#publicList"),
  heldList: document.querySelector("#heldList"),
  conceptItems: document.querySelector("#conceptItems"),
  exampleItems: document.querySelector("#exampleItems"),
  enterpriseItems: document.querySelector("#enterpriseItems"),
  fileInput: document.querySelector("#fileInput"),
  viewTitle: document.querySelector("#viewTitle")
};

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => setView(button.dataset.view));
});

document.querySelector("#processCapture").addEventListener("click", () => {
  const text = selectors.captureText.value.trim();
  if (!text) return;
  addCapture(text, "pasted note");
  selectors.captureText.value = "";
});

document.querySelector("#addSample").addEventListener("click", () => {
  const text = sampleCaptures[state.captures.length % sampleCaptures.length];
  addCapture(text, "sample capture");
});

document.querySelector("#clearCaptures").addEventListener("click", () => {
  state.captures = [];
  save();
  render();
});

selectors.fileInput.addEventListener("change", async (event) => {
  const files = Array.from(event.target.files || []);
  for (const file of files) {
    if (file.type.startsWith("text/") || file.name.endsWith(".md") || file.name.endsWith(".txt")) {
      const text = await file.text();
      addCapture(text.slice(0, 2500), file.name);
    } else {
      addCapture(`Document received: ${file.name}. Type: ${file.type || "unknown"}. Size: ${file.size} bytes.`, file.name);
    }
  }
  selectors.fileInput.value = "";
});

function setView(view) {
  document.querySelectorAll(".nav-item").forEach((button) => {
    button.classList.toggle("active", button.dataset.view === view);
  });
  document.querySelectorAll(".view").forEach((panel) => {
    panel.classList.toggle("active", panel.id === `view-${view}`);
  });
  selectors.viewTitle.textContent = views[view];
}

function addCapture(text, source) {
  const capture = classifyCapture(text, source);
  state.captures.unshift(capture);
  save();
  render();
}

function classifyCapture(text, source) {
  const lowered = text.toLowerCase();
  const secretTerms = ["password", "token", "key", "credential", "secret", ".env", "oauth", "certificate"];
  const privateTerms = ["feeling", "life", "private", "family", "personal", "main mushroom", "truth", "profile"];
  const publicTerms = ["public", "concept", "example", "template", "architecture", "pattern", "demo"];
  const enterpriseTerms = ["enterprise", "deploy", "compliance", "runbook", "production", "credentials", "rotate"];

  const hasSecret = secretTerms.some((term) => lowered.includes(term));
  const isPrivate = privateTerms.some((term) => lowered.includes(term));
  const isPublic = publicTerms.some((term) => lowered.includes(term)) && !hasSecret;
  const isEnterprise = enterpriseTerms.some((term) => lowered.includes(term));

  let boundary = "private";
  if (hasSecret) boundary = "secret";
  else if (isPublic && !isPrivate) boundary = "public";

  let lane = "concepts";
  if (lowered.includes("example") || lowered.includes("demo") || lowered.includes("template")) lane = "examples";
  if (isEnterprise) lane = "enterprise";

  const relevance = deriveRelevance(boundary, lane, lowered);

  return {
    id: crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`,
    title: titleFromText(text, source),
    source,
    text,
    boundary,
    lane,
    relevance,
    createdAt: new Date().toLocaleString()
  };
}

function deriveRelevance(boundary, lane, lowered) {
  if (boundary === "secret") return "Protects the system from accidental exposure and keeps public work usable.";
  if (lowered.includes("feeling") || lowered.includes("life")) return "Keeps the private signal connected to public direction without publishing the raw source.";
  if (lane === "enterprise") return "Moves a known-working pattern toward a supportable system.";
  if (lane === "examples") return "Turns the idea into something others can try safely.";
  return "Distills private truth into a public-safe concept.";
}

function titleFromText(text, source) {
  const compact = text.replace(/\s+/g, " ").trim();
  if (compact.length > 0) return compact.slice(0, 68);
  return source;
}

function save() {
  localStorage.setItem("mycelium-ui-captures", JSON.stringify(state.captures));
}

function render() {
  const counts = countBoundaries();
  selectors.privateCount.textContent = counts.private;
  selectors.publicCount.textContent = counts.public;
  selectors.secretCount.textContent = counts.secret;
  selectors.captureTotal.textContent = `${state.captures.length} items`;

  renderCaptures(selectors.captureList, state.captures);
  renderRelevance();
  renderProjects();
  renderPublicOutput();
}

function countBoundaries() {
  return state.captures.reduce((acc, item) => {
    acc[item.boundary] += 1;
    return acc;
  }, { private: 0, public: 0, secret: 0 });
}

function renderCaptures(target, items) {
  target.innerHTML = "";
  if (!items.length) {
    target.append(emptyState("No captures yet."));
    return;
  }
  items.forEach((item) => target.append(captureCard(item)));
}

function renderRelevance() {
  selectors.relevanceList.innerHTML = "";
  const privateItems = state.captures.filter((item) => item.boundary !== "public");
  if (!privateItems.length) {
    selectors.relevanceList.append(emptyState("No private relevance to review."));
    return;
  }
  privateItems.forEach((item) => {
    const card = document.createElement("article");
    card.className = "relevance-card";
    card.innerHTML = `<strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.relevance)}</p>`;
    selectors.relevanceList.append(card);
  });
}

function renderProjects() {
  const lanes = {
    concepts: selectors.conceptItems,
    examples: selectors.exampleItems,
    enterprise: selectors.enterpriseItems
  };

  Object.entries(lanes).forEach(([lane, target]) => {
    target.innerHTML = "";
    const items = state.captures.filter((item) => item.lane === lane && item.boundary !== "secret");
    if (!items.length) {
      target.append(emptyState("Nothing assigned."));
      return;
    }
    items.forEach((item) => {
      const card = document.createElement("article");
      card.className = "lane-card";
      card.innerHTML = `<strong>${escapeHtml(item.title)}</strong><p>${escapeHtml(item.relevance)}</p>`;
      target.append(card);
    });
  });
}

function renderPublicOutput() {
  const publicItems = state.captures.filter((item) => item.boundary === "public");
  const heldItems = state.captures.filter((item) => item.boundary !== "public");
  renderCaptures(selectors.publicList, publicItems);
  renderCaptures(selectors.heldList, heldItems);
}

function captureCard(item) {
  const card = document.createElement("article");
  card.className = "capture-card";
  card.innerHTML = `
    <header>
      <strong>${escapeHtml(item.title)}</strong>
      <span class="tag ${item.boundary}">${item.boundary}</span>
    </header>
    <div class="capture-meta">${escapeHtml(item.source)} | ${escapeHtml(item.createdAt)}</div>
    <p>${escapeHtml(item.text.slice(0, 180))}${item.text.length > 180 ? "..." : ""}</p>
    <div class="tag-row">
      <span class="tag process">${escapeHtml(item.lane)}</span>
    </div>
  `;
  return card;
}

function emptyState(text) {
  const div = document.createElement("div");
  div.className = "empty-state";
  div.textContent = text;
  return div;
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

render();
