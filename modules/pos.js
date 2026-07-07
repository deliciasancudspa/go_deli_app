// ============================================================================
// Go Business 2.0 — Módulo POS (Punto de Venta)
// ============================================================================

(function() {
  'use strict';

  // ── Estado privado ──────────────────────────────────────────────────────
  var _cart = [];
  var _products = [];
  var _categories = [];
  var _selectedCat = null;
  var _searchTerm = '';
  var _orderMode = 'INMEDIATA';   // INMEDIATA | RETIRO | DELIVERY
  var _orderSource = 'POS';       // POS | WHATSAPP | INSTAGRAM | etc.
  var _deliveryMethod = 'go_rider'; // go_rider | own
  var _paymentMethod = 'cash';
  var _customerName = '';
  var _customerPhone = '';
  var _customerAddress = '';
  var _customerRef = '';
  var _customerNotes = '';

  // ── Barra de impresora ───────────────────────────────────────────────────
  function _printerBar() {
    var printer = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;
    if (!printer) {
      // Módulo no cargado aún — mostrar placeholder con botón de diagnóstico
      return '<div class="pos-printer-bar" style="background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:8px 14px;margin-bottom:14px;font-size:12px;display:flex;align-items:center;gap:8px">' +
        '<span>🖨️</span> <span style="color:var(--muted)">Módulo de impresión no cargado</span>' +
        '<button class="btn btn-sm" style="margin-left:auto;background:var(--error);color:#fff;font-size:11px" onclick="alert(\'navigator.serial=\'+!!(navigator&&navigator.serial)+\'\\nGoBusiness=\'+!!window.GoBusiness+\'\\nmodulos=\'+Object.keys(window.GoBusiness&&window.GoBusiness.modules||{}).join(\',\'))">🔍 Diagnosticar</button></div>';
    }
    var hasSerial = !!(navigator && navigator.serial);
    if (!hasSerial) {
      return '<div class="pos-printer-bar" style="background:#FFF8E1;border:1px solid var(--warning);border-radius:10px;padding:8px 14px;margin-bottom:14px;font-size:12px;display:flex;align-items:center;gap:8px">' +
        '<span>⚠️</span> <span>Impresión no disponible en este navegador. Usa <strong>Chrome o Edge</strong> para conectar impresora térmica y cajón.</span></div>';
    }
    var connected = printer.isConnected();
    var name = printer.getPrinterName();
    if (connected) {
      return '<div class="pos-printer-bar" style="background:#E8FFE8;border:1px solid var(--success);border-radius:10px;padding:8px 14px;margin-bottom:14px;font-size:12px;display:flex;align-items:center;gap:8px">' +
        '<span>🖨️</span> <span><strong>' + name + '</strong> conectada</span>' +
        '<span style="margin-left:auto;display:flex;gap:6px">' +
          '<button class="btn btn-sm" style="background:var(--success);color:#fff;font-size:11px" onclick="window._printerAction(\"openDrawer\")">💰 Cajón</button>' +
          '<button class="btn btn-outline btn-sm" style="font-size:11px" onclick="window._printerAction(\"disconnect\")">Desconectar</button>' +
        '</span></div>';
    }
    return '<div class="pos-printer-bar" style="background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:8px 14px;margin-bottom:14px;font-size:12px;display:flex;align-items:center;gap:8px">' +
      '<span>🖨️</span> <span style="color:var(--muted)">Impresora no conectada</span>' +
      '<button class="btn btn-sm" style="margin-left:auto;background:var(--primary);color:#fff;font-size:11px" onclick="window._printerAction(\"connect\")">🔌 Conectar</button></div>';
  }

  // ── Render principal ────────────────────────────────────────────────────
  function render() {
    var container = document.getElementById('section-pos');
    if (!container) return;

    // 🔒 Si la tienda está cerrada, mostrar pantalla de bloqueo
    if (window.storeData && !window.storeData.is_open) {
      container.innerHTML =
        '<div style="display:flex;align-items:center;justify-content:center;min-height:60vh;flex-direction:column;gap:20px">' +
          '<div style="font-size:64px">🔒</div>' +
          '<h2 style="font-size:20px;font-weight:800;color:var(--text);text-align:center">Tienda cerrada</h2>' +
          '<p style="color:var(--muted);text-align:center;max-width:400px;font-size:14px;line-height:1.5">' +
            'Para usar el Punto de Venta y registrar ventas, tu tienda debe estar <strong>abierta</strong>.<br>' +
            'Esto asegura que tus clientes también puedan encontrarte en la app.' +
          '</p>' +
          '<button class="btn-primary" onclick="GoBusiness.modules.pos._openStoreFromPOS()" style="width:auto;padding:14px 32px;font-size:15px">🔓 Abrir tienda ahora</button>' +
        '</div>';
      return;
    }

    container.innerHTML = _printerBar() + '<div class="pos-layout">' +
      // Panel izquierdo: productos
      '<div class="pos-left">' +
        '<div class="pos-search-bar">' +
          '<input type="text" id="pos-search" placeholder="🔍 Buscar producto..." oninput="GoBusiness.modules.pos._onSearch(this.value)">' +
          '<select id="pos-cat-filter" onchange="GoBusiness.modules.pos._onCatFilter(this.value)" style="padding:10px 12px;border:1.5px solid var(--border);border-radius:10px;font-size:13px;background:var(--surface);min-width:160px">' +
            '<option value="">Todas las categorías</option>' +
          '</select>' +
        '</div>' +
        '<div id="pos-products" class="pos-product-grid"></div>' +
      '</div>' +
      // Panel derecho: carrito + configuración
      '<div class="pos-right">' +
        '<div class="pos-config">' +
          '<div class="pos-field">' +
            '<label>Modalidad</label>' +
            '<select id="pos-mode" onchange="GoBusiness.modules.pos._onModeChange(this.value)">' +
              '<option value="INMEDIATA">⚡ Inmediata</option>' +
              '<option value="RETIRO">🏪 Retiro</option>' +
              '<option value="DELIVERY">🛵 Delivery</option>' +
            '</select>' +
          '</div>' +
          '<div class="pos-field">' +
            '<label>Canal de venta</label>' +
            '<select id="pos-source" onchange="GoBusiness.modules.pos._onSourceChange(this.value)">' +
              '<option value="POS">🖥️ POS</option>' +
              '<option value="WHATSAPP">💬 WhatsApp</option>' +
              '<option value="INSTAGRAM">📷 Instagram</option>' +
              '<option value="FACEBOOK">👍 Facebook</option>' +
              '<option value="TELEFONO">📞 Teléfono</option>' +
              '<option value="WEB">🌐 Web</option>' +
              '<option value="MARKETPLACE">🏪 Marketplace</option>' +
              '<option value="OTRO">📋 Otro</option>' +
            '</select>' +
          '</div>' +
          '<div class="pos-field">' +
            '<label>Método de pago</label>' +
            '<select id="pos-payment" onchange="GoBusiness.modules.pos._onPaymentChange(this.value)"></select>' +
          '</div>' +
        '</div>' +
        // Delivery config (solo visible en modo DELIVERY)
        '<div id="pos-delivery-config" class="pos-delivery-config" style="display:none">' +
          '<div class="pos-field">' +
            '<label>Método de reparto</label>' +
            '<select id="pos-delivery-method" onchange="GoBusiness.modules.pos._onDeliveryMethodChange(this.value)">' +
              '<option value="go_rider">🛵 Go Rider</option>' +
              '<option value="own">🚗 Repartidor propio</option>' +
            '</select>' +
          '</div>' +
          '<div id="pos-customer-form" style="display:none">' +
            '<div class="pos-field"><label>Nombre del cliente</label><input type="text" id="pos-cust-name" placeholder="Nombre completo"></div>' +
            '<div class="pos-field"><label>Teléfono</label><input type="text" id="pos-cust-phone" placeholder="+56 9..."></div>' +
            '<div class="pos-field"><label>Dirección</label><input type="text" id="pos-cust-address" placeholder="Busca tu dirección..." autocomplete="off"><input type="hidden" id="pos-cust-lat"><input type="hidden" id="pos-cust-lng"></div>' +
            '<div class="pos-field"><label>Referencia</label><input type="text" id="pos-cust-ref" placeholder="Casa azul, depto 3B..."></div>' +
            '<div class="pos-field"><label>Notas</label><input type="text" id="pos-cust-notes" placeholder="Timbre no funciona, llamar..."></div>' +
          '</div>' +
        '</div>' +
        // Carrito
        '<div class="pos-cart">' +
          '<div class="pos-cart-header"><h3>🛒 Pedido actual</h3><button class="btn btn-sec btn-sm" onclick="GoBusiness.modules.pos._clearCart()">Vaciar</button></div>' +
          '<div id="pos-cart-items" class="pos-cart-items">' +
            '<p style="text-align:center;color:var(--muted);padding:40px 0">Selecciona productos del catálogo</p>' +
          '</div>' +
          '<div class="pos-cart-footer">' +
            '<div class="pos-cart-row"><span>Subtotal</span><span id="pos-subtotal">$0</span></div>' +
            '<div class="pos-cart-row" id="pos-delivery-row" style="display:none"><span>Delivery</span><span id="pos-delivery-fee">$0</span></div>' +
            '<div class="pos-cart-row pos-cart-total"><span>Total</span><span id="pos-total">$0</span></div>' +
            '<button class="btn-primary" id="pos-submit-btn" onclick="GoBusiness.modules.pos._submitOrder()" style="margin-top:12px">✅ Confirmar pedido</button>' +
            '<div id="pos-printer-actions" style="margin-top:8px;display:flex;gap:8px">' +
              '<button class="btn btn-sec btn-sm" onclick="window._printerAction(\"openDrawer\")" title="Abrir cajón de billetes">💰 Abrir cajón</button>' +
              '<button class="btn btn-sm" style="background:#374151;color:#fff" onclick="window._printerAction(\"test\")" title="Imprimir ticket de prueba">🧪 Test</button>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</div>';

    _loadProducts();
    _loadPaymentMethods();
    _bindModeListeners();
    _initAddressAutocomplete();
  }

  // ── Google Places Autocomplete para dirección de delivery ───────────────
  function _initAddressAutocomplete() {
    var addrInput = document.getElementById('pos-cust-address');
    if (!addrInput || addrInput._autocomplete) return;

    // Esperar a que Google Maps esté disponible
    var tryInit = function() {
      if (typeof google !== 'undefined' && google.maps && google.maps.places) {
        var ac = new google.maps.places.Autocomplete(addrInput, {
          componentRestrictions: { country: 'cl' },
          types: ['address']
        });
        ac.addListener('place_changed', function() {
          var place = ac.getPlace();
          if (place && place.geometry) {
            document.getElementById('pos-cust-lat').value = place.geometry.location.lat();
            document.getElementById('pos-cust-lng').value = place.geometry.location.lng();
          } else {
            // Si no se seleccionó una dirección válida, limpiar coordenadas
            document.getElementById('pos-cust-lat').value = '';
            document.getElementById('pos-cust-lng').value = '';
          }
        });
        addrInput._autocomplete = ac;
      } else {
        setTimeout(tryInit, 300);
      }
    };
    tryInit();
  }

  // ── Cargar productos ─────────────────────────────────────────────────────
  function _loadProducts() {
    if (!window.storeData) return;
    window.sb.from('menu_items')
      .select('*, menu_categories(name)')
      .eq('store_id', window.storeData.id)
      .eq('is_available', true)
      .order('name')
      .then(function(res) {
        _products = res.data || [];
        _categories = [];
        var seen = {};
        _products.forEach(function(p) {
          if (p.menu_categories && !seen[p.menu_categories.name]) {
            seen[p.menu_categories.name] = true;
            _categories.push(p.menu_categories.name);
          }
        });
        _categories.sort();
        _renderProducts();
        _renderCatFilter();
      });
  }

  // ── Cargar métodos de pago de la tienda ──────────────────────────────────
  function _loadPaymentMethods() {
    if (!window.storeData) return;
    var methods = window.storeData.payment_methods;
    if (typeof methods === 'string') {
      try { methods = JSON.parse(methods); } catch(e) { methods = null; }
    }
    if (!methods || !Array.isArray(methods)) methods = ['cash','debit','credit','transfer'];
    var labels = {cash:'💵 Efectivo',debit:'🏧 Débito',credit:'💳 Crédito',transfer:'🏦 Transferencia',qr:'📱 QR',webpay:'🌐 Webpay',mercadopago:'🟡 Mercado Pago',go_wallet:'🟣 Go Wallet'};
    var sel = document.getElementById('pos-payment');
    if (!sel) return;
    sel.innerHTML = methods.map(function(m) {
      return '<option value="' + m + '">' + (labels[m] || m) + '</option>';
    }).join('');
  }

  // ── Render productos ────────────────────────────────────────────────────
  function _renderProducts() {
    var grid = document.getElementById('pos-products');
    if (!grid) return;
    var filtered = _products;
    if (_selectedCat) filtered = filtered.filter(function(p) { return p.menu_categories && p.menu_categories.name === _selectedCat; });
    if (_searchTerm) {
      var term = _searchTerm.toLowerCase();
      filtered = filtered.filter(function(p) { return (p.name||'').toLowerCase().indexOf(term) >= 0; });
    }
    if (!filtered.length) {
      grid.innerHTML = '<p style="text-align:center;color:var(--muted);padding:40px">No se encontraron productos</p>';
      return;
    }
    grid.innerHTML = filtered.map(function(p) {
      var price = '$' + (p.price||0).toLocaleString('es-CL');
      var emoji = p.emoji || '📦';
      var imgHtml = p.image_url
        ? '<div class="pos-product-img">' +
            '<span class="pos-product-emoji">' + emoji + '</span>' +
            '<img src="' + _escAttr(p.image_url) + '" alt="" loading="lazy">' +
          '</div>'
        : '<div class="pos-product-emoji">' + emoji + '</div>';
      return '<div class="pos-product-card" onclick="GoBusiness.modules.pos._addToCart(\'' + p.id + '\')">' +
        imgHtml +
        '<div class="pos-product-name">' + _esc(p.name) + '</div>' +
        '<div class="pos-product-price">' + price + '</div>' +
      '</div>';
    }).join('');
  }

  function _renderCatFilter() {
    var sel = document.getElementById('pos-cat-filter');
    if (!sel) return;
    var cur = sel.value;
    sel.innerHTML = '<option value="">Todas las categorías</option>' +
      _categories.map(function(c) { return '<option value="' + c + '">' + c + '</option>'; }).join('');
    sel.value = cur;
  }

  // ── Carrito ──────────────────────────────────────────────────────────────
  function _addToCart(productId) {
    var existing = _cart.find(function(i) { return i.product_id === productId; });
    if (existing) { existing.qty++; }
    else {
      var p = _products.find(function(p) { return p.id === productId; });
      if (!p) return;
      _cart.push({ product_id: p.id, name: p.name, price: p.price||0, qty: 1, image_url: p.image_url || null, emoji: p.emoji || '📦' });
    }
    _renderCart();
  }

  function _removeFromCart(index) {
    _cart.splice(index, 1);
    _renderCart();
  }

  function _clearCart() {
    _cart = [];
    _renderCart();
  }

  function _renderCart() {
    var container = document.getElementById('pos-cart-items');
    if (!container) return;
    if (!_cart.length) {
      container.innerHTML = '<p style="text-align:center;color:var(--muted);padding:40px 0">Selecciona productos del catálogo</p>';
    } else {
      container.innerHTML = _cart.map(function(item, i) {
        var thumbHtml = item.image_url
          ? '<img src="' + _escAttr(item.image_url) + '" alt="" width="40" height="40" style="width:40px;height:40px;object-fit:cover;border-radius:8px;flex-shrink:0">'
          : '<span style="font-size:28px;flex-shrink:0;width:40px;height:40px;display:flex;align-items:center;justify-content:center">' + item.emoji + '</span>';
        return '<div class="pos-cart-item">' +
          thumbHtml +
          '<div style="flex:1"><strong>' + _esc(item.name) + '</strong><br><span style="font-size:12px;color:var(--muted)">$' + item.price.toLocaleString('es-CL') + ' c/u</span></div>' +
          '<div style="display:flex;align-items:center;gap:8px">' +
            '<button class="qty-btn" onclick="GoBusiness.modules.pos._changeQty(' + i + ',-1)">−</button>' +
            '<span style="font-weight:700;min-width:24px;text-align:center">' + item.qty + '</span>' +
            '<button class="qty-btn" onclick="GoBusiness.modules.pos._changeQty(' + i + ',1)">+</button>' +
            '<button class="btn-remove" onclick="GoBusiness.modules.pos._removeFromCart(' + i + ')" style="background:var(--error);color:#fff;border:none;border-radius:6px;width:26px;height:26px;cursor:pointer">×</button>' +
          '</div>' +
        '</div>';
      }).join('');
    }
    _updateTotals();
  }

  function _changeQty(index, delta) {
    if (!_cart[index]) return;
    _cart[index].qty += delta;
    if (_cart[index].qty <= 0) { _cart.splice(index, 1); }
    _renderCart();
  }

  function _updateTotals() {
    var subtotal = _cart.reduce(function(s, i) { return s + (i.price * i.qty); }, 0);
    // Cobrar delivery siempre en modo DELIVERY, con el monto configurado por el aliado
    var deliveryFee = (_orderMode === 'DELIVERY') ? ((window.storeData && window.storeData.delivery_fee_max) || 2500) : 0;
    var total = subtotal + deliveryFee;

    var st = document.getElementById('pos-subtotal'); if (st) st.textContent = '$' + subtotal.toLocaleString('es-CL');
    var df = document.getElementById('pos-delivery-fee'); if (df) df.textContent = '$' + deliveryFee.toLocaleString('es-CL');
    var tt = document.getElementById('pos-total'); if (tt) tt.textContent = '$' + total.toLocaleString('es-CL');
    var dr = document.getElementById('pos-delivery-row'); if (dr) dr.style.display = deliveryFee > 0 ? '' : 'none';
  }

  // ── Eventos de selectores ────────────────────────────────────────────────
  function _bindModeListeners() {
    var modeSel = document.getElementById('pos-mode');
    var delivCfg = document.getElementById('pos-delivery-config');
    var custForm = document.getElementById('pos-customer-form');
    if (modeSel && delivCfg && custForm) {
      delivCfg.style.display = modeSel.value === 'DELIVERY' ? '' : 'none';
      custForm.style.display = modeSel.value === 'DELIVERY' ? '' : 'none';
    }
  }

  function _onModeChange(val) {
    _orderMode = val;
    var delivCfg = document.getElementById('pos-delivery-config');
    var custForm = document.getElementById('pos-customer-form');
    if (delivCfg) delivCfg.style.display = val === 'DELIVERY' ? '' : 'none';
    if (custForm) custForm.style.display = val === 'DELIVERY' ? '' : 'none';
    _updateTotals();
  }

  function _onSourceChange(val) { _orderSource = val; }
  function _onPaymentChange(val) { _paymentMethod = val; }
  function _onDeliveryMethodChange(val) { _deliveryMethod = val; _updateTotals(); }
  function _onSearch(term) { _searchTerm = term; _renderProducts(); }
  function _onCatFilter(cat) { _selectedCat = cat || null; _renderProducts(); }

  // ── Abrir tienda desde el POS ──────────────────────────────────────────────
  async function _openStoreFromPOS() {
    if (!window.storeData) return;
    await window.sb.from('stores').update({ is_open: true }).eq('id', window.storeData.id);
    window.storeData.is_open = true;
    window.showToast('✅ Tienda abierta — POS habilitado');
    render();
    // Actualizar el toggle en la UI global
    if (typeof window.setOnline === 'function') window.setOnline(true);
  }

  // ── Submit ───────────────────────────────────────────────────────────────
  async function _submitOrder() {
    // 🔒 Bloquear si la tienda está cerrada
    if (window.storeData && !window.storeData.is_open) {
      window.showToast('🔒 La tienda está cerrada. Ábrela para registrar ventas.', 'error');
      render(); // Refrescar para mostrar pantalla de bloqueo
      return;
    }
    if (!_cart.length) { window.showToast('Agrega al menos un producto', 'error'); return; }
    if (!window.storeData) { window.showToast('Error: tienda no cargada', 'error'); return; }

    // Validar datos de delivery si corresponde (siempre en modo DELIVERY)
    if (_orderMode === 'DELIVERY') {
      _customerName = document.getElementById('pos-cust-name')?.value.trim() || '';
      _customerPhone = document.getElementById('pos-cust-phone')?.value.trim() || '';
      _customerAddress = document.getElementById('pos-cust-address')?.value.trim() || '';
      var custLat = parseFloat(document.getElementById('pos-cust-lat')?.value) || null;
      var custLng = parseFloat(document.getElementById('pos-cust-lng')?.value) || null;
      _customerRef = document.getElementById('pos-cust-ref')?.value.trim() || '';
      _customerNotes = document.getElementById('pos-cust-notes')?.value.trim() || '';
      if (!_customerName || !_customerPhone || !_customerAddress) {
        window.showToast('Completa nombre, teléfono y dirección del cliente', 'error');
        return;
      }
      // Validar que la dirección sea real (seleccionada del autocomplete de Google)
      if (!custLat || !custLng) {
        window.showToast('Selecciona una dirección válida del listado de Google. Escribe y elige una sugerencia.', 'error');
        return;
      }
    }

    // 🔒 Validar que la caja esté abierta
    var sessionRes = await window.sb.from('cash_sessions')
      .select('*').eq('store_id', window.storeData.id).eq('status', 'open')
      .order('opened_at', { ascending: false }).limit(1);
    if (sessionRes.error || !sessionRes.data || !sessionRes.data.length) {
      window.showToast('🔒 Debes abrir caja para tomar pedidos. Ve a la sección Caja.', 'error');
      return;
    }
    var currentSession = sessionRes.data[0];

    var btn = document.getElementById('pos-submit-btn');
    if (btn) { btn.disabled = true; btn.textContent = '⏳ Creando pedido...'; }

    var subtotal = _cart.reduce(function(s, i) { return s + (i.price * i.qty); }, 0);
    var deliveryFee = (_orderMode === 'DELIVERY') ? ((window.storeData && window.storeData.delivery_fee_max) || 2500) : 0;
    var total = subtotal + deliveryFee;
    var commission = 0; // 0% para POS

    var orderType = _orderMode === 'DELIVERY' ? 'delivery' : (_orderMode === 'RETIRO' ? 'pickup' : 'dine_in');
    var orderStatus = _orderMode === 'INMEDIATA' ? 'delivered' : 'pending';

    var orderData = {
      store_id: window.storeData.id,
      client_id: window.storeData.owner_id,  // POS: aliado actúa en nombre del cliente
      order_source: _orderSource,
      order_mode: _orderMode,
      delivery_method: _deliveryMethod,
      order_type: orderType,
      subtotal: subtotal,
      delivery_fee: deliveryFee,
      total: total,
      platform_commission: commission,
      go_rider_platform_fee: (_orderMode === 'DELIVERY' && _deliveryMethod === 'go_rider') ? 2500 : 0,
      payment_method: _paymentMethod,
      status: orderStatus,
      customer_name: _customerName || null,
      customer_phone: _customerPhone || null,
      customer_address: _customerAddress || null,
      customer_lat: custLat,
      customer_lng: custLng,
      delivery_address: _customerAddress || null,
      delivery_lat: custLat,
      delivery_lng: custLng,
      delivery_reference: _customerRef || null,
      notes: _customerNotes || null,
    };

    // Si la tienda tiene commune_id, usarlo
    if (window.storeData.commune_id) orderData.commune_id = window.storeData.commune_id;

    try {
      var res = await window.sb.from('orders').insert(orderData).select('id').single();
      if (res.error) throw res.error;
      var orderId = res.data.id;

      // Insertar items
      var items = _cart.map(function(i) {
        return {
          order_id: orderId,
          item_name: i.name,
          quantity: i.qty,
          item_price: i.price,
          subtotal: i.price * i.qty
        };
      });
      await window.sb.from('order_items').insert(items);

      // 💵 Registrar movimiento de caja si es efectivo
      if (_paymentMethod === 'cash') {
        window.sb.from('cash_movements').insert({
          store_id: window.storeData.id,
          session_id: currentSession.id,
          type: 'venta',
          payment_method: 'cash',
          amount: total,
          description: 'Pedido #' + (orderId ? orderId.slice(0, 8) : '') + ' — POS'
        }).then(function(){}, function(){});
      }

      window.showToast('✅ Pedido #' + (orderId ? orderId.slice(0,8) : '') + ' creado');
      // El stock se descuenta automáticamente via trigger en la BD (trg_decrement_stock)

      // 🖨️ Auto-imprimir ticket si la impresora está conectada
      var printer = window.GoBusiness.modules.printer;
      if (printer && printer.isConnected()) {
        var printOrder = Object.assign({}, orderData, { id: orderId, items: _cart, order_items: _cart });
        printer.printReceipt(printOrder)
          .then(function() {})
          .catch(function(e) { window.showToast('⚠️ Impresora: ' + e.message, 'error'); });
      }

      _cart = [];
      _renderCart();
    } catch(e) {
      window.showToast('Error: ' + (e.message || 'No se pudo crear el pedido'), 'error');
      if (btn) { btn.disabled = false; btn.textContent = '✅ Confirmar pedido'; }
    }
  }

  // ── Escape ─────────────────────────────────────────────────────────────
  function _esc(s) {
    return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
  // Escape para atributos HTML (solo comillas y &)
  function _escAttr(s) {
    return (s||'').replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }

  // ── Refrescar barra de impresora ────────────────────────────────────────
  function _refreshPrinterBar() {
    var container = document.getElementById('section-pos');
    if (!container) return;
    var bar = container.querySelector('.pos-printer-bar');
    if (!bar) return;
    var temp = document.createElement('div');
    temp.innerHTML = _printerBar();
    var newBar = temp.firstChild;
    bar.parentNode.replaceChild(newBar, bar);
  }

  // ── Destroy ────────────────────────────────────────────────────────────
  function destroy() {
    _cart = [];
    _products = [];
    _categories = [];
  }

  // ── Registrar módulo ──────────────────────────────────────────────────
  window.GoBusiness.modules.pos = {
    render: render,
    destroy: destroy,
    _openStoreFromPOS: _openStoreFromPOS,
    _addToCart: _addToCart,
    _removeFromCart: _removeFromCart,
    _clearCart: _clearCart,
    _changeQty: _changeQty,
    _onSearch: _onSearch,
    _onCatFilter: _onCatFilter,
    _onModeChange: _onModeChange,
    _onSourceChange: _onSourceChange,
    _onPaymentChange: _onPaymentChange,
    _onDeliveryMethodChange: _onDeliveryMethodChange,
    _submitOrder: _submitOrder,
    _refreshPrinterBar: _refreshPrinterBar
  };

})();
