// ============================================================================
// Go Business 2.0 — Módulo Clientes
// ============================================================================
(function() {
  'use strict';

  function render() {
    var c = document.getElementById('section-clients');
    if (!c) return;
    if (!window.storeData) return;
    c.innerHTML = '<div style="padding:24px"><div class="card"><div class="card-header"><h3>👥 Clientes</h3></div>' +
      '<div id="clients-loading" style="padding:24px;text-align:center;color:var(--muted)">Cargando...</div>' +
      '<table style="display:none" id="clients-table"><thead><tr><th>Cliente</th><th>Pedidos</th><th>Total comprado</th><th>Última compra</th><th>Canal principal</th></tr></thead><tbody id="clients-body"></tbody></table>' +
      '</div></div>';
    _load();
  }

  function _load() {
    window.sb.from('orders')
      .select('id,total,created_at,order_source,status,users!client_id(name,email,phone)')
      .eq('store_id', window.storeData.id)
      .order('created_at', { ascending: false })
      .limit(200)
      .then(function(r) {
        var orders = (r.data || []).filter(function(o) { return o.status !== 'cancelled' && o.status !== 'returned'; });
        var clients = {};
        orders.forEach(function(o) {
          var uid = o.users ? (o.users.email || o.users.phone || o.client_id) : o.client_id;
          if (!uid) return;
          if (!clients[uid]) {
            clients[uid] = {
              name: (o.users && o.users.name) || (o.users && o.users.email) || 'Cliente',
              email: o.users && o.users.email,
              phone: o.users && o.users.phone,
              total: 0, count: 0, lastDate: null, sources: {}
            };
          }
          clients[uid].total += o.total || 0;
          clients[uid].count++;
          if (!clients[uid].lastDate || o.created_at > clients[uid].lastDate) clients[uid].lastDate = o.created_at;
          var src = o.order_source || 'GO_DELI';
          clients[uid].sources[src] = (clients[uid].sources[src] || 0) + 1;
        });
        var list = Object.entries(clients).sort(function(a,b) { return b[1].total - a[1].total; });
        document.getElementById('clients-loading').style.display = 'none';
        var table = document.getElementById('clients-table');
        var tbody = document.getElementById('clients-body');
        if (!list.length) {
          tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--muted);padding:24px">No hay clientes registrados aún</td></tr>';
        } else {
          tbody.innerHTML = list.map(function(e) {
            var cl = e[1];
            var topSource = Object.entries(cl.sources).sort(function(a,b){return b[1]-a[1]})[0];
            return '<tr>' +
              '<td><strong>' + _esc(cl.name) + '</strong><br><span style="font-size:12px;color:var(--muted)">' + _esc(cl.phone||cl.email||'') + '</span></td>' +
              '<td>' + cl.count + '</td>' +
              '<td><strong>$' + Math.round(cl.total).toLocaleString('es-CL') + '</strong></td>' +
              '<td style="font-size:12px">' + (cl.lastDate ? new Date(cl.lastDate).toLocaleDateString('es-CL') : '-') + '</td>' +
              '<td><span class="badge badge-blue">' + (topSource ? topSource[0] : '-') + '</span></td>' +
              '</tr>';
          }).join('');
        }
        table.style.display = '';
      });
  }

  function _esc(s) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

  window.GoBusiness.modules.clients = { render: render, destroy: function(){} };
})();
