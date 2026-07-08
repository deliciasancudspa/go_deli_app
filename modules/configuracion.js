// ============================================================================
// Go Business 2.0 — Módulo Configuración
// ============================================================================

(function() {
  'use strict';

  function showToast(msg, type) { if (typeof window.showToast === 'function') window.showToast(msg, type); }

  // ── RENDER ───────────────────────────────────────────────────────────
  function render() {
    var container = document.getElementById('section-configuracion');
    if (!container) return;

    // Build config UI
    container.innerHTML =
      '<div class="card" style="margin-bottom:20px">' +
        '<div class="card-header"><h3>💳 Métodos de pago</h3><button class="btn btn-primary btn-sm" onclick="GoBusiness.modules.configuracion._saveConfig()">Guardar</button></div>' +
        '<div style="padding:20px">' +
          '<p style="color:var(--muted);font-size:13px;margin-bottom:16px">Selecciona los métodos de pago que aceptas en tu negocio.</p>' +
          '<div id="payment-methods-cfg" style="display:flex;flex-wrap:wrap;gap:10px"></div>' +
        '</div>' +
      '</div>' +
      '<div class="card" style="margin-bottom:20px">' +
        '<div class="card-header"><h3>🛵 Configuración de delivery</h3></div>' +
        '<div style="padding:20px">' +
          '<p style="color:var(--muted);font-size:13px;margin-bottom:16px">Elige quién entrega los pedidos que recibes desde la app Go Deli.</p>' +
          '<div id="delivery-mode-cfg" style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:20px">' +
            '<label class="delivery-mode-card" data-value="go_rider" style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:20px 16px;border:2px solid var(--border);border-radius:12px;cursor:pointer;text-align:center;transition:all .2s;background:var(--surface)">' +
              '<span style="font-size:32px">🛵</span>' +
              '<span style="font-weight:700;font-size:14px">Go Rider</span>' +
              '<span style="font-size:11px;color:var(--muted)">Nuestros repartidores entregan tus pedidos</span>' +
            '</label>' +
            '<label class="delivery-mode-card" data-value="own" style="display:flex;flex-direction:column;align-items:center;gap:8px;padding:20px 16px;border:2px solid var(--border);border-radius:12px;cursor:pointer;text-align:center;transition:all .2s;background:var(--surface)">' +
              '<span style="font-size:32px">🏪</span>' +
              '<span style="font-weight:700;font-size:14px">Repartidor propio</span>' +
              '<span style="font-size:11px;color:var(--muted)">Tú o tu equipo entregan los pedidos</span>' +
            '</label>' +
          '</div>' +
          '<input type="hidden" id="delivery-mode-value" value="go_rider">' +
          '<div class="form-group" style="margin-top:20px">' +
            '<label>Costo de delivery en POS (CLP)</label>' +
            '<input type="number" id="delivery-fee-pos-cfg" value="2500" min="0" step="100" style="max-width:200px">' +
            '<p style="font-size:11px;color:var(--muted);margin-top:4px">Este monto se suma al subtotal en cada pedido con delivery creado desde el POS, sin importar quién reparte.</p>' +
          '</div>' +
          '<button class="btn btn-primary" onclick="GoBusiness.modules.configuracion._saveConfig()" style="margin-top:16px">Guardar configuración</button>' +
        '</div>' +
      '</div>';

    // Bind delivery mode card clicks
    var cards = container.querySelectorAll('.delivery-mode-card');
    cards.forEach(function(card) {
      card.addEventListener('click', function() {
        var currentVal = document.getElementById('delivery-mode-value').value;
        // Si estaba en 'both', ahora el usuario elige explícitamente uno
        document.getElementById('delivery-mode-value').value = this.dataset.value;
        cards.forEach(function(c) { c.style.borderColor = 'var(--border)'; c.style.background = 'var(--surface)'; });
        this.style.borderColor = 'var(--primary)';
        this.style.background = '#FFF5F2';
      });
    });

    loadConfig();
  }

  async function loadConfig() {
    var storeData = window.storeData;
    if (!storeData) return;

    // Payment methods
    var methods = storeData.payment_methods;
    if (typeof methods === 'string') {
      try { methods = JSON.parse(methods); } catch(e) { methods = ['cash','debit','credit','transfer']; }
    }
    if (!methods || !Array.isArray(methods)) methods = ['cash','debit','credit','transfer'];

    var allMethods = [
      { id:'cash', label:'💵 Efectivo' },
      { id:'debit', label:'💳 Débito' },
      { id:'credit', label:'💳 Crédito' },
      { id:'transfer', label:'🏦 Transferencia' },
      { id:'webpay', label:'🌐 Webpay' },
      { id:'mercadopago', label:'📱 Mercado Pago' },
    ];

    var pmContainer = document.getElementById('payment-methods-cfg');
    if (pmContainer) {
      pmContainer.innerHTML = allMethods.map(function(m) {
        var checked = methods.indexOf(m.id) >= 0;
        return '<label style="display:flex;align-items:center;gap:6px;font-size:13px;cursor:pointer;padding:8px 16px;border:1.5px solid ' + (checked ? 'var(--primary)' : 'var(--border)') + ';border-radius:20px;background:' + (checked ? '#FFF5F2' : 'var(--surface)') + ';font-weight:600">' +
          '<input type="checkbox" value="' + m.id + '" ' + (checked ? 'checked' : '') + ' style="accent-color:var(--primary)"> ' + m.label +
        '</label>';
      }).join('');
    }

    // Delivery mode toggle
    var priority = storeData.delivery_priority || 'go_rider';
    // 'both' = la tienda acepta ambos métodos (Go Rider + repartidor propio).
    // No sobrescribir silenciosamente: mostrar ambas tarjetas destacadas.
    if (priority === 'both') {
      document.getElementById('delivery-mode-value').value = 'both';
    } else {
      document.getElementById('delivery-mode-value').value = priority;
    }

    var cards = document.querySelectorAll('.delivery-mode-card');
    cards.forEach(function(c) {
      if (priority === 'both' || c.dataset.value === priority) {
        c.style.borderColor = 'var(--primary)';
        c.style.background = '#FFF5F2';
      } else {
        c.style.borderColor = 'var(--border)';
        c.style.background = 'var(--surface)';
      }
    });

    // Delivery fee for POS
    var feePos = storeData.delivery_fee_max || 2500;
    var feeEl = document.getElementById('delivery-fee-pos-cfg');
    if (feeEl) feeEl.value = feePos;
  }

  async function saveConfig() {
    var storeData = window.storeData;
    if (!storeData) return;

    var pmContainer = document.getElementById('payment-methods-cfg');
    var paymentMethods = pmContainer
      ? Array.from(pmContainer.querySelectorAll('input:checked')).map(function(cb) { return cb.value; })
      : ['cash','debit','credit','transfer'];

    var deliveryMode = document.getElementById('delivery-mode-value')?.value || 'go_rider';
    var deliveryFeePos = parseInt(document.getElementById('delivery-fee-pos-cfg')?.value) || 2500;

    // delivery_methods: array con los métodos habilitados
    var deliveryMethods = deliveryMode === 'both' ? ['go_rider', 'own'] : [deliveryMode];

    var updates = {
      payment_methods: JSON.stringify(paymentMethods),
      delivery_priority: deliveryMode,
      delivery_methods: JSON.stringify(deliveryMethods),
      delivery_fee_max: deliveryFeePos,
    };

    var res = await window.sb.from('stores').update(updates).eq('id', storeData.id);
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    Object.assign(storeData, updates);
    showToast('✅ Configuración guardada');
  }

  function destroy() {}

  window.GoBusiness.modules.configuracion = {
    render: render, destroy: destroy,
    _loadConfig: loadConfig, _saveConfig: saveConfig,
  };

})();
