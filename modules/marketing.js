// ============================================================================
// Go Business 2.0 — Módulo Marketing (Promociones + Publicidad)
// ============================================================================

(function() {
  'use strict';

  function showToast(msg, type) { if (typeof window.showToast === 'function') window.showToast(msg, type); }
  function openModal(id) { var el = document.getElementById(id); if (el) el.classList.add('open'); }
  function closeModal(id) { var el = document.getElementById(id); if (el) el.classList.remove('open'); }

  var AD_PLANS = {
    banner:   { name: 'Banner Home',          price: 29990, icon: '🎯' },
    featured: { name: 'Tienda Destacada',      price: 49990, icon: '⭐' },
    category: { name: 'Publicidad Redes Sociales', price: 89990, icon: '📱' },
  };
  var selectedAdPlan = 'banner';

  // ── PROMOCIONES ──────────────────────────────────────────────────────
  async function loadPromos() {
    var storeData = window.storeData;
    if (!storeData) return;
    var container = document.getElementById('promos-content');
    if (container) container.innerHTML = '<div class="loading"><div class="spinner"></div></div>';
    var res = await window.sb.from('promotions').select('*').eq('store_id', storeData.id).order('created_at',{ascending:false});
    var promos = res.data || [];
    if (!promos.length) {
      if (container) container.innerHTML = '<div class="empty"><div class="empty-icon">🎯</div><p>Sin promociones activas. Crea tu primera promo.</p></div>';
      return;
    }
    if (container) {
      container.innerHTML = '<table><thead><tr><th>Nombre</th><th>Tipo</th><th>Valor</th><th>Vigencia</th><th>Acciones</th></tr></thead><tbody>' +
        promos.map(function(p) {
          return '<tr>' +
            '<td><strong>' + (p.name||'') + '</strong></td>' +
            '<td>' + (p.discount_type||'-') + '</td>' +
            '<td>' + (p.discount_type==='discount_pct' ? (p.discount_value||0)+'%' : '$'+(p.discount_value||0).toLocaleString('es-CL')) + '</td>' +
            '<td><span style="font-size:12px">' + (p.start_date||'?') + ' → ' + (p.end_date||'?') + '</span></td>' +
            '<td><button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.marketing._deletePromo(\'' + p.id + '\')">Eliminar</button></td>' +
          '</tr>';
        }).join('') + '</tbody></table>';
    }
  }

  function openPromoModal() { openModal('promo-modal'); }

  async function savePromo() {
    var storeData = window.storeData;
    if (!storeData) return;
    var name  = document.getElementById('promo-name')?.value.trim();
    var type  = document.getElementById('promo-type')?.value;
    var value = parseInt(document.getElementById('promo-value')?.value);
    var start = document.getElementById('promo-start')?.value;
    var end   = document.getElementById('promo-end')?.value;
    if (!name || !value) { showToast('Completa nombre y valor', 'error'); return; }
    var res = await window.sb.from('promotions').insert({
      store_id: storeData.id, name: name, description: document.getElementById('promo-desc')?.value || '',
      discount_type: type, discount_value: value,
      start_date: start || null, end_date: end || null, is_active: true
    });
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    showToast('Promoción creada');
    closeModal('promo-modal');
    loadPromos();
  }

  async function deletePromo(id) {
    if (!confirm('¿Eliminar esta promoción?')) return;
    var res = await window.sb.from('promotions').delete().eq('id', id).select('id');
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    showToast('Promoción eliminada');
    loadPromos();
  }

  // ── PUBLICIDAD ───────────────────────────────────────────────────────
  async function loadAdPrices() {
    try {
      var res = await window.sb.from('config').select('value').eq('key','ad_prices').maybeSingle();
      if (res.data?.value) {
        var prices = JSON.parse(res.data.value);
        if (prices.banner)   AD_PLANS.banner.price   = prices.banner;
        if (prices.featured) AD_PLANS.featured.price = prices.featured;
        if (prices.social)   AD_PLANS.category.price = prices.social;
        document.querySelectorAll('.ad-plan').forEach(function(el) {
          var plan = el.getAttribute('onclick')?.match(/selectAdPlan\('(\w+)'/)?.[1];
          if (plan && AD_PLANS[plan]) {
            var priceEl = el.querySelector('.plan-price');
            if (priceEl) priceEl.textContent = '$' + AD_PLANS[plan].price.toLocaleString('es-CL') + '/sem';
          }
        });
        updateAdTotal();
      }
    } catch(e) {}
  }

  function selectAdPlan(plan, el) {
    selectedAdPlan = plan;
    document.querySelectorAll('.ad-plan').forEach(function(p) { p.classList.remove('selected'); });
    if (el) el.classList.add('selected');
    updateAdTotal();
  }

  function updateAdTotal() {
    var weeks = parseInt(document.getElementById('ad-duration')?.value) || 1;
    var total = (AD_PLANS[selectedAdPlan]?.price || 0) * weeks;
    var el = document.getElementById('ad-total');
    if (el) el.textContent = '$' + total.toLocaleString('es-CL');
  }

  async function submitAdCampaign() {
    var storeData = window.storeData;
    if (!storeData) return;
    var plan    = AD_PLANS[selectedAdPlan];
    var weeks   = parseInt(document.getElementById('ad-duration')?.value) || 1;
    var start   = document.getElementById('ad-start-date')?.value;
    var imageEl = document.getElementById('ad-img-input');
    var image_url = null;

    if (imageEl?.files[0] && typeof window.uploadToStorage === 'function') {
      image_url = await window.uploadToStorage(imageEl.files[0], 'ad-images', 'banners');
    }

    var res = await window.sb.from('ad_campaigns').insert({
      store_id: storeData.id,
      plan_type: selectedAdPlan,
      plan_name: plan.name,
      total_price: plan.price * weeks,
      weeks: weeks,
      start_date: start,
      image_url: image_url,
      status: 'pending'
    });
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    showToast('✅ Campaña solicitada. Un administrador la revisará.');
    loadMyCampaigns();
  }

  async function loadMyCampaigns() {
    var storeData = window.storeData;
    if (!storeData) return;
    var container = document.getElementById('campaigns-content');
    if (!container) return;
    try {
      var res = await window.sb.from('ad_campaigns').select('*').eq('store_id', storeData.id).order('created_at',{ascending:false}).limit(20);
      var campaigns = res.data || [];
      if (!campaigns.length) {
        container.innerHTML = '<div class="empty"><div class="empty-icon">📢</div><p>No tienes campañas aún</p></div>';
        return;
      }
      var statusLabels = { pending:'⏳ Pendiente', active:'✅ Activa', rejected:'❌ Rechazada', expired:'⏰ Expirada' };
      container.innerHTML = '<table><thead><tr><th>Plan</th><th>Inicio</th><th>Semanas</th><th>Total</th><th>Estado</th></tr></thead><tbody>' +
        campaigns.map(function(c) {
          return '<tr>' +
            '<td><strong>' + (c.plan_name||c.plan_type||'') + '</strong></td>' +
            '<td style="font-size:12px;color:var(--muted)">' + (c.start_date||'-') + '</td>' +
            '<td>' + (c.weeks||0) + '</td>' +
            '<td><strong>$' + ((c.total_price||0)).toLocaleString('es-CL') + '</strong></td>' +
            '<td><span class="badge ' + (c.status==='active'?'badge-green':c.status==='pending'?'badge-yellow':'badge-gray') + '">' + (statusLabels[c.status]||c.status) + '</span></td>' +
          '</tr>';
        }).join('') + '</tbody></table>';
    } catch(e) {
      container.innerHTML = '<div class="empty"><div class="empty-icon">📢</div><p>Módulo disponible próximamente</p></div>';
    }
  }

  async function cancelCampaign(id) {
    if (!confirm('¿Cancelar esta campaña?')) return;
    await window.sb.from('ad_campaigns').update({ status:'cancelled' }).eq('id', id);
    showToast('Campaña cancelada');
    loadMyCampaigns();
  }

  // ── RENDER ───────────────────────────────────────────────────────────
  function render() {
    // Marketing = promociones + publicidad
    var promosSection = document.getElementById('section-promociones');
    if (promosSection) promosSection.style.display = 'block';
    var adSection = document.getElementById('section-publicidad');
    if (adSection) adSection.style.display = 'block';
    loadPromos();
    loadAdPrices();
    updateAdTotal();
    loadMyCampaigns();
    var startDate = document.getElementById('ad-start-date');
    if (startDate) startDate.min = new Date().toISOString().split('T')[0];
    var duration = document.getElementById('ad-duration');
    if (duration) duration.addEventListener('change', updateAdTotal);
  }

  function destroy() {}

  window.GoBusiness.modules.marketing = {
    render: render, destroy: destroy,
    _loadPromos: loadPromos, _savePromo: savePromo, _deletePromo: deletePromo,
    _openPromoModal: openPromoModal,
    _loadAdPrices: loadAdPrices, _selectAdPlan: selectAdPlan,
    _updateAdTotal: updateAdTotal, _submitAdCampaign: submitAdCampaign,
    _loadMyCampaigns: loadMyCampaigns, _cancelCampaign: cancelCampaign,
  };

})();
