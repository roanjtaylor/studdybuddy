// Pan/zoom for the SVG, the chat scrolled to its newest message, and a "thinking…"
// state while a form that talks to the model is in flight (Ctrl/Cmd+Enter submits).
(function () {
  document.querySelectorAll('form').forEach(function (form) {
    form.addEventListener('submit', function () { form.classList.add('pending'); });
    form.querySelectorAll('textarea').forEach(function (ta) {
      ta.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); form.requestSubmit(); }
      });
    });
  });

  var log = document.querySelector('.chat-log');
  if (log) log.scrollTop = log.scrollHeight;

  var svg = document.getElementById('map');
  var view = document.getElementById('viewport');
  if (!svg || !view || svg.closest('.view-timeline')) return;

  var tx = 0, ty = 0, scale = 1;
  var dragging = false, moved = false, lastX = 0, lastY = 0;

  function apply() {
    view.setAttribute('transform', 'translate(' + tx + ' ' + ty + ') scale(' + scale + ')');
  }

  // Convert screen pixels to viewBox units so panning tracks the pointer exactly.
  function unit() {
    var vb = svg.viewBox.baseVal;
    var r = svg.getBoundingClientRect();
    return vb.width / r.width;
  }

  svg.addEventListener('pointerdown', function (e) {
    dragging = true; moved = false; lastX = e.clientX; lastY = e.clientY;
    svg.setPointerCapture(e.pointerId);
  });
  svg.addEventListener('pointermove', function (e) {
    if (!dragging) return;
    var u = unit();
    var dx = (e.clientX - lastX) * u, dy = (e.clientY - lastY) * u;
    if (Math.abs(dx) + Math.abs(dy) > 0.5) moved = true;
    tx += dx; ty += dy; lastX = e.clientX; lastY = e.clientY;
    apply();
  });
  svg.addEventListener('pointerup', function () { dragging = false; });
  svg.addEventListener('pointercancel', function () { dragging = false; });

  // A drag must not count as a click on a node link.
  svg.addEventListener('click', function (e) {
    if (moved) { e.preventDefault(); e.stopPropagation(); moved = false; }
  }, true);

  svg.addEventListener('wheel', function (e) {
    e.preventDefault();
    var factor = e.deltaY < 0 ? 1.1 : 1 / 1.1;
    var next = Math.min(4, Math.max(0.3, scale * factor));
    factor = next / scale;
    var r = svg.getBoundingClientRect();
    var u = unit();
    var px = (e.clientX - r.left) * u, py = (e.clientY - r.top) * u;
    tx = px - (px - tx) * factor;
    ty = py - (py - ty) * factor;
    scale = next;
    apply();
  }, { passive: false });
})();
