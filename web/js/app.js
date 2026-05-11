console.log('app.js starting...');

// Dynamic Library Loader (Bypasses AMD conflicts)
function loadScriptSafe(url, callback) {
    console.log('Loading script safely:', url);
    const oldDefine = window.define;
    window.define = undefined; // Hide Monaco's AMD loader
    
    const script = document.createElement('script');
    script.src = url + '?t=' + Date.now();
    script.async = true;
    script.onload = () => {
        window.define = oldDefine; // Restore loader
        console.log('Script loaded successfully:', url);
        if (callback) callback();
    };
    script.onerror = (e) => {
        window.define = oldDefine;
        console.error('Failed to load script:', url, e);
    };
    document.head.appendChild(script);
}

// Load ForceGraph immediately
loadScriptSafe('https://cdn.jsdelivr.net/npm/force-graph@1.43.0/dist/force-graph.min.js', () => {
    console.log('ForceGraph ready callback triggered.');
});

// Monaco Setup
require.config({ paths: { 'vs': 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.44.0/min/vs' }});

const wsUrl = `ws://${window.location.host}/ws`;
let ws;
try {
    ws = new WebSocket(wsUrl);
} catch (e) {
    console.error('Failed to create WebSocket:', e);
}

const repoMapEl = document.getElementById('repo-map');
const contentEl = document.getElementById('docs-view');
const searchInput = document.getElementById('search-input');
const indexingOverlay = document.getElementById('indexing-overlay');
const indexingBar = document.getElementById('indexing-bar');
const indexingStatus = document.getElementById('indexing-status');

let editor = null;
let skeletonEditor = null;
let graphData = { nodes: [], links: [] };
let graph = null;
let packGraph = null;
let allFilesList = [];
let currentProjectName = "Project";
let favorites = [];
let contextCart = [];
let contextPacks = [];
let currentPackId = null;
let currentPackName = null;

// Settings
let settings = {
    autoDocs: true,
    skeletonOpen: localStorage.getItem('cckit_skeleton_open') === 'true'
};

// Load settings
const savedSettings = localStorage.getItem('cckit_settings');
if (savedSettings) {
    const parsed = JSON.parse(savedSettings);
    settings.autoDocs = parsed.autoDocs;
}

if (ws) {
    ws.onopen = () => {
        console.log('WebSocket Connected');
        send({ type: 'get_map' });
        send({ type: 'get_stats' });
        const autoDocsEl = document.getElementById('setting-auto-docs');
        if (autoDocsEl) autoDocsEl.checked = settings.autoDocs;
        
        setTimeout(handleInitialRoute, 200);
        renderCart();
    };

    ws.onmessage = (event) => {
        try {
            const message = JSON.parse(event.data);
            handleMessage(message);
        } catch (e) {
            console.error('Failed to parse message:', e);
        }
    };
}

// Helper to get ForceGraph regardless of loader
function getForceGraph() {
    if (typeof ForceGraph === 'function') return ForceGraph;
    if (typeof window.ForceGraph === 'function') return window.ForceGraph;
    if (window.ForceGraph && typeof window.ForceGraph.default === 'function') return window.ForceGraph.default;
    return null;
}

// Router
window.onpopstate = () => { handleInitialRoute(); };
function navigate(path, push = true) { 
    if (push && window.location.pathname !== path) { 
        history.pushState(null, '', path); 
    } 
}

function handleInitialRoute() {
    const path = window.location.pathname;
    
    if (path === '/' || path === '/dashboard') { 
        viewDashboard(false); 
    } else if (path === '/grep') { 
        showView('grep', false); 
    } else if (path === '/graph') { 
        showView('graph', false); 
    } else if (path === '/pack') { 
        currentPackId = null;
        currentPackName = null;
        showView('pack', false); 
    } else if (path.startsWith('/pack/')) {
        const id = path.substring(6);
        currentPackId = parseInt(id);
        showView('pack', false);
        send({ type: 'get_pack_details', id: currentPackId });
    } else if (path === '/chat') { 
        showView('chat', false); 
    } else if (path === '/terminal') { 
        showView('terminal', false); 
    } else if (path === '/settings') { 
        showView('settings', false); 
    } else if (path === '/last-context') { 
        viewLastContext(false); 
    } else if (path.startsWith('/file/')) { 
        viewFullFile(path.substring(6), false); 
    } else if (path.startsWith('/file-symbols/')) { 
        viewFile(path.substring(14), false); 
    } else if (path.startsWith('/symbol/')) {
        const decode = decodeURIComponent(path.substring(8));
        const parts = decode.split('/');
        const symbolName = parts[0];
        const filePath = parts.slice(1).join('/');
        viewSymbol(symbolName, filePath, false);
    }
}

function send(data) {
    if (ws && ws.readyState === WebSocket.OPEN) { ws.send(JSON.stringify(data)); }
}

function handleMessage(message) {
    switch (message.type) {
        case 'config': updateConfig(message.data); break;
        case 'map': renderRepoMap(message.data); restoreSidebarState(); break;
        case 'stats':
            if (message.data.favorites) { favorites = message.data.favorites; renderFavorites(); }
            if (message.data.contextPacks) { contextPacks = message.data.contextPacks; renderContextPacks(); }
            renderStats(message.data);
            break;
        case 'favorites_updated': favorites = message.data; renderFavorites(); break;
        case 'packs_updated': 
            contextPacks = message.data; 
            if (currentPackId) {
                const p = contextPacks.find(x => x.id == currentPackId);
                if (p) currentPackName = p.name;
            }
            renderContextPacks(); 
            break;
        case 'pack_details': 
            contextCart = message.data;
            renderCart();
            if (window.location.pathname.startsWith('/pack')) renderPackView();
            break;
        case 'pack_text_preview':
            const previewEl = document.getElementById('pack-text-preview');
            const estimateEl = document.getElementById('embedding-estimate');
            if (previewEl) previewEl.innerText = message.data;
            if (estimateEl) estimateEl.innerText = `Embedding Estimate: ${message.estimate.toFixed(2)}`;
            break;
        case 'expanded_context':
            contextCart = message.data;
            const reasoningEl = document.getElementById('pack-reasoning-summary');
            if (reasoningEl) {
                reasoningEl.style.display = 'block';
                document.getElementById('reasoning-text').innerText = message.reasoning;
            }
            renderCart();
            if (window.location.pathname.startsWith('/pack')) renderPackView();
            break;
        case 'last_context': renderLastContext(message.data); break;
        case 'file_content': renderFileContent(message.data); break;
        case 'skeleton_content': populateSkeleton(message.data); break;
        case 'generated_summary': displaySummary(message.data); break;
        case 'grep_results': renderGrepResults(message.data); break;
        case 'search_results': renderSearchResults(message.data); break;
        case 'symbol_detail': renderSymbolDetail(message.data); break;
        case 'chat_reply':
            const chatHistory = document.getElementById('chat-history');
            if (chatHistory) {
                chatHistory.innerHTML += `<div style="align-self: flex-start; background: white; border: 1px solid var(--border-color); padding: 10px 15px; border-radius: 12px 12px 12px 0; max-width: 80%; line-height: 1.5;">${escapeHtml(message.data).replace(/\\n/g, '<br>')}</div>`;
                chatHistory.scrollTop = chatHistory.scrollHeight;
            }
            break;
        case 'command_output':
            const termOutput = document.getElementById('term-output');
            if (termOutput) {
                termOutput.innerText += message.data;
                termOutput.scrollTop = termOutput.scrollHeight;
            }
            break;
        case 'indexing_start': showIndexing(true); break;
        case 'indexing_progress':
            showIndexing(true);
            const percent = (message.completed / message.total) * 100;
            indexingBar.style.width = `${percent}%`;
            indexingStatus.innerText = `Indexing ${message.file} (${message.completed}/${message.total})`;
            break;
        case 'indexing_finish':
            indexingStatus.innerText = `Finished!`;
            setTimeout(() => { showIndexing(false); send({ type: 'get_map' }); send({ type: 'get_stats' }); }, 1000);
            break;
    }
}

// Context Cart Logic
function addToCart(path, kind, reason = "Directly Added") {
    if (!contextCart.some(i => i.path === path)) {
        contextCart.push({ path, kind, reason });
        renderCart();
        if (window.location.pathname.startsWith('/pack')) renderPackView();
    }
}

function removeFromCart(path) {
    contextCart = contextCart.filter(i => i.path !== path);
    renderCart();
    if (window.location.pathname.startsWith('/pack')) renderPackView();
}

function clearCart() {
    if (confirm("Clear all items from Context Cart?")) {
        contextCart = [];
        currentPackId = null;
        currentPackName = null;
        navigate('/pack');
        const reasoningEl = document.getElementById('pack-reasoning-summary');
        if (reasoningEl) reasoningEl.style.display = 'none';
        renderCart();
        if (window.location.pathname.startsWith('/pack')) renderPackView();
    }
}

function expandContext() {
    if (contextCart.length === 0) return;
    send({ type: 'get_associated_context', items: contextCart });
}

function renderCart() {
    const listEl = document.getElementById('cart-list');
    const countEl = document.getElementById('cart-count');
    if (!listEl || !countEl) return;
    countEl.innerText = contextCart.length;
    if (contextCart.length === 0) {
        listEl.innerHTML = '<div style="padding: 10px 20px; font-size: 0.8rem; color: #888;">Cart is empty.</div>';
        return;
    }
    listEl.innerHTML = contextCart.map(item => {
        const label = item.kind === 'file' ? '📄' : (item.kind === 'symbol' ? '🔶' : '🖥️');
        const name = item.path.includes('::') ? item.path.split('::')[0] : item.path.split('/').pop();
        return `
            <div class="tree-file" style="padding-left: 20px; display: flex; justify-content: space-between; align-items: center;">
                <div class="path-link" title="Reason: ${item.reason}" onclick="${item.kind === 'file' ? `viewFullFile('${item.path}')` : (item.kind === 'symbol' ? `viewSymbol('${item.path.split('::')[0]}', '${item.path.split('::')[1]}')` : '')}">
                    ${label} ${name}
                </div>
                <span onclick="removeFromCart('${item.path}')" style="cursor:pointer; color:#888; padding: 0 5px;">✕</span>
            </div>
        `;
    }).join('');
}

function packCart() {
    if (contextCart.length === 0) return;
    let name = currentPackName;
    if (!name) {
        name = prompt("Enter a name for this context pack:", "Feature Context");
    }
    if (!name) return;
    send({ type: 'save_context_pack', name: name, items: contextCart, description: `Built with ${contextCart.length} items.` });
    send({ type: 'pack_cart', items: contextCart });
    setTimeout(() => viewLastContext(), 500);
}

// Aider Chat & Terminal Runner
function sendChat() {
    const input = document.getElementById('chat-input');
    const history = document.getElementById('chat-history');
    if (!input || !history || !input.value.trim()) return;
    const text = input.value;
    history.innerHTML += `<div style="align-self: flex-end; background: var(--accent-color); color: white; padding: 10px 15px; border-radius: 12px 12px 0 12px; max-width: 80%;">${escapeHtml(text)}</div>`;
    input.value = '';
    send({ type: 'chat_ask', text: text, context: contextCart });
}

function runCommand() {
    const input = document.getElementById('term-input');
    const output = document.getElementById('term-output');
    if (!input || !output || !input.value.trim()) return;
    output.innerText = `Running: ${input.value}\n`;
    send({ type: 'run_command', command: input.value });
}

function addTerminalToCart() {
    const output = document.getElementById('term-output');
    if (output && output.innerText) {
        addToCart('Terminal Output', 'terminal', "Captured failure log");
        alert('Terminal output added to Context Cart!');
    }
}

// Pack View Component
function renderContextPacks() {
    const sideListEl = document.getElementById('packs-list');
    const fullListEl = document.getElementById('saved-packs-full-list');
    if (!sideListEl) return;
    const html = contextPacks.map(p => `
        <div class="tree-file" style="padding-left: 20px; display: flex; justify-content: space-between; align-items: center;">
            <div class="path-link ${p.id == currentPackId ? 'active' : ''}" onclick="loadPack(${p.id})" title="${p.description}">📦 ${p.name}</div>
            <span onclick="deletePack('${p.name}')" style="cursor:pointer; color:#888; padding: 0 5px;">🗑️</span>
        </div>
    `).join('');
    sideListEl.innerHTML = contextPacks.length === 0 ? '<div style="padding: 10px 20px; font-size: 0.8rem; color: #888;">No saved packs.</div>' : html;
    if (fullListEl) {
        fullListEl.innerHTML = contextPacks.map(p => `
            <div style="background: white; border: ${p.id == currentPackId ? '2px solid var(--accent-color)' : '1px solid var(--border-color)'}; padding: 15px; border-radius: 12px; display: flex; flex-direction: column; gap: 10px;">
                <div style="font-weight: 600;">📦 ${p.name}</div>
                <div style="font-size: 0.8rem; color: #86868b;">${p.description}</div>
                <div style="display: flex; gap: 10px; margin-top: 10px;">
                    <button class="action-btn" style="flex: 1; justify-content: center;" onclick="loadPack(${p.id})">Load</button>
                    <button class="action-btn" onclick="deletePack('${p.name}')">✕</button>
                </div>
            </div>
        `).join('');
    }
}

function loadPack(id) {
    if (confirm("Loading this pack will replace your current Context Cart. Continue?")) {
        currentPackId = id;
        const p = contextPacks.find(x => x.id == id);
        if (p) currentPackName = p.name;
        navigate(`/pack/${id}`);
        send({ type: 'get_pack_details', id: id });
        showView('pack', false);
    }
}

function deletePack(name) {
    if (confirm(`Are you sure you want to delete the context pack '${name}'?`)) {
        if (currentPackName === name) {
            currentPackId = null;
            currentPackName = null;
            navigate('/pack');
        }
        send({ type: 'delete_context_pack', name: name });
    }
}

function renderPackView() {
    const listEl = document.getElementById('pack-items-list');
    if (!listEl) return;
    document.getElementById('pack-title').innerText = currentPackName ? `Context Pack: ${currentPackName}` : "Active Context Pack";
    document.getElementById('pack-save-btn').innerText = currentPackId ? "💾 Save Changes" : "📦 Save & Generate";
    if (contextCart.length === 0) {
        listEl.innerHTML = '<div style="padding: 40px; text-align: center; color: #888;">Your context cart is empty.<br>Browse the project and click "➕ Add to Cart" to start building a pack.</div>';
    } else {
        listEl.innerHTML = contextCart.map(item => {
            const isFile = item.kind === 'file';
            const isSymbol = item.kind === 'symbol';
            const name = item.path.includes('::') ? item.path.split('::')[0] : item.path;
            return `
                <div style="padding: 10px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center;">
                    <div>
                        <div class="path-link" style="font-weight: 600;" onclick="${isFile ? `viewFullFile('${item.path}')` : (isSymbol ? `viewSymbol('${item.path.split('::')[0]}', '${item.path.split('::')[1]}')` : '')}">
                            ${isFile ? '📄' : (isSymbol ? '🔶' : '🖥️')} ${name}
                        </div>
                        <div style="font-size: 0.75rem; color: #86868b; margin-top: 4px;">Reason: <i>${item.reason}</i></div>
                    </div>
                    <button class="action-btn" style="padding: 4px 8px;" onclick="removeFromCart('${item.path}')">✕</button>
                </div>
            `;
        }).join('');
    }
    
    // Defer graph update to ensure DOM is ready and library is checked
    setTimeout(updatePackGraph, 200);
    renderContextPacks();
    const surgicalMode = document.getElementById('surgical-mode')?.checked ?? false;
    send({ type: 'get_pack_preview', items: contextCart, surgicalMode: surgicalMode });
}

function updatePackGraph() {
    const container = document.getElementById('pack-graph-container');
    if (!container) return;
    
    const rect = container.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) {
        console.warn('Pack graph container has no dimensions yet.');
        return;
    }

    const nodes = [{ id: 'Context Pack', label: 'Context Pack', group: 'root', val: 12 }];
    const links = [];
    contextCart.forEach(item => {
        const label = item.path.includes('::') ? item.path.split('::')[0] : item.path.split('/').pop();
        nodes.push({ id: item.path, label: label, group: item.kind, val: 8 });
        links.push({ source: 'Context Pack', target: item.path });
    });

    const FG = getForceGraph();
    if (FG) {
        if (!packGraph) {
            console.log('Initializing Pack Graph...');
            packGraph = FG()(container)
                .graphData({ nodes, links })
                .nodeAutoColorBy('group')
                .backgroundColor('rgba(0,0,0,0)')
                .width(rect.width)
                .height(rect.height)
                .nodeCanvasObject((node, ctx, globalScale) => {
                    const label = node.label;
                    const fontSize = 14/globalScale;
                    ctx.font = `${fontSize}px Sans-Serif`;
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillStyle = node.color;
                    ctx.beginPath(); ctx.arc(node.x, node.y, 6, 0, 2 * Math.PI, false); ctx.fill();
                    ctx.fillStyle = 'black';
                    ctx.fillText(label, node.x, node.y + 10);
                })
                .onNodeClick(node => {
                    if (node.group === 'file') viewFullFile(node.id);
                    else if (node.group === 'symbol') viewSymbol(node.id.split('::')[0], node.id.split('::')[1]);
                    showView('docs');
                });
        } else {
            packGraph.graphData({ nodes, links });
            packGraph.width(rect.width).height(rect.height);
        }
    } else {
        container.innerHTML = '<div style="padding: 20px; color: #888; font-size: 0.8rem;">Loading visualization library... (Try refreshing if this persists)</div>';
        setTimeout(updatePackGraph, 1000);
    }
}

// Standard View Components
function updateConfig(config) {
    currentProjectName = config.projectName;
    document.title = `${config.projectName} - Visualizer`;
    const headerTitle = document.querySelector('.nav-header h1');
    if (headerTitle) headerTitle.innerText = config.projectName;
    if (config.readme) {
        contentEl.innerHTML = `
            <div class="readme">
                <div style="display: flex; justify-content: space-between; align-items: center;">
                    <h2>README.md</h2>
                    <div style="display: flex; gap: 10px;">
                        <button class="action-btn" onclick="addToCart('README.md', 'file', 'Initial Project Context')">➕ Add to Cart</button>
                        <button class="action-btn" onclick="openInEditor('README.md')">↗️ Open in Editor</button>
                    </div>
                </div>
                <div style="background: var(--secondary-background); padding: 30px; border-radius: 12px; border: 1px solid var(--border-color); white-space: pre-wrap; font-family: inherit; line-height: 1.6;">${config.readme}</div>
            </div>
        `;
    }
}

function renderRepoMap(files) {
    allFilesList = files;
    if (!files || files.length === 0) { repoMapEl.innerHTML = '<div style="padding:20px; color:#888">No files indexed yet.</div>'; return; }
    const nodes = [{ id: 'Project', label: 'Project', group: 'root', val: 15 }];
    const links = [];
    const folders = new Set();
    files.forEach(file => {
        const shortName = file.path.split('/').pop();
        nodes.push({ id: file.path, label: shortName, group: 'file', val: 5 });
        const parts = file.path.split('/');
        if (parts.length > 1) {
            let pathAcc = "";
            parts.slice(0, -1).forEach(part => {
                const parent = pathAcc || 'Project';
                pathAcc = pathAcc ? `${pathAcc}/${part}` : part;
                if (!folders.has(pathAcc)) { 
                    folders.add(pathAcc); 
                    nodes.push({ id: pathAcc, label: part, group: 'folder', val: 8 }); 
                    links.push({ source: parent, target: pathAcc }); 
                }
            });
            links.push({ source: pathAcc, target: file.path });
        } else { links.push({ source: 'Project', target: file.path }); }
    });
    graphData = { nodes, links };
    
    // Init main graph if on graph view
    if (window.location.pathname === '/graph') setTimeout(initGraph, 200);

    const tree = {};
    files.forEach(file => {
        const parts = file.path.split('/');
        let current = tree;
        parts.forEach((part, i) => { if (!current[part]) { current[part] = i === parts.length - 1 ? { __file: file } : { __folder: true }; } current = current[part]; });
    });
    repoMapEl.innerHTML = renderTreeNode(tree, '');
}

function renderTreeNode(node, parentPath) {
    let html = '';
    const sortedKeys = Object.keys(node).sort((a, b) => { const aIsDir = node[a].__folder; const bIsDir = node[b].__folder; if (aIsDir && !bIsDir) return -1; if (!aIsDir && bIsDir) return 1; return a.localeCompare(b); });
    sortedKeys.forEach(name => {
        if (name === '__folder' || name === '__file') return;
        const child = node[name];
        const fullPath = parentPath ? `${parentPath}/${name}` : name;
        if (child.__folder) {
            const isModule = (parentPath === 'Sources' || parentPath === 'Tests');
            const style = isModule ? 'color: var(--accent-color); font-size: 0.9rem;' : '';
            const clickHandler = isModule ? `viewModuleStats(this, '${fullPath}')` : 'toggleFolder(this)';
            html += `<div class="tree-node"><div class="tree-folder" onclick="${clickHandler}" data-path="${fullPath}" style="${style}">${isModule ? '📦 ' : ''}${name}</div><div class="tree-children">${renderTreeNode(child, fullPath)}</div></div>`;
        } else {
            const ext = name.split('.').pop().toLowerCase();
            html += `<div class="tree-file ${ext} path-link" onclick="viewFullFile('${child.__file.path}')">${name}</div>`;
        }
    });
    return html;
}

function toggleFolder(el) { el.classList.toggle('open'); saveSidebarState(); }
function saveSidebarState() { const openPaths = Array.from(document.querySelectorAll('.tree-folder.open')).map(el => el.getAttribute('data-path')); localStorage.setItem('cckit_open_folders', JSON.stringify(openPaths)); }
function restoreSidebarState() { const saved = localStorage.getItem('cckit_open_folders'); if (!saved) return; const openPaths = JSON.parse(saved); document.querySelectorAll('.tree-folder').forEach(el => { if (openPaths.includes(el.getAttribute('data-path'))) { el.classList.add('open'); } }); }

function renderFavorites() {
    const favsEl = document.getElementById('favorites-list');
    if (!favsEl) return;
    if (favorites.length === 0) { favsEl.innerHTML = '<div style="padding: 10px 20px; font-size: 0.8rem; color: #888;">No favorites yet.</div>'; return; }
    favsEl.innerHTML = favorites.map(f => {
        const isFullFile = f.viewMode === 'full';
        const label = f.kind === 'file' ? '📄' : '🔶';
        const clickHandler = f.kind === 'file' ? (isFullFile ? `viewFullFile('${f.filePath}')` : `viewFile('${f.filePath}')`) : `viewSymbol('${f.name}', '${f.filePath}')`;
        return `<div class="tree-file path-link" style="padding-left: 20px;" onclick="${clickHandler}">${label} ${f.name}</div>`;
    }).join('');
}

function renderStats(stats) {
    const kindList = Object.entries(stats.kindCounts).sort((a, b) => b[1] - a[1]).map(([kind, count]) => `<li><strong>${kind}:</strong> ${count}</li>`).join('');
    contentEl.innerHTML = `<div class="dashboard"><h2>${currentProjectName} Statistics</h2><div class="stats-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-top: 20px;"><div class="stat-card"><h3>Files</h3><div style="font-size: 2rem; font-weight: bold;">${stats.fileCount}</div></div><div class="stat-card"><h3>Symbols</h3><div style="font-size: 2rem; font-weight: bold;">${stats.symbolCount}</div></div><div class="stat-card"><h3>Total Size</h3><div style="font-size: 2rem; font-weight: bold;">${(stats.totalBytes / 1024).toFixed(1)} KB</div></div><div class="stat-card"><h3>Code Lines</h3><div style="font-size: 2rem; font-weight: bold;">${stats.totalCodeLines || 0}</div></div><div class="stat-card"><h3>Doc Lines</h3><div style="font-size: 2rem; font-weight: bold;">${stats.totalDocLines || 0}</div></div></div><div style="margin-top: 40px;"><h3>Symbols by Kind</h3><ul style="list-style: none; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px;">${kindList}</ul></div>${stats.unusedSymbols && stats.unusedSymbols.length > 0 ? `<div style="margin-top: 40px;"><h3>⚠️ Potentially Unused Symbols</h3><div style="background: #fff5f5; border: 1px solid #feb2b2; padding: 20px; border-radius: 8px;"><ul style="list-style: none; padding: 0;">${stats.unusedSymbols.map(s => `<li style="padding: 8px 0; border-bottom: 1px solid #fed7d7; display: flex; justify-content: space-between; align-items: center;"><div><div class="path-link" onclick="viewSymbol('${s.qualifiedName}', '${s.file}')" style="font-weight: 600;">${s.qualifiedName}</div><div class="path-link" style="font-size: 0.75rem;" onclick="viewFile('${s.file}')">${s.file}</div></div><span style="font-size: 0.7rem; background: #feb2b2; color: #c53030; padding: 2px 6px; border-radius: 4px; text-transform: uppercase; font-weight: bold;">${s.kind}</span></li>`).join('')}</ul></div></div>` : ''}</div>`;
}

function viewModuleStats(el, path) { toggleFolder(el); send({ type: 'get_module_stats', path: path }); showView('docs'); }

function getStandardHeader(filePath, actions) {
    const parts = filePath.split('/');
    let title = filePath;
    let subtitle = filePath;
    if (parts.length >= 2) { const module = parts.find(p => p !== 'Sources' && p !== 'Tests') || parts[0]; const fileName = parts[parts.length - 1]; title = `${module} / ${fileName}`; }
    return `<div class="page-header" style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 30px;"><div><h2 style="margin: 0; font-size: 1.8rem;">${title}</h2><div class="path-link" style="font-size: 0.85rem; margin-top: 4px;" onclick="viewFile('${filePath}')">${subtitle}</div></div><div style="display: flex; gap: 10px;">${actions}</div></div>`;
}

function renderSearchResults(data) {
    const semantic = data.semanticMatches || [];
    const files = data.files || [];
    const symbols = data.symbols || [];
    const text = data.textMatches || [];
    
    let html = `<h3>Search Discovery</h3>`;
    
    if (semantic.length > 0) {
        html += `<div style="margin-top: 20px;"><h4>🧠 Semantic Matches</h4><div style="display: grid; gap: 10px;">`;
        html += semantic.map(res => `<div class="search-result" style="background: #f0f7ff; border: 1px solid #c0d9ff;"><div style="display: flex; justify-content: space-between;"><div class="symbol-kind">${res.kind}</div><div style="font-size:0.75rem; color:#004085;">Match: ${(res.score * 100).toFixed(1)}%</div></div><div class="search-result-title path-link" onclick="viewSymbol('${res.symbol}', '${res.file}')">${res.symbol}</div><div class="search-result-path path-link" onclick="viewFullFile('${res.file}')">${res.file}</div></div>`).join('');
        html += `</div></div>`;
    }

    if (files.length > 0) {
        html += `<div style="margin-top: 30px;"><h4>📄 File Matches</h4><div style="display: grid; gap: 10px;">`;
        html += files.map(f => `<div class="search-result"><div style="display: flex; justify-content: space-between;"><div class="symbol-kind">file</div><div style="font-size:0.75rem; color:#888">${f.language}</div></div><div class="search-result-title path-link" onclick="viewFullFile('${f.path}')">${f.path.split('/').pop()}</div><div class="search-result-path path-link" onclick="viewFullFile('${f.path}')">${f.path}</div></div>`).join('');
        html += `</div></div>`;
    }
    
    if (symbols.length > 0) {
        html += `<div style="margin-top: 30px;"><h4>🔶 Symbol Matches</h4><div style="display: grid; gap: 10px;">`;
        html += symbols.map(res => `<div class="search-result"><div style="display: flex; justify-content: space-between;"><div class="symbol-kind">${res.kind}</div><div style="font-size:0.75rem; color:#888">${res.refCount} refs</div></div><div class="search-result-title path-link" onclick="viewSymbol('${res.symbol}', '${res.file}')">${res.symbol}</div><div class="search-result-path path-link" onclick="viewFullFile('${res.file}')">${res.file}</div></div>`).join('');
        html += `</div></div>`;
    }
    
    if (text.length > 0) {
        html += `<div style="margin-top: 30px;"><h4>🔍 Literal Text Matches</h4><div style="display: grid; gap: 10px;">`;
        html += text.map(res => `<div class="search-result" style="padding: 10px; border-radius: 8px; border: 1px solid var(--border-color); background: white;"><div style="display: flex; justify-content: space-between; margin-bottom: 5px;"><div class="path-link" style="font-size: 0.75rem; font-weight: 600;" onclick="viewFullFile('${res.file}')">${res.file} : L${res.line}</div></div><div style="font-family: monospace; font-size: 0.85rem; padding: 5px; background: #f8f9fa; border-radius: 4px;">${escapeHtml(res.content)}</div></div>`).join('');
        html += `</div></div>`;
    }
    
    if (semantic.length === 0 && symbols.length === 0 && text.length === 0) {
        html += `<div style="padding: 40px; text-align: center; color: #888;">No matches found for your query. Try different terms or use 'semantic:' for conceptual search.</div>`;
    }
    
    contentEl.innerHTML = `<div style="padding: 20px;">${html}</div>`;
}

function renderSymbolDetail(symbol) {
    const isFav = isFavorite(symbol.qualifiedName, symbol.filePath);
    const isOpen = settings.skeletonOpen;
    const actions = `<button class="action-btn" onclick="addToCart('${symbol.qualifiedName}::${symbol.filePath}', 'symbol', 'Selected for Implementation')">➕ Add to Cart</button><button class="action-btn" onclick="toggleFavorite('${symbol.qualifiedName}', '${symbol.filePath}', '${symbol.kind}', 'symbol')">${isFav ? '⭐' : '☆'} Favorite</button><button class="action-btn" onclick="requestSummary('${symbol.name}', '${symbol.signature}', '${symbol.filePath}')">✨ Generate Summary</button><button class="action-btn" onclick="openInEditor('${symbol.filePath}')">↗️ Open in Editor</button>`;
    contentEl.innerHTML = `<div class="symbol-detail">${getStandardHeader(symbol.filePath, actions)}<div style="margin-top: 20px; border: 1px solid var(--border-color); border-radius: 8px; overflow: hidden;"><div onclick="toggleSkeleton()" style="background: var(--secondary-background); padding: 10px 15px; cursor: pointer; display: flex; justify-content: space-between; align-items: center; border-bottom: ${isOpen ? '1px solid var(--border-color)' : 'none'}"><span style="font-weight: 600; font-size: 0.9rem;">🦴 File Skeleton</span><span id="skeleton-arrow" style="font-size: 0.8rem; transform: rotate(${isOpen ? '90deg' : '0deg'}); transition: transform 0.2s;">▶</span></div><div id="skeleton-container" style="display: ${isOpen ? 'block' : 'none'}; height: 250px; background: #fff;"></div></div><div style="margin-top: 30px;"><div class="symbol-kind">${symbol.kind}</div><h2 style="margin-top: 0;">${symbol.name}</h2><div class="symbol-signature"><pre><code>${symbol.signature}</code></pre></div></div><div id="ai-summary-container" style="display:none; margin: 20px 0; background: #f0f7ff; border: 1px solid #c0d9ff; padding: 20px; border-radius: 8px;"><div style="display: flex; justify-content: space-between; align-items: center;"><h4 style="margin:0">✨ AI Summary</h4><button class="action-btn" onclick="applyComment('${symbol.filePath}', '${symbol.qualifiedName}')">📝 Add to Source</button></div><p id="ai-summary-text" style="font-size: 0.9rem; line-height: 1.5; color: #004085;"></p></div>${symbol.docComment ? `<div class="doc-comment">${symbol.docComment}</div>` : ''}<div id="monaco-container" style="height: 400px; border: 1px solid var(--border-color); border-radius: 8px; margin-top: 20px;"></div><div style="margin-top: 30px;"><h3>References (${symbol.references ? symbol.references.length : 0})</h3><div style="font-size: 0.85rem; color: #424245; margin-top: 15px;">${symbol.references && symbol.references.length > 0 ? symbol.references.map(r => `<div style="display: flex; justify-content: space-between; align-items: center; padding: 8px 15px; background: var(--secondary-background); border-radius: 8px; margin-bottom: 8px; border: 1px solid var(--border-color);"><div>Used in <strong class="path-link" onclick="viewSymbol('${r.context}', '${r.file}')">${r.context || 'Global'}</strong> (Line ${r.startLine}) in <code class="path-link" onclick="viewFile('${r.file}')">${r.file}</code></div><div style="display:flex; gap:5px"><button class="action-btn" style="padding: 4px 8px; font-size: 0.7rem;" onclick="addToCart('${r.file}', 'file', 'Call Site Reference')">🛒 Add File</button><button class="action-btn" style="padding: 4px 8px; font-size: 0.7rem;" onclick="copyToClipboard('${r.file}:${r.startLine}')">📋 Copy Link</button></div></div>`).join('') : 'No references found.'}</div></div></div>`;
    send({ type: 'get_skeleton', path: symbol.filePath });
    setTimeout(() => initMonaco('monaco-container', symbol.body, 'swift'), 50);
    if (settings.autoDocs && !symbol.docComment) { requestSummary(symbol.name, symbol.signature, symbol.filePath); }
}

function renderFileContent(file) {
    const isFav = isFavorite(file.path, file.path);
    const actions = `<button class="action-btn" onclick="addToCart('${file.path}', 'file', 'Code Review')">➕ Add to Cart</button><button class="action-btn" onclick="toggleFavorite('${file.path}', '${file.path}', 'file', 'full')">${isFav ? '⭐' : '☆'} Favorite</button><button class="action-btn" onclick="viewFile('${file.path}')">🔍 View Symbols</button><button class="action-btn" onclick="openInEditor('${file.path}')">↗️ Open in Editor</button>`;
    
    const ext = file.path.split('.').pop().toLowerCase();
    if (ext === 'md') {
        const rendered = (typeof marked !== 'undefined') ? marked.parse(file.content) : `<pre>${file.content}</pre>`;
        contentEl.innerHTML = `<div class="file-content">${getStandardHeader(file.path, actions)}<div class="markdown-body" style="padding: 30px; background: white; border: 1px solid var(--border-color); border-radius: 8px; margin-top: 20px; line-height: 1.6; overflow-y: auto;">${rendered}</div></div>`;
    } else {
        contentEl.innerHTML = `<div class="file-content">${getStandardHeader(file.path, actions)}<div id="monaco-container" style="height: calc(100vh - 150px); border: 1px solid var(--border-color); border-radius: 8px; margin-top: 20px;"></div></div>`;
        setTimeout(() => initMonaco('monaco-container', file.content, 'swift'), 50);
    }
}

function copyToClipboard(text) { navigator.clipboard.writeText(text).then(() => { const toast = document.createElement('div'); toast.innerText = `Copied: ${text}`; toast.style = 'position: fixed; bottom: 20px; right: 20px; background: #333; color: white; padding: 10px 20px; border-radius: 8px; z-index: 100000; font-size: 0.8rem;'; document.body.appendChild(toast); setTimeout(() => toast.remove(), 2000); }); }
function populateSkeleton(file) { const container = document.getElementById('skeleton-container'); if (!container) return; initMonaco('skeleton-container', file.content, 'swift', true); }

function toggleSkeleton() {
    settings.skeletonOpen = !settings.skeletonOpen; localStorage.setItem('cckit_skeleton_open', settings.skeletonOpen);
    const container = document.getElementById('skeleton-container'); const arrow = document.getElementById('skeleton-arrow');
    if (container && arrow) { container.style.display = settings.skeletonOpen ? 'block' : 'none'; arrow.style.transform = `rotate(${settings.skeletonOpen ? '90deg' : '0deg'})`; if (settings.skeletonOpen && !skeletonEditor) { let path = document.querySelector('.page-header div .path-link')?.innerText; if (path) send({ type: 'get_skeleton', path: path }); } }
}

function isFavorite(name, filePath) { return favorites.some(f => f.name === name && f.filePath === filePath); }
function toggleFavorite(name, filePath, kind, viewMode = 'symbols') { if (isFavorite(name, filePath)) { send({ type: 'remove_favorite', name: name, filePath: filePath }); } else { send({ type: 'add_favorite', name: name, filePath: filePath, kind: kind, viewMode: viewMode }); } const path = window.location.pathname; if (path.startsWith('/file/')) viewFullFile(filePath, false); else if (path.startsWith('/symbol/')) { const parts = decodeURIComponent(path.substring(8)).split('/'); viewSymbol(parts[0], parts.slice(1).join('/'), false); } else if (path.startsWith('/file-symbols/')) viewFile(filePath, false); }
function requestSummary(name, signature, file) { const container = document.getElementById('ai-summary-container'); if (container) container.style.display = 'block'; const textEl = document.getElementById('ai-summary-text'); if (textEl) textEl.innerText = '🤖 Asking Foundation Model...'; send({ type: 'generate_summary', name: name, signature: signature, file: file }); }
function displaySummary(data) { const textEl = document.getElementById('ai-summary-text'); if (textEl) textEl.innerText = data.summary; }
function applyComment(path, name) { const comment = document.getElementById('ai-summary-text').innerText; send({ type: 'apply_doc_comment', path: path, name: name, comment: comment }); alert('Doc comment applied to source code!'); }
function updateSettings() { settings.autoDocs = document.getElementById('setting-auto-docs').checked; localStorage.setItem('cckit_settings', JSON.stringify(settings)); }
function initMonaco(id, content, lang, isSkeleton = false) { require(['vs/editor/editor.main'], function() { const container = document.getElementById(id); if (!container) return; const newEditor = monaco.editor.create(container, { value: content, language: lang, theme: 'vs-light', readOnly: true, minimap: { enabled: !isSkeleton }, automaticLayout: true, scrollBeyondLastLine: false, fontSize: isSkeleton ? 11 : 13, lineNumbers: isSkeleton ? 'off' : 'on' }); if (isSkeleton) { if (skeletonEditor) skeletonEditor.dispose(); skeletonEditor = newEditor; } else { if (editor) editor.dispose(); editor = newEditor; } }); }
function showView(view, push = true) {
    const views = ['docs', 'chat', 'terminal', 'graph', 'settings', 'pack'];
    views.forEach(v => {
        const el = document.getElementById(`${v}-view`);
        if (el) {
            el.style.display = (v === view) ? (v === 'pack' ? 'flex' : 'block') : 'none';
        }
    });
    
    if (view === 'graph') { setTimeout(initGraph, 200); }
    if (view === 'pack') { 
        renderPackView(); 
        // Force graph to fit container after view is flexed
        setTimeout(() => {
            const container = document.getElementById('pack-graph-container');
            if (packGraph && container) {
                const rect = container.getBoundingClientRect();
                packGraph.width(rect.width).height(rect.height);
            }
        }, 300);
    }
    navigate(`/${view}`, push);
}
function initGraph() { 
    const container = document.getElementById('graph-container'); 
    if (!container || !graphData.nodes.length) return; 
    
    const rect = container.getBoundingClientRect();
    if (rect.width === 0 || rect.height === 0) {
        setTimeout(initGraph, 300);
        return;
    }

    const FG = getForceGraph();
    if (FG) { 
        if (!graph) { 
            console.log('Initializing Main Graph...');
            graph = FG()(container)
                .graphData(graphData)
                .nodeAutoColorBy('group')
                .width(rect.width)
                .height(rect.height)
                .linkDirectionalParticles(2)
                .linkDirectionalParticleSpeed(d => 0.005)
                .nodeCanvasObject((node, ctx, globalScale) => {
                    const label = node.label || node.id;
                    const fontSize = 12/globalScale;
                    ctx.font = `${fontSize}px Sans-Serif`;
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.fillStyle = node.color;
                    ctx.beginPath(); ctx.arc(node.x, node.y, 5, 0, 2 * Math.PI, false); ctx.fill();
                    ctx.fillStyle = 'black';
                    ctx.fillText(label, node.x, node.y + 8);
                })
                .onNodeClick(node => { if (node.group === 'file') viewFile(node.id); else if (node.group === 'root') viewDashboard(); showView('docs'); }); 
        } else { 
            graph.graphData(graphData); 
            graph.width(rect.width).height(rect.height);
        } 
    } else {
        console.warn('ForceGraph not loaded for main graph, retrying...');
        setTimeout(initGraph, 1000);
    }
}
function escapeHtml(unsafe) { return unsafe.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;"); }
if (searchInput) { 
    searchInput.placeholder = "Search symbols (use 'semantic:' for meaning search)...";
    searchInput.onkeypress = (e) => { 
        if (e.key === 'Enter') { 
            send({ type: 'search', query: searchInput.value }); 
            showView('docs'); 
        } 
    }; 
}
function viewSymbol(name, filePath, push = true) { send({ type: 'get_symbol', name: name, filePath: filePath }); showView('docs', false); navigate(`/symbol/${encodeURIComponent(name)}/${filePath}`, push); }
function viewFile(path, push = true) { send({ type: 'search', query: `file:${path}` }); showView('docs', false); navigate(`/file-symbols/${path}`, push); }
function viewFullFile(path, push = true) { send({ type: 'get_file_content', path: path }); showView('docs', false); navigate(`/file/${path}`, push); }
function viewSkeleton(path) { send({ type: 'get_skeleton', path: path }); showView('docs'); }
function openInEditor(path) { console.log('Requesting to open file:', path); send({ type: 'open_file', path: path }); }
function viewDashboard(push = true) { send({ type: 'get_stats' }); showView('docs', false); if (window.location.pathname !== '/') navigate('/dashboard', push); }
function viewLastContext(push = true) { send({ type: 'get_last_context' }); showView('docs', false); navigate('/last-context', push); }
function reindexProject() {
    if (confirm("This will scan your entire codebase for changes. Continue?")) {
        send({ type: 'reindex' });
    }
}
function showIndexing(show) { indexingOverlay.style.display = show ? 'flex' : 'none'; }
