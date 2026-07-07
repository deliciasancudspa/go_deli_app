// ============================================================================
// Go Business 2.0 — Módulo Pedidos
// ============================================================================

(function() {
  'use strict';

  var _riderPollInterval = null;

  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function fmtCLP(n) { return '$' + Math.round(n||0).toLocaleString('es-CL'); }
  function showToast(msg, type) { if (typeof window.showToast === 'function') window.showToast(msg, type); }
  function openModal(id) { var el = document.getElementById(id); if (el) el.classList.add('open'); }
  function closeModal(id) { var el = document.getElementById(id); if (el) el.classList.remove('open'); }

  var STATUS = window.STATUS || { pending:'⏳ Nuevo', accepted:'✅ Aceptado', preparing:'👨‍🍳 Preparando', ready:'🎉 Listo', assigned:'🛵 Asignado', picked_up:'📍 Recogido', on_the_way:'🚀 En camino', delivered:'🎊 Entregado', cancelled:'❌ Cancelado' };
  var SBADGE = window.SBADGE || { pending:'badge-yellow', accepted:'badge-blue', preparing:'badge-orange', ready:'badge-green', on_the_way:'badge-orange', delivered:'badge-green', cancelled:'badge-red' };

  function aliadoTotal(o) {
    return (Number(o.total)||0) - (Number(o.service_fee)||0);
  }

  function fmtDate(d) { if(!d) return '-'; return new Date(d).toLocaleString('es-CL',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'}); }

  function getStoreData() { return window.storeData; }
  function getAllOrders() { return window.allOrders || []; }
  function setAllOrders(v) { window.allOrders = v; }

  // ── LOAD ORDERS ──────────────────────────────────────────────────────
  async function loadOrders() {
    var storeData = window.storeData;
    if (!storeData) return;
    var el = document.getElementById('orders-table');
    if (el) el.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    var res = await window.sb.from('orders').select('*, users!client_id(name,email,phone), order_items(item_name,quantity,item_price,subtotal)').eq('store_id', storeData.id).order('created_at',{ascending:false}).limit(100);
    var data = (res.data || []).filter(function(o) {
      return (o.payment_method !== 'webpay' && o.payment_method !== 'khipu' && o.payment_method !== 'mercadopago') || o.payment_status === 'paid';
    });
    window.allOrders = data;
    renderOrders();
  }

  // ── FILTER / RENDER ──────────────────────────────────────────────────
  function filterOrders(status, btn) {
    window.currentOrderFilter = status;
    document.querySelectorAll('#order-filters .period-tab').forEach(function(b) { b.classList.remove('active'); });
    if (btn) btn.classList.add('active');
    renderOrders();
  }

  function renderOrders() {
    var currentFilter = window.currentOrderFilter || 'all';
    var allOrders = getAllOrders();
    var filtered = currentFilter === 'all' ? allOrders : allOrders.filter(function(o) { return o.status === currentFilter; });
    var table = document.getElementById('orders-table');
    if (!table) return;

    if (!filtered.length) {
      table.innerHTML = '<div class="empty"><div class="empty-icon">📦</div><p>Sin pedidos en este estado</p></div>';
      return;
    }

    table.innerHTML = '<table><thead><tr><th>ID</th><th>Tipo</th><th>Cliente</th><th>Total</th><th>Estado</th><th>Hora</th><th>Acciones</th></tr></thead><tbody>' +
      filtered.map(function(o) {
        return '<tr>' +
          '<td style="font-family:monospace;font-size:12px;color:var(--muted)">#' + o.id.slice(0,8) + '</td>' +
          '<td>' + (o.order_type==='pickup'?'<span class="badge badge-green">🏪 Retiro</span>':(o.order_type==='dine_in'?'<span class="badge" style="background:#FDF4FF;color:#6b21a8;border:1px solid #C084FC">🍽️ En local</span>':'<span class="badge badge-blue">🛵 Delivery</span>')) + '</td>' +
          '<td>' + esc(o.users?.name||o.users?.email||'N/A') + '</td>' +
          '<td><strong>' + fmtCLP(aliadoTotal(o)) + '</strong></td>' +
          '<td><span class="badge ' + (SBADGE[o.status]||'badge-gray') + '">' + (STATUS[o.status]||o.status) + '</span></td>' +
          '<td style="color:var(--muted);font-size:12px">' + fmtDate(o.created_at) + '</td>' +
          '<td style="display:flex;gap:6px;flex-wrap:wrap">' +
            '<button class="btn btn-sec btn-sm" onclick="GoBusiness.modules.pedidos._viewOrder(\'' + o.id + '\')">Ver</button>' +
            (['accepted','preparing','ready','assigned'].indexOf(o.status) >= 0 ? '<button class="btn btn-sm" style="background:#374151;color:#fff" onclick="GoBusiness.modules.pedidos._printOrder(\'' + o.id + '\')">🖨️</button>' : '') +
            (o.prescription_url ? '<span class="badge" style="background:#FDF4FF;color:#6b21a8;border:1px solid #C084FC">💊 Receta</span>' : '') +
            (o.status === 'pending' ? '<button class="btn btn-success btn-sm" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'accepted\')">Aceptar</button><button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.pedidos._openReject(\'' + o.id + '\')">Rechazar</button>' : '') +
            (o.status === 'accepted' ? '<button class="btn btn-warning btn-sm" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'preparing\')">👨‍🍳 Preparando</button>' : '') +
            (o.status === 'preparing' ? '<button class="btn btn-success btn-sm" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'ready\')">✅ Listo</button>' : '') +
            (['accepted','preparing','ready'].indexOf(o.status) >= 0 && o.order_type !== 'pickup' && o.order_type !== 'dine_in' && !o.deliverer_id && ['searching','needs_manual','external','assigned'].indexOf(o.rider_search_status) < 0
              ? '<button class="btn btn-primary btn-sm" onclick="GoBusiness.modules.pedidos._callRider(\'' + o.id + '\')">🛵 Llamar Rider</button>' : '') +
            (['searching','needs_manual'].indexOf(o.rider_search_status) >= 0
              ? '<span style="background:#FFF3E8;color:#9A3412;font-size:11px;padding:4px 10px;border-radius:8px;font-weight:600">⏳ Esperando rider...</span>' : '') +
            (o.rider_search_status === 'external' ? '<button class="btn btn-sm" style="background:#7C3AED;color:#fff" onclick="GoBusiness.modules.pedidos._viewOrder(\'' + o.id + '\')">🔑 Ingresar código</button>' : '') +
            (o.status === 'assigned' && o.rider_search_status !== 'external' ? '<button class="btn btn-sm" style="background:#7C3AED;color:#fff" onclick="GoBusiness.modules.pedidos._viewOrder(\'' + o.id + '\')">🔑 Ingresar código</button>' : '') +
          '</td>' +
        '</tr>';
      }).join('') + '</tbody></table>';
  }

  // ── VIEW ORDER ───────────────────────────────────────────────────────
  async function viewOrder(id) {
    var allOrders = getAllOrders();
    var o = allOrders.find(function(x) { return x.id === id; });
    if (!o) return;
    var items = o.order_items || [];
    var content = document.getElementById('order-modal-content');
    if (!content) return;

    var html =
      '<div style="margin-bottom:16px">' +
        '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Tipo</span>' + (o.order_type==='pickup'?'<span class="badge badge-green">🏪 Retiro en tienda</span>':(o.order_type==='dine_in'?'<span class="badge" style="background:#FDF4FF;color:#6b21a8;border:1px solid #C084FC">🍽️ En local</span>':'<span class="badge badge-blue">🛵 Delivery a domicilio</span>')) + '</div>' +
        '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Cliente</span><strong>' + esc(o.users?.name||o.users?.email||'N/A') + '</strong></div>' +
        '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Telefono</span><strong>' + esc(o.users?.phone||'-') + '</strong></div>' +
        ((o.order_type!=='pickup' && o.order_type!=='dine_in') ? '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Direccion</span><strong>' + esc(o.delivery_address||'-') + '</strong></div>' : '') +
        '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Pago</span><strong>' + esc(o.payment_method||'-') + '</strong></div>' +
        '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span style="color:var(--muted);font-size:13px">Estado</span><span class="badge ' + (SBADGE[o.status]||'badge-gray') + '">' + (STATUS[o.status]||o.status) + '</span></div>' +
        (o.notes ? '<div style="background:#FFF5F2;border-radius:10px;padding:12px;margin-top:8px;border:1.5px solid #FFD5C0"><div style="font-weight:700;font-size:13px;color:var(--primary);margin-bottom:4px">📝 Nota del cliente</div><div style="font-size:13px;color:var(--text)">' + esc(o.notes) + '</div></div>' : '') +
      '</div>' +
      (o.prescription_url ? '<div style="background:#FDF4FF;border-radius:12px;padding:16px;margin-bottom:16px;border:2px solid #C084FC">' +
        '<div style="font-weight:800;color:#6b21a8;margin-bottom:4px">💊 Receta médica adjunta</div>' +
        '<p style="font-size:12px;color:#7e22ce;margin-bottom:10px">Revisa la receta ANTES de aceptar.</p>' +
        '<a href="' + o.prescription_url + '" target="_blank"><img src="' + o.prescription_url + '" style="max-width:100%;max-height:320px;border-radius:10px;border:1px solid #E9D5FF;display:block;margin-bottom:10px;cursor:zoom-in" onerror="this.style.display=\'none\'"></a>' +
        '<div style="display:flex;gap:10px">' +
          '<a href="' + o.prescription_url + '" target="_blank" style="padding:8px 16px;background:#7C3AED;color:#fff;border-radius:8px;text-decoration:none;font-weight:700;font-size:13px">🔍 Ampliar</a>' +
          '<a href="' + o.prescription_url + '" download style="padding:8px 16px;background:#fff;color:#6b21a8;border:1px solid #E9D5FF;border-radius:8px;text-decoration:none;font-weight:700;font-size:13px">⬇️ Descargar</a>' +
        '</div>' +
      '</div>' : '') +
      '<div style="border-top:1px solid var(--border);padding-top:16px">' +
        '<p style="font-size:12px;font-weight:700;color:var(--muted);margin-bottom:10px">PRODUCTOS</p>' +
        items.map(function(i) { return '<div style="display:flex;justify-content:space-between;margin-bottom:8px"><span>' + i.quantity + 'x ' + esc(i.item_name) + '</span><strong>' + fmtCLP(i.subtotal) + '</strong></div>'; }).join('') +
        '<div style="display:flex;justify-content:space-between;border-top:1px solid var(--border);padding-top:12px;margin-top:8px">' +
          '<strong>Total</strong><strong style="color:var(--primary);font-size:18px">' + fmtCLP(aliadoTotal(o)) + '</strong>' +
        '</div>' +
      '</div>' +
      '<div style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<button class="btn" style="background:#374151;color:#fff" onclick="GoBusiness.modules.pedidos._printOrder(\'' + o.id + '\')">🖨️ Imprimir</button>' +
        (o.status === 'pending' ? '<button class="btn btn-success" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'accepted\');closeModal(\'order-modal\')">Aceptar pedido</button><button class="btn btn-danger" onclick="closeModal(\'order-modal\');GoBusiness.modules.pedidos._openReject(\'' + o.id + '\')">Rechazar</button>' : '') +
        (o.status === 'accepted' ? '<button class="btn btn-warning" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'preparing\');closeModal(\'order-modal\')">👨‍🍳 Preparando</button>' : '') +
        (o.status === 'preparing' ? '<button class="btn btn-success" onclick="GoBusiness.modules.pedidos._updateStatus(\'' + o.id + '\',\'ready\');closeModal(\'order-modal\')">✅ Listo</button>' : '') +
        (['accepted','preparing','ready'].indexOf(o.status) >= 0 && o.order_type !== 'pickup' && o.order_type !== 'dine_in' && !o.deliverer_id && ['searching','needs_manual','external','assigned'].indexOf(o.rider_search_status) < 0
          ? '<button class="btn btn-primary" onclick="GoBusiness.modules.pedidos._callRider(\'' + o.id + '\');closeModal(\'order-modal\')">🛵 Llamar Rider</button>' : '') +
        (['searching','needs_manual'].indexOf(o.rider_search_status) >= 0
          ? '<span style="background:#FFF3E8;color:#9A3412;font-size:13px;padding:8px 14px;border-radius:8px;font-weight:600">⏳ Esperando rider...</span>' : '') +
        ((o.status === 'assigned' || o.rider_search_status === 'external') && o.order_type !== 'pickup' && o.order_type !== 'dine_in' ?
          '<div style="margin-top:16px;background:#F5F0FF;border-radius:14px;padding:16px;border:2px solid #7C3AED;width:100%">' +
            '<p style="font-weight:800;font-size:13px;margin-bottom:4px;color:#4C1D95">🛵 CÓDIGO DE RETIRO</p>' +
            '<p style="color:#6B7280;font-size:12px;margin-bottom:12px">El repartidor te mostrará un código. Ingrésalo para confirmar que retiró el pedido.</p>' +
            '<div style="display:flex;gap:8px">' +
              '<input type="text" id="rider-code-' + o.id + '" placeholder="CÓDIGO" maxlength="6" inputmode="text" style="text-transform:uppercase;flex:1;padding:10px 14px;border:1.5px solid #7C3AED;border-radius:10px;font-size:24px;font-weight:900;letter-spacing:8px;text-align:center;outline:none;font-family:monospace;background:#fff">' +
              '<button onclick="GoBusiness.modules.pedidos._verifyRiderCode(\'' + o.id + '\')" style="padding:10px 18px;background:#7C3AED;color:#fff;border:none;border-radius:10px;font-weight:700;cursor:pointer">✓ Confirmar</button>' +
            '</div>' +
            '<p id="rider-code-msg-' + o.id + '" style="font-size:12px;margin-top:8px;display:none"></p>' +
          '</div>' : '') +
      '</div>';

    content.innerHTML = html;
    openModal('order-modal');
  }

  // ── UPDATE STATUS ────────────────────────────────────────────────────
  async function updateStatus(id, status) {
    var res = await window.sb.from('orders').update({ status: status }).eq('id', id);
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    showToast('Estado actualizado: ' + (STATUS[status]||status));
    loadOrders();
    if (typeof window.loadDashboard === 'function') window.loadDashboard();
  }

  // ── REJECT ───────────────────────────────────────────────────────────
  function openReject(id) {
    window.rejectOrderId = id;
    openModal('reject-modal');
  }

  async function confirmReject() {
    var reason = document.getElementById('reject-reason')?.value;
    if (!reason) { showToast('Selecciona un motivo', 'error'); return; }
    var obs = document.getElementById('reject-obs')?.value || '';
    await window.sb.from('orders').update({ status:'cancelled', cancel_reason: reason + (obs?' - '+obs:'') }).eq('id', window.rejectOrderId);
    closeModal('reject-modal');
    showToast('Pedido rechazado');
    loadOrders();
    if (typeof window.loadDashboard === 'function') window.loadDashboard();
  }

  // ── ORDER ALERT ──────────────────────────────────────────────────────
  function showOrderAlert(order) {
    window.pendingOrderId = order.id;
    var items = order.order_items || [];
    var details = document.getElementById('alert-order-details');
    if (details) {
      details.innerHTML =
        '<div class="order-detail-row"><span>Productos</span><span>' + items.length + ' item(s)</span></div>' +
        '<div class="order-detail-row"><span>Pago</span><span>' + esc(order.payment_method||'-') + '</span></div>' +
        '<div class="order-detail-row"><span>Total</span><span>' + fmtCLP(aliadoTotal(order)) + '</span></div>';
    }
    var alert = document.getElementById('order-alert');
    if (alert) alert.classList.add('show');
    playAlertSound();
    var secs = 60;
    var timerFill = document.getElementById('timer-fill');
    if (timerFill) timerFill.style.width = '100%';
    if (window.timerInterval) clearInterval(window.timerInterval);
    window.timerInterval = setInterval(function() {
      secs--;
      if (timerFill) timerFill.style.width = (secs/60*100) + '%';
      if (secs <= 0) {
        clearInterval(window.timerInterval);
        if (alert) alert.classList.remove('show');
      }
    }, 1000);
  }

  function playAlertSound() {
    try {
      if (!window.audioCtx) window.audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      var play = function(freq, start, dur) {
        var osc = window.audioCtx.createOscillator();
        var gain = window.audioCtx.createGain();
        osc.connect(gain); gain.connect(window.audioCtx.destination);
        osc.frequency.value = freq; osc.type = 'sine';
        gain.gain.setValueAtTime(0.3, window.audioCtx.currentTime + start);
        gain.gain.exponentialRampToValueAtTime(0.01, window.audioCtx.currentTime + start + dur);
        osc.start(window.audioCtx.currentTime + start);
        osc.stop(window.audioCtx.currentTime + start + dur);
      };
      for (var i = 0; i < 3; i++) { play(880, i*0.4, 0.3); play(1100, i*0.4+0.15, 0.2); }
    } catch(e) {}
  }

  function acceptFromAlert() {
    if (!window.pendingOrderId) return;
    clearInterval(window.timerInterval);
    var alert = document.getElementById('order-alert');
    if (alert) alert.classList.remove('show');
    updateStatus(window.pendingOrderId, 'accepted');
    window.pendingOrderId = null;
  }

  function rejectFromAlert() {
    if (!window.pendingOrderId) return;
    clearInterval(window.timerInterval);
    var alert = document.getElementById('order-alert');
    if (alert) alert.classList.remove('show');
    openReject(window.pendingOrderId);
    window.pendingOrderId = null;
  }

  // ── PRINT ORDER ──────────────────────────────────────────────────────
  async function printOrder(orderId) {
    var allOrders = getAllOrders();
    var o = allOrders.find(function(x) { return x.id === orderId; });
    if (!o) return;
    var res = await window.sb.from('order_items').select('*').eq('order_id', orderId);
    var items = (res.data && res.data.length) ? res.data : (o.order_items || []);
    var storeData = window.storeData;
    var win = window.open('', '_blank', 'width=420,height=650');
    win.document.write('<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Pedido #' + o.id.slice(0,8) + '</title><style>body{font-family:monospace;font-size:13px;padding:16px;max-width:380px;margin:0 auto}h2{text-align:center;font-size:18px}.row{display:flex;justify-content:space-between;margin-bottom:4px}.divider{border-top:1px dashed #000;margin:10px 0}.total{font-size:16px;font-weight:bold}.center{text-align:center}</style></head><body>');
    win.document.write('<h2>' + esc(storeData?.name||'Go Deli') + '</h2>');
    win.document.write('<p class="center" style="color:#666;font-size:12px">' + esc(storeData?.address||'') + '</p>');
    win.document.write('<div class="divider"></div>');
    win.document.write('<div class="row"><span>Pedido #</span><strong>' + o.id.slice(0,8).toUpperCase() + '</strong></div>');
    win.document.write('<div class="row"><span>Fecha</span><span>' + new Date(o.created_at).toLocaleString('es-CL') + '</span></div>');
    win.document.write('<div class="row"><span>Tipo</span><strong>' + (o.order_type==='pickup'?'RETIRO EN TIENDA':(o.order_type==='dine_in'?'EN LOCAL':'DELIVERY')) + '</strong></div>');
    win.document.write('<div class="row"><span>Cliente</span><strong>' + esc(o.users?.name||'N/A') + '</strong></div>');
    if (o.users?.phone) win.document.write('<div class="row"><span>Telefono</span><span>' + esc(o.users.phone) + '</span></div>');
    if (o.order_type!=='pickup' && o.order_type!=='dine_in' && o.delivery_address) win.document.write('<div class="row"><span>Direccion</span><span style="text-align:right;max-width:200px">' + esc(o.delivery_address) + '</span></div>');
    win.document.write('<div class="row"><span>Pago</span><span>' + (o.payment_method==='cash'?'EFECTIVO':o.payment_method==='card'?'TARJETA':'TRANSFERENCIA') + '</span></div>');
    win.document.write('<div class="divider"></div><p style="font-weight:bold;margin-bottom:8px">PRODUCTOS:</p>');
    items.forEach(function(i) { win.document.write('<div class="row"><span>' + i.quantity + 'x ' + esc(i.item_name) + '</span><span>$' + Math.round(i.subtotal||0).toLocaleString('es-CL') + '</span></div>'); });
    win.document.write('<div class="divider"></div>');
    win.document.write('<div class="row total"><span>TOTAL</span><span>$' + Math.round(aliadoTotal(o)).toLocaleString('es-CL') + '</span></div>');
    if (o.special_instructions) win.document.write('<div class="divider"></div><p style="font-size:11px;font-weight:bold">INSTRUCCIONES:</p><p>' + esc(o.special_instructions) + '</p>');
    win.document.write('<div class="divider"></div><p class="center" style="font-size:11px;color:#666">Go Deli - App Delivery</p>');
    win.document.write('<script>window.onload=function(){window.print();window.onafterprint=function(){window.close();};}<\/script></body></html>');
    win.document.close();
  }

  // ── CALL RIDER ───────────────────────────────────────────────────────
  async function callRider(orderId) {
    var allOrders = getAllOrders();
    var localOrder = allOrders.find(function(x) { return x.id === orderId; });
    if (localOrder) localOrder.rider_search_status = 'searching';
    renderOrders();
    try {
      var res = await window.sb.rpc('start_dispatch', { p_order_id: orderId });
      if (res.error) throw res.error;
      if (res.data === 'forbidden') { showToast('No tienes permiso sobre este pedido', 'error'); return; }
      if (typeof res.data === 'string' && res.data.startsWith('needs_manual')) {
        if (localOrder) localOrder.rider_search_status = 'needs_manual';
        renderOrders();
        showToast('Sin repartidores disponibles ahora. El admin fue notificado.', 'error');
      } else {
        showToast('🛵 Buscando repartidor más cercano...');
      }
    } catch(e) {
      showToast('Error al buscar rider: ' + (e.message||e), 'error');
    }
    loadOrders();
    if (typeof window.loadDashboard === 'function') window.loadDashboard();
  }

  // ── VERIFY RIDER CODE ────────────────────────────────────────────────
  async function verifyRiderCode(orderId) {
    var allOrders = getAllOrders();
    var order = allOrders.find(function(x) { return x.id === orderId; });
    if (!order) return;
    var input = document.getElementById('rider-code-' + orderId);
    var msgEl = document.getElementById('rider-code-msg-' + orderId);
    var entered = (input?.value || '').trim().toUpperCase();
    if (!entered) {
      if (msgEl) { msgEl.textContent = 'Ingresa el código'; msgEl.style.display = 'block'; msgEl.style.color = 'var(--error)'; }
      return;
    }
    var storedCode = order.pickup_code || order.delivery_code || '';

    // Check standard codes
    if (storedCode === entered) {
      var isExternal = order.rider_search_status === 'external';
      var res = await window.sb.from('orders').update({
        status: 'on_the_way',
        rider_search_status: 'assigned',
      }).eq('id', orderId);
      if (res.error) {
        if (msgEl) { msgEl.textContent = 'Error al actualizar: ' + res.error.message; msgEl.style.color = 'var(--error)'; }
        return;
      }
      if (msgEl) { msgEl.textContent = '✅ Código correcto. ¡El repartidor ya va en camino!'; msgEl.style.color = 'var(--success)'; msgEl.style.display = 'block'; }
      showToast('🛵 Repartidor en camino');
      setTimeout(function() { closeModal('order-modal'); loadOrders(); if (typeof window.loadDashboard === 'function') window.loadDashboard(); }, 1500);
    } else {
      if (msgEl) { msgEl.textContent = '❌ Código incorrecto. Pídele al repartidor que lo verifique.'; msgEl.style.color = 'var(--error)'; msgEl.style.display = 'block'; }
    }
  }

  // ── RIDER CANCEL ALERT ───────────────────────────────────────────────
  function showRiderCancelAlert(orderId, reason) {
    var el = document.createElement('div');
    el.style.cssText = 'position:fixed;top:20px;right:24px;background:#1A0033;color:#fff;padding:20px 24px;border-radius:16px;z-index:9999;border-left:5px solid #EF4444;max-width:400px;box-shadow:0 8px 32px rgba(0,0,0,0.4);animation:slideIn 0.3s ease';
    el.innerHTML =
      '<div style="font-size:17px;font-weight:900;margin-bottom:6px">🚨 Pedido cancelado por el repartidor</div>' +
      '<div style="color:rgba(255,255,255,0.5);font-size:12px;margin-bottom:10px">Pedido #' + orderId.slice(0,8).toUpperCase() + '</div>' +
      '<div style="background:rgba(239,68,68,0.15);border-radius:10px;padding:12px;font-size:13px;font-weight:500;line-height:1.5">' + esc(reason) + '</div>' +
      '<button onclick="this.parentElement.remove()" style="margin-top:14px;width:100%;padding:8px;background:rgba(255,255,255,0.1);border:none;color:#fff;border-radius:8px;cursor:pointer;font-size:13px;font-weight:600">Entendido</button>';
    document.body.appendChild(el);
    setTimeout(function() { el?.remove(); }, 15000);
  }

  // ── RENDER ───────────────────────────────────────────────────────────
  function render() {
    var section = document.getElementById('section-pedidos');
    if (section) section.style.display = 'block';
    loadOrders();
  }

  function destroy() {
    if (_riderPollInterval) { clearInterval(_riderPollInterval); _riderPollInterval = null; }
  }

  // ── Public API ───────────────────────────────────────────────────────
  var mod = {
    render: render,
    destroy: destroy,
    _loadOrders: loadOrders,
    _filterOrders: filterOrders,
    _renderOrders: renderOrders,
    _viewOrder: viewOrder,
    _updateStatus: updateStatus,
    _openReject: openReject,
    _confirmReject: confirmReject,
    _showOrderAlert: showOrderAlert,
    _acceptFromAlert: acceptFromAlert,
    _rejectFromAlert: rejectFromAlert,
    _printOrder: printOrder,
    _callRider: callRider,
    _verifyRiderCode: verifyRiderCode,
    _showRiderCancelAlert: showRiderCancelAlert,
  };

  window.GoBusiness.modules.pedidos = mod;

})();
