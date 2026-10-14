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
    document.addEventListener('click', function (e) {
      var el = e.target && e.target.closest ? e.target.closest('a,button') : null;
      if (!el) return;
      var label = (el.getAttribute('data-track') || el.innerText || el.getAttribute('aria-label') || '').replace(/\s+/g, ' ').trim().slice(0, 60);
      var href = el.tagName === 'A' ? el.href : '';
      send({ t: 'click', p: location.pathname, c: (label + (href ? ' → ' + href : '')).slice(0, 200) });
    }, true);
  } catch (e) {}
})();
