// ── THE ORANGE ROBOT · Global Leaderboard Client ──
// Talks to the standalone leaderboard Worker (see /leaderboard-worker in the repo).
// Games call LB.submitScore(...) at game end, and LB.renderBoard(...) to display results.

const LB = (function () {
  // ⚠️ Replace this with your deployed Worker URL after running `wrangler deploy`.
  const API_BASE = 'https://orange-robot-leaderboard.victor-cb4.workers.dev';

  async function submitScore(game, initials, score, sats) {
    try {
      const res = await fetch(API_BASE + '/submit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ game, initials, score, sats }),
      });
      if (!res.ok) throw new Error('submit failed: ' + res.status);
      return await res.json();
    } catch (e) {
      console.warn('[leaderboard] submit failed', e);
      return null;
    }
  }

  async function fetchTop(game, limit) {
    try {
      const url = API_BASE + '/leaderboard?game=' + encodeURIComponent(game) + '&limit=' + (limit || 10);
      const res = await fetch(url);
      if (!res.ok) throw new Error('fetch failed: ' + res.status);
      const data = await res.json();
      return (data && data.entries) || [];
    } catch (e) {
      console.warn('[leaderboard] fetch failed', e);
      return null; // null = couldn't reach server (vs [] = reached, just empty)
    }
  }

  function fmtSats(n) {
    n = parseFloat(n) || 0;
    if (n >= 1000000) return (n / 1000000).toFixed(2) + 'M';
    if (n >= 1000) return (n / 1000).toFixed(1) + 'k';
    return n.toFixed(0);
  }

  // Renders a simple ranked list into a container element.
  // entries: [{initials, score, sats}] or [{initials, sats}] for vault
  function renderBoard(containerEl, entries, opts) {
    opts = opts || {};
    const scoreLabel = opts.scoreLabel || 'SCORE';
    const showScore = opts.showScore !== false;

    if (entries === null) {
      containerEl.innerHTML = '<div class="lb-empty">Leaderboard unavailable right now.</div>';
      return;
    }
    if (entries.length === 0) {
      containerEl.innerHTML = '<div class="lb-empty">No scores yet — be the first!</div>';
      return;
    }
    const rows = entries
      .map((e, i) => {
        const rank = i + 1;
        const medal = rank === 1 ? '🥇' : rank === 2 ? '🥈' : rank === 3 ? '🥉' : rank;
        return `
        <div class="lb-row${rank <= 3 ? ' lb-top3' : ''}">
          <span class="lb-rank">${medal}</span>
          <span class="lb-initials">${e.initials}</span>
          ${showScore ? `<span class="lb-score">${(e.score || 0).toLocaleString()}</span>` : ''}
          <span class="lb-sats">${fmtSats(e.sats)} ⚡</span>
        </div>`;
      })
      .join('');
    containerEl.innerHTML = `
      <div class="lb-header">
        <span class="lb-rank">#</span>
        <span class="lb-initials">NAME</span>
        ${showScore ? `<span class="lb-score">${scoreLabel}</span>` : ''}
        <span class="lb-sats">SATS</span>
      </div>
      ${rows}
    `;
  }

  // A small reusable initials-entry prompt. Returns a Promise<string|null>.
  function promptInitials() {
    return new Promise((resolve) => {
      const overlay = document.createElement('div');
      overlay.className = 'lb-prompt-overlay';
      overlay.innerHTML = `
        <div class="lb-prompt-box">
          <div class="lb-prompt-title">ENTER YOUR INITIALS</div>
          <input class="lb-prompt-input" maxlength="3" autocapitalize="characters" autocomplete="off" spellcheck="false" placeholder="ABC" />
          <button class="lb-prompt-btn">SUBMIT TO LEADERBOARD</button>
          <div class="lb-prompt-skip">skip</div>
        </div>`;
      if (!document.getElementById('lb-prompt-style')) {
        const s = document.createElement('style');
        s.id = 'lb-prompt-style';
        s.textContent = `
          .lb-prompt-overlay{position:fixed;inset:0;background:rgba(13,11,9,0.92);display:flex;align-items:center;justify-content:center;z-index:999;padding:20px;}
          .lb-prompt-box{background:#1a1410;border:1px solid #e06820;border-radius:10px;padding:24px;text-align:center;max-width:280px;width:100%;}
          .lb-prompt-title{font-family:'Cinzel',serif;font-size:13px;letter-spacing:0.15em;color:#c9a84c;margin-bottom:14px;}
          .lb-prompt-input{width:100%;font-family:'Cinzel',serif;font-size:28px;text-align:center;letter-spacing:0.3em;text-transform:uppercase;background:#241d16;border:1px solid #2e2519;color:#f5f0e8;border-radius:8px;padding:10px;margin-bottom:14px;}
          .lb-prompt-btn{width:100%;font-family:'Cinzel',serif;font-size:12px;letter-spacing:0.1em;padding:12px;background:#b5541a;color:#f5f0e8;border:none;border-radius:8px;cursor:pointer;font-weight:600;}
          .lb-prompt-btn:hover{background:#e06820;}
          .lb-prompt-skip{margin-top:12px;font-family:'IBM Plex Mono',monospace;font-size:11px;color:#7a6e62;cursor:pointer;text-decoration:underline;}
        `;
        document.head.appendChild(s);
      }
      document.body.appendChild(overlay);
      const input = overlay.querySelector('.lb-prompt-input');
      const btn = overlay.querySelector('.lb-prompt-btn');
      const skip = overlay.querySelector('.lb-prompt-skip');
      setTimeout(() => input.focus(), 50);
      input.addEventListener('input', () => {
        input.value = input.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 3);
      });
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') submit();
      });
      function submit() {
        const val = input.value.trim();
        overlay.remove();
        resolve(val.length > 0 ? val : null);
      }
      btn.addEventListener('click', submit);
      skip.addEventListener('click', () => {
        overlay.remove();
        resolve(null);
      });
    });
  }

  return { submitScore, fetchTop, renderBoard, promptInitials, fmtSats };
})();
