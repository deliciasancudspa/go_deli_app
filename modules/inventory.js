// ============================================================================
// Go Business 2.0 — Módulo Inventario
// ============================================================================

(function() {
  'use strict';

  var _products = [];
  var _filterStock = 'all'; // all | low | out
  var _movements = [];

  function render() {
    var c = document.getElementById('section-inventory');
    if (!c) return;
    c.innerHTML =
      '<div class="kpi-grid" style="grid-template-columns:repeat(4,1fr)" id="inv-kpis"></div>' +
      '<div class="card">' +
        '<div class="card-header">' +
          '<h3>Productos</h3>' +
          '<div style="display:flex;gap:8px">' +
            '<select id="inv-filter" onchange="GoBusiness.modules.inventory._filter(this.value)" style="padding:6px 10px;border:1px solid var(--border);border-radius:6px;font-size:12px">' +
              '<option value="all">Todos</option>' +
              '<option value="low">⚠️ Bajo stock mínimo</option>' +
              '<option value="out">❌ Sin stock</option>' +
            '</select>' +
          '</div>' +
        '</div>' +
        '<table>' +
          '<thead><tr><th>Producto</th><th>SKU</th><th>Stock</th><th>Mínimo</th><th>Estado</th><th style="text-align:right">Acciones</th></tr></thead>' +
          '<tbody id="inv-body"></tbody>' +
        '</table>' +
      '</div>' +
      '<div class="card" style="margin-top:20px">' +
        '<div class="card-header"><h3>Últimos movimientos</h3></div>' +
        '<table>' +
          '<thead><tr><th>Fecha</th><th>Producto</th><th>Tipo</th><th>Cantidad</th><th>Stock anterior → nuevo</th><th>Motivo</th></tr></thead>' +
          '<tbody id="inv-mov-body"><tr><td colspan="6" style="text-align:center;color:var(--muted)">Cargando...</td></tr></tbody>' +
        '</table>' +
      '</div>';

    _load();
  }

  function _load() {
    if (!window.storeData) return;
    window.sb.from('menu_items')
      .select('id,name,emoji,sku,stock,stock_min')
      .eq('store_id', window.storeData.id)
      .order('name')
      .then(function(r) {
        _products = r.data || [];
        _renderProducts();
        _renderKPIs();
      });

    window.sb.from('inventory_movements')
      .select('*, menu_items(name,emoji)')
      .eq('store_id', window.storeData.id)
      .order('created_at', { ascending: false })
      .limit(50)
      .then(function(r) {
        _movements = r.data || [];
        _renderMovements();
      });
  }

  function _renderKPIs() {
    var total = _products.length;
    var lowStock = _products.filter(function(p) { return p.stock > 0 && p.stock <= (p.stock_min||5); }).length;
    var outStock = _products.filter(function(p) { return !p.stock || p.stock <= 0; }).length;
    var totalStock = _products.reduce(function(s,p) { return s + (p.stock||0); }, 0);
    var el = document.getElementById('inv-kpis');
    if (!el) return;
    var lowColor = lowStock > 0 ? 'var(--warning)' : 'var(--text)';
    var outColor = outStock > 0 ? 'var(--error)' : 'var(--text)';
    el.innerHTML =
      '<div class="kpi-card"><div class="kpi-icon">📦</div><div class="kpi-label">Productos</div><div class="kpi-value">'+total+'</div></div>' +
      '<div class="kpi-card"><div class="kpi-icon">📋</div><div class="kpi-label">Stock total</div><div class="kpi-value">'+totalStock+'</div></div>' +
      '<div class="kpi-card"><div class="kpi-icon">⚠️</div><div class="kpi-label">Bajo stock</div><div class="kpi-value" style="color:' + lowColor + '">'+lowStock+'</div></div>' +
      '<div class="kpi-card"><div class="kpi-icon">❌</div><div class="kpi-label">Sin stock</div><div class="kpi-value" style="color:' + outColor + '">'+outStock+'</div></div>';
  }

  function _renderProducts() {
    var filtered = _products;
    if (_filterStock === 'low') filtered = filtered.filter(function(p) { return p.stock > 0 && p.stock <= (p.stock_min||5); });
    if (_filterStock === 'out') filtered = filtered.filter(function(p) { return !p.stock || p.stock <= 0; });

    var tbody = document.getElementById('inv-body');
    if (!tbody) return;
    if (!filtered.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--muted);padding:24px">No se encontraron productos</td></tr>';
      return;
    }
    tbody.innerHTML = filtered.map(function(p) {
      var stock = p.stock || 0, min = p.stock_min || 5;
      var badge = stock <= 0 ? '<span class="badge badge-red">Sin stock</span>' :
                  stock <= min ? '<span class="badge badge-yellow">Bajo</span>' :
                  '<span class="badge badge-green">OK</span>';
      return '<tr>' +
        '<td>' + (p.emoji||'📦') + ' <strong>' + _esc(p.name) + '</strong></td>' +
        '<td style="color:var(--muted);font-size:12px">' + (p.sku || '-') + '</td>' +
        '<td><strong>' + stock + '</strong></td>' +
        '<td style="color:var(--muted)">' + min + '</td>' +
        '<td>' + badge + '</td>' +
        '<td style="text-align:right">' +
          '<button class="btn btn-sm" style="background:var(--success);color:#fff;margin-right:4px" onclick="GoBusiness.modules.inventory._quickAdjust(\''+p.id+'\','+stock+',\'entrada\')">+</button>' +
          '<button class="btn btn-sm" style="background:var(--error);color:#fff" onclick="GoBusiness.modules.inventory._quickAdjust(\''+p.id+'\','+stock+',\'salida\')">−</button>' +
        '</td>' +
      '</tr>';
    }).join('');
  }

  function _renderMovements() {
    var tbody = document.getElementById('inv-mov-body');
    if (!tbody) return;
    if (!_movements.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--muted);padding:24px">Sin movimientos registrados</td></tr>';
      return;
    }
    var typeLabels = {entrada:'🟢 Entrada',salida:'🔴 Salida',ajuste:'🔵 Ajuste'};
    tbody.innerHTML = _movements.map(function(m) {
      var pname = m.menu_items ? m.menu_items.name : (m.product_id||'').slice(0,8);
      var date = new Date(m.created_at).toLocaleString('es-CL', {day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
      return '<tr>' +
        '<td style="font-size:12px">' + date + '</td>' +
        '<td>' + _esc(pname) + '</td>' +
        '<td>' + (typeLabels[m.type]||m.type) + '</td>' +
        '<td><strong>' + (m.type==='salida'?'-':'+') + m.quantity + '</strong></td>' +
        '<td style="font-size:12px;color:var(--muted)">' + (m.previous_stock||'-') + ' → ' + (m.new_stock||'-') + '</td>' +
        '<td style="font-size:12px;color:var(--muted)">' + (m.reason||'Ajuste manual') + '</td>' +
      '</tr>';
    }).join('');
  }

  function _quickAdjust(productId, currentStock, type) {
    var qty = prompt('Cantidad (' + (type==='entrada'?'entrada':'salida') + '):', '1');
    if (!qty || isNaN(parseInt(qty))) return;
    qty = parseInt(qty);
    if (qty <= 0) return;
    var newStock = type === 'entrada' ? currentStock + qty : Math.max(0, currentStock - qty);

    window.sb.from('menu_items').update({ stock: newStock }).eq('id', productId)
      .then(function() {
        return window.sb.from('inventory_movements').insert({
          store_id: window.storeData.id,
          product_id: productId,
          type: type,
          quantity: qty,
          previous_stock: currentStock,
          new_stock: newStock,
          reason: 'Ajuste manual desde panel',
          created_by: window.storeData.owner_id
        });
      })
      .then(function() {
        window.showToast('✅ Stock actualizado');
        _load();
      })
      .catch(function(e) { window.showToast('Error: ' + e.message, 'error'); });
  }

  function _filter(val) { _filterStock = val; _renderProducts(); }

  function _esc(s) { return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }

  window.GoBusiness.modules.inventory = {
    render: render, destroy: function(){},
    _filter: _filter, _quickAdjust: _quickAdjust
  };
})();
