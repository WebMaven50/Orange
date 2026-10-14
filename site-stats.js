// Counts page views and clicks for the console at orange-robot-site-stats.
// Sends the page path, the referrer, and what was clicked. No cookies, no identifiers stored in
// the browser. Does nothing if the visitor has Do Not Track or Global Privacy Control switched on.
(function () {
  try {
    if (navigator.doNotTrack === '1' || window.doNotTrack === '1' || navigator.globalPrivacyControl) return;
    var ENDPOINT = 'https://orange-robot-site-stats.victor-cb4.workers.dev/hit';
    function send(payload) {
      try {
        var body = JSON.stringify(payload);
        if (navigator.sendBeacon) {
          navigator.sendBeacon(ENDPOINT, new Blob([body], { type: 'text/plain' }));
        } else {
          fetch(ENDPOINT, { method: 'POST', body: body, keepalive: true, mode: 'no-cors' });
        }
      } catch (e) {}
    }
    send({ t: 'view', p: location.pathname, r: document.referrer });

    // Time on page: seconds the page was actually visible, reported when the visitor leaves
    // or switches away. Phones sometimes close pages without notice, so this is approximate.
    var visibleSince = document.visibilityState === 'visible' ? Date.now() : null;
    var activeMs = 0;
    function stopClock() {
      if (visibleSince !== null) { activeMs += Date.now() - visibleSince; visibleSince = null; }
    }
    function reportTime() {
      stopClock();
      var s = Math.round(activeMs / 1000);
      if (s >= 1) { send({ t: 'time', p: location.pathname, s: Math.min(s, 1800) }); activeMs = 0; }
    }
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'hidden') reportTime();
      else if (visibleSince === null) visibleSince = Date.now();
    });
    window.addEventListener('pagehide', reportTime);
    document.addEventListener('click', function (e) {
      var el = e.target && e.target.closest ? e.target.closest('a,button') : null;
      if (!el) return;
      var label = (el.getAttribute('data-track') || el.innerText || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 60);
      var href = el.tagName === 'A' ? el.href : '';
      send({ t: 'click', p: location.pathname, c: (label + (href ? ' → ' + href : '')).slice(0, 200) });
    }, true);
  } catch (e) {}
})();
