// ============================================================================
// Go Business 2.0 — Module System & Shared Utilities
// ============================================================================

window.GoBusiness = window.GoBusiness || {
  modules: {},
  _loaded: {},
  _config: {
    COMMISSION_APP_PCT: 8,
    COMMISSION_POS_PCT: 0,
    GO_RIDER_PLATFORM_FEE: 2500,
    DELIVERY_FEE_MAX: 2500,
    ORDER_SOURCES: ['GO_DELI','POS','WHATSAPP','INSTAGRAM','FACEBOOK','TELEFONO','WEB','MARKETPLACE','OTRO'],
    ORDER_MODES: ['INMEDIATA','RETIRO','DELIVERY'],
    PAYMENT_METHODS: ['cash','debit','credit','transfer','qr','webpay','mercadopago','go_wallet'],
  }
};

const GoB = window.GoBusiness;

// ── Module loader ─────────────────────────────────────────────────────────
GoB.loadModule = function(name) {
  if (GoB._loaded[name]) {
    const mod = GoB.modules[name];
    if (mod && mod.render) mod.render();
    return;
  }
  const script = document.createElement('script');
  script.src = `/modules/${name}.js?v=20260707c`;
  script.onload = function() {
    GoB._loaded[name] = true;
    const mod = GoB.modules[name];
    if (mod && mod.render) mod.render();
  };
  script.onerror = function() {
    console.error(`GoBusiness: failed to load module "${name}"`);
    const container = document.getElementById(`section-${name}`);
    if (container) container.innerHTML = `<div style="padding:40px;text-align:center;color:var(--muted)"><p style="font-size:48px;margin-bottom:16px">🔧</p><p>Módulo "${name}" en desarrollo</p></div>`;
  };
  document.head.appendChild(script);
};

// ── Placeholder renderer for modules not yet built ─────────────────────────
GoB.placeholder = function(name, title) {
  return function() {
    const container = document.getElementById(`section-${name}`);
    if (!container) return;
    container.innerHTML = `<div style="padding:60px;text-align:center">
      <div style="font-size:64px;margin-bottom:20px">🚧</div>
      <h2 style="font-weight:800;margin-bottom:8px">${title || name}</h2>
      <p style="color:var(--muted);font-size:15px">Este módulo estará disponible próximamente.</p>
    </div>`;
  };
};

// ── Eager-load implemented modules ────────────────────────────────────────
;(function() {
  ['pos','inventory','clients','caja','reportes','catalogo','pedidos','marketing','mi_negocio','configuracion'].forEach(function(name) {
    var s = document.createElement('script');
    s.src = '/modules/' + name + '.js?v=20260707c';
    document.head.appendChild(s);
  });
})();

// Todos los módulos ya están implementados — no quedan stubs.
