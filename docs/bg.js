// Living background (#59): the crew as a network in the three kinds' colors.
// Plain JavaScript, no library. Pauses on visibilitychange or when off screen,
// caps DPR at 2 and node count by area, and draws one still frame under
// prefers-reduced-motion: reduce.
(function () {
  'use strict';

  var canvas = document.querySelector('canvas.bg-net') || document.getElementById('bg-net') || document.querySelector('body > canvas');
  if (!canvas || !canvas.getContext) return;
  var ctx = canvas.getContext('2d');
  if (!ctx) return;

  canvas.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;z-index:-1;pointer-events:none;display:block;opacity:0.2';

  // The three kinds' colors: claude (#d97757), codex (#10a37f), agy (#4285f4).
  var KINDS = [
    { hex: '#d97757', rgb: '217, 119, 87' },
    { hex: '#10a37f', rgb: '16, 163, 127' },
    { hex: '#4285f4', rgb: '66, 133, 244' }
  ];

  var MAX_DPR = 2;
  var MIN_NODES = 16;
  var MAX_NODES = 42;
  var AREA_PER_NODE = 26000;
  var LINK_DIST = 175;
  var LINK_DIST_SQ = LINK_DIST * LINK_DIST;
  var MAX_PULSES = 5;

  var width = 0, height = 0, dpr = 1;
  var nodes = [], pulses = [];
  var rafId = 0, lastTime = 0, pulseTimer = 0, onScreen = true;

  var motionQuery = window.matchMedia
    ? window.matchMedia('(prefers-reduced-motion: reduce)')
    : { matches: false };

  var seed = 42071;
  function rand() {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  }

  function spawnPulse(initT) {
    if (pulses.length >= MAX_PULSES || nodes.length < 2) return;
    var n = nodes.length;
    var start = Math.floor(rand() * n);
    for (var s = 0; s < n; s++) {
      var a = (start + s) % n, na = nodes[a];
      for (var b = a + 1; b < n; b++) {
        var nb = nodes[b], dx = nb.x - na.x, dy = nb.y - na.y;
        var dSq = dx * dx + dy * dy;
        if (dSq > 2400 && dSq < LINK_DIST_SQ * 0.88) {
          var dup = false;
          for (var p = 0; p < pulses.length; p++) {
            if ((pulses[p].a === a && pulses[p].b === b) || (pulses[p].a === b && pulses[p].b === a)) {
              dup = true;
              break;
            }
          }
          if (!dup) {
            var fwd = rand() > 0.5;
            pulses.push({
              a: fwd ? a : b,
              b: fwd ? b : a,
              t: typeof initT === 'number' ? initT : 0,
              speed: 0.42 + rand() * 0.25
            });
            return;
          }
        }
      }
    }
  }

  function buildNetwork() {
    seed = 42071;
    var count = Math.max(MIN_NODES, Math.min(MAX_NODES, Math.round((width * height) / AREA_PER_NODE)));
    nodes.length = 0;
    pulses.length = 0;

    var cols = Math.max(3, Math.round(Math.sqrt((count * width) / Math.max(height, 1))));
    var rows = Math.max(3, Math.ceil(count / cols));
    var cellW = width / cols, cellH = height / rows;

    for (var i = 0; i < count; i++) {
      var col = i % cols, row = Math.floor(i / cols);
      var angle = rand() * Math.PI * 2, speed = 7 + rand() * 8;
      nodes.push({
        x: (col + 0.16 + 0.68 * rand()) * cellW,
        y: (row + 0.16 + 0.68 * rand()) * cellH,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        r: 2.1 + (i % 3 === 0 ? 0.6 : 0),
        kind: KINDS[i % KINDS.length]
      });
    }

    spawnPulse(0.28);
    spawnPulse(0.54);
    spawnPulse(0.74);
  }

  function step(dt) {
    var pad = 20;
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      n.x += n.vx * dt;
      n.y += n.vy * dt;
      if (n.x < pad) { n.x = pad; n.vx = Math.abs(n.vx); }
      else if (n.x > width - pad) { n.x = width - pad; n.vx = -Math.abs(n.vx); }
      if (n.y < pad) { n.y = pad; n.vy = Math.abs(n.vy); }
      else if (n.y > height - pad) { n.y = height - pad; n.vy = -Math.abs(n.vy); }
    }

    for (var p = pulses.length - 1; p >= 0; p--) {
      var pl = pulses[p], na = nodes[pl.a], nb = nodes[pl.b];
      if (!na || !nb) { pulses.splice(p, 1); continue; }
      var dx = nb.x - na.x, dy = nb.y - na.y;
      pl.t += pl.speed * dt;
      if (dx * dx + dy * dy > LINK_DIST_SQ || pl.t >= 1) pulses.splice(p, 1);
    }

    pulseTimer += dt;
    if (pulseTimer >= 0.9) {
      pulseTimer = 0;
      spawnPulse(0);
    }
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    var n = nodes.length;

    ctx.lineWidth = 1;
    for (var i = 0; i < n; i++) {
      var na = nodes[i];
      for (var j = i + 1; j < n; j++) {
        var nb = nodes[j], dx = nb.x - na.x, dy = nb.y - na.y;
        var dSq = dx * dx + dy * dy;
        if (dSq < LINK_DIST_SQ) {
          var alpha = (1 - Math.sqrt(dSq) / LINK_DIST) * 0.55;
          ctx.strokeStyle = 'rgba(' + na.kind.rgb + ',' + alpha.toFixed(3) + ')';
          ctx.beginPath();
          ctx.moveTo(na.x, na.y);
          ctx.lineTo(nb.x, nb.y);
          ctx.stroke();
        }
      }
    }

    for (var p = 0; p < pulses.length; p++) {
      var pl = pulses[p], a = nodes[pl.a], b = nodes[pl.b];
      if (!a || !b) continue;
      var t = pl.t;
      var px = a.x + (b.x - a.x) * t, py = a.y + (b.y - a.y) * t;
      var tail = Math.max(0, t - 0.18), env = Math.sin(t * Math.PI);

      ctx.strokeStyle = 'rgba(' + a.kind.rgb + ',' + (0.85 * env).toFixed(3) + ')';
      ctx.lineWidth = 1.6;
      ctx.beginPath();
      ctx.moveTo(a.x + (b.x - a.x) * tail, a.y + (b.y - a.y) * tail);
      ctx.lineTo(px, py);
      ctx.stroke();

      ctx.fillStyle = 'rgba(' + a.kind.rgb + ',' + (0.98 * env).toFixed(3) + ')';
      ctx.beginPath();
      ctx.arc(px, py, 2.5, 0, Math.PI * 2);
      ctx.fill();
    }

    for (var k = 0; k < n; k++) {
      var nd = nodes[k];
      ctx.fillStyle = 'rgba(' + nd.kind.rgb + ',0.35)';
      ctx.beginPath();
      ctx.arc(nd.x, nd.y, nd.r * 2.6, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = 'rgba(' + nd.kind.rgb + ',0.95)';
      ctx.beginPath();
      ctx.arc(nd.x, nd.y, nd.r, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  function active() {
    return !motionQuery.matches && !document.hidden && document.visibilityState !== 'hidden' && onScreen;
  }

  function tick(now) {
    rafId = 0;
    if (!active()) return;
    if (!lastTime) lastTime = now;
    var dt = Math.min((now - lastTime) / 1000, 0.1);
    lastTime = now;
    step(dt);
    draw();
    rafId = window.requestAnimationFrame(tick);
  }

  function syncLoop() {
    if (active()) {
      if (!rafId) {
        lastTime = 0;
        rafId = window.requestAnimationFrame(tick);
      }
    } else if (rafId) {
      window.cancelAnimationFrame(rafId);
      rafId = 0;
      lastTime = 0;
    }
  }

  function resize() {
    var w = document.documentElement.clientWidth || window.innerWidth || 1024;
    var h = window.innerHeight || document.documentElement.clientHeight || 768;
    var nextDpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
    if (w === width && h === height && nextDpr === dpr && nodes.length) return;
    width = w;
    height = h;
    dpr = nextDpr;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    buildNetwork();
    draw();
  }

  document.addEventListener('visibilitychange', syncLoop);

  if (typeof IntersectionObserver === 'function') {
    new IntersectionObserver(function (entries) {
      for (var i = 0; i < entries.length; i++) onScreen = entries[i].isIntersecting;
      syncLoop();
    }).observe(canvas);
  }

  if (motionQuery.addEventListener) {
    motionQuery.addEventListener('change', function () {
      draw();
      syncLoop();
    });
  }

  window.addEventListener('resize', resize, { passive: true });
  resize();
  syncLoop();
})();
