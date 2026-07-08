// ============================================================================
// Go Business 2.0 — Módulo POS (Punto de Venta) v2 — Julio 2026
// ============================================================================
// Cambios: método de pago se selecciona DESPUÉS de confirmar pedido.
// Soporte para múltiples métodos de pago simultáneos (split).
// Campos de comprobante/voucher, descuentos (%)/($), notas del pedido.
// Apertura automática de cajón al recibir efectivo.
// ============================================================================

(function() {
  'use strict';

  console.log('🧪 [POS] pos.js v20260707b CARGADO — flujo con modal de pago post-confirmación');

  // ── Estado privado ──────────────────────────────────────────────────────
  var _cart = [];
  var _products = [];
  var _categories = [];
  var _selectedCat = null;
  var _searchTerm = '';
  var _orderMode = 'INMEDIATA';   // INMEDIATA | RETIRO | DELIVERY
  var _orderSource = 'POS';       // POS | WHATSAPP | INSTAGRAM | etc.
  var _deliveryMethod = 'go_rider'; // go_rider | own
  var _customerName = '';
  var _customerPhone = '';
  var _customerAddress = '';
  var _customerRef = '';
  var _customerNotes = '';
  // Descuento y notas (nuevo)
  var _discountType = 'fixed';    // 'fixed' | 'pct'
  var _discountValue = 0;
  var _orderNotes = '';
  // Estado del modal de pago
  var _pendingOrderData = null;
  var _pendingOrderId = null;
  var _pendingTotal = 0;
  var _cashAmount = 0;            // monto asignado a efectivo en el split
  // Nuevos estados — mejoras julio 2026 v2
  var _customerType = 'none';       // 'none' | 'registered' | 'new'
  var _selectedClientId = null;
  var _selectedClientName = '';
  var _selectedClientPhone = '';
  var _currentProductModal = null;  // estado del modal de variantes/opciones
  var _lastCompletedOrder = null;   // para toast de reimpresión
  var _variantGroupsCache = {};     // lazy-load: groupId → datos
  var _optionGroupsCache = {};      // lazy-load: groupId → datos

  // ── Barra de impresora ───────────────────────────────────────────────────
  function _printerBar() {
    var printer = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;
    if (!printer) {
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
        '</div>' +
        '<div class="pos-cat-chips" id="pos-cat-chips"></div>' +
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
        '</div>' +
        // ── Selector de cliente ──────────────────────────────────────────
        '<div class="pos-customer-section">' +
          '<div class="pos-field"><label>Cliente</label>' +
            '<div class="customer-toggle">' +
              '<label class="cust-toggle-btn active" onclick="GoBusiness.modules.pos._setCustomerType(\'none\', this)"><input type="radio" name="cust-type" checked> Sin cliente</label>' +
              '<label class="cust-toggle-btn" onclick="GoBusiness.modules.pos._setCustomerType(\'registered\', this)"><input type="radio" name="cust-type"> 👤 Registrado</label>' +
              '<label class="cust-toggle-btn" onclick="GoBusiness.modules.pos._setCustomerType(\'new\', this)"><input type="radio" name="cust-type"> ✨ Nuevo</label>' +
            '</div>' +
          '</div>' +
          '<div id="pos-customer-search" style="display:none;position:relative;margin-top:8px">' +
            '<input type="text" id="pos-cust-search-input" placeholder="Buscar por nombre o teléfono..." ' +
              'oninput="GoBusiness.modules.pos._searchCustomers(this.value)" autocomplete="off" ' +
              'style="width:100%;padding:10px 12px;border:1.5px solid var(--border);border-radius:10px;font-size:13px">' +
            '<div id="pos-cust-search-results" class="customer-dropdown"></div>' +
          '</div>' +
          '<div id="pos-customer-new-form" style="display:none;margin-top:8px">' +
            '<div class="pos-field"><input type="text" id="pos-new-cust-name" placeholder="Nombre completo" style="width:100%"></div>' +
            '<div class="pos-field"><input type="text" id="pos-new-cust-phone" placeholder="+56 9..." style="width:100%"></div>' +
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
          // Descuento y notas (NUEVO)
          '<div class="pos-discount-section" style="padding:0 16px;margin-top:8px">' +
            '<div style="display:flex;gap:8px;align-items:center;margin-bottom:8px">' +
              '<span style="font-size:13px;font-weight:600;white-space:nowrap">🏷️ Descuento:</span>' +
              '<input type="number" id="pos-discount-value" value="0" min="0" style="width:80px;padding:6px 8px;border:1.5px solid var(--border);border-radius:6px;text-align:right;font-size:13px" oninput="GoBusiness.modules.pos._onDiscountChange()">' +
              '<select id="pos-discount-type" style="padding:6px 8px;border:1.5px solid var(--border);border-radius:6px;font-size:12px" onchange="GoBusiness.modules.pos._onDiscountChange()">' +
                '<option value="fixed">$</option>' +
                '<option value="pct">%</option>' +
              '</select>' +
            '</div>' +
            '<div class="pos-field" style="margin-bottom:0">' +
              '<input type="text" id="pos-order-notes" placeholder="📝 Indicaciones del pedido..." style="font-size:12px">' +
            '</div>' +
          '</div>' +
          '<div class="pos-cart-footer">' +
            '<div class="pos-cart-row"><span>Subtotal</span><span id="pos-subtotal">$0</span></div>' +
            '<div class="pos-cart-row" id="pos-discount-row" style="display:none"><span>Descuento</span><span id="pos-discount-amount" style="color:var(--success)">$0</span></div>' +
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
    _bindModeListeners();
    _initAddressAutocomplete();
  }

  // ── Google Places Autocomplete para dirección de delivery ───────────────
  function _initAddressAutocomplete() {
    var addrInput = document.getElementById('pos-cust-address');
    if (!addrInput || addrInput._autocomplete) return;

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
        if (res.error) { console.error('[POS] Error cargando productos:', res.error); return; }
        _products = res.data || [];
        _categories = [];
        var seen = {};
        _products.forEach(function(p) {
          if (p.menu_categories && !seen[p.menu_categories.name]) {
            seen[p.menu_categories.name] = true;
            _categories.push({name: p.menu_categories.name, emoji: '📦'});
          }
        });
        _categories.sort(function(a,b) { return a.name.localeCompare(b.name); });
        _renderProducts();
        _renderCatChips();
      }).catch(function(e) {
        console.error('[POS] Error cargando productos:', e);
      });
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

      // Stock badge
      var stockBadge = '';
      var isOutOfStock = false;
      if (p.stock !== null && p.stock !== undefined) {
        if (p.stock <= 0) { stockBadge = '<div class="pos-stock-badge out">Agotado</div>'; isOutOfStock = true; }
        else if (p.stock <= 5) { stockBadge = '<div class="pos-stock-badge low">Quedan ' + p.stock + '</div>'; }
      }

      var opacityStyle = isOutOfStock ? 'opacity:0.5;cursor:default' : '';
      var onClick = isOutOfStock ? '' : 'GoBusiness.modules.pos._openProductModal(\'' + p.id + '\')';

      return '<div class="pos-product-card" onclick="' + onClick + '" style="' + opacityStyle + '">' +
        imgHtml + stockBadge +
        '<div class="pos-product-name">' + _esc(p.name) + '</div>' +
        '<div class="pos-product-price">' + price + '</div>' +
      '</div>';
    }).join('');
  }

  function _renderCatChips() {
    var container = document.getElementById('pos-cat-chips');
    if (!container) return;
    var chips = [{name: 'Todas', emoji: '📋', value: ''}].concat(
      _categories.map(function(cat) {
        return {name: cat.name, emoji: cat.emoji || '📦', value: cat.name};
      })
    );
    container.innerHTML = chips.map(function(chip) {
      var isActive = (!_selectedCat && !chip.value) || (_selectedCat === chip.value);
      return '<button class="pos-cat-chip' + (isActive ? ' active' : '') + '" ' +
        'onclick="GoBusiness.modules.pos._onCatChipClick(\'' + _escAttr(chip.value) + '\', this)" ' +
        'data-value="' + _escAttr(chip.value) + '">' +
        '<span class="chip-emoji">' + chip.emoji + '</span>' +
        '<span class="chip-name">' + _esc(chip.name) + '</span>' +
      '</button>';
    }).join('');
  }

  function _onCatChipClick(value, btn) {
    _selectedCat = value || null;
    document.querySelectorAll('.pos-cat-chip').forEach(function(c) {
      c.classList.toggle('active', c.dataset.value === value);
    });
    _renderProducts();
  }

  // ── Carrito ──────────────────────────────────────────────────────────────
  function _addToCart(productId) {
    var p = _products.find(function(p) { return p.id === productId; });
    if (!p) return;
    // Verificar stock
    if (p.stock !== null && p.stock !== undefined && p.stock <= 0) {
      window.showToast('Sin stock disponible', 'error');
      return;
    }
    var existing = _cart.find(function(i) { return i.product_id === productId && !i.variant_details && !i.option_details; });
    if (existing) { existing.qty++; }
    else {
      _cart.push({ product_id: p.id, name: p.name, price: p.price||0, qty: 1, image_url: p.image_url || null, emoji: p.emoji || '📦', _key: productId });
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
        var variantInfo = '';
        if (item.variant_details) variantInfo += '<br><span style="font-size:11px;color:var(--secondary)">' + _esc(item.variant_details) + '</span>';
        if (item.option_details) variantInfo += '<br><span style="font-size:11px;color:var(--muted)">' + _esc(item.option_details) + '</span>';
        return '<div class="pos-cart-item">' +
          thumbHtml +
          '<div style="flex:1"><strong>' + _esc(item.name) + '</strong>' + variantInfo +
          '<br><span style="font-size:12px;color:var(--muted)">$' + item.price.toLocaleString('es-CL') + ' c/u</span></div>' +
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

  // ── Descuento ───────────────────────────────────────────────────────────
  function _onDiscountChange() {
    var valEl = document.getElementById('pos-discount-value');
    var typeEl = document.getElementById('pos-discount-type');
    _discountValue = parseInt(valEl && valEl.value) || 0;
    _discountType = (typeEl && typeEl.value) || 'fixed';
    _updateTotals();
  }

  function _updateTotals() {
    var subtotal = _cart.reduce(function(s, i) { return s + (i.price * i.qty); }, 0);
    var deliveryFee = (_orderMode === 'DELIVERY') ? ((window.storeData && window.storeData.delivery_fee_max) || 2500) : 0;

    // Calcular descuento
    var discountAmount = 0;
    if (_discountType === 'pct') {
      discountAmount = Math.round(subtotal * _discountValue / 100);
    } else {
      discountAmount = _discountValue;
    }
    if (discountAmount > subtotal) discountAmount = subtotal; // no negativo

    var total = subtotal + deliveryFee - discountAmount;
    if (total < 0) total = 0;

    var st = document.getElementById('pos-subtotal'); if (st) st.textContent = '$' + subtotal.toLocaleString('es-CL');
    var df = document.getElementById('pos-delivery-fee'); if (df) df.textContent = '$' + deliveryFee.toLocaleString('es-CL');
    var tt = document.getElementById('pos-total'); if (tt) tt.textContent = '$' + total.toLocaleString('es-CL');
    var dr = document.getElementById('pos-delivery-row'); if (dr) dr.style.display = deliveryFee > 0 ? '' : 'none';
    var discRow = document.getElementById('pos-discount-row');
    var discAmt = document.getElementById('pos-discount-amount');
    if (discRow) discRow.style.display = discountAmount > 0 ? '' : 'none';
    if (discAmt) discAmt.textContent = '−$' + discountAmount.toLocaleString('es-CL');
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
  function _onDeliveryMethodChange(val) { _deliveryMethod = val; _updateTotals(); }
  function _onSearch(term) { _searchTerm = term; _renderProducts(); }
  function _onCatFilter(cat) { _selectedCat = cat || null; _renderProducts(); }

  // ── MODAL DE PRODUCTO (variantes y opciones) ─────────────────────────────

  function _openProductModal(productId) {
    var p = _products.find(function(p) { return p.id === productId; });
    if (!p) return;

    _currentProductModal = {
      productId: p.id,
      basePrice: p.price || 0,
      qty: 1,
      selectedVariants: {},
      selectedOptions: {},
      variantNames: {},
      optionNames: {},
      stock: p.stock,
      name: p.name,
      emoji: p.emoji || '📦'
    };

    // Cargar variantes y opciones lazy (on-demand)
    // 1. Obtener group_ids asociados al producto desde las tablas puente
    var vgPromise = window.sb.from('menu_item_variant_groups')
      .select('group_id').eq('item_id', productId)
      .then(function(r) {
        var ids = (r.data || []).map(function(v) { return v.group_id; }).filter(Boolean);
        if (!ids.length) return [];
        return window.sb.from('variant_groups').select('id, name')
          .in('id', ids).order('name')
          .then(function(r2) {
            var groups = r2.data || [];
            if (!groups.length) return [];
            var itemPromises = groups.map(function(g) {
              return window.sb.from('variant_items')
                .select('id, name, price_modifier, sort_order')
                .eq('group_id', g.id).order('sort_order')
                .then(function(r3) { g.variant_items = r3.data || []; return g; });
            });
            return Promise.all(itemPromises);
          });
      }).catch(function() { return []; });

    // También parsear variantes inline (JSON antiguo: menu_items.variants)
    var inlineVariants = [];
    if (p.variants) {
      try {
        var raw = typeof p.variants === 'string' ? JSON.parse(p.variants) : p.variants;
        // Soporta array [{name, price}] o objeto con items
        if (Array.isArray(raw) && raw.length > 0) {
          inlineVariants = raw.filter(function(v) { return v && v.name; });
        }
      } catch(e) { console.error('[POS] Error parseando p.variants:', e); }
    }
    // Y variant_groups JSON (tienda-style: [{title, items: [{name, price}]}])
    var inlineVariantGroups = [];
    if (p.variant_groups) {
      try {
        var rawVg = typeof p.variant_groups === 'string' ? JSON.parse(p.variant_groups) : p.variant_groups;
        if (Array.isArray(rawVg) && rawVg.length > 0) {
          inlineVariantGroups = rawVg.filter(function(v) { return v && v.title; });
        }
      } catch(e) { console.error('[POS] Error parseando p.variant_groups:', e); }
    }

    var ogPromise = window.sb.from('menu_item_option_groups')
      .select('group_id').eq('item_id', productId)
      .then(function(r) {
        var ids = (r.data || []).map(function(o) { return o.group_id; }).filter(Boolean);
        if (!ids.length) return [];
        return window.sb.from('option_groups').select('id, name')
          .in('id', ids).order('name')
          .then(function(r2) {
            var groups = r2.data || [];
            if (!groups.length) return [];
            var itemPromises = groups.map(function(g) {
              return window.sb.from('option_items')
                .select('id, name, surcharge, sort_order')
                .eq('group_id', g.id).order('sort_order')
                .then(function(r3) { g.option_items = r3.data || []; return g; });
            });
            return Promise.all(itemPromises);
          });
      }).catch(function() { return []; });

    // También parsear opciones inline (JSON antiguo: menu_items.options)
    var inlineOptions = [];
    if (p.options) {
      try {
        var rawOpt = typeof p.options === 'string' ? JSON.parse(p.options) : p.options;
        if (Array.isArray(rawOpt) && rawOpt.length > 0) {
          inlineOptions = rawOpt.filter(function(o) { return o && o.title; });
        }
      } catch(e) { console.error('[POS] Error parseando p.options:', e); }
    }

    Promise.all([vgPromise, ogPromise]).then(function(results) {
      _variantGroupsCache[productId] = results[0] || [];
      _optionGroupsCache[productId] = results[1] || [];
      // Guardar inline variants/options para el renderizado
      _variantGroupsCache[productId + '_inline'] = inlineVariants;
      _variantGroupsCache[productId + '_inline_groups'] = inlineVariantGroups;
      _optionGroupsCache[productId + '_inline'] = inlineOptions;
      _renderProductModal(p);
    }).catch(function(e) {
      console.error('[POS] Error cargando variantes/opciones:', e);
      _variantGroupsCache[productId] = [];
      _optionGroupsCache[productId] = [];
      _renderProductModal(p);
    });
  }

  function _renderProductModal(p) {
    var vg = _variantGroupsCache[p.id] || [];
    var og = _optionGroupsCache[p.id] || [];
    var inlineVar = _variantGroupsCache[p.id + '_inline'] || [];
    var inlineVarGroups = _variantGroupsCache[p.id + '_inline_groups'] || [];
    var inlineOpt = _optionGroupsCache[p.id + '_inline'] || [];

    var html = '<div class="pm-header">' +
      '<div class="pm-emoji">' + _currentProductModal.emoji + '</div>' +
      '<div><h3>' + _esc(p.name) + '</h3>' +
      '<p class="pm-price">$' + (p.price||0).toLocaleString('es-CL') + '</p></div>' +
      '</div>';

    // DEDUP: eliminar grupos duplicados por id (relacionales)
    var seenVg = {};
    vg = vg.filter(function(g) { if (seenVg[g.id]) return false; seenVg[g.id] = true; return true; });
    // DEDUP items dentro de cada grupo relacional por nombre
    vg.forEach(function(g) {
      var seenVi = {};
      g.variant_items = (g.variant_items || []).filter(function(vi) { if (seenVi[vi.name]) return false; seenVi[vi.name] = true; return true; });
    });
    var seenOg = {};
    og = og.filter(function(g) { if (seenOg[g.id]) return false; seenOg[g.id] = true; return true; });
    og.forEach(function(g) {
      var seenOi = {};
      g.option_items = (g.option_items || []).filter(function(oi) { if (seenOi[oi.name]) return false; seenOi[oi.name] = true; return true; });
    });

    // DEDUP inline: filtrar items repetidos por nombre dentro de cada fuente
    var seenInv = {};
    inlineVar = inlineVar.filter(function(v) { if (seenInv[v.name]) return false; seenInv[v.name] = true; return true; });
    inlineVarGroups.forEach(function(ivg) {
      var seenIvg = {};
      ivg.items = (ivg.items || []).filter(function(vi) { if (seenIvg[vi.name]) return false; seenIvg[vi.name] = true; return true; });
    });
    inlineOpt.forEach(function(iog) {
      var seenIoi = {};
      iog.items = (iog.items || []).filter(function(oi) { if (seenIoi[oi.name]) return false; seenIoi[oi.name] = true; return true; });
    });

    // DEDUP inline vs relacional por nombre
    var relVarNames = [];
    vg.forEach(function(g) { (g.variant_items || []).forEach(function(vi) { relVarNames.push(vi.name.toLowerCase()); }); });
    inlineVar = inlineVar.filter(function(v) { return relVarNames.indexOf((v.name || '').toLowerCase()) < 0; });
    inlineVarGroups = inlineVarGroups.filter(function(ivg) {
      if (!ivg.items) return false;
      ivg.items = ivg.items.filter(function(vi) { return relVarNames.indexOf((vi.name || '').toLowerCase()) < 0; });
      return ivg.items.length > 0;
    });
    var relOptNames = [];
    og.forEach(function(g) { (g.option_items || []).forEach(function(oi) { relOptNames.push(oi.name.toLowerCase()); }); });
    inlineOpt = inlineOpt.filter(function(iog) {
      if (!iog.items) return false;
      iog.items = iog.items.filter(function(oi) { return relOptNames.indexOf((oi.name || '').toLowerCase()) < 0; });
      return iog.items.length > 0;
    });

    console.log('[POS] Modal producto:', p.name,
      'vg:', vg.length, 'og:', og.length,
      'inlineVar:', inlineVar.length, 'inlineVarGroups:', inlineVarGroups.length, 'inlineOpt:', inlineOpt.length,
      'rawVariants:', typeof p.variants, 'rawVariantGroups:', typeof p.variant_groups, 'rawOptions:', typeof p.options);

    var hasAnyVariants = vg.length > 0 || inlineVar.length > 0 || inlineVarGroups.length > 0;
    // Variantes primero ────────────────────────────────────────────────────
    if (hasAnyVariants) {
      html += '<div class="pm-section"><h4>🎨 Variantes</h4>';

      // Relational variant groups
      vg.forEach(function(g) {
        var items = (g.variant_items || []).sort(function(a,b) { return (a.sort_order||0) - (b.sort_order||0); });
        var isRequired = g.required && !g.multi_select;
        html += '<div class="pm-variant-group"><p class="pm-group-name">' + _esc(g.name) + (isRequired ? ' <span class="required">*</span>' : '') + '</p>';
        items.forEach(function(vi) {
          var inputType = isRequired ? 'radio' : 'checkbox';
          html += '<label class="pm-variant-item">' +
            '<input type="' + inputType + '" name="vg_' + g.id + '" value="' + vi.id + '" ' +
            'onchange="GoBusiness.modules.pos._pmOnVariantChange(\'' + g.id + '\', \'' + vi.id + '\', ' + (vi.price_modifier||0) + ', \'' + inputType + '\', \'' + _escAttr(vi.name) + '\')">' +
            '<span>' + _esc(vi.name) + '</span>' +
            (vi.price_modifier ? '<span class="pm-price-adj">+$' + vi.price_modifier.toLocaleString('es-CL') + '</span>' : '') +
          '</label>';
        });
        html += '</div>';
      });

      // Inline simple variants
      if (inlineVar.length) {
        html += '<div class="pm-variant-group"><p class="pm-group-name">Tamaño / Variante</p>';
        inlineVar.forEach(function(v, i) {
          var vid = 'inv_' + i;
          html += '<label class="pm-variant-item">' +
            '<input type="radio" name="vg_inline" value="' + vid + '" ' +
            'onchange="GoBusiness.modules.pos._pmOnVariantChange(\'inline\', \'' + vid + '\', ' + (v.price||0) + ', \'radio\', \'' + _escAttr(v.name) + '\')">' +
            '<span>' + _esc(v.name) + '</span>' +
            (v.price ? '<span class="pm-price-adj">+$' + Math.round(v.price).toLocaleString('es-CL') + '</span>' : '') +
          '</label>';
        });
        html += '</div>';
      }

      // Inline variant groups — tienda style
      if (inlineVarGroups.length) {
        inlineVarGroups.forEach(function(vg) {
          html += '<div class="pm-variant-group"><p class="pm-group-name">' + _esc(vg.title || '') + '</p>';
          (vg.items || []).forEach(function(vi, j) {
            var vid = 'ivg_' + j;
            html += '<label class="pm-variant-item">' +
              '<input type="radio" name="vg_ig_' + _escAttr(vg.title || j) + '" value="' + vid + '" ' +
              'onchange="GoBusiness.modules.pos._pmOnVariantChange(\'ig_' + _escAttr(vg.title || '') + '\', \'' + vid + '\', ' + (vi.price||0) + ', \'radio\', \'' + _escAttr(vi.name) + '\')">' +
              '<span>' + _esc(vi.name) + '</span>' +
              (vi.price ? '<span class="pm-price-adj">+$' + Math.round(vi.price).toLocaleString('es-CL') + '</span>' : '') +
            '</label>';
          });
          html += '</div>';
        });
      }
      html += '</div>';
    }

    // Opciones después ──────────────────────────────────────────────────────
    var hasAnyOptions = og.length > 0 || inlineOpt.length > 0;
    if (hasAnyOptions) {
      html += '<div class="pm-section"><h4>➕ Opciones</h4>';

      // Relational option groups (prioritarias)
      if (og.length) {
        og.forEach(function(g) {
          var items = (g.option_items || []).sort(function(a,b) { return (a.sort_order||0) - (b.sort_order||0); });
          html += '<div class="pm-option-group"><p class="pm-group-name">' + _esc(g.name) + '</p>';
          items.forEach(function(oi) {
            html += '<label class="pm-option-item">' +
              '<input type="checkbox" name="og_' + g.id + '" value="' + oi.id + '" ' +
              'onchange="GoBusiness.modules.pos._pmOnOptionChange(\'' + g.id + '\', \'' + oi.id + '\', ' + (oi.surcharge||0) + ', \'' + _escAttr(oi.name) + '\')">' +
              '<span>' + _esc(oi.name) + '</span>' +
              (oi.surcharge ? '<span class="pm-price-adj">+$' + oi.surcharge.toLocaleString('es-CL') + '</span>' : '') +
            '</label>';
          });
          html += '</div>';
        });
      }

      // Inline options
      if (inlineOpt.length) {
        inlineOpt.forEach(function(optGroup) {
          html += '<div class="pm-option-group"><p class="pm-group-name">' + _esc(optGroup.title || '') + '</p>';
          (optGroup.items || []).forEach(function(oi, k) {
            var oid = 'io_' + k;
            html += '<label class="pm-option-item">' +
              '<input type="checkbox" name="og_inline_' + _escAttr(optGroup.title || k) + '" value="' + oid + '" ' +
              'onchange="GoBusiness.modules.pos._pmOnOptionChange(\'iog_' + _escAttr(optGroup.title || '') + '\', \'' + oid + '\', ' + (oi.price||0) + ', \'' + _escAttr(oi.name) + '\')">' +
              '<span>' + _esc(oi.name) + '</span>' +
              (oi.price ? '<span class="pm-price-adj">+$' + Math.round(oi.price).toLocaleString('es-CL') + '</span>' : '') +
            '</label>';
          });
          html += '</div>';
        });
      }
      html += '</div>';
    }

    // Quantity
    html += '<div class="pm-qty"><label>Cantidad</label>' +
      '<div class="qty-selector">' +
        '<button onclick="GoBusiness.modules.pos._pmChangeQty(-1)">−</button>' +
        '<span id="pm-qty-val">1</span>' +
        '<button onclick="GoBusiness.modules.pos._pmChangeQty(1)">+</button>' +
      '</div></div>';

    // Stock warning
    html += '<div id="pm-stock-warning"></div>';

    // Total
    html += '<div class="pm-total">Total: <strong id="pm-total-price">$' + (p.price||0).toLocaleString('es-CL') + '</strong></div>';

    // Add button
    html += '<button class="btn-primary" id="pm-add-btn" onclick="GoBusiness.modules.pos._pmAddToCart()">Agregar al carrito</button>';

    _showProductModalOverlay(html);
    _pmCheckStock();
  }

  // ── Product modal helpers ────────────────────────────────────────────────

  function _showProductModalOverlay(html) {
    var existing = document.getElementById('product-modal');
    if (existing) existing.remove();
    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay open';
    overlay.id = 'product-modal';
    overlay.innerHTML = '<div class="modal product-modal-dialog">' +
      '<div class="modal-header"><h3>Personalizar producto</h3>' +
      '<button class="modal-close" onclick="GoBusiness.modules.pos._closeProductModal()">✕</button></div>' +
      html + '</div>';
    overlay.addEventListener('click', function(e) {
      if (e.target === overlay) _closeProductModal();
    });
    document.body.appendChild(overlay);
  }

  function _closeProductModal() {
    var el = document.getElementById('product-modal');
    if (el) el.remove();
    _currentProductModal = null;
  }

  function _pmChangeQty(delta) {
    if (!_currentProductModal) return;
    _currentProductModal.qty = Math.max(1, _currentProductModal.qty + delta);
    document.getElementById('pm-qty-val').textContent = _currentProductModal.qty;
    _pmUpdateTotal();
    _pmCheckStock();
  }

  function _pmOnVariantChange(groupId, itemId, priceMod, inputType, itemName) {
    if (!_currentProductModal) return;
    _currentProductModal.variantNames[itemId] = itemName;
    if (inputType === 'radio') {
      _currentProductModal.selectedVariants[groupId] = {id: itemId, priceMod: priceMod, name: itemName};
    } else {
      if (_currentProductModal.selectedVariants[groupId] && _currentProductModal.selectedVariants[groupId].id === itemId) {
        delete _currentProductModal.selectedVariants[groupId];
      } else {
        _currentProductModal.selectedVariants[groupId] = {id: itemId, priceMod: priceMod, name: itemName};
      }
    }
    _pmUpdateTotal();
  }

  function _pmOnOptionChange(groupId, itemId, surcharge, itemName) {
    if (!_currentProductModal) return;
    _currentProductModal.optionNames[itemId] = itemName;
    if (!_currentProductModal.selectedOptions[groupId]) _currentProductModal.selectedOptions[groupId] = [];
    var arr = _currentProductModal.selectedOptions[groupId];
    var idx = arr.findIndex(function(o) { return o.id === itemId; });
    if (idx >= 0) { arr.splice(idx, 1); if (!arr.length) delete _currentProductModal.selectedOptions[groupId]; }
    else { arr.push({id: itemId, surcharge: surcharge, name: itemName}); }
    _pmUpdateTotal();
  }

  function _pmUpdateTotal() {
    if (!_currentProductModal) return;
    var total = _currentProductModal.basePrice;
    Object.values(_currentProductModal.selectedVariants).forEach(function(v) { total += v.priceMod; });
    Object.values(_currentProductModal.selectedOptions).forEach(function(arr) {
      arr.forEach(function(o) { total += o.surcharge; });
    });
    total *= _currentProductModal.qty;
    var el = document.getElementById('pm-total-price');
    if (el) el.textContent = '$' + total.toLocaleString('es-CL');
  }

  function _pmCheckStock() {
    if (!_currentProductModal) return;
    var stock = _currentProductModal.stock;
    var qty = _currentProductModal.qty;
    var warningEl = document.getElementById('pm-stock-warning');
    var addBtn = document.getElementById('pm-add-btn');
    if (!warningEl || !addBtn) return;
    if (stock !== null && stock !== undefined) {
      if (stock <= 0) {
        warningEl.innerHTML = '<div class="pm-warning error">Sin stock disponible</div>';
        addBtn.disabled = true; addBtn.textContent = 'Sin stock';
      } else if (stock < qty) {
        warningEl.innerHTML = '<div class="pm-warning warn">Solo quedan ' + stock + ' disponibles</div>';
        addBtn.disabled = false; addBtn.textContent = 'Agregar al carrito (' + stock + ' disp.)';
      } else {
        warningEl.innerHTML = stock <= 5 ? '<div class="pm-warning info">Quedan ' + stock + ' unidades</div>' : '';
        addBtn.disabled = false; addBtn.textContent = 'Agregar al carrito';
      }
    } else {
      warningEl.innerHTML = '';
      addBtn.disabled = false; addBtn.textContent = 'Agregar al carrito';
    }
  }

  function _pmAddToCart() {
    if (!_currentProductModal) return;
    var pm = _currentProductModal;
    var variantDetails = Object.values(pm.selectedVariants).map(function(v) { return v.name; }).filter(Boolean).join(', ');
    var optionDetails = Object.values(pm.selectedOptions).flat().map(function(o) { return o.name; }).filter(Boolean).join(', ');
    var unitPrice = pm.basePrice;
    Object.values(pm.selectedVariants).forEach(function(v) { unitPrice += v.priceMod; });
    Object.values(pm.selectedOptions).forEach(function(arr) { arr.forEach(function(o) { unitPrice += o.surcharge; }); });
    var key = pm.productId + '|' + variantDetails + '|' + optionDetails;
    var existing = _cart.find(function(i) { return i._key === key; });
    if (existing) { existing.qty += pm.qty; }
    else {
      var p = _products.find(function(p) { return p.id === pm.productId; });
      _cart.push({
        _key: key,
        product_id: pm.productId,
        name: p ? p.name : pm.name,
        price: unitPrice,
        qty: pm.qty,
        image_url: p ? p.image_url : null,
        emoji: p ? (p.emoji || '📦') : pm.emoji,
        variant_details: variantDetails || null,
        option_details: optionDetails || null
      });
    }
    _renderCart();
    _closeProductModal();
    window.showToast('Agregado: ' + (p ? p.name : pm.name));
  }

  // ── SELECTOR DE CLIENTE ──────────────────────────────────────────────────

  function _setCustomerType(type, btn) {
    _customerType = type;
    _selectedClientId = null;
    _selectedClientName = '';
    _selectedClientPhone = '';
    document.querySelectorAll('.cust-toggle-btn').forEach(function(b) { b.classList.remove('active'); });
    if (btn) btn.classList.add('active');
    var searchDiv = document.getElementById('pos-customer-search');
    var newForm = document.getElementById('pos-customer-new-form');
    if (searchDiv) searchDiv.style.display = type === 'registered' ? '' : 'none';
    if (newForm) newForm.style.display = type === 'new' ? '' : 'none';
    if (type !== 'registered') {
      var results = document.getElementById('pos-cust-search-results');
      if (results) results.innerHTML = '';
    }
  }

  var _customerSearchTimeout = null;
  function _searchCustomers(query) {
    if (_customerSearchTimeout) clearTimeout(_customerSearchTimeout);
    if (!query || query.length < 2) {
      document.getElementById('pos-cust-search-results').innerHTML = '';
      return;
    }
    _customerSearchTimeout = setTimeout(function() {
      var term = query.toLowerCase();
      window.sb.from('orders')
        .select('customer_name, customer_phone, client_id')
        .eq('store_id', window.storeData.id)
        .not('customer_name', 'is', null)
        .order('created_at', {ascending: false})
        .limit(50)
        .then(function(r) {
          var seen = {};
          var merged = [];
          (r.data || []).forEach(function(o) {
            var key = (o.customer_phone || o.customer_name || '').toLowerCase();
            if (key && !seen[key] && o.customer_name) {
              seen[key] = true;
              merged.push({id: o.client_id, name: o.customer_name, phone: o.customer_phone});
            }
          });
          var filtered = merged.filter(function(c) {
            return (c.name || '').toLowerCase().indexOf(term) >= 0 ||
                   (c.phone || '').indexOf(term) >= 0;
          }).slice(0, 8);
          _renderCustomerResults(filtered);
        });
    }, 300);
  }

  function _renderCustomerResults(results) {
    var container = document.getElementById('pos-cust-search-results');
    if (!container) return;
    if (!results.length) {
      container.innerHTML = '<div class="cust-no-results">No se encontraron clientes</div>';
      return;
    }
    container.innerHTML = results.map(function(c) {
      return '<div class="cust-result-item" onclick="GoBusiness.modules.pos._selectCustomer(\'' +
        _escAttr(c.id || '') + '\', \'' + _escAttr(c.name || '') + '\', \'' + _escAttr(c.phone || '') + '\')">' +
        '<span class="cust-icon">👤</span>' +
        '<div><strong>' + _esc(c.name) + '</strong>' +
        '<br><span style="font-size:11px;color:var(--muted)">' + _esc(c.phone || 'Sin teléfono') + '</span></div>' +
      '</div>';
    }).join('');
  }

  function _selectCustomer(id, name, phone) {
    _selectedClientId = id || null;
    _selectedClientName = name;
    _selectedClientPhone = phone;
    var input = document.getElementById('pos-cust-search-input');
    if (input) input.value = name + ' (' + (phone || '') + ')';
    document.getElementById('pos-cust-search-results').innerHTML = '';
  }

  // ── TOAST DE IMPRESIÓN POST-PAGO ─────────────────────────────────────────

  function _showPrintToast() {
    var existing = document.getElementById('print-toast');
    if (existing) existing.remove();
    var toast = document.createElement('div');
    toast.id = 'print-toast';
    toast.className = 'print-toast';
    toast.innerHTML =
      '<div class="print-toast-content">' +
        '<p class="print-toast-title">✅ Pedido completado</p>' +
        '<p class="print-toast-sub">#' + (_lastCompletedOrder ? _lastCompletedOrder.id.slice(0, 8) : '') + '</p>' +
        '<div class="print-toast-buttons">' +
          '<button class="print-toast-btn ticket" onclick="GoBusiness.modules.pos._printAction(\'ticket\')">🧾 Ticket</button>' +
          '<button class="print-toast-btn kitchen" onclick="GoBusiness.modules.pos._printAction(\'kitchen\')">👨‍🍳 Comanda</button>' +
          '<button class="print-toast-btn both" onclick="GoBusiness.modules.pos._printAction(\'both\')">📋 Ambos</button>' +
          '<button class="print-toast-btn close" onclick="GoBusiness.modules.pos._dismissPrintToast()">✕ Cerrar</button>' +
        '</div>' +
      '</div>';
    document.body.appendChild(toast);
    _printToastTimeout = setTimeout(function() { _dismissPrintToast(); }, 30000);
  }

  var _printToastTimeout = null;
  function _printAction(action) {
    var printer = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;
    if (!printer || !printer.isConnected()) {
      window.showToast('⚠️ Impresora no conectada', 'error');
      return;
    }
    var order = _lastCompletedOrder;
    if (!order) return;
    var printOrder = {
      id: order.id,
      order_type: order.orderType || 'dine_in',
      items: order.items,
      order_items: order.items,
      payment_method: order.paymentMethod || 'cash',
      payments: order.payments,
      subtotal: order.subtotal || (order.total - (order.deliveryFee || 0)),
      delivery_fee: order.deliveryFee || 0,
      total: order.total
    };
    if (action === 'ticket' || action === 'both') {
      printer.printReceipt(printOrder).catch(function(e) {
        window.showToast('Error al imprimir ticket: ' + e.message, 'error');
      });
    }
    if (action === 'kitchen' || action === 'both') {
      printer.printKitchenTicket(printOrder).catch(function(e) {
        window.showToast('Error al imprimir comanda: ' + e.message, 'error');
      });
    }
    if (action !== 'both') _dismissPrintToast();
    else setTimeout(function() { _dismissPrintToast(); }, 2000);
  }

  function _dismissPrintToast() {
    if (_printToastTimeout) { clearTimeout(_printToastTimeout); _printToastTimeout = null; }
    var el = document.getElementById('print-toast');
    if (el) el.remove();
  }

  // ── Abrir tienda desde el POS ──────────────────────────────────────────────
  async function _openStoreFromPOS() {
    if (!window.storeData) return;
    await window.sb.from('stores').update({ is_open: true }).eq('id', window.storeData.id);
    window.storeData.is_open = true;
    window.showToast('✅ Tienda abierta — POS habilitado');
    render();
    if (typeof window.setOnline === 'function') window.setOnline(true);
  }

  // ── Submit: Crear orden y abrir modal de pago ──────────────────────────
  async function _submitOrder() {
    if (window.storeData && !window.storeData.is_open) {
      window.showToast('🔒 La tienda está cerrada. Ábrela para registrar ventas.', 'error');
      render(); return;
    }
    if (!_cart.length) { window.showToast('Agrega al menos un producto', 'error'); return; }
    if (!window.storeData) { window.showToast('Error: tienda no cargada', 'error'); return; }

    var custLat = null, custLng = null;

    // Validar datos de delivery
    if (_orderMode === 'DELIVERY') {
      _customerName = document.getElementById('pos-cust-name')?.value.trim() || '';
      _customerPhone = document.getElementById('pos-cust-phone')?.value.trim() || '';
      _customerAddress = document.getElementById('pos-cust-address')?.value.trim() || '';
      custLat = parseFloat(document.getElementById('pos-cust-lat')?.value) || null;
      custLng = parseFloat(document.getElementById('pos-cust-lng')?.value) || null;
      _customerRef = document.getElementById('pos-cust-ref')?.value.trim() || '';
      _customerNotes = document.getElementById('pos-cust-notes')?.value.trim() || '';
      if (!_customerName || !_customerPhone || !_customerAddress) {
        window.showToast('Completa nombre, teléfono y dirección del cliente', 'error'); return;
      }
      if (!custLat || !custLng) {
        window.showToast('Selecciona una dirección válida del listado de Google', 'error'); return;
      }
    }

    // Recoger descuento y notas
    _discountType = (document.getElementById('pos-discount-type')?.value) || 'fixed';
    _discountValue = parseInt(document.getElementById('pos-discount-value')?.value) || 0;
    _orderNotes = (document.getElementById('pos-order-notes')?.value || '').trim();

    // Validar caja abierta
    var sessionRes = await window.sb.from('cash_sessions')
      .select('*').eq('store_id', window.storeData.id).eq('status', 'open')
      .order('opened_at', { ascending: false }).limit(1);
    if (sessionRes.error) { console.error('cash_sessions query error:', sessionRes.error); }
    if (sessionRes.error || !sessionRes.data || !sessionRes.data.length) {
      window.showToast('🔒 Debes abrir caja para tomar pedidos. Ve a la sección Caja.', 'error'); return;
    }

    var btn = document.getElementById('pos-submit-btn');
    if (btn) { btn.disabled = true; btn.textContent = '⏳ Creando pedido...'; }

    var subtotal = _cart.reduce(function(s, i) { return s + (i.price * i.qty); }, 0);
    var deliveryFee = (_orderMode === 'DELIVERY') ? ((window.storeData && window.storeData.delivery_fee_max) || 2500) : 0;

    // Calcular descuento
    var discountAmount = 0;
    if (_discountType === 'pct') {
      discountAmount = Math.round(subtotal * _discountValue / 100);
    } else {
      discountAmount = _discountValue;
    }
    if (discountAmount > subtotal) discountAmount = subtotal;

    var dbSubtotal = subtotal - discountAmount;
    var total = dbSubtotal + deliveryFee;
    if (total < 0) total = 0;

    var commission = 0;
    var orderType = _orderMode === 'DELIVERY' ? 'delivery' : (_orderMode === 'RETIRO' ? 'pickup' : 'dine_in');
    var orderStatus = _orderMode === 'INMEDIATA' ? 'delivered' : 'pending';

    var orderData = {
      store_id: window.storeData.id,
      client_id: _selectedClientId || window.storeData.owner_id,
      order_source: _orderSource,
      order_mode: _orderMode,
      delivery_method: orderType === 'delivery' ? _deliveryMethod : null,
      order_type: orderType,
      subtotal: dbSubtotal,
      delivery_fee: deliveryFee,
      total: total,
      discount_type: _discountType,
      discount_value: _discountValue,
      discount: discountAmount,
      platform_commission: commission,
      go_rider_platform_fee: (_orderMode === 'DELIVERY' && _deliveryMethod === 'go_rider') ? 2500 : 0,
      payment_method: 'pending', // se actualiza al confirmar pago
      status: orderStatus,
      customer_name: _customerType === 'new'
        ? ((document.getElementById('pos-new-cust-name')?.value || '').trim() || null)
        : (_customerType === 'registered' ? _selectedClientName : (_customerName || null)),
      customer_phone: _customerType === 'new'
        ? ((document.getElementById('pos-new-cust-phone')?.value || '').trim() || null)
        : (_customerType === 'registered' ? _selectedClientPhone : (_customerPhone || null)),
      customer_address: _customerAddress || null,
      customer_lat: custLat,
      customer_lng: custLng,
      delivery_address: _customerAddress || null,
      delivery_lat: custLat,
      delivery_lng: custLng,
      delivery_reference: _customerRef || null,
      notes: _orderNotes || _customerNotes || null,
    };

    if (window.storeData.commune_id) orderData.commune_id = window.storeData.commune_id;

    try {
      var res = await window.sb.from('orders').insert(orderData).select('id').single();
      if (res.error) throw res.error;
      var orderId = res.data.id;

      // Insertar items (con menu_item_id para trigger de stock)
      var items = _cart.map(function(i) {
        return {
          order_id: orderId,
          menu_item_id: i.product_id,
          item_name: i.name,
          quantity: i.qty,
          item_price: i.price,
          subtotal: i.price * i.qty,
          variant_details: i.variant_details || null,
          option_details: i.option_details || null
        };
      });
      await window.sb.from('order_items').insert(items);

      if (btn) { btn.disabled = false; btn.textContent = '✅ Confirmar pedido'; }

      // Guardar estado para el modal de pago
      _pendingOrderData = orderData;
      _pendingOrderId = orderId;
      _pendingTotal = total;

      // Abrir modal de pago
      console.log('[POS] Orden creada:', orderId, 'total:', total);
      _showPaymentModal(orderData, orderId, total);
    } catch(e) {
      console.error('[POS] Error al crear orden:', e);
      window.showToast('Error: ' + (e.message || 'No se pudo crear el pedido'), 'error');
      if (btn) { btn.disabled = false; btn.textContent = '✅ Confirmar pedido'; }
    }
  }

  // ── MODAL DE PAGO POST-CONFIRMACIÓN ────────────────────────────────────

  var _paymentMethods = []; // [{method: 'cash', amount: 0, voucher: ''}, ...]

  function _showPaymentModal(orderData, orderId, total) {
    console.log('[POS] _showPaymentModal llamado, total:', total);
    var modal = document.getElementById('payment-modal');
    if (!modal) { console.error('[POS] payment-modal no encontrado en el DOM'); window.showToast('Error: modal de pago no disponible', 'error'); return; }

    // Cargar métodos de pago configurados
    var methods = window.storeData && window.storeData.payment_methods;
    if (typeof methods === 'string') {
      try { methods = JSON.parse(methods); } catch(e) { methods = null; }
    }
    if (!methods || !Array.isArray(methods)) methods = ['cash','debit','credit','transfer'];

    var labels = {cash:'💵 Efectivo',debit:'🏧 Débito',credit:'💳 Crédito',transfer:'🏦 Transferencia',qr:'📱 QR',webpay:'🌐 Webpay',mercadopago:'🟡 Mercado Pago',go_wallet:'🟣 Go Wallet'};

    // Renderizar métodos
    var grid = document.getElementById('payment-methods-grid');
    if (grid) {
      grid.innerHTML = methods.map(function(m) {
        return '<div class="pay-method-row" id="pay-row-' + m + '" onclick="GoBusiness.modules.pos._togglePaymentMethod(\'' + m + '\')">' +
          '<input type="checkbox" id="pay-chk-' + m + '" onclick="event.stopPropagation(); GoBusiness.modules.pos._togglePaymentMethod(\'' + m + '\')">' +
          '<span class="pay-method-label">' + (labels[m] || m) + '</span>' +
          '<input type="number" class="pay-method-amount" id="pay-amt-' + m + '" placeholder="$0" min="0" oninput="GoBusiness.modules.pos._updatePaymentSummary()" onclick="event.stopPropagation()">' +
          '</div>';
      }).join('');
    }

    // Mostrar total
    var totalEl = document.getElementById('payment-total-amount');
    if (totalEl) totalEl.textContent = '$' + total.toLocaleString('es-CL');

    // Resetear estado
    _paymentMethods = [];
    _cashAmount = 0;

    // Ocultar secciones condicionales
    var cashSec = document.getElementById('payment-cash-section');
    if (cashSec) cashSec.style.display = 'none';
    var changeDiv = document.getElementById('payment-change');
    if (changeDiv) changeDiv.style.display = 'none';
    var cashRec = document.getElementById('payment-cash-received');
    if (cashRec) cashRec.value = '';
    var voucherFields = document.getElementById('payment-voucher-fields');
    if (voucherFields) voucherFields.innerHTML = '';
    var summary = document.getElementById('payment-summary');
    if (summary) summary.style.display = 'none';

    openModal('payment-modal');
  }

  function _togglePaymentMethod(method) {
    var row = document.getElementById('pay-row-' + method);
    var chk = document.getElementById('pay-chk-' + method);
    var amt = document.getElementById('pay-amt-' + method);

    if (!row || !chk) return;

    var isSelected = row.classList.contains('selected');
    if (isSelected) {
      // Deseleccionar
      row.classList.remove('selected');
      chk.checked = false;
      if (amt) amt.value = '';
      _paymentMethods = _paymentMethods.filter(function(p) { return p.method !== method; });

      // Si se deselecciona efectivo, ocultar sección de efectivo
      if (method === 'cash') {
        var cashSec = document.getElementById('payment-cash-section');
        if (cashSec) cashSec.style.display = 'none';
        _cashAmount = 0;
      }
      // Ocultar voucher
      _updateVoucherFields();
    } else {
      // Seleccionar
      row.classList.add('selected');
      chk.checked = true;
      _paymentMethods.push({ method: method, amount: 0, voucher: '' });

      // Si se selecciona efectivo, mostrar sección
      if (method === 'cash') {
        var cashSec = document.getElementById('payment-cash-section');
        if (cashSec) cashSec.style.display = '';
      }
      // Mostrar voucher si aplica
      _updateVoucherFields();

      // Si es el único método, asignar total automáticamente
      if (_paymentMethods.length === 1 && amt) {
        amt.value = _pendingTotal;
        _paymentMethods[0].amount = _pendingTotal;
        if (method === 'cash') _cashAmount = _pendingTotal;
      }
    }
    _updatePaymentSummary();
  }

  function _updateVoucherFields() {
    var container = document.getElementById('payment-voucher-fields');
    if (!container) return;
    var voucherMethods = _paymentMethods.filter(function(p) {
      return p.method === 'debit' || p.method === 'credit' || p.method === 'transfer';
    });
    if (!voucherMethods.length) {
      container.innerHTML = '';
      return;
    }
    var labels = {debit:'🏧 Débito',credit:'💳 Crédito',transfer:'🏦 Transferencia'};
    container.innerHTML = voucherMethods.map(function(p) {
      return '<div class="form-group" style="margin-bottom:8px"><label>' + (labels[p.method] || p.method) + ' — N° Comprobante</label>' +
        '<input type="text" id="pay-voucher-' + p.method + '" placeholder="N° voucher o comprobante" style="width:100%;font-size:13px" oninput="GoBusiness.modules.pos._onVoucherChange(\'' + p.method + '\', this.value)"></div>';
    }).join('');
  }

  function _onVoucherChange(method, value) {
    var pm = _paymentMethods.find(function(p) { return p.method === method; });
    if (pm) pm.voucher = value;
  }

  function _updatePaymentSummary() {
    var summary = document.getElementById('payment-summary');
    var content = document.getElementById('payment-summary-content');
    var pending = document.getElementById('payment-pending');
    if (!summary || !content || !pending) return;

    // Leer montos de los inputs
    _paymentMethods.forEach(function(pm) {
      var amtEl = document.getElementById('pay-amt-' + pm.method);
      pm.amount = parseInt(amtEl && amtEl.value) || 0;
    });

    var totalAssigned = _paymentMethods.reduce(function(s, pm) { return s + pm.amount; }, 0);
    var diff = _pendingTotal - totalAssigned;

    var labels = {cash:'Efectivo',debit:'Débito',credit:'Crédito',transfer:'Transferencia',qr:'QR',webpay:'Webpay',mercadopago:'Mercado Pago',go_wallet:'Go Wallet'};

    summary.style.display = _paymentMethods.length > 0 ? '' : 'none';
    content.innerHTML = _paymentMethods.map(function(pm) {
      return '<div class="pay-summary-row"><span>' + (labels[pm.method] || pm.method) + (pm.voucher ? ' (# ' + pm.voucher + ')' : '') + '</span><span>$' + (pm.amount||0).toLocaleString('es-CL') + '</span></div>';
    }).join('') +
      '<div class="pay-summary-row pay-summary-total"><span>Total asignado</span><span>$' + totalAssigned.toLocaleString('es-CL') + '</span></div>';

    if (diff > 0) {
      pending.style.display = '';
      pending.textContent = '⚠️ Falta por asignar: $' + diff.toLocaleString('es-CL');
    } else if (diff < 0) {
      pending.style.display = '';
      pending.textContent = '⚠️ Excede el total en: $' + Math.abs(diff).toLocaleString('es-CL');
    } else {
      pending.style.display = 'none';
    }
  }

  function _calcChange() {
    var received = parseInt(document.getElementById('payment-cash-received')?.value) || 0;
    // Leer monto en efectivo directamente del DOM (no de _cashAmount que puede estar desactualizado)
    var cashAmtEl = document.getElementById('pay-amt-cash');
    var cashAmount = parseInt(cashAmtEl && cashAmtEl.value) || 0;
    var changeDiv = document.getElementById('payment-change');

    if (!changeDiv) return;

    if (received > 0 && cashAmount > 0) {
      var change = received - cashAmount;
      changeDiv.style.display = '';
      changeDiv.style.background = change >= 0 ? '#F0FFF4' : '#FFF0F0';
      changeDiv.innerHTML = change >= 0
        ? '💱 Vuelto: <span style="font-size:18px;color:var(--success)">$' + change.toLocaleString('es-CL') + '</span>'
        : '⚠️ Faltan: <span style="font-size:18px;color:var(--error)">$' + Math.abs(change).toLocaleString('es-CL') + '</span>';
    } else {
      changeDiv.style.display = 'none';
    }
  }

  // ── Confirmar pago ──────────────────────────────────────────────────────
  async function _confirmPayment() {
    console.log('[POS] _confirmPayment iniciado, _pendingOrderId:', _pendingOrderId, '_paymentMethods:', _paymentMethods.length);
    if (!_pendingOrderId) {
      window.showToast('Error: no hay pedido pendiente', 'error'); return;
    }

    // Actualizar montos desde inputs
    _paymentMethods.forEach(function(pm) {
      var amtEl = document.getElementById('pay-amt-' + pm.method);
      pm.amount = parseInt(amtEl && amtEl.value) || 0;
      var vchEl = document.getElementById('pay-voucher-' + pm.method);
      if (vchEl) pm.voucher = vchEl.value.trim();
    });

    // Filtrar métodos con monto > 0
    var activePayments = _paymentMethods.filter(function(p) { return p.amount > 0; });
    if (!activePayments.length) {
      window.showToast('Selecciona al menos un método de pago con monto', 'error'); return;
    }

    var totalAssigned = activePayments.reduce(function(s, pm) { return s + pm.amount; }, 0);

    // Validar cash recibido
    var cashPm = activePayments.find(function(p) { return p.method === 'cash'; });
    if (cashPm) {
      _cashAmount = cashPm.amount;
      var received = parseInt(document.getElementById('payment-cash-received')?.value) || 0;
      if (received < _cashAmount) {
        window.showToast('El monto recibido en efectivo ($' + received.toLocaleString('es-CL') + ') no cubre el total en efectivo ($' + _cashAmount.toLocaleString('es-CL') + ')', 'error');
        return;
      }
    }

    if (totalAssigned !== _pendingTotal) {
      if (!confirm('El total asignado ($' + totalAssigned.toLocaleString('es-CL') + ') no coincide con el total del pedido ($' + _pendingTotal.toLocaleString('es-CL') + '). ¿Deseas continuar?')) return;
    }

    var btn = document.getElementById('payment-confirm-btn');
    if (btn) { btn.disabled = true; btn.textContent = '⏳ Registrando pago...'; }

    try {
      // Buscar sesión de caja activa
      var sessionRes = await window.sb.from('cash_sessions')
        .select('id').eq('store_id', window.storeData.id).eq('status', 'open')
        .order('opened_at', { ascending: false }).limit(1);
      var activeSessionId = (sessionRes.data && sessionRes.data.length) ? sessionRes.data[0].id : null;

      // 1. Insertar order_payments
      var payInserts = activePayments.map(function(pm) {
        return {
          order_id: _pendingOrderId,
          payment_method: pm.method,
          amount: pm.amount,
          voucher_number: pm.voucher || null
        };
      });
      await window.sb.from('order_payments').insert(payInserts);

      // 2. Determinar payment_method principal
      var mainMethod = activePayments.length === 1 ? activePayments[0].method : 'mixed';

      // 3. Actualizar orden
      await window.sb.from('orders').update({
        payment_method: mainMethod
      }).eq('id', _pendingOrderId);

      // 4. Registrar cash_movements (solo parte efectivo va a caja)
      if (cashPm) {
        window.sb.from('cash_movements').insert({
          store_id: window.storeData.id,
          session_id: activeSessionId,
          type: 'venta',
          payment_method: 'cash',
          amount: cashPm.amount,
          description: 'Pedido #' + _pendingOrderId.slice(0, 8) + ' — POS',
          order_id: _pendingOrderId
        }).then(function(){}, function(){});
      }

      // 5. Otros métodos (débito, crédito, transferencia) NO generan movimiento de caja
      // Solo se registran en order_payments (ya hecho arriba)

      // 6. Referencia a la impresora
      var printer = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;

      // 7. Guardar orden para toast de reimpresión
      _lastCompletedOrder = {
        id: _pendingOrderId,
        orderType: _pendingOrderData.order_type,
        items: _cart,
        total: _pendingTotal,
        subtotal: _pendingOrderData.subtotal,
        deliveryFee: _pendingOrderData.delivery_fee,
        paymentMethod: mainMethod,
        payments: activePayments
      };

      // 7. Mostrar toast de impresión (ticket/comanda/ambos)
      _showPrintToast();

      // 8. Abrir cajón si hay efectivo
      if (cashPm && printer && printer.safeOpenDrawer) {
        printer.safeOpenDrawer();
      }

      var paymentDesc = activePayments.map(function(pm) {
        return pm.method + ' $' + pm.amount.toLocaleString('es-CL');
      }).join(' + ');

      window.showToast('✅ Pedido #' + _pendingOrderId.slice(0,8) + ' — ' + paymentDesc);

      // Limpiar
      _cart = [];
      _renderCart();
      closeModal('payment-modal');
      _pendingOrderData = null;
      _pendingOrderId = null;
      _pendingTotal = 0;
      _paymentMethods = [];
      _cashAmount = 0;

    } catch(e) {
      window.showToast('Error: ' + (e.message || 'No se pudo registrar el pago'), 'error');
      if (btn) { btn.disabled = false; btn.textContent = '✅ Confirmar pago'; }
    }
  }

  // ── Escape ─────────────────────────────────────────────────────────────
  function _esc(s) {
    return (s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
  }
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
    _pendingOrderData = null;
    _pendingOrderId = null;
    _paymentMethods = [];
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
    _onCatChipClick: _onCatChipClick,
    _onModeChange: _onModeChange,
    _onSourceChange: _onSourceChange,
    _onDeliveryMethodChange: _onDeliveryMethodChange,
    _onDiscountChange: _onDiscountChange,
    _submitOrder: _submitOrder,
    _refreshPrinterBar: _refreshPrinterBar,
    // Modal de pago
    _togglePaymentMethod: _togglePaymentMethod,
    _onVoucherChange: _onVoucherChange,
    _updatePaymentSummary: _updatePaymentSummary,
    _calcChange: _calcChange,
    _confirmPayment: _confirmPayment,
    // Modal de producto (variantes/opciones)
    _openProductModal: _openProductModal,
    _closeProductModal: _closeProductModal,
    _pmChangeQty: _pmChangeQty,
    _pmOnVariantChange: _pmOnVariantChange,
    _pmOnOptionChange: _pmOnOptionChange,
    _pmAddToCart: _pmAddToCart,
    // Selector de cliente
    _setCustomerType: _setCustomerType,
    _searchCustomers: _searchCustomers,
    _selectCustomer: _selectCustomer,
    // Toast de impresión
    _printAction: _printAction,
    _dismissPrintToast: _dismissPrintToast
  };

})();
