// Living background (#59): crew network in the three kinds' colors.
(function () {
  'use strict';
  var canvas = document.querySelector('canvas.bg-net') || document.getElementById('bg-net') || document.querySelector('body > canvas');
  if (!canvas || !canvas.getContext) return;
  var ctx = canvas.getContext('2d');
  if (!ctx) return;

  var OVER = 120;
  var MASK = 'linear-gradient(90deg,#000,rgba(0,0,0,.08) max(1rem,calc((100% - 72rem)/2)),rgba(0,0,0,.08) min(calc(100% - 1rem),calc((100% + 72rem)/2)),#000)';
  canvas.style.cssText = 'position:fixed;left:0;right:0;top:0;width:100%;height:calc(100% + ' + OVER + 'px);z-index:-1;pointer-events:none;display:block;opacity:0.92;will-change:transform;-webkit-mask-image:' + MASK + ';mask-image:' + MASK;

  // claude #d97757, codex #10a37f, agy #4285f4
  var KINDS = ['217, 119, 87', '16, 163, 127', '66, 133, 244'];
  var width = 0, height = 0, viewH = 0, dpr = 1, maxD = 220, maxDSq = 48400;
  var nodes = [], pulses = [], rafId = 0, lastT = 0, pTimer = 0, onScreen = true, seed = 42071;
  var mq = window.matchMedia ? window.matchMedia('(prefers-reduced-motion: reduce)') : { matches: false };

  function rand() { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; }
  function rgba(k, a) { return 'rgba(' + k + ',' + a + ')'; }
  function dot(x, y, r, f) { ctx.fillStyle = f; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.fill(); }
  function line(x1, y1, x2, y2, w, s) { ctx.lineWidth = w; ctx.strokeStyle = s; ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); }
  function rgrad(x, y, r, k, a0, a1, m) {
    var g = ctx.createRadialGradient(x, y, 0, x, y, r);
    g.addColorStop(0, rgba(k, a0));
    if (m) g.addColorStop(0.4, rgba(k, a1));
    g.addColorStop(1, rgba(k, 0));
    return g;
  }

  function spawnPulse(initT) {
    if (pulses.length >= 6 || nodes.length < 2) return;
    var n = nodes.length, st = Math.floor(rand() * n);
    for (var s = 0; s < n; s++) {
      var a = (st + s) % n, na = nodes[a];
      for (var b = a + 1; b < n; b++) {
        var nb = nodes[b], dx = nb.x - na.x, dy = nb.y - na.y, dSq = dx * dx + dy * dy;
        if (dSq > 3200 && dSq < maxDSq * 0.9) {
          var dup = 0;
          for (var p = 0; p < pulses.length; p++) {
            if ((pulses[p].a === a && pulses[p].b === b) || (pulses[p].a === b && pulses[p].b === a)) dup = 1;
          }
          if (!dup) {
            var f = rand() > 0.5;
            pulses.push({ a: f ? a : b, b: f ? b : a, t: initT || 0, speed: 0.36 + rand() * 0.24 });
            return;
          }
        }
      }
    }
  }

  function build() {
    seed = 42071;
    var count = Math.max(18, Math.min(42, Math.round((width * viewH) / 26000)));
    maxD = Math.max(180, Math.min(265, Math.round(Math.max(width, viewH) * 0.18)));
    maxDSq = maxD * maxD;
    nodes.length = 0; pulses.length = 0;
    var cols = Math.max(3, Math.round(Math.sqrt((count * width) / Math.max(height, 1))));
    var rows = Math.max(3, Math.ceil(count / cols)), cw = width / cols, ch = height / rows;
    for (var i = 0; i < count; i++) {
      var ang = rand() * 6.2832, spd = 7 + rand() * 8, mem = (i % 3 === 0);
      nodes.push({
        x: ((i % cols) + 0.14 + 0.72 * rand()) * cw,
        y: (Math.floor(i / cols) + 0.14 + 0.72 * rand()) * ch,
        vx: Math.cos(ang) * spd, vy: Math.sin(ang) * spd,
        r: mem ? 4.3 + (i % 2) * 0.5 : 2.3, mem: mem, kind: KINDS[i % 3]
      });
    }
    var seeds = [0.22, 0.36, 0.50, 0.64, 0.77, 0.88];
    for (var s = 0; s < seeds.length; s++) spawnPulse(seeds[s]);
  }

  function step(dt) {
    var pad = 20;
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      n.x += n.vx * dt; n.y += n.vy * dt;
      if (n.x < pad || n.x > width - pad) { n.x = Math.max(pad, Math.min(width - pad, n.x)); n.vx = -n.vx; }
      if (n.y < pad || n.y > height - pad) { n.y = Math.max(pad, Math.min(height - pad, n.y)); n.vy = -n.vy; }
    }
    for (var p = pulses.length - 1; p >= 0; p--) {
      var pl = pulses[p], na = nodes[pl.a], nb = nodes[pl.b];
      if (!na || !nb) { pulses.splice(p, 1); continue; }
      var dx = nb.x - na.x, dy = nb.y - na.y;
      pl.t += pl.speed * dt;
      if (dx * dx + dy * dy > maxDSq || pl.t >= 1) pulses.splice(p, 1);
    }
    pTimer += dt;
    if (pTimer >= 0.75) { pTimer = 0; spawnPulse(0); }
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    var n = nodes.length;
    for (var i = 0; i < n; i++) {
      var na = nodes[i];
      for (var j = i + 1; j < n; j++) {
        var nb = nodes[j], dx = nb.x - na.x, dy = nb.y - na.y, dSq = dx * dx + dy * dy;
        if (dSq < maxDSq) {
          var alpha = (1 - Math.sqrt(dSq) / maxD) * ((na.mem || nb.mem) ? 0.68 : 0.48);
          line(na.x, na.y, nb.x, nb.y, (na.mem && nb.mem) ? 1.5 : 1.15, rgba(na.kind, alpha.toFixed(3)));
        }
      }
    }
    for (var p = 0; p < pulses.length; p++) {
      var pl = pulses[p], a = nodes[pl.a], b = nodes[pl.b];
      if (!a || !b) continue;
      var t = pl.t, tail = Math.max(0, t - 0.28), env = Math.sin(t * Math.PI);
      var px = a.x + (b.x - a.x) * t, py = a.y + (b.y - a.y) * t;
      var tx = a.x + (b.x - a.x) * tail, ty = a.y + (b.y - a.y) * tail;
      var grad = ctx.createLinearGradient(tx, ty, px, py);
      grad.addColorStop(0, rgba(a.kind, 0));
      grad.addColorStop(1, rgba(a.kind, (0.98 * env).toFixed(3)));
      line(tx, ty, px, py, 2.5, grad);
      dot(px, py, 14, rgrad(px, py, 14, a.kind, (0.76 * env).toFixed(3), 0, 0));
      dot(px, py, 3.4, rgba(a.kind, (0.98 * env).toFixed(3)));
      dot(px, py, 1.6, 'rgba(255,255,255,' + (0.92 * env).toFixed(3) + ')');
    }
    for (var k = 0; k < n; k++) {
      var nd = nodes[k], hr = nd.r * (nd.mem ? 6.5 : 5.2);
      dot(nd.x, nd.y, hr, rgrad(nd.x, nd.y, hr, nd.kind, nd.mem ? '0.72' : '0.52', nd.mem ? '0.26' : '0.16', 1));
      dot(nd.x, nd.y, nd.r, rgba(nd.kind, nd.mem ? '0.98' : '0.88'));
      if (nd.mem) dot(nd.x, nd.y, nd.r * 0.42, 'rgba(255,255,255,0.85)');
    }
  }

  function parallax() {
    if (mq.matches) { canvas.style.transform = 'none'; return; }
    var bt = document.body ? document.body.getBoundingClientRect().top : 0;
    var sy = Math.max(0, window.scrollY || window.pageYOffset || -bt);
    var maxS = Math.max(1, (document.documentElement.scrollHeight || 4000) - viewH);
    canvas.style.transform = 'translate3d(0,' + (-OVER * Math.min(1, sy / maxS)).toFixed(1) + 'px,0)';
  }
  function active() { return !mq.matches && !document.hidden && document.visibilityState !== 'hidden' && onScreen; }
  function tick(now) {
    rafId = 0;
    if (!active()) return;
    if (!lastT || now - lastT >= 32) {
      step(lastT ? Math.min((now - lastT) / 1000, 0.1) : 0);
      lastT = now; draw();
    }
    rafId = window.requestAnimationFrame(tick);
  }
  function syncLoop() {
    parallax();
    if (active()) { if (!rafId) { lastT = 0; rafId = window.requestAnimationFrame(tick); } }
    else if (rafId) { window.cancelAnimationFrame(rafId); rafId = 0; lastT = 0; }
  }

  function resize() {
    var w = document.documentElement.clientWidth || window.innerWidth || 1024;
    var vh = window.innerHeight || document.documentElement.clientHeight || 768;
    var h = vh + OVER, d = Math.min(window.devicePixelRatio || 1, 2);
    if (w === width && h === height && d === dpr && nodes.length) return;
    width = w; viewH = vh; height = h; dpr = d;
    canvas.width = Math.round(w * d); canvas.height = Math.round(h * d);
    ctx.setTransform(d, 0, 0, d, 0, 0);
    build(); parallax(); draw();
  }
  document.addEventListener('visibilitychange', syncLoop);
  window.addEventListener('scroll', parallax, { passive: true });
  if (typeof IntersectionObserver === 'function') {
    new IntersectionObserver(function (e) {
      for (var i = 0; i < e.length; i++) onScreen = e[i].isIntersecting;
      syncLoop();
    }).observe(canvas);
  }
  if (mq.addEventListener) mq.addEventListener('change', function () { parallax(); draw(); syncLoop(); });
  window.addEventListener('resize', resize, { passive: true });
  resize(); syncLoop();
})();
