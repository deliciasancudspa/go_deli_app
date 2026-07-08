// ============================================================================
// Go Business 2.0 — Módulo Mi Negocio (Horarios + Perfil + Delivery Config)
// ============================================================================

(function() {
  'use strict';

  function showToast(msg, type) { if (typeof window.showToast === 'function') window.showToast(msg, type); }
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  var DAYS = ['Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo'];

  // ── HORARIOS ─────────────────────────────────────────────────────────
  function buildHorarios(containerId) {
    var container = document.getElementById(containerId);
    if (!container) return;
    var storeData = window.storeData;
    var schedule = {};
    try { if (storeData?.schedule) schedule = typeof storeData.schedule === 'string' ? JSON.parse(storeData.schedule) : storeData.schedule; } catch(e) {}
    container.innerHTML = DAYS.map(function(day) {
      var s = schedule[day] || { open:'09:00', close:'22:00', closed: (day === 'Domingo') };
      return '<div class="schedule-row">' +
        '<label><input type="checkbox" class="day-check" data-day="' + day + '" ' + (s.closed ? '' : 'checked') + ' onchange="GoBusiness.modules.mi_negocio._toggleDay(this)"> ' + day + '</label>' +
        '<input type="time" value="' + (s.open||'09:00') + '" class="time-open" data-day="' + day + '" ' + (s.closed ? 'disabled' : '') + '>' +
        '<input type="time" value="' + (s.close||'22:00') + '" class="time-close" data-day="' + day + '" ' + (s.closed ? 'disabled' : '') + '>' +
        '<span style="font-size:12px;color:' + (s.closed ? 'var(--error)' : 'var(--success)') + '">' + (s.closed ? 'Cerrado' : 'Abierto') + '</span>' +
      '</div>';
    }).join('');
  }

  function toggleDay(cb) {
    var row = cb.closest('.schedule-row');
    var inputs = row ? row.querySelectorAll('input[type=time]') : [];
    inputs.forEach(function(i) { i.disabled = !cb.checked; });
  }

  async function saveHorarios() {
    var storeData = window.storeData;
    if (!storeData) return;
    var schedule = {};
    document.querySelectorAll('.schedule-row').forEach(function(row) {
      var cb = row.querySelector('.day-check');
      var day = cb?.dataset.day;
      if (!day) return;
      var open  = row.querySelector('.time-open')?.value || '09:00';
      var close = row.querySelector('.time-close')?.value || '22:00';
      schedule[day] = { open: open, close: close, closed: !cb.checked };
    });
    var res = await window.sb.from('stores').update({ schedule: JSON.stringify(schedule) }).eq('id', storeData.id);
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    if (storeData) storeData.schedule = JSON.stringify(schedule);
    showToast('Horarios guardados');
  }

  // ── DELIVERY CONFIG ──────────────────────────────────────────────────
  async function loadDeliveryConfig() {
    var storeData = window.storeData;
    if (!storeData) return;
    var deliveryTime = document.getElementById('h-delivery-time');
    var minOrder = document.getElementById('h-min-order');
    if (deliveryTime && storeData.delivery_time) deliveryTime.value = storeData.delivery_time;
    if (minOrder && storeData.min_order != null) minOrder.value = storeData.min_order;

    // Load fee config
    try {
      var res = await window.sb.from('config').select('value').eq('key','delivery_fees').maybeSingle();
      if (res.data?.value) {
        var fees = JSON.parse(res.data.value);
        if (fees.store_portion != null) {
          var portion = fees.store_portion;
          var maxFee = _getDeliveryFeeMax();
          if (portion === 0) selectFeeOption('store');
          else if (portion >= maxFee) selectFeeOption('client');
          else { selectFeeOption('split'); document.getElementById('fee-store-amount').value = portion; syncSplitFee('store'); }
        }
      }
    } catch(e) {}
    buildHorarios('horarios-grid');
  }

  async function saveDeliveryConfig() {
    var storeData = window.storeData;
    if (!storeData) return;
    var deliveryTime = document.getElementById('h-delivery-time');
    var minOrder = document.getElementById('h-min-order');
    var updates = {};
    if (deliveryTime) updates.delivery_time = deliveryTime.value;
    if (minOrder) updates.min_order = parseInt(minOrder.value) || 0;
    await window.sb.from('stores').update(updates).eq('id', storeData.id);
    Object.assign(storeData, updates);

    // Persistir fee split en config.delivery_fees
    var selectedOption = null;
    ['store','client','split'].forEach(function(o) {
      var el = document.getElementById('fee-opt-' + o);
      if (el && el.classList.contains('selected')) selectedOption = o;
    });
    if (selectedOption) {
      var maxFee = _getDeliveryFeeMax();
      var storePortion = 0;
      if (selectedOption === 'store') storePortion = maxFee;    // tienda paga todo → store_portion = maxFee
      else if (selectedOption === 'client') storePortion = 0;    // cliente paga todo → store_portion = 0
      else storePortion = parseInt(document.getElementById('fee-store-amount')?.value) || 0; // split

      try {
        var res = await window.sb.from('config').select('value').eq('key','delivery_fees').maybeSingle();
        var fees = {};
        try { if (res.data?.value) fees = JSON.parse(res.data.value); } catch(e) {}
        fees.store_portion = storePortion;
        await window.sb.from('config').upsert({ key: 'delivery_fees', value: JSON.stringify(fees) }, { onConflict: 'key' });
      } catch(e) { /* non-blocking: el split se guarda como best-effort */ }
    }

    showToast('Configuración de delivery guardada');
  }

  function selectFeeOption(option) {
    ['store','client','split'].forEach(function(o) {
      var el = document.getElementById('fee-opt-' + o);
      if (el) {
        if (o === option) { el.style.border = '2px solid var(--primary)'; el.style.background = '#FFF5F2'; el.classList.add('selected'); }
        else { el.style.border = '2px solid var(--border)'; el.style.background = ''; el.classList.remove('selected'); }
      }
    });
    var panel = document.getElementById('fee-split-panel');
    if (panel) panel.style.display = option === 'split' ? 'block' : 'none';
    updateFeePreview(option);
  }

  function _getDeliveryFeeMax() {
    return (window.storeData && window.storeData.delivery_fee_max) || GoB._config.DELIVERY_FEE_MAX || 2500;
  }

  function syncSplitFee(from) {
    var maxFee = _getDeliveryFeeMax();
    var storeAmt  = parseInt(document.getElementById('fee-store-amount')?.value) || 0;
    var clientAmt = parseInt(document.getElementById('fee-client-amount')?.value) || 0;
    if (from === 'store') {
      clientAmt = maxFee - storeAmt;
      var clientEl = document.getElementById('fee-client-amount');
      if (clientEl) clientEl.value = Math.max(0, clientAmt);
    } else {
      storeAmt = maxFee - clientAmt;
      var storeEl = document.getElementById('fee-store-amount');
      if (storeEl) storeEl.value = Math.max(0, storeAmt);
    }
    updateFeePreview('split');
  }

  function updateFeePreview(option) {
    var preview = document.getElementById('fee-preview');
    if (!preview) return;
    var maxFee = _getDeliveryFeeMax();
    if (option === 'store') preview.textContent = 'Gratis';
    else if (option === 'client') preview.textContent = '$' + maxFee.toLocaleString('es-CL');
    else {
      var clientAmt = parseInt(document.getElementById('fee-client-amount')?.value) || 0;
      preview.textContent = '$' + clientAmt.toLocaleString('es-CL');
    }
  }

  // ── PERFIL ───────────────────────────────────────────────────────────
  function buildCategorySelector(currentCat) {
    var container = document.getElementById('p-category-container');
    if (!container) return;
    var storeData = window.storeData;
    var type = (storeData?.store_type) || window.selectedStoreType || 'restaurante';
    var STORE_CATEGORIES = {
      restaurante: ['Entradas','Sopas','Ensaladas','Carnes','Aves','Mariscos','Pastas','Pizzas','Sushi','Hamburguesas','Sándwiches','Comida Rápida','Café','Jugos','Postres','Bebidas','Otro'],
      mercado:     ['Supermercado','Minimarket','Carnicería','Verdulería','Botillería','Panadería','Rotisería','Otro'],
      tienda:      ['Ropa','Calzado','Tecnología','Ferretería','Librería','Juguetería','Deporte','Hogar','Mascotas','Otro'],
      farmacia:    ['Farmacia','Perfumería','Droguería','Óptica','Otro'],
    };
    var cats = STORE_CATEGORIES[type] || STORE_CATEGORIES.restaurante;
    var selected = (currentCat || '').split(',').map(function(s) { return s.trim(); });
    container.innerHTML = cats.map(function(c) {
      return '<label style="display:flex;align-items:center;gap:6px;font-size:13px;cursor:pointer;padding:6px 12px;border:1.5px solid ' + (selected.indexOf(c) >= 0 ? 'var(--primary)' : 'var(--border)') + ';border-radius:20px;background:' + (selected.indexOf(c) >= 0 ? '#FFF5F2' : 'var(--surface)') + ';font-weight:600">' +
        '<input type="checkbox" value="' + c + '" ' + (selected.indexOf(c) >= 0 ? 'checked' : '') + ' style="accent-color:var(--primary)" onchange="GoBusiness.modules.mi_negocio._updateCategoryInput()"> ' + c +
      '</label>';
    }).join('');
    updateCategoryInput();
  }

  function updateCategoryInput() {
    var container = document.getElementById('p-category-container');
    var hidden = document.getElementById('p-category');
    if (!container || !hidden) return;
    var checked = Array.from(container.querySelectorAll('input:checked')).map(function(cb) { return cb.value; });
    hidden.value = checked.join(',');
  }

  async function savePerfil() {
    var storeData = window.storeData;
    if (!storeData) return;
    var updates = {
      name: document.getElementById('p-name')?.value || '',
      description: document.getElementById('p-desc')?.value || '',
      phone: document.getElementById('p-phone')?.value || '',
      address: document.getElementById('p-address')?.value || '',
      category: document.getElementById('p-category')?.value || '',
      allow_pickup: document.getElementById('p-allow-pickup')?.checked || false,
      latitude: parseFloat(document.getElementById('p-lat')?.value) || null,
      longitude: parseFloat(document.getElementById('p-lng')?.value) || null,
    };
    // Mapear a los nombres de columna reales en la DB (lat/lng, no latitude/longitude)
    updates.lat = updates.latitude;
    updates.lng = updates.longitude;
    delete updates.latitude;
    delete updates.longitude;
    var res = await window.sb.from('stores').update(updates).eq('id', storeData.id);
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    Object.assign(storeData, updates);
    showToast('Perfil actualizado');
  }

  async function saveBrandImages() {
    var storeData = window.storeData;
    if (!storeData) return;
    var logoFile  = document.getElementById('logo-input')?.files[0];
    var coverFile = document.getElementById('cover-input')?.files[0];
    if (!logoFile && !coverFile) { showToast('Selecciona al menos una imagen', 'error'); return; }
    showToast('Subiendo imágenes...');
    try {
      var updates = {};
      if (logoFile && typeof window.uploadToStorage === 'function')  updates.logo_url  = await window.uploadToStorage(logoFile, 'store-images', 'logos');
      if (coverFile && typeof window.uploadToStorage === 'function') updates.cover_url = await window.uploadToStorage(coverFile, 'store-images', 'covers');
      await window.sb.from('stores').update(updates).eq('id', storeData.id);
      Object.assign(storeData, updates);
      showToast('✅ Imágenes actualizadas');
    } catch(e) { showToast('Error: ' + e.message, 'error'); }
  }

  function previewBrandImage(input, previewId, triggerId) {
    var file = input.files[0]; if (!file) return;
    var reader = new FileReader();
    reader.onload = function(e) {
      var img = document.getElementById(previewId);
      if (img) { img.src = e.target.result; img.style.display = 'block'; }
    };
    reader.readAsDataURL(file);
  }

  function geocodeStoreAddress() {
    var address = document.getElementById('p-address')?.value;
    if (!address || !window.google) return;
    var geocoder = new google.maps.Geocoder();
    geocoder.geocode({ address: address + ', Chile' }, function(results, status) {
      if (status === 'OK' && results[0]) {
        var loc = results[0].geometry.location;
        document.getElementById('p-lat').value = loc.lat().toFixed(6);
        document.getElementById('p-lng').value = loc.lng().toFixed(6);
        var coordsText = document.getElementById('p-coords-text');
        if (coordsText) coordsText.textContent = '📍 ' + loc.lat().toFixed(6) + ', ' + loc.lng().toFixed(6);
        initStoreMap();
      }
    });
  }

  function initStoreMap() {
    var mapEl = document.getElementById('store-location-map');
    if (!mapEl || !window.google) return;
    var lat = parseFloat(document.getElementById('p-lat')?.value) || -33.4489;
    var lng = parseFloat(document.getElementById('p-lng')?.value) || -70.6693;
    var map = new google.maps.Map(mapEl, {
      center: { lat: lat, lng: lng }, zoom: 15,
      styles: [{ featureType:'poi',stylers:[{visibility:'off'}] }]
    });
    var marker = new google.maps.Marker({
      position: { lat: lat, lng: lng }, map: map, draggable: true,
      icon: { url:'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="36" height="36" viewBox="0 0 36 36"><circle cx="18" cy="18" r="16" fill="#FF6B00" stroke="#fff" stroke-width="3"/><text x="18" y="23" text-anchor="middle" font-size="16" fill="#fff">📍</text></svg>') }
    });
    marker.addListener('dragend', function() {
      var pos = marker.getPosition();
      document.getElementById('p-lat').value = pos.lat().toFixed(6);
      document.getElementById('p-lng').value = pos.lng().toFixed(6);
      var coordsText = document.getElementById('p-coords-text');
      if (coordsText) coordsText.textContent = '📍 ' + pos.lat().toFixed(6) + ', ' + pos.lng().toFixed(6);
    });
    mapEl._mapInstance = map;
    mapEl._mapMarker = marker;
  }

  // ── RENDER ───────────────────────────────────────────────────────────
  function render() {
    // Show horarios + perfil sections
    var horarios = document.getElementById('section-horarios');
    if (horarios) horarios.style.display = 'block';
    var perfil = document.getElementById('section-perfil');
    if (perfil) perfil.style.display = 'block';

    buildHorarios('horarios-grid');
    loadDeliveryConfig();
    buildCategorySelector(window.storeData?.category || '');

    // Init map after Google Maps loads
    var tryMap = function() {
      if (typeof google !== 'undefined') initStoreMap();
      else setTimeout(tryMap, 400);
    };
    setTimeout(tryMap, 300);
  }

  function destroy() {}

  window.GoBusiness.modules.mi_negocio = {
    render: render, destroy: destroy,
    _buildHorarios: buildHorarios, _saveHorarios: saveHorarios,
    _toggleDay: toggleDay,
    _loadDeliveryConfig: loadDeliveryConfig, _saveDeliveryConfig: saveDeliveryConfig,
    _selectFeeOption: selectFeeOption, _syncSplitFee: syncSplitFee,
    _savePerfil: savePerfil, _buildCategorySelector: buildCategorySelector,
    _updateCategoryInput: updateCategoryInput,
    _saveBrandImages: saveBrandImages, _previewBrandImage: previewBrandImage,
    _geocodeStoreAddress: geocodeStoreAddress, _initStoreMap: initStoreMap,
  };

})();
