// ============================================================================
// Go Business 2.0 — Módulo Reportes
// ============================================================================
(function() {
  'use strict';

  var _period  = 'day';
  var _channel = 'all'; // 'all' | 'GO_DELI' | 'POS'

  function render() {
    var c = document.getElementById('section-reportes');
    if (!c) return;
    c.innerHTML =
      // ── Filtros de período ──
      '<div style="display:flex;gap:10px;margin-bottom:12px">' +
        '<button class="btn btn-sm period-btn active" onclick="GoBusiness.modules.reportes._setPeriod(\'day\',this)">Hoy</button>' +
        '<button class="btn btn-sm period-btn" onclick="GoBusiness.modules.reportes._setPeriod(\'week\',this)">Esta semana</button>' +
        '<button class="btn btn-sm period-btn" onclick="GoBusiness.modules.reportes._setPeriod(\'month\',this)">Este mes</button>' +
      '</div>' +
      // ── Filtros de canal ──
      '<div style="display:flex;gap:10px;margin-bottom:20px">' +
        '<button class="btn btn-sm channel-btn active" onclick="GoBusiness.modules.reportes._setChannel(\'all\',this)">📊 Total</button>' +
        '<button class="btn btn-sm channel-btn" onclick="GoBusiness.modules.reportes._setChannel(\'GO_DELI\',this)">🛵 Go Deli</button>' +
        '<button class="btn btn-sm channel-btn" onclick="GoBusiness.modules.reportes._setChannel(\'POS\',this)">💻 POS</button>' +
      '</div>' +
      // ── KPIs ──
      '<div class="kpi-grid" id="rep-kpis"></div>' +
      // ── Resumen por canal ──
      '<div id="rep-channel-cards" style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:20px"></div>' +
      // ── Tabla detallada ──
      '<div class="card"><div class="card-header"><h3>📋 Detalle de pedidos</h3></div>' +
        '<div style="overflow-x:auto"><table style="width:100%;font-size:12px">' +
          '<thead><tr>' +
            '<th>Fecha</th><th>Canal</th><th>Tipo</th><th>Pedido</th><th>Subt.</th><th>Comisión (8%)</th><th>Go Rider</th><th>Neto</th>' +
          '</tr></thead>' +
          '<tbody id="rep-order-table"></tbody>' +
        '</table></div>' +
      '</div>';
    _load();
  }

  // ── PERÍODO ────────────────────────────────────────────────────────────
  function _setPeriod(p, btn) {
    _period = p;
    document.querySelectorAll('.period-btn').forEach(function(b){b.classList.remove('active');});
    if (btn) btn.classList.add('active');
    _load();
  }

  // ── CANAL ──────────────────────────────────────────────────────────────
  function _setChannel(ch, btn) {
    _channel = ch;
    document.querySelectorAll('.channel-btn').forEach(function(b){b.classList.remove('active');});
    if (btn) btn.classList.add('active');
    _load();
  }

  // ── CARGA DE DATOS ─────────────────────────────────────────────────────
  function _load() {
    if (!window.storeData) return;
    var now = new Date();
    var from;
    if (_period === 'day') { from = new Date(now.getFullYear(), now.getMonth(), now.getDate()); }
    else if (_period === 'week') { var d = now.getDay(); from = new Date(now.getFullYear(), now.getMonth(), now.getDate()-d); }
    else { from = new Date(now.getFullYear(), now.getMonth(), 1); }

    window.sb.from('orders')
      .select('id,total,subtotal,order_source,order_type,delivery_method,payment_method,platform_fee,go_rider_platform_fee,service_fee,created_at,order_items(item_name,quantity,item_price)')
      .eq('store_id', window.storeData.id)
      .gte('created_at', from.toISOString())
      .order('created_at', { ascending: false })
      .then(function(r) {
        var orders = (r.data || []).filter(function(o) {
          return o.status !== 'cancelled' && o.status !== 'returned';
        });
        if (_channel !== 'all') {
          orders = orders.filter(function(o) { return (o.order_source || 'GO_DELI') === _channel; });
        }
        _renderKPIs(orders);
        _renderChannelCards(orders);
        _renderOrderTable(orders);
      });
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────
  function _commission(o) {
    // Comisión 8% solo para pedidos de la app Go Deli. POS = 0%.
    var src = o.order_source || 'GO_DELI';
    if (src === 'POS') return 0;
    return o.platform_fee || 0;
  }

  function _goRiderFee(o) {
    // Tarifa Go Rider $2.500 solo para delivery con Go Rider.
    // No aplica a retiro, en local, ni delivery propio.
    if (o.order_type !== 'delivery') return 0;
    return (o.delivery_method === 'go_rider') ? (o.go_rider_platform_fee || 2500) : 0;
  }

  function _isNonCashGoRider(o) {
    // Pedido delivery con Go Rider pagado con método distinto a efectivo.
    return o.order_type === 'delivery' && o.delivery_method === 'go_rider' && o.payment_method !== 'cash';
  }

  function _net(o) {
    // Delivery con Go Rider: Total - tarifa Go Rider (sin comisión)
    if (o.order_type === 'delivery' && o.delivery_method === 'go_rider') return (o.total || 0) - _goRiderFee(o);
    // Retiro / local / delivery propio: Total - service_fee - comisión
    return (o.total || 0) - (o.service_fee || 0) - _commission(o);
  }

  // ── KPIs ───────────────────────────────────────────────────────────────
  function _renderKPIs(orders) {
    var gross = orders.reduce(function(s,o){return s+(o.total||0);},0);
    var count = orders.length;
    var servFee   = orders.reduce(function(s,o){return s+(o.service_fee||0);},0);
    var commTotal = orders.reduce(function(s,o){return s+_commission(o);},0);
    var riderTotal = orders.reduce(function(s,o){return s+_goRiderFee(o);},0);
    var deductions = commTotal + riderTotal;
    var net = orders.reduce(function(s,o){return s+_net(o);},0);

    var el = document.getElementById('rep-kpis');
    if (!el) return;
    el.innerHTML =
      '<div class="kpi-card"><div class="kpi-icon">📦</div><div class="kpi-label">Pedidos</div><div class="kpi-value">'+count+'</div></div>' +
      '<div class="kpi-card"><div class="kpi-icon">💰</div><div class="kpi-label">Ventas brutas</div><div class="kpi-value">$'+Math.round(gross).toLocaleString('es-CL')+'</div></div>' +
      '<div class="kpi-card"><div class="kpi-icon">📉</div><div class="kpi-label">Comisión + Go Rider</div><div class="kpi-value" style="color:var(--error)">-$'+Math.round(deductions).toLocaleString('es-CL')+'</div></div>' +
      '<div class="kpi-card" style="border:2px solid var(--success)"><div class="kpi-icon">💵</div><div class="kpi-label">Neto a recibir</div><div class="kpi-value" style="color:var(--success)">$'+Math.round(net).toLocaleString('es-CL')+'</div></div>';
  }

  // ── TARJETAS RESUMEN POR CANAL ─────────────────────────────────────────
  function _renderChannelCards(orders) {
    var channels = { 'GO_DELI': [], 'POS': [] };
    orders.forEach(function(o) {
      var src = o.order_source || 'GO_DELI';
      if (channels[src]) channels[src].push(o);
      else channels['GO_DELI'].push(o);
    });

    var el = document.getElementById('rep-channel-cards');
    if (!el) return;

    if (!orders.length) { el.innerHTML = ''; return; }

    var labels = {
      'GO_DELI': { icon: '🛵', name: 'Go Deli', hasCommission: true },
      'POS':     { icon: '💻', name: 'POS',       hasCommission: false }
    };

    el.innerHTML = Object.keys(channels).map(function(key) {
      var chOrders = channels[key];
      if (!chOrders.length) return '';
      var info = labels[key];
      var subtotal   = chOrders.reduce(function(s,o){return s+(o.subtotal||0);},0);
      var total      = chOrders.reduce(function(s,o){return s+(o.total||0);},0);
      var servFee    = chOrders.reduce(function(s,o){return s+(o.service_fee||0);},0);
      var commTotal  = chOrders.reduce(function(s,o){return s+_commission(o);},0);
      var riderTotal = chOrders.reduce(function(s,o){return s+_goRiderFee(o);},0);
      var riderCount = chOrders.filter(function(o){return o.order_type === 'delivery' && o.delivery_method === 'go_rider';}).length;
      var net        = chOrders.reduce(function(s,o){return s+_net(o);},0);
      var count      = chOrders.length;

      var rows = '';
      rows += _feeRow('Subtotal productos', '$'+Math.round(subtotal).toLocaleString('es-CL'), false);
      if (info.hasCommission) {
        rows += _feeRow('Comisión (8%)', '-$'+Math.round(commTotal).toLocaleString('es-CL'), true);
      } else {
        rows += _feeRow('Comisión', '$0 (POS sin comisión)', false);
      }
      if (riderCount > 0) {
        rows += _feeRow('Tarifa Go Rider ('+riderCount+' × $2.500)', '-$'+Math.round(riderTotal).toLocaleString('es-CL'), true);
      } else {
        rows += _feeRow('Tarifa Go Rider', '$0 (sin Rider)', false);
      }
      rows += '<div style="border-top:1px solid var(--border);padding-top:8px;display:flex;justify-content:space-between;margin-top:4px">' +
        '<span style="font-weight:700">Neto</span>' +
        '<span style="font-weight:900;font-size:15px;color:var(--success)">$'+Math.round(net).toLocaleString('es-CL')+'</span></div>';

      return '<div style="background:var(--surface);border:1px solid var(--border);border-radius:14px;padding:20px">' +
        '<div style="display:flex;align-items:center;gap:8px;margin-bottom:16px">' +
          '<span style="font-size:24px">'+info.icon+'</span>' +
          '<span style="font-weight:800;font-size:15px">'+info.name+'</span>' +
          '<span style="margin-left:auto;font-size:12px;color:var(--muted)">'+count+' pedido(s)</span>' +
        '</div>' +
        '<div style="display:grid;gap:8px;font-size:13px">'+rows+'</div>' +
      '</div>';
    }).join('');
  }

  function _feeRow(label, value, isNegative) {
    return '<div style="display:flex;justify-content:space-between">' +
      '<span style="color:var(--muted)">'+label+'</span>' +
      '<span style="font-weight:600;'+(isNegative ? 'color:var(--error)' : '')+'">'+value+'</span></div>';
  }

  // ── TABLA DETALLADA ────────────────────────────────────────────────────
  function _renderOrderTable(orders) {
    var tbody = document.getElementById('rep-order-table');
    if (!tbody) return;

    if (!orders.length) {
      tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:var(--muted);padding:24px">Sin pedidos en este período</td></tr>';
      return;
    }

    var shown = orders.slice(0, 50);

    tbody.innerHTML = shown.map(function(o) {
      var src     = o.order_source || 'GO_DELI';
      var channel = src === 'POS' ? '💻 POS' : '🛵 Go Deli';
      var date    = new Date(o.created_at).toLocaleDateString('es-CL', {day:'2-digit',month:'2-digit',year:'2-digit'});
      var orderId = (o.id||'').toString().slice(-6).toUpperCase();
      var subt    = o.subtotal || 0;
      var comm    = _commission(o);
      var rider   = _goRiderFee(o);
      var net     = _net(o);

      // Tipo abreviado
      var type = o.order_type || 'delivery';
      var typeLabel =
        type === 'pickup'   ? '🏪 Retiro' :
        type === 'dine_in'  ? '🍽️ En local' :
        o.delivery_method === 'own' ? '🚗 Propio' : '🛵 Rider';

      return '<tr>' +
        '<td style="white-space:nowrap">'+date+'</td>' +
        '<td>'+channel+'</td>' +
        '<td style="font-size:11px">'+typeLabel+'</td>' +
        '<td style="font-family:monospace;font-size:11px">#'+orderId+'</td>' +
        '<td style="text-align:right">$'+Math.round(subt).toLocaleString('es-CL')+'</td>' +
        '<td style="text-align:right;'+(comm>0?'color:var(--error)':'color:var(--muted)')+'">'+(comm>0?'-$'+Math.round(comm).toLocaleString('es-CL'):'$0')+'</td>' +
        '<td style="text-align:right;'+(rider>0?'color:var(--error)':'color:var(--muted)')+'">'+(rider>0?'-$'+Math.round(rider).toLocaleString('es-CL'):'$0')+'</td>' +
        '<td style="text-align:right;font-weight:700;color:var(--success)">$'+Math.round(net).toLocaleString('es-CL')+'</td>' +
      '</tr>';
    }).join('');

    if (orders.length > 50) {
      tbody.innerHTML += '<tr><td colspan="8" style="text-align:center;color:var(--muted);padding:8px;font-size:11px">Mostrando 50 de '+orders.length+' pedidos</td></tr>';
    }
  }

  function destroy() {}

  window.GoBusiness.modules.reportes = {
    render: render, destroy: destroy,
    _setPeriod: _setPeriod, _setChannel: _setChannel
  };
})();
