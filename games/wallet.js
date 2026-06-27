// ── THE ORANGE ROBOT · Shared Sat Wallet ──
// All games read/write through this module.
// Key: tor_sats (total), tor_log (last 20 events), tor_completed (set of game ids)

const TOR = (function() {
  const KEY_SATS      = 'tor_sats';
  const KEY_LOG       = 'tor_log';
  const KEY_DONE      = 'tor_completed';
  const KEY_UNLOCKS   = 'tor_unlocks';

  function getSats()    { return parseFloat(localStorage.getItem(KEY_SATS) || '0'); }
  function setSats(n)   { localStorage.setItem(KEY_SATS, Math.max(0, n).toFixed(4)); }
  function getLog()     { try { return JSON.parse(localStorage.getItem(KEY_LOG) || '[]'); } catch(e) { return []; } }
  function getDone()    { try { return JSON.parse(localStorage.getItem(KEY_DONE) || '[]'); } catch(e) { return []; } }
  function getUnlocks() { try { return JSON.parse(localStorage.getItem(KEY_UNLOCKS) || '[]'); } catch(e) { return []; } }

  function earn(amount, label) {
    const prev = getSats();
    const next = prev + amount;
    setSats(next);
    // Log it
    const log = getLog();
    log.unshift({ ts: Date.now(), label, amount, total: next });
    if (log.length > 40) log.pop();
    localStorage.setItem(KEY_LOG, JSON.stringify(log));
    // Check unlocks
    checkUnlocks(next);
    return next;
  }

  function markDone(gameId) {
    const done = getDone();
    if (!done.includes(gameId)) {
      done.push(gameId);
      localStorage.setItem(KEY_DONE, JSON.stringify(done));
    }
  }

  function isDone(gameId) { return getDone().includes(gameId); }

  // Unlock thresholds → bonus scene ids
  const UNLOCK_GATES = [
    { sats: 200,  id: 'estate-sale',   title: 'The Estate Sale',    available: true  },
    { sats: 500,  id: 'early-bird',    title: 'Early Bird',         available: true  },
    { sats: 900,  id: 'wedding',       title: 'The Celebration',    available: true  },
    { sats: 1400, id: 'scene-4',       title: 'Scene 4',            available: false },
  ];

  function checkUnlocks(totalSats) {
    const unlocked = getUnlocks();
    UNLOCK_GATES.forEach(function(gate) {
      if (totalSats >= gate.sats && !unlocked.includes(gate.id)) {
        unlocked.push(gate.id);
        localStorage.setItem(KEY_UNLOCKS, JSON.stringify(unlocked));
      }
    });
  }

  function isUnlocked(id) { return getUnlocks().includes(id); }

  function wipeWallet() {
    localStorage.removeItem(KEY_SATS);
    localStorage.removeItem(KEY_LOG);
    localStorage.removeItem(KEY_DONE);
    localStorage.removeItem(KEY_UNLOCKS);
  }

  // Format sats nicely
  function fmt(n) {
    n = parseFloat(n) || 0;
    if (n >= 1000000) return (n/1000000).toFixed(2) + 'M';
    if (n >= 1000)    return (n/1000).toFixed(1) + 'k';
    return n.toFixed(n % 1 === 0 ? 0 : 2);
  }

  // Render a floating "+X sats" toast
  function toast(amount, anchorEl) {
    const el = document.createElement('div');
    el.textContent = '+' + fmt(amount) + ' ⚡';
    el.style.cssText = [
      'position:fixed',
      'font-family:monospace',
      'font-size:1.1rem',
      'font-weight:700',
      'color:#c9a84c',
      'text-shadow:0 0 12px rgba(201,168,76,0.8)',
      'pointer-events:none',
      'z-index:9999',
      'animation:tor-toast 1.4s ease-out forwards',
    ].join(';');
    // Position near anchor or center
    if (anchorEl) {
      const r = anchorEl.getBoundingClientRect();
      el.style.left = (r.left + r.width/2 - 40) + 'px';
      el.style.top  = (r.top - 10) + 'px';
    } else {
      el.style.left = '50%';
      el.style.top  = '60%';
      el.style.transform = 'translateX(-50%)';
    }
    if (!document.getElementById('tor-toast-style')) {
      const s = document.createElement('style');
      s.id = 'tor-toast-style';
      s.textContent = '@keyframes tor-toast{0%{opacity:0;transform:translateY(0) scale(0.8)}15%{opacity:1;transform:translateY(-8px) scale(1.1)}80%{opacity:1;transform:translateY(-40px) scale(1)}100%{opacity:0;transform:translateY(-60px) scale(0.9)}}';
      document.head.appendChild(s);
    }
    document.body.appendChild(el);
    setTimeout(function() { el.remove(); }, 1500);
  }

  return {
    getSats, earn, markDone, isDone, isUnlocked,
    wipeWallet, fmt, toast,
    UNLOCK_GATES,
    getLog, getUnlocks
  };
})();
