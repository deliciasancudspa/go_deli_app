// ============================================================================
// Go Business 2.0 — Módulo Caja (v2 — Julio 2026)
// ============================================================================
// Nuevo: desglose de billetes/monedas chilenas, entrada/salida de efectivo,
//        apertura automática de cajón vía printer.safeOpenDrawer()
// ============================================================================
(function() {
  'use strict';

  var _currentSession = null;

  // ── Denominaciones chilenas ──────────────────────────────────────────────
  var DENOMINATIONS = [
    { value: 20000, label: 'Billete $20.000', type: 'bill' },
    { value: 10000, label: 'Billete $10.000', type: 'bill' },
    { value:  5000, label: 'Billete $5.000',  type: 'bill' },
    { value:  2000, label: 'Billete $2.000',  type: 'bill' },
    { value:  1000, label: 'Billete $1.000',  type: 'bill' },
    { value:   500, label: 'Moneda $500',     type: 'coin' },
    { value:   100, label: 'Moneda $100',     type: 'coin' },
    { value:    50, label: 'Moneda $50',      type: 'coin' },
    { value:    10, label: 'Moneda $10',      type: 'coin' }
  ];

  // ── Helpers de denominaciones ────────────────────────────────────────────

  // Genera HTML de grilla de billetes/monedas
  function _renderBreakdown(prefix) {
    var bills  = DENOMINATIONS.filter(function(d) { return d.type === 'bill'; });
    var coins  = DENOMINATIONS.filter(function(d) { return d.type === 'coin'; });
    var fn = prefix || '';

    var html = '<div class="denom-grid">';

    // Columna izquierda: billetes
    html += '<div><div class="denom-section-title">💵 Billetes</div>';
    bills.forEach(function(d) {
      html += '<div class="denom-row">' +
        '<span class="denom-label">' + d.label + '</span>' +
        '<input type="number" class="denom-input" id="' + fn + 'qty_' + d.value + '" value="0" min="0" oninput="GoBusiness.modules.caja._updateBreakdownTotal(\'' + fn + '\')">' +
        '<span class="denom-subtotal" id="' + fn + 'sub_' + d.value + '">$0</span>' +
      '</div>';
    });
    html += '</div>';

    // Columna derecha: monedas
    html += '<div><div class="denom-section-title">🪙 Monedas</div>';
    coins.forEach(function(d) {
      html += '<div class="denom-row">' +
        '<span class="denom-label">' + d.label + '</span>' +
        '<input type="number" class="denom-input" id="' + fn + 'qty_' + d.value + '" value="0" min="0" oninput="GoBusiness.modules.caja._updateBreakdownTotal(\'' + fn + '\')">' +
        '<span class="denom-subtotal" id="' + fn + 'sub_' + d.value + '">$0</span>' +
      '</div>';
    });
    html += '</div></div>';

    return html;
  }

  // Recalcula total de la grilla (llamado desde oninput)
  function _updateBreakdownTotal(prefix) {
    var fn = prefix || '';
    var total = 0;
    DENOMINATIONS.forEach(function(d) {
      var el = document.getElementById(fn + 'qty_' + d.value);
      var qty = parseInt(el && el.value) || 0;
      var subtotal = qty * d.value;
      total += subtotal;
      var subEl = document.getElementById(fn + 'sub_' + d.value);
      if (subEl) subEl.textContent = '$' + subtotal.toLocaleString('es-CL');
    });
    var totalEl = document.getElementById(fn + 'total');
    if (totalEl) totalEl.textContent = '$' + total.toLocaleString('es-CL');
    return total;
  }

  // Recolecta breakdown como objeto JSON
  function _collectBreakdown(prefix) {
    var fn = prefix || '';
    var breakdown = {};
    DENOMINATIONS.forEach(function(d) {
      var el = document.getElementById(fn + 'qty_' + d.value);
      breakdown[d.value] = parseInt(el && el.value) || 0;
    });
    return breakdown;
  }

  // ── Abrir cajón (safe wrapper) ───────────────────────────────────────────
  function _openDrawer() {
    var p = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;
    if (p && p.safeOpenDrawer) {
      p.safeOpenDrawer();
      return true;
    }
    return false;
  }

  // ── Render principal ────────────────────────────────────────────────────
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
          '<button class="btn btn-sec btn-sm" id="caja-open-btn" onclick="GoBusiness.modules.caja._showOpenModal()">🔓 Abrir caja</button>' +
          '<button class="btn btn-sm" style="background:var(--primary);color:#fff;display:none" id="caja-close-btn" onclick="GoBusiness.modules.caja._showCloseModal()">🔒 Cerrar caja</button>' +
          '<button class="btn btn-sm" style="background:#22c55e;color:#fff;display:none" id="caja-in-btn" onclick="GoBusiness.modules.caja._showIOModal(\'ingreso\')">+ Entrada</button>' +
          '<button class="btn btn-sm" style="background:#ef4444;color:#fff;display:none" id="caja-out-btn" onclick="GoBusiness.modules.caja._showIOModal(\'retiro\')">− Salida</button>' +
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
    // Ventas en efectivo del día — incluye pagos split (mixed) consultando order_payments
    var today = new Date().toISOString().split('T')[0];
    // Obtener IDs de órdenes válidas del día (no canceladas ni devueltas)
    window.sb.from('orders')
      .select('id').eq('store_id', window.storeData.id)
      .gte('created_at', today)
      .not('status', 'in', '("cancelled","returned")')
      .then(function(orderRes) {
        var validOrderIds = (orderRes.data || []).map(function(o) { return o.id; });
        if (!validOrderIds.length) {
          var el = document.getElementById('caja-day-sales');
          if (el) el.textContent = '$0';
          return;
        }
        // Buscar todos los pagos en efectivo de esas órdenes
        window.sb.from('order_payments')
          .select('amount').eq('payment_method', 'cash')
          .in('order_id', validOrderIds)
          .then(function(payRes) {
            var total = (payRes.data || []).reduce(function(s, p) { return s + (p.amount || 0); }, 0);
            var el = document.getElementById('caja-day-sales');
            if (el) el.textContent = '$' + Math.round(total).toLocaleString('es-CL');
          });
      });
    _loadMovements();
  }

  function _renderSession() {
    var info = document.getElementById('caja-session-info');
    var openBtn = document.getElementById('caja-open-btn');
    var closeBtn = document.getElementById('caja-close-btn');
    var inBtn = document.getElementById('caja-in-btn');
    var outBtn = document.getElementById('caja-out-btn');
    var statusEl = document.getElementById('caja-session-status');

    if (_currentSession) {
      var breakdownHtml = '';
      if (_currentSession.opening_breakdown) {
        breakdownHtml = '<p style="font-size:12px;color:var(--muted);margin-top:4px">Desglose inicial: ';
        var parts = [];
        DENOMINATIONS.forEach(function(d) {
          var qty = _currentSession.opening_breakdown[d.value] || 0;
          if (qty > 0) parts.push(qty + '×' + d.label.replace('Billete ','').replace('Moneda ',''));
        });
        breakdownHtml += (parts.length ? parts.join(', ') : 'Sin desglose') + '</p>';
      }

      if (info) info.innerHTML = '<div style="font-size:48px;margin-bottom:12px">🔓</div><p style="font-weight:700;font-size:16px;margin-bottom:4px">Caja abierta</p><p style="font-size:13px;color:var(--muted)">Monto inicial: <strong>$' + (_currentSession.opening_amount||0).toLocaleString('es-CL') + '</strong></p>' + breakdownHtml + '<p style="font-size:12px;color:var(--muted)">Abierta: ' + new Date(_currentSession.opened_at).toLocaleString('es-CL') + '</p>';
      if (openBtn) openBtn.style.display = 'none';
      if (closeBtn) closeBtn.style.display = '';
      if (inBtn) inBtn.style.display = '';
      if (outBtn) outBtn.style.display = '';
      if (statusEl) statusEl.textContent = 'Abierta';
    } else {
      if (info) info.innerHTML = '<div style="font-size:48px;margin-bottom:12px">🔒</div><p style="font-weight:700;font-size:16px;margin-bottom:4px">Caja cerrada</p><p style="font-size:13px;color:var(--muted)">Abre la caja para registrar movimientos</p>';
      if (openBtn) openBtn.style.display = '';
      if (closeBtn) closeBtn.style.display = 'none';
      if (inBtn) inBtn.style.display = 'none';
      if (outBtn) outBtn.style.display = 'none';
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
            var voucherInfo = m.voucher_number ? '<br><span style="font-size:11px;color:var(--muted)">#' + m.voucher_number + '</span>' : '';
            return '<tr>' +
              '<td style="font-size:12px">' + new Date(m.created_at).toLocaleTimeString('es-CL',{hour:'2-digit',minute:'2-digit'}) + '</td>' +
              '<td>' + (typeLabels[m.type]||m.type) + voucherInfo + '</td>' +
              '<td>' + (m.description||'-') + '</td>' +
              '<td>' + (m.payment_method||'-') + '</td>' +
              '<td style="text-align:right"><strong>$' + m.amount.toLocaleString('es-CL') + '</strong></td>' +
              '</tr>';
          }).join('');
        }
        // Efectivo estimado: incluye movimientos de efectivo + todos los retiros (siempre son cash)
        var cashEst = movs.filter(function(m){return m.payment_method==='cash' || m.type==='retiro';}).reduce(function(s,m){return s + (m.type==='retiro'?-m.amount:m.amount);},0);
        // Incluir saldo inicial
        if (_currentSession) cashEst += (_currentSession.opening_amount||0);
        var el = document.getElementById('caja-cash-est');
        if (el) el.textContent = '$' + Math.round(Math.max(0,cashEst)).toLocaleString('es-CL');
      });
  }

  // ── Modal: Abrir caja ──────────────────────────────────────────────────
  function _showOpenModal() {
    var container = document.getElementById('cash-open-breakdown');
    if (container) {
      container.innerHTML = _renderBreakdown('open_');
      // Resetear valores
      DENOMINATIONS.forEach(function(d) {
        var el = document.getElementById('open_qty_' + d.value);
        if (el) el.value = '0';
      });
      document.getElementById('open_total').textContent = '$0';
    }
    openModal('cash-open-modal');
  }

  function _confirmOpen() {
    var breakdown = _collectBreakdown('open_');
    var total = _updateBreakdownTotal('open_');
    if (total <= 0 && !confirm('El monto inicial es $0. ¿Deseas continuar?')) return;

    window.sb.from('cash_sessions').insert({
      store_id: window.storeData.id,
      opened_by: window.storeData.owner_id,
      opening_amount: total,
      opening_breakdown: breakdown
    }).select().single().then(function(r) {
      _currentSession = r.data;
      _renderSession();
      _loadMovements();
      closeModal('cash-open-modal');
      window.showToast('✅ Caja abierta — $' + total.toLocaleString('es-CL'));

      // Abrir cajón
      if (!_openDrawer()) {
        window.showToast('💡 Conecta la impresora para abrir el cajón automáticamente', 'warning');
      }
    }).catch(function(e) { window.showToast('Error: '+e.message,'error'); });
  }

  // ── Modal: Cerrar caja ─────────────────────────────────────────────────
  function _showCloseModal() {
    if (!_currentSession) return;
    var container = document.getElementById('cash-close-breakdown');
    if (container) {
      container.innerHTML = _renderBreakdown('close_');
      DENOMINATIONS.forEach(function(d) {
        var el = document.getElementById('close_qty_' + d.value);
        if (el) {
          // Precargar con breakdown de apertura si existe
          var prev = (_currentSession.opening_breakdown && _currentSession.opening_breakdown[d.value]) || 0;
          el.value = prev;
        }
      });
      _updateBreakdownTotal('close_');

      // Mostrar resumen de operaciones del día
      _loadDaySummary(function(summary) {
        var diffEl = document.getElementById('cash-close-diff');
        if (diffEl) {
          diffEl.style.display = '';
          diffEl.innerHTML = '<div style="display:flex;justify-content:space-between;margin-bottom:4px"><span>🟢 Ventas en efectivo:</span><span>$' + (summary.cashSales||0).toLocaleString('es-CL') + '</span></div>' +
            '<div style="display:flex;justify-content:space-between;margin-bottom:4px"><span>🟣 Ingresos:</span><span>$' + (summary.ingresos||0).toLocaleString('es-CL') + '</span></div>' +
            '<div style="display:flex;justify-content:space-between;margin-bottom:4px"><span>🔴 Retiros:</span><span>$' + (summary.retiros||0).toLocaleString('es-CL') + '</span></div>' +
            '<div style="display:flex;justify-content:space-between;font-weight:700;border-top:1px solid var(--border);padding-top:4px;margin-top:4px"><span>📋 Efectivo esperado:</span><span>$' + (summary.expected||0).toLocaleString('es-CL') + '</span></div>';
        }
      });
    }
    openModal('cash-close-modal');
  }

  function _loadDaySummary(callback) {
    var today = new Date().toISOString().split('T')[0];
    var summary = { cashSales: 0, ingresos: 0, retiros: 0, expected: 0 };

    // Ventas en efectivo del día — usa order_payments para incluir pagos split (mixed)
    window.sb.from('orders')
      .select('id').eq('store_id', window.storeData.id)
      .gte('created_at', today)
      .not('status', 'in', '("cancelled","returned")')
      .then(function(orderRes) {
        var validOrderIds = (orderRes.data || []).map(function(o) { return o.id; });
        if (!validOrderIds.length) {
          // Sin órdenes válidas hoy, seguir con movimientos
          return window.sb.from('cash_movements').select('type,amount')
            .eq('store_id', window.storeData.id).gte('created_at', today);
        }
        return window.sb.from('order_payments')
          .select('amount').eq('payment_method', 'cash')
          .in('order_id', validOrderIds)
          .then(function(payRes) {
            summary.cashSales = (payRes.data || []).reduce(function(s, p) { return s + (p.amount || 0); }, 0);
            // Movimientos del día
            return window.sb.from('cash_movements').select('type,amount')
              .eq('store_id', window.storeData.id).gte('created_at', today);
          });
      }).then(function(r) {
        (r.data||[]).forEach(function(m) {
          if (m.type === 'ingreso' && m.payment_method === 'cash') summary.ingresos += (m.amount||0);
          if (m.type === 'retiro') summary.retiros += (m.amount||0); // retiros siempre son efectivo
        });
        summary.expected = (_currentSession.opening_amount||0) + summary.cashSales + summary.ingresos - summary.retiros;
        callback(summary);
      }).catch(function() { callback(summary); });
  }

  function _confirmClose() {
    if (!_currentSession) return;
    var breakdown = _collectBreakdown('close_');
    var total = _updateBreakdownTotal('close_');
    if (total <= 0 && !confirm('El monto final es $0. ¿Deseas continuar?')) return;

    var diff = total - (_currentSession.opening_amount||0);

    window.sb.from('cash_sessions').update({
      closing_amount: total,
      closing_breakdown: breakdown,
      difference: diff,
      status: 'closed',
      closed_by: window.storeData.owner_id,
      closed_at: new Date().toISOString()
    }).eq('id', _currentSession.id).then(function() {
      var msg = '✅ Caja cerrada — Total: $' + total.toLocaleString('es-CL');
      if (diff >= 0) msg += ' (+$' + diff.toLocaleString('es-CL') + ')';
      else msg += ' (−$' + Math.abs(diff).toLocaleString('es-CL') + ')';
      window.showToast(msg);
      _currentSession = null;
      _renderSession();
      _loadMovements();
      closeModal('cash-close-modal');

      if (!_openDrawer()) {
        window.showToast('💡 Conecta la impresora para abrir el cajón automáticamente', 'warning');
      }
    }).catch(function(e) { window.showToast('Error: '+e.message,'error'); });
  }

  // ── Modal: Entrada / Salida de efectivo ──────────────────────────────────
  var _ioType = 'ingreso'; // 'ingreso' | 'retiro'

  function _showIOModal(type) {
    if (!_currentSession) {
      window.showToast('🔒 Debes abrir caja primero', 'error');
      return;
    }
    _ioType = type;
    var title = document.getElementById('cash-io-title');
    var btn = document.getElementById('cash-io-confirm');
    if (title) {
      title.textContent = type === 'ingreso' ? '🟣 Entrada de efectivo' : '🔴 Salida de efectivo';
    }
    if (btn) {
      btn.textContent = type === 'ingreso' ? '🟣 Registrar entrada' : '🔴 Registrar salida';
      btn.style.background = type === 'ingreso' ? '#22c55e' : '#ef4444';
    }

    // Limpiar campos
    var amtEl = document.getElementById('cash-io-amount');
    var descEl = document.getElementById('cash-io-desc');
    if (amtEl) amtEl.value = '';
    if (descEl) descEl.value = '';

    var container = document.getElementById('cash-io-breakdown');
    if (container) {
      container.innerHTML = _renderBreakdown('io_');
      DENOMINATIONS.forEach(function(d) {
        var el = document.getElementById('io_qty_' + d.value);
        if (el) el.value = '0';
      });
      document.getElementById('io_total').textContent = '$0';
    }

    openModal('cash-io-modal');
  }

  function _confirmIO() {
    var amtEl = document.getElementById('cash-io-amount');
    var descEl = document.getElementById('cash-io-desc');
    var amount = parseInt(amtEl && amtEl.value) || 0;
    var description = (descEl && descEl.value || '').trim();

    // Si no hay monto manual, usar el total del desglose
    if (amount <= 0) {
      amount = _updateBreakdownTotal('io_');
    }

    if (amount <= 0) {
      window.showToast('Ingresa un monto mayor a $0', 'error');
      return;
    }
    if (!description) {
      window.showToast('Ingresa una descripción', 'error');
      return;
    }

    var breakdown = _collectBreakdown('io_');

    window.sb.from('cash_movements').insert({
      store_id: window.storeData.id,
      session_id: _currentSession.id,
      type: _ioType,
      amount: amount,
      payment_method: 'cash',
      description: description,
      created_by: window.storeData.owner_id
    }).then(function(r) {
      if (r.error) { window.showToast('Error: ' + r.error.message, 'error'); return; }
      var label = _ioType === 'ingreso' ? 'Entrada' : 'Salida';
      window.showToast('✅ ' + label + ' registrada — $' + amount.toLocaleString('es-CL'));
      closeModal('cash-io-modal');
      _loadMovements();

      if (!_openDrawer()) {
        window.showToast('💡 Conecta la impresora para abrir el cajón automáticamente', 'warning');
      }
    }).catch(function(e) { window.showToast('Error: ' + e.message, 'error'); });
  }

  // ── Refrescar barra de impresora (llamado por printer._notify) ──────────
  function _refreshPrinterBar() {
    // La caja no tiene barra de impresora visible; no-op por ahora.
    // Si en el futuro se agrega, refrescar aquí.
  }

  // ── Destroy ────────────────────────────────────────────────────────────
  function destroy() {
    _currentSession = null;
  }

  // ── Registrar módulo ──────────────────────────────────────────────────
  window.GoBusiness.modules.caja = {
    render: render,
    destroy: destroy,
    // Apertura / cierre
    _showOpenModal: _showOpenModal,
    _confirmOpen: _confirmOpen,
    _showCloseModal: _showCloseModal,
    _confirmClose: _confirmClose,
    // Entrada / salida
    _showIOModal: _showIOModal,
    _confirmIO: _confirmIO,
    // Helpers de denominaciones
    _updateBreakdownTotal: _updateBreakdownTotal,
    _renderBreakdown: _renderBreakdown,
    // Printer
    _refreshPrinterBar: _refreshPrinterBar
  };
})();
