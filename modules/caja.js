// ============================================================================
// Go Business 2.0 — Módulo Caja
// ============================================================================
(function() {
  'use strict';

  var _currentSession = null;

  function render() {
    var c = document.getElementById('section-caja');
    if (!c) return;
    c.innerHTML =
      '<div class="kpi-grid" style="grid-template-columns:repeat(3,1fr)" id="caja-kpis">' +
        '<div class="kpi-card"><div class="kpi-icon">💰</div><div class="kpi-label">Ventas del día</div><div class="kpi-value" id="caja-day-sales">-</div></div>' +
        '<div class="kpi-card"><div class="kpi-icon">📋</div><div class="kpi-label">Sesión actual</div><div class="kpi-value" id="caja-session-status">-</div></div>' +
        '<div class="kpi-card"><div class="kpi-icon">🏦</div><div class="kpi-label">Efectivo estimado</div><div class="kpi-value" id="caja-cash-est">-</div></div>' +
      '</div>' +
      '<div class="card">' +
        '<div class="card-header"><h3>💵 Control de caja</h3>' +
          '<button class="btn btn-sec btn-sm" id="caja-open-btn" onclick="GoBusiness.modules.caja._openSession()">🔓 Abrir caja</button>' +
          '<button class="btn btn-sm" style="background:var(--primary);color:#fff;display:none" id="caja-close-btn" onclick="GoBusiness.modules.caja._closeSession()">🔒 Cerrar caja</button>' +
        '</div>' +
        '<div id="caja-session-info" style="padding:16px;color:var(--muted);text-align:center">Cargando...</div>' +
        '<table style="display:none" id="caja-mov-table"><thead><tr><th>Hora</th><th>Tipo</th><th>Descripción</th><th>Método</th><th style="text-align:right">Monto</th></tr></thead><tbody id="caja-mov-body"></tbody></table>' +
      '</div>';
    _load();
  }

  function _load() {
    if (!window.storeData) return;
    // Buscar sesión abierta
    window.sb.from('cash_sessions')
      .select('*').eq('store_id', window.storeData.id).eq('status','open')
      .order('opened_at', { ascending: false }).limit(1)
      .then(function(r) {
        _currentSession = (r.data && r.data.length) ? r.data[0] : null;
        _renderSession();
      });
    // Ventas en efectivo del día (excluye canceladas y devueltas)
    var today = new Date().toISOString().split('T')[0];
    window.sb.from('orders')
      .select('total,payment_method,status').eq('store_id', window.storeData.id)
      .gte('created_at', today).eq('payment_method','cash')
      .then(function(r) {
        var total = (r.data||[]).filter(function(o){ return o.status !== 'cancelled' && o.status !== 'returned'; }).reduce(function(s,o){return s+(o.total||0);},0);
        var el = document.getElementById('caja-day-sales');
        if (el) el.textContent = '$' + Math.round(total).toLocaleString('es-CL');
      });
    _loadMovements();
  }

  function _renderSession() {
    var info = document.getElementById('caja-session-info');
    var openBtn = document.getElementById('caja-open-btn');
    var closeBtn = document.getElementById('caja-close-btn');
    var statusEl = document.getElementById('caja-session-status');

    if (_currentSession) {
      if (info) info.innerHTML = '<div style="font-size:48px;margin-bottom:12px">🔓</div><p style="font-weight:700;font-size:16px;margin-bottom:4px">Caja abierta</p><p style="font-size:13px;color:var(--muted)">Monto inicial: <strong>$' + (_currentSession.opening_amount||0).toLocaleString('es-CL') + '</strong></p><p style="font-size:12px;color:var(--muted)">Abierta: ' + new Date(_currentSession.opened_at).toLocaleString('es-CL') + '</p>';
      if (openBtn) openBtn.style.display = 'none';
      if (closeBtn) closeBtn.style.display = '';
      if (statusEl) statusEl.textContent = 'Abierta';
    } else {
      if (info) info.innerHTML = '<div style="font-size:48px;margin-bottom:12px">🔒</div><p style="font-weight:700;font-size:16px;margin-bottom:4px">Caja cerrada</p><p style="font-size:13px;color:var(--muted)">Abre la caja para registrar movimientos</p>';
      if (openBtn) openBtn.style.display = '';
      if (closeBtn) closeBtn.style.display = 'none';
      if (statusEl) statusEl.textContent = 'Cerrada';
    }
  }

  function _loadMovements() {
    window.sb.from('cash_movements')
      .select('*').eq('store_id', window.storeData.id)
      .order('created_at', { ascending: false }).limit(30)
      .then(function(r) {
        var movs = r.data || [];
        var tbody = document.getElementById('caja-mov-body');
        var table = document.getElementById('caja-mov-table');
        if (table) table.style.display = '';
        if (!tbody) return;
        var typeLabels = {venta:'🟢 Venta',retiro:'🔴 Retiro',ingreso:'🟣 Ingreso',ajuste:'🔵 Ajuste'};
        if (!movs.length) {
          tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--muted);padding:24px">Sin movimientos</td></tr>';
        } else {
          tbody.innerHTML = movs.map(function(m) {
            return '<tr>' +
              '<td style="font-size:12px">' + new Date(m.created_at).toLocaleTimeString('es-CL',{hour:'2-digit',minute:'2-digit'}) + '</td>' +
              '<td>' + (typeLabels[m.type]||m.type) + '</td>' +
              '<td>' + (m.description||'-') + '</td>' +
              '<td>' + (m.payment_method||'-') + '</td>' +
              '<td style="text-align:right"><strong>$' + m.amount.toLocaleString('es-CL') + '</strong></td>' +
              '</tr>';
          }).join('');
        }
        var cashEst = movs.filter(function(m){return m.payment_method==='cash'}).reduce(function(s,m){return s + (m.type==='retiro'?-m.amount:m.amount);},0);
        var el = document.getElementById('caja-cash-est');
        if (el) el.textContent = '$' + Math.round(Math.max(0,cashEst)).toLocaleString('es-CL');
      });
  }

  function _openSession() {
    var amount = prompt('Monto inicial de caja (CLP):', '0');
    if (amount === null) return;
    amount = parseInt(amount) || 0;
    window.sb.from('cash_sessions').insert({
      store_id: window.storeData.id,
      opened_by: window.storeData.owner_id,
      opening_amount: amount
    }).select().single().then(function(r) {
      _currentSession = r.data;
      _renderSession();
      window.showToast('✅ Caja abierta');
    }).catch(function(e) { window.showToast('Error: '+e.message,'error'); });
  }

  function _closeSession() {
    if (!_currentSession) return;
    var amount = prompt('Monto final de caja (CLP):', '0');
    if (amount === null) return;
    amount = parseInt(amount) || 0;
    var diff = amount - (_currentSession.opening_amount||0);
    window.sb.from('cash_sessions').update({
      closing_amount: amount, difference: diff, status: 'closed',
      closed_by: window.storeData.owner_id, closed_at: new Date().toISOString()
    }).eq('id', _currentSession.id).then(function() {
      _currentSession = null;
      _renderSession();
      window.showToast('✅ Caja cerrada. Diferencia: $' + diff.toLocaleString('es-CL'));
    }).catch(function(e) { window.showToast('Error: '+e.message,'error'); });
  }

  window.GoBusiness.modules.caja = {
    render: render, destroy: function(){},
    _openSession: _openSession, _closeSession: _closeSession
  };
})();
