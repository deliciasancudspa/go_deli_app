// ============================================================================
// Go Business 2.0 — Módulo Catálogo Universal
// ============================================================================
// Item-modal con tabs por store_type, variantes, opciones, IA, stock.
// Reemplaza ~500 líneas de JS inline en aliados.html.
// ============================================================================

(function() {
  'use strict';

  // ── Estado privado ──────────────────────────────────────────────────────
  var _items = [];
  var _categories = [];
  var _editingId = null;
  var _variantCount = 0;
  var _variantGroupCounter = 0;
  var _variantItemCounter = 0;
  var _subGroupCounter = 0;
  var _subItemCounter = 0;
  var _optGroupCount = 0;
  var _optItemCount = 0;
  var _recCount = 0;

  // ── Helpers (usan las funciones globales de aliados.html) ───────────────
  function esc(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function fmtCLP(n) { return '$' + Math.round(n||0).toLocaleString('es-CL'); }
  function showToast(msg, type) { if (typeof window.showToast === 'function') window.showToast(msg, type); }
  function openModal(id) { var el = document.getElementById(id); if (el) el.classList.add('open'); }
  function closeModal(id) { var el = document.getElementById(id); if (el) el.classList.remove('open'); }

  function storeType() {
    return (window.storeData && window.storeData.store_type) || window.selectedStoreType || 'restaurante';
  }

  function storeEmoji() {
    var map = { restaurante:'🍽️', mercado:'🛒', tienda:'🏪', farmacia:'💊', cafeteria:'☕', licoreria:'🍷', mascotas:'🐾', flores:'💐' };
    return map[storeType()] || '🏪';
  }

  // ── Ensure item-modal HTML exists (created once, reused) ────────────────
  function ensureModalHTML() {
    if (document.getElementById('item-modal-dynamic')) return;
    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.id = 'item-modal-dynamic';
    overlay.innerHTML =
      '<div class="modal" style="width:620px;max-height:88vh;overflow-y:auto">' +
        '<div class="modal-header">' +
          '<h3 id="item-modal-title-dyn">Nuevo producto</h3>' +
          '<button class="modal-close" onclick="GoBusiness.modules.catalogo._closeEditor()">✕</button>' +
        '</div>' +
        '<input type="hidden" id="item-id-dyn">' +
        '<input type="hidden" id="item-img-url-dyn">' +
        // ── Tabs ──────────────────────────────────────────────────────────
        '<div id="item-tabs" style="display:flex;gap:4px;margin-bottom:16px;border-bottom:2px solid var(--border);padding-bottom:0;overflow-x:auto">' +
          '<button class="item-tab-btn active" data-tab="basico" onclick="GoBusiness.modules.catalogo._switchTab(\'basico\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;white-space:nowrap;color:var(--muted)">📋 Básico</button>' +
          '<button class="item-tab-btn" data-tab="tipo" onclick="GoBusiness.modules.catalogo._switchTab(\'tipo\',this)" id="tab-btn-tipo" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;white-space:nowrap;color:var(--muted)">📦 Detalles</button>' +
          '<button class="item-tab-btn" data-tab="variantes" onclick="GoBusiness.modules.catalogo._switchTab(\'variantes\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;white-space:nowrap;color:var(--muted)">🎨 Variantes</button>' +
          '<button class="item-tab-btn" data-tab="opciones" onclick="GoBusiness.modules.catalogo._switchTab(\'opciones\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;white-space:nowrap;color:var(--muted)">➕ Opciones</button>' +
          '<button class="item-tab-btn" data-tab="ia" onclick="GoBusiness.modules.catalogo._switchTab(\'ia\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;white-space:nowrap;color:var(--muted)">🤖 IA</button>' +
        '</div>' +
        // ── Tab: Básico ──────────────────────────────────────────────────
        '<div id="tab-basico" class="item-tab-content">' +
          '<div class="form-group">' +
            '<label>Foto del producto</label>' +
            '<div class="upload-trigger" onclick="document.getElementById(\'item-img-input-dyn\').click()" id="item-img-trigger-dyn" style="border:2px dashed var(--border);border-radius:12px;padding:18px;text-align:center;cursor:pointer;transition:all 0.2s;background:var(--bg);font-size:13px;color:var(--muted)">' +
              '📸 Subir foto (JPG/PNG, máx 5MB)' +
              '<input type="file" id="item-img-input-dyn" accept="image/*" style="display:none" onchange="GoBusiness.modules.catalogo._previewImage(this)">' +
            '</div>' +
            '<img id="item-img-preview-dyn" style="width:100%;height:100px;object-fit:cover;border-radius:10px;margin-top:8px;display:none">' +
          '</div>' +
          '<div class="form-row">' +
            '<div class="form-group"><label id="item-name-label-dyn">Nombre *</label><input type="text" id="item-name-dyn" placeholder="Nombre del producto"></div>' +
            '<div class="form-group"><label>Precio (CLP) *</label><input type="number" id="item-price-dyn" placeholder="5990" oninput="GoBusiness.modules.catalogo._calcDiscountPreview()"></div>' +
          '</div>' +
          '<div class="form-group"><label id="item-desc-label-dyn">Descripción</label><textarea id="item-desc-dyn" rows="2" placeholder="Descripción del producto..."></textarea></div>' +
          '<div class="form-group"><label>Categoría</label><select id="item-category-dyn"></select></div>' +
          '<div style="margin-bottom:10px">' +
            '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-popular-dyn" style="accent-color:var(--primary)"> ⭐ Producto popular</label>' +
          '</div>' +
          '<div style="background:#FFF3E8;border-radius:10px;padding:14px;margin-bottom:16px;border:1px solid #FFD4A8">' +
            '<div style="font-weight:700;font-size:12px;color:#9A3412;margin-bottom:10px">🏠 Visibilidad en Home de Go Deli</div>' +
            '<div style="margin-bottom:10px"><label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-featured-dyn" style="accent-color:#FF6B00"> 🔥 Mostrar en card de la tienda (Home)</label>' +
            '<p style="font-size:11px;color:#9A3412;margin-top:4px;margin-left:24px">Aparece en el scroll de tu tienda en la pantalla de inicio</p></div>' +
          '</div>' +
          '<div style="background:#F0FDF4;border-radius:10px;padding:14px;margin-bottom:16px;border:1px solid #BBF7D0">' +
            '<div style="font-weight:700;font-size:12px;color:#166534;margin-bottom:10px">💰 Precio y descuento</div>' +
            '<p style="font-size:11px;color:#166534;margin-bottom:10px">Si tienes un precio de venta menor al precio original, el sistema calcula automáticamente el % de descuento que verá el cliente.</p>' +
            '<div class="form-row">' +
              '<div class="form-group" style="margin-bottom:0"><label>Precio antes de la rebaja (CLP)</label><input type="number" id="item-original-price-dyn" placeholder="Ej: 9990" oninput="GoBusiness.modules.catalogo._calcDiscountPreview()"></div>' +
              '<div class="form-group" style="margin-bottom:0"><label>% de descuento (auto-calculado)</label><div id="discount-preview-dyn" style="padding:10px 14px;background:#fff;border:1.5px solid var(--border);border-radius:8px;font-size:14px;font-weight:700;color:var(--primary);min-height:42px;display:flex;align-items:center">—</div></div>' +
            '</div>' +
          '</div>' +
          // Stock (global para todos los tipos)
          '<div class="form-row">' +
            '<div class="form-group"><label>Stock disponible</label><input type="number" id="item-stock-dyn" placeholder="0" min="0"></div>' +
            '<div class="form-group"><label>Stock mínimo (alerta)</label><input type="number" id="item-stock-min-dyn" placeholder="5" min="0"></div>' +
          '</div>' +
          '<div class="form-row">' +
            '<div class="form-group"><label>SKU (opcional)</label><input type="text" id="item-sku-dyn" placeholder="Código interno"></div>' +
            '<div class="form-group"><label>Marca</label><input type="text" id="item-brand-dyn" placeholder="Marca del producto"></div>' +
          '</div>' +
        '</div>' +
        // ── Tab: Tipo (campos específicos según store_type) ──────────────
        '<div id="tab-tipo" class="item-tab-content" style="display:none">' +
          '<div id="tipo-restaurante" style="display:none">' +
            '<div style="display:flex;gap:16px;flex-wrap:wrap;margin-bottom:16px">' +
              '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-vegano-dyn" style="accent-color:#16a34a"> 🌱 Vegano</label>' +
              '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-vegetariano-dyn" style="accent-color:#16a34a"> 🥗 Vegetariano</label>' +
              '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-picante-dyn" style="accent-color:#dc2626"> 🌶️ Picante</label>' +
              '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-sin-gluten-dyn" style="accent-color:#7C3AED"> 🌾 Sin gluten</label>' +
              '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-alcohol-dyn" style="accent-color:var(--error)"> 🍺 Contiene alcohol</label>' +
            '</div>' +
            '<div style="background:#FFF7ED;border-radius:12px;padding:16px;margin-bottom:12px;border:1px solid #FED7AA">' +
              '<div style="font-weight:800;color:#C2410C;margin-bottom:12px;font-size:13px">🍽️ Información del plato</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>Tiempo de preparación (min)</label><input type="number" id="item-prep-time-dyn" placeholder="15" min="1" max="120"></div>' +
                '<div class="form-group"><label>Calorías (kcal) opcional</label><input type="number" id="item-calories-dyn" placeholder="450"></div>' +
              '</div>' +
              '<div class="form-group"><label>Alérgenos</label>' +
                '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:6px">' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="gluten"> Gluten</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="lactosa"> Lactosa</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="mariscos"> Mariscos</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="frutos_secos"> Frutos secos</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="huevo"> Huevo</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="soja"> Soja</label>' +
                  '<label style="display:flex;align-items:center;gap:6px;font-size:12px;font-weight:600;cursor:pointer"><input type="checkbox" class="allergen-check-dyn" value="mani"> Maní</label>' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
          '<div id="tipo-mercado" style="display:none">' +
            '<div style="background:#F0FDF4;border-radius:12px;padding:16px;margin-bottom:12px;border:1px solid #BBF7D0">' +
              '<div style="font-weight:800;color:#166534;margin-bottom:12px;font-size:13px">🛒 Información del producto</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>Unidad de medida</label>' +
                  '<select id="item-unit-dyn"><option value="un">Unidad (un)</option><option value="kg">Kilogramo (kg)</option><option value="g">Gramo (g)</option><option value="lt">Litro (lt)</option><option value="ml">Mililitro (ml)</option><option value="paq">Paquete</option><option value="caja">Caja</option><option value="bolsa">Bolsa</option></select></div>' +
                '<div class="form-group"><label>Código de barras</label><input type="text" id="item-barcode-dyn" placeholder="7802300..."></div>' +
              '</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>N° de lote</label><input type="text" id="item-lot-dyn" placeholder="Lote (opcional)"></div>' +
                '<div class="form-group"><label>Fecha de vencimiento</label><input type="date" id="item-expiration-dyn"></div>' +
              '</div>' +
              '<div style="margin-top:8px"><label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-refrigerado-dyn" style="accent-color:#0ea5e9"> ❄️ Requiere refrigeración</label></div>' +
            '</div>' +
          '</div>' +
          '<div id="tipo-tienda" style="display:none">' +
            '<div style="background:#EFF6FF;border-radius:12px;padding:16px;margin-bottom:12px;border:1px solid #BFDBFE">' +
              '<div style="font-weight:800;color:#1e40af;margin-bottom:12px;font-size:13px">🏪 Información del producto</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>Garantía (opcional)</label><input type="text" id="item-garantia-dyn" placeholder="Ej: 12 meses"></div>' +
                '<div class="form-group"><label>Peso / Dimensiones</label><input type="text" id="item-dimensions-dyn" placeholder="Ej: 30×20×5 cm, 500g"></div>' +
              '</div>' +
            '</div>' +
          '</div>' +
          '<div id="tipo-farmacia" style="display:none">' +
            '<div style="background:#FDF4FF;border-radius:12px;padding:16px;margin-bottom:12px;border:1px solid #E9D5FF">' +
              '<div style="font-weight:800;color:#6b21a8;margin-bottom:12px;font-size:13px">💊 Información del producto de salud</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>Laboratorio / Marca</label><input type="text" id="item-laboratorio-dyn" placeholder="Ej: Bayer, Abbott..."></div>' +
                '<div class="form-group"><label>Principio activo (opcional)</label><input type="text" id="item-principio-dyn" placeholder="Ej: Ibuprofeno 400mg"></div>' +
              '</div>' +
              '<div class="form-row">' +
                '<div class="form-group"><label>Formato / Presentación</label><input type="text" id="item-formato-dyn" placeholder="Ej: Caja 20 comprimidos"></div>' +
                '<div class="form-group"><label>Código ISP (opcional)</label><input type="text" id="item-isp-dyn" placeholder="Registro ISP"></div>' +
              '</div>' +
              '<div style="margin-top:8px;display:flex;gap:20px;flex-wrap:wrap">' +
                '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-receta-dyn" style="accent-color:#7c3aed"> 📋 Requiere receta médica</label>' +
                '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-refrigerado-farm-dyn" style="accent-color:#0ea5e9"> ❄️ Requiere refrigeración</label>' +
                '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer"><input type="checkbox" id="item-controlado-dyn" style="accent-color:#dc2626"> ⚠️ Producto controlado</label>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
        // ── Tab: Variantes ───────────────────────────────────────────────
        '<div id="tab-variantes" class="item-tab-content" style="display:none">' +
          // Grupos de variantes reutilizables
          '<div style="background:#F5F0FF;border-radius:12px;padding:14px;margin-bottom:16px;border:2px solid #DDD6FE">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
              '<strong style="font-size:13px;color:#5b21b6">🎨 Grupos de variantes guardados</strong>' +
              '<button class="btn btn-sm" style="background:#7C3AED;color:#fff;font-size:11px" onclick="GoBusiness.modules.catalogo._openGroupManager()">⚙️ Gestionar</button>' +
            '</div>' +
            '<p style="font-size:11px;color:var(--muted);margin-bottom:8px">Selecciona grupos existentes. Todos sus ítems se aplicarán a este producto.</p>' +
            '<div id="variant-groups-selector" style="display:flex;flex-wrap:wrap;gap:6px"></div>' +
            '<div id="variant-groups-empty" style="text-align:center;padding:10px;color:var(--muted);font-size:12px">No hay grupos creados. <a href="javascript:void(0)" onclick="GoBusiness.modules.catalogo._openGroupManager()" style="color:var(--secondary);font-weight:700">Crear uno</a></div>' +
          '</div>' +
          // Variantes simples (restaurante/mercado/farmacia)
          '<div id="variants-simple-section" style="border-top:1px solid var(--border);padding-top:16px;margin-bottom:16px">' +
            '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">' +
              '<div><label style="font-size:13px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:0.5px">Variantes / Tamaños</label>' +
              '<p style="font-size:11px;color:var(--muted);margin-top:3px">Si agregas variantes el precio base queda sin efecto. El cliente verá "desde $X".</p></div>' +
              '<button class="add-row-btn" onclick="GoBusiness.modules.catalogo._addVariantRow()" style="padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">+ Agregar variante</button>' +
            '</div>' +
            '<div id="variants-list-dyn"></div>' +
            '<div id="variants-preview-dyn" style="display:none;margin-top:8px;padding:10px 12px;background:#F5F0FF;border-radius:8px;font-size:12px;color:#6B00B3;font-weight:600"></div>' +
          '</div>' +
          // Variantes con subvariantes (tienda)
          '<div id="variants-tienda-section" style="display:none;background:#F5F3FF;border-radius:12px;padding:16px;margin-bottom:12px;border:1px solid #DDD6FE">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">' +
              '<div style="font-weight:800;color:#5b21b6;font-size:13px">🎨 Variantes y subvariantes</div>' +
              '<button type="button" class="btn btn-sm" style="background:#7C3AED;color:#fff" onclick="GoBusiness.modules.catalogo._addVariantGroupTienda()">+ Agregar grupo</button>' +
            '</div>' +
            '<p style="font-size:12px;color:var(--muted);margin-bottom:12px">Ejemplo: Grupo "Talla" → opciones S($500), M($600), L($700); cada opción puede tener subvariantes como "Color".</p>' +
            '<div id="variant-groups-tienda-dyn"></div>' +
          '</div>' +
        '</div>' +
        // ── Tab: Opciones ────────────────────────────────────────────────
        '<div id="tab-opciones" class="item-tab-content" style="display:none">' +
          // Grupos de opciones reutilizables
          '<div style="background:#FFF5F2;border-radius:12px;padding:14px;margin-bottom:16px;border:2px solid #FFD5C0">' +
            '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
              '<strong style="font-size:13px;color:#9A3412">➕ Grupos de opciones guardados</strong>' +
              '<button class="btn btn-sm" style="background:#FF6B00;color:#fff;font-size:11px" onclick="GoBusiness.modules.catalogo._openGroupManager()">⚙️ Gestionar</button>' +
            '</div>' +
            '<p style="font-size:11px;color:var(--muted);margin-bottom:8px">Selecciona grupos existentes. Todos sus ítems se aplicarán a este producto.</p>' +
            '<div id="option-groups-selector" style="display:flex;flex-wrap:wrap;gap:6px"></div>' +
            '<div id="option-groups-empty" style="text-align:center;padding:10px;color:var(--muted);font-size:12px">No hay grupos creados. <a href="javascript:void(0)" onclick="GoBusiness.modules.catalogo._openGroupManager()" style="color:var(--secondary);font-weight:700">Crear uno</a></div>' +
          '</div>' +
          '<div style="border-top:1px solid var(--border);padding-top:16px;margin-bottom:16px">' +
            '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">' +
              '<div><label style="font-size:13px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:0.5px">Añadir a tu pedido</label>' +
              '<p style="font-size:11px;color:var(--muted);margin-top:3px">El cliente verá: "Añade a tu pedido: Papas fritas $2.000 · Salsa Mayo $500".</p></div>' +
              '<button class="add-row-btn" onclick="GoBusiness.modules.catalogo._addOptionGroup()" style="padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">+ Agregar grupo</button>' +
            '</div>' +
            '<div id="options-list-dyn"></div>' +
          '</div>' +
          // Recomendaciones
          '<div style="border-top:1px solid var(--border);padding-top:16px;margin-bottom:16px">' +
            '<div style="margin-bottom:10px"><label style="font-size:13px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:0.5px">Te recomendamos también</label>' +
            '<p style="font-size:11px;color:var(--muted);margin-top:3px">El cliente verá hasta 5 productos sugeridos debajo de este producto.</p></div>' +
            '<div id="recommendations-list-dyn" style="display:flex;flex-direction:column;gap:8px;margin-bottom:10px"></div>' +
            '<button class="add-row-btn" onclick="GoBusiness.modules.catalogo._addRecommendation()" id="add-rec-btn-dyn" style="padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">+ Agregar recomendación</button>' +
            '<p id="rec-limit-msg-dyn" style="font-size:11px;color:var(--error);margin-top:6px;display:none">Máximo 5 recomendaciones</p>' +
          '</div>' +
        '</div>' +
        // ── Tab: IA ──────────────────────────────────────────────────────
        '<div id="tab-ia" class="item-tab-content" style="display:none">' +
          '<div style="text-align:center;padding:40px 20px">' +
            '<div style="font-size:64px;margin-bottom:16px">🤖</div>' +
            '<h3 style="font-weight:800;margin-bottom:8px">Asistente IA</h3>' +
            '<p style="color:var(--muted);font-size:14px;margin-bottom:24px">Sube una foto de tu carta, un PDF o un link y la IA arma tu catálogo automáticamente.</p>' +
            '<button class="btn" style="background:linear-gradient(135deg,#7C3AED,#FF6B35);color:#fff;padding:14px 32px;font-size:15px;font-weight:700;border-radius:12px;border:none;cursor:pointer" onclick="if(typeof openIAModal===\'function\')openIAModal();else GoBusiness.modules.catalogo._openIA()">✨ Usar asistente IA</button>' +
          '</div>' +
        '</div>' +
        // ── Save button ──────────────────────────────────────────────────
        '<button class="btn-primary" onclick="GoBusiness.modules.catalogo._saveItem()" id="save-item-btn-dyn" style="margin-top:8px">Guardar producto</button>' +
      '</div>';
    document.body.appendChild(overlay);
  }

  // ── Tab switching ──────────────────────────────────────────────────────
  function switchTab(tabName, btn) {
    // Update button styles
    document.querySelectorAll('.item-tab-btn').forEach(function(b) {
      b.style.borderBottomColor = 'transparent';
      b.style.color = 'var(--muted)';
      b.classList.remove('active');
    });
    if (btn) {
      btn.style.borderBottomColor = 'var(--primary)';
      btn.style.color = 'var(--primary)';
      btn.classList.add('active');
    }
    // Show/hide content
    document.querySelectorAll('.item-tab-content').forEach(function(c) { c.style.display = 'none'; });
    var target = document.getElementById('tab-' + tabName);
    if (target) target.style.display = 'block';
  }

  // ── Adapt labels per store type ───────────────────────────────────────
  function adaptLabels() {
    var type = storeType();
    var nameLabel = document.getElementById('item-name-label-dyn');
    var descLabel = document.getElementById('item-desc-label-dyn');
    var nameInput = document.getElementById('item-name-dyn');
    var tabBtnTipo = document.getElementById('tab-btn-tipo');

    var configs = {
      restaurante: { nameLabel: 'Nombre del plato *', namePh: 'Ej: Burger Clásica', descLabel: 'Descripción / Ingredientes', tipoLabel: '🍽️ Plato' },
      mercado:     { nameLabel: 'Nombre del producto *', namePh: 'Ej: Leche entera 1lt', descLabel: 'Descripción', tipoLabel: '🛒 Producto' },
      tienda:      { nameLabel: 'Nombre del producto *', namePh: 'Ej: Zapatillas Running', descLabel: 'Descripción / Características', tipoLabel: '🏪 Producto' },
      farmacia:    { nameLabel: 'Nombre del producto *', namePh: 'Ej: Paracetamol 500mg', descLabel: 'Descripción / Indicaciones', tipoLabel: '💊 Salud' },
      cafeteria:   { nameLabel: 'Nombre del producto *', namePh: 'Ej: Latte Grande', descLabel: 'Descripción', tipoLabel: '☕ Producto' },
      licoreria:   { nameLabel: 'Nombre del producto *', namePh: 'Ej: Cerveza Artesanal', descLabel: 'Descripción', tipoLabel: '🍷 Producto' },
      mascotas:    { nameLabel: 'Nombre del producto *', namePh: 'Ej: Alimento Perro 15kg', descLabel: 'Descripción', tipoLabel: '🐾 Producto' },
      flores:      { nameLabel: 'Nombre del producto *', namePh: 'Ej: Ramo de Rosas', descLabel: 'Descripción', tipoLabel: '💐 Producto' }
    };
    var cfg = configs[type] || configs.restaurante;

    if (nameLabel) nameLabel.textContent = cfg.nameLabel;
    if (nameInput) nameInput.placeholder = cfg.namePh;
    if (descLabel) descLabel.textContent = cfg.descLabel;
    if (tabBtnTipo) tabBtnTipo.textContent = cfg.tipoLabel;
  }

  // ── Show/hide type-specific sections ──────────────────────────────────
  function showTypeSection() {
    var type = storeType();
    var types = ['restaurante','mercado','tienda','farmacia','cafeteria','licoreria','mascotas','flores'];
    types.forEach(function(t) {
      var el = document.getElementById('tipo-' + t);
      if (el) el.style.display = (t === type) ? 'block' : 'none';
    });
    // Show/hide variant sections
    var simpleVar = document.getElementById('variants-simple-section');
    var tiendaVar = document.getElementById('variants-tienda-section');
    if (type === 'tienda') {
      if (simpleVar) simpleVar.style.display = 'none';
      if (tiendaVar) tiendaVar.style.display = 'block';
    } else {
      if (simpleVar) simpleVar.style.display = 'block';
      if (tiendaVar) tiendaVar.style.display = 'none';
    }
  }

  // ── Discount calculation ──────────────────────────────────────────────
  function calcDiscountPct() {
    var price = parseInt(document.getElementById('item-price-dyn')?.value) || 0;
    var originalPrice = parseInt(document.getElementById('item-original-price-dyn')?.value) || 0;
    return (originalPrice > price) ? Math.round(((originalPrice - price) / originalPrice) * 100) : 0;
  }

  function calcDiscountPreview() {
    var price = parseInt(document.getElementById('item-price-dyn')?.value) || 0;
    var originalPrice = parseInt(document.getElementById('item-original-price-dyn')?.value) || 0;
    var preview = document.getElementById('discount-preview-dyn');
    if (!preview) return;
    if (originalPrice > price) {
      var pct = Math.round(((originalPrice - price) / originalPrice) * 100);
      preview.innerHTML = '<span style="color:#166534;font-size:20px">-' + pct + '%</span>';
    } else {
      preview.innerHTML = '<span style="color:var(--muted);font-size:13px">Sin descuento</span>';
    }
  }

  // ── Image preview ─────────────────────────────────────────────────────
  function previewImage(input) {
    var file = input.files[0]; if (!file) return;
    var reader = new FileReader();
    reader.onload = function(e) {
      var img = document.getElementById('item-img-preview-dyn');
      img.src = e.target.result; img.style.display = 'block';
      var trigger = document.getElementById('item-img-trigger-dyn');
      if (trigger) trigger.style.borderColor = 'var(--success)';
    };
    reader.readAsDataURL(file);
  }

  // ── Simple variants (restaurante/mercado/farmacia) ────────────────────
  function addVariantRow(name, price) {
    name = name || ''; price = price || '';
    _variantCount++;
    var id = 'v-dyn-' + _variantCount;
    var div = document.createElement('div');
    div.className = 'variant-row'; div.id = id;
    div.style.cssText = 'display:grid;grid-template-columns:1fr 110px 36px;gap:8px;align-items:center;margin-bottom:8px';
    div.innerHTML =
      '<input type="text" placeholder="Ej: Papas chicas" value="' + esc(name) + '" style="padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px;width:100%" oninput="GoBusiness.modules.catalogo._updateVariantsPreview()">' +
      '<input type="number" placeholder="Precio CLP" value="' + price + '" min="0" style="padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px;width:100%" oninput="GoBusiness.modules.catalogo._updateVariantsPreview()">' +
      '<button class="remove-row-btn" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer" onclick="document.getElementById(\'' + id + '\').remove();GoBusiness.modules.catalogo._updateVariantsPreview()">×</button>';
    var list = document.getElementById('variants-list-dyn');
    if (list) { list.appendChild(div); updateVariantsPreview(); }
  }

  function updateVariantsPreview() {
    var variants = getVariants();
    var preview = document.getElementById('variants-preview-dyn');
    var priceEl = document.getElementById('item-price-dyn');
    if (!preview) return;
    if (variants.length > 0) {
      var minPrice = Math.min.apply(null, variants.map(function(v){return v.price;}).filter(function(p){return p>0;}));
      preview.style.display = 'block';
      preview.textContent = 'Vista previa: "' + ((document.getElementById('item-name-dyn')?.value)||'Producto') + ' desde $' + (minPrice||0).toLocaleString('es-CL') + '"';
      if (priceEl) { priceEl.style.opacity = '0.4'; priceEl.title = 'El precio base no aplica cuando hay variantes'; }
    } else {
      preview.style.display = 'none';
      if (priceEl) { priceEl.style.opacity = '1'; priceEl.title = ''; }
    }
  }

  function getVariants() {
    var list = document.getElementById('variants-list-dyn');
    if (!list) return [];
    return Array.from(list.querySelectorAll('.variant-row')).map(function(row) {
      var inputs = row.querySelectorAll('input');
      return { name: (inputs[0]?.value || '').trim(), price: parseInt(inputs[1]?.value)||0 };
    }).filter(function(v) { return v.name; });
  }

  // ── Tienda variant groups ─────────────────────────────────────────────
  function addVariantGroupTienda() {
    var container = document.getElementById('variant-groups-tienda-dyn');
    if (!container) return;
    var gid = ++_variantGroupCounter;
    var div = document.createElement('div');
    div.id = 'vg-dyn-' + gid;
    div.style.cssText = 'background:#fff;border:1.5px solid #DDD6FE;border-radius:10px;padding:14px;margin-bottom:12px';
    div.innerHTML =
      '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px">' +
        '<input type="text" placeholder="Nombre del grupo (ej: Talla, Color, Material)" id="vg-title-dyn-' + gid + '" style="flex:1;border:1px solid var(--border);border-radius:8px;padding:8px 10px;font-size:13px;font-weight:700;outline:none;margin-right:8px">' +
        '<button type="button" onclick="document.getElementById(\'vg-dyn-' + gid + '\').remove()" style="background:#FEE2E2;color:#991B1B;border:none;padding:4px 10px;border-radius:6px;font-size:12px;cursor:pointer">✕</button>' +
      '</div>' +
      '<div id="vg-items-dyn-' + gid + '"></div>' +
      '<div style="display:flex;gap:8px;margin-top:8px">' +
        '<button type="button" onclick="GoBusiness.modules.catalogo._addVariantItem(' + gid + ')" style="font-size:12px;background:var(--bg);border:1px dashed var(--border);padding:5px 12px;border-radius:6px;cursor:pointer;color:var(--secondary);font-weight:600">+ Opción</button>' +
        '<button type="button" onclick="GoBusiness.modules.catalogo._addSubVariantGroup(' + gid + ')" style="font-size:12px;background:var(--bg);border:1px dashed #DDD6FE;padding:5px 12px;border-radius:6px;cursor:pointer;color:#7C3AED;font-weight:600">+ Subvariante</button>' +
      '</div>';
    container.appendChild(div);
    addVariantItem(gid);
  }

  function addVariantItem(gid, name, price) {
    name = name || ''; price = price || '';
    var container = document.getElementById('vg-items-dyn-' + gid);
    if (!container) return;
    var iid = ++_variantItemCounter;
    var div = document.createElement('div');
    div.id = 'vi-dyn-' + iid;
    div.style.cssText = 'display:flex;gap:8px;align-items:center;margin-bottom:6px';
    div.innerHTML =
      '<input type="text" placeholder="Nombre (ej: S, Rojo, Algodón)" id="vi-name-dyn-' + iid + '" value="' + esc(name) + '" style="flex:2;border:1px solid var(--border);border-radius:8px;padding:7px 10px;font-size:13px;outline:none">' +
      '<input type="number" placeholder="Precio" id="vi-price-dyn-' + iid + '" value="' + price + '" min="0" step="100" style="flex:1;border:1px solid var(--border);border-radius:8px;padding:7px 10px;font-size:13px;outline:none">' +
      '<button type="button" onclick="document.getElementById(\'vi-dyn-' + iid + '\').remove()" style="background:none;border:none;color:var(--muted);font-size:16px;cursor:pointer">✕</button>';
    container.appendChild(div);
  }

  function addSubVariantGroup(gid) {
    var parentDiv = document.getElementById('vg-dyn-' + gid);
    if (!parentDiv) return;
    var sgid = ++_subGroupCounter;
    var div = document.createElement('div');
    div.id = 'sg-dyn-' + sgid;
    div.style.cssText = 'background:#F5F3FF;border:1px solid #DDD6FE;border-radius:8px;padding:12px;margin-top:10px';
    div.innerHTML =
      '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
        '<input type="text" placeholder="Nombre subvariante (ej: Color)" id="sg-title-dyn-' + sgid + '" style="flex:1;border:1px solid #DDD6FE;border-radius:6px;padding:6px 10px;font-size:12px;font-weight:700;outline:none;margin-right:8px;background:#fff">' +
        '<button type="button" onclick="document.getElementById(\'sg-dyn-' + sgid + '\').remove()" style="background:#EDE9FE;color:#5b21b6;border:none;padding:3px 8px;border-radius:4px;font-size:11px;cursor:pointer">✕</button>' +
      '</div>' +
      '<div id="sg-items-dyn-' + sgid + '"></div>' +
      '<button type="button" onclick="GoBusiness.modules.catalogo._addSubVariantItem(' + sgid + ')" style="font-size:11px;background:#fff;border:1px dashed #DDD6FE;padding:4px 10px;border-radius:5px;cursor:pointer;color:#7C3AED;margin-top:4px">+ Opción</button>';
    var btnRow = parentDiv.lastElementChild;
    parentDiv.insertBefore(div, btnRow);
    addSubVariantItem(sgid);
  }

  function addSubVariantItem(sgid, name, price) {
    name = name || ''; price = price || '';
    var container = document.getElementById('sg-items-dyn-' + sgid);
    if (!container) return;
    var siid = ++_subItemCounter;
    var div = document.createElement('div');
    div.id = 'si-dyn-' + siid;
    div.style.cssText = 'display:flex;gap:6px;align-items:center;margin-bottom:4px';
    div.innerHTML =
      '<input type="text" placeholder="Ej: Rojo" id="si-name-dyn-' + siid + '" value="' + esc(name) + '" style="flex:2;border:1px solid #DDD6FE;border-radius:6px;padding:5px 8px;font-size:12px;outline:none;background:#fff">' +
      '<input type="number" placeholder="+$" id="si-price-dyn-' + siid + '" value="' + price + '" min="0" step="100" style="flex:1;border:1px solid #DDD6FE;border-radius:6px;padding:5px 8px;font-size:12px;outline:none;background:#fff">' +
      '<button type="button" onclick="document.getElementById(\'si-dyn-' + siid + '\').remove()" style="background:none;border:none;color:var(--muted);font-size:14px;cursor:pointer">✕</button>';
    container.appendChild(div);
  }

  function getVariantGroupsTienda() {
    var groups = [];
    var container = document.getElementById('variant-groups-tienda-dyn');
    if (!container) return groups;
    container.querySelectorAll('[id^="vg-dyn-"]').forEach(function(gDiv) {
      if (gDiv.id.indexOf('items') >= 0) return;
      var gid = gDiv.id.replace('vg-dyn-','');
      var title = (document.getElementById('vg-title-dyn-' + gid)?.value || '').trim();
      if (!title) return;
      var items = [];
      gDiv.querySelectorAll('[id^="vi-dyn-"]').forEach(function(iDiv) {
        var iid = iDiv.id.replace('vi-dyn-','');
        var name  = (document.getElementById('vi-name-dyn-' + iid)?.value || '').trim();
        var price = parseInt(document.getElementById('vi-price-dyn-' + iid)?.value)||0;
        if (name) items.push({ name: name, price: price });
      });
      var subGroups = [];
      gDiv.querySelectorAll('[id^="sg-dyn-"]').forEach(function(sgDiv) {
        var sgid = sgDiv.id.replace('sg-dyn-','');
        var stitle = (document.getElementById('sg-title-dyn-' + sgid)?.value || '').trim();
        if (!stitle) return;
        var subitems = [];
        sgDiv.querySelectorAll('[id^="si-dyn-"]').forEach(function(siDiv) {
          var siid = siDiv.id.replace('si-dyn-','');
          var sname  = (document.getElementById('si-name-dyn-' + siid)?.value || '').trim();
          var sprice = parseInt(document.getElementById('si-price-dyn-' + siid)?.value)||0;
          if (sname) subitems.push({ name: sname, price: sprice });
        });
        if (subitems.length) subGroups.push({ title: stitle, items: subitems });
      });
      if (items.length) groups.push({ title: title, items: items, subGroups: subGroups });
    });
    return groups;
  }

  // ── Options ────────────────────────────────────────────────────────────
  function addOptionGroup(title, items, minSel, maxSel) {
    title = title || ''; items = items || []; minSel = minSel || 0; maxSel = maxSel || 0;
    _optGroupCount++;
    var gid = 'og-dyn-' + _optGroupCount;
    var div = document.createElement('div');
    div.className = 'opt-group-box'; div.id = gid;
    div.style.cssText = 'background:var(--bg);border-radius:12px;padding:14px;margin-bottom:12px;border:1px solid var(--border)';
    div.innerHTML =
      '<div style="display:flex;align-items:center;gap:8px;margin-bottom:8px">' +
        '<input type="text" placeholder="Ej: Proteínas, Salsas..." value="' + esc(title) + '" style="flex:1;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
        '<button class="remove-row-btn" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer" onclick="document.getElementById(\'' + gid + '\').remove()">×</button>' +
      '</div>' +
      '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px">' +
        '<div><label style="font-size:11px;color:var(--muted);font-weight:600;display:block;margin-bottom:3px">Mín. selecciones (0 = opcional)</label>' +
        '<input type="number" min="0" value="' + minSel + '" id="' + gid + '-min" style="width:100%;padding:6px 10px;border:1px solid var(--border);border-radius:8px;font-size:13px;box-sizing:border-box"></div>' +
        '<div><label style="font-size:11px;color:var(--muted);font-weight:600;display:block;margin-bottom:3px">Máx. selecciones (0 = sin límite)</label>' +
        '<input type="number" min="0" value="' + maxSel + '" id="' + gid + '-max" style="width:100%;padding:6px 10px;border:1px solid var(--border);border-radius:8px;font-size:13px;box-sizing:border-box"></div>' +
      '</div>' +
      '<p style="font-size:11px;color:var(--muted);margin-bottom:8px">Nombre + precio de cada opción. El precio se suma al total del pedido.</p>' +
      '<div class="opt-items-' + gid + '"></div>' +
      '<button class="add-row-btn" style="font-size:11px;margin-top:6px;padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;cursor:pointer" onclick="GoBusiness.modules.catalogo._addOptionItem(\'' + gid + '\')">+ Agregar opción</button>';
    var list = document.getElementById('options-list-dyn');
    if (list) {
      list.appendChild(div);
      if (items.length) {
        items.forEach(function(item) {
          addOptionItem(gid, item.name || item, item.price || 0);
        });
      } else {
        addOptionItem(gid);
      }
    }
  }

  function addOptionItem(gid, name, price) {
    name = name || ''; price = price || 0;
    _optItemCount++;
    var iid = 'oi-dyn-' + _optItemCount;
    var div = document.createElement('div');
    div.className = 'opt-item-row'; div.id = iid;
    div.style.cssText = 'display:flex;gap:8px;align-items:center;margin-bottom:6px';
    div.innerHTML =
      '<input type="text" placeholder="Ej: Papas fritas" value="' + esc(name) + '" style="flex:1;padding:7px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<input type="number" placeholder="Precio" value="' + price + '" min="0" style="width:100px;padding:7px 10px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<button class="remove-row-btn" style="width:26px;height:26px;font-size:12px;background:var(--error);color:#fff;border:none;border-radius:6px;cursor:pointer" onclick="document.getElementById(\'' + iid + '\').remove()">×</button>';
    var container = document.querySelector('.opt-items-' + gid);
    if (container) container.appendChild(div);
  }

  function getOptions() {
    var list = document.getElementById('options-list-dyn');
    if (!list) return [];
    return Array.from(list.querySelectorAll('.opt-group-box')).map(function(group) {
      var titleInput = group.querySelector('input[type=text]');
      var minInput   = group.querySelector('input[id$="-min"]');
      var maxInput   = group.querySelector('input[id$="-max"]');
      var itemRows   = Array.from(group.querySelectorAll('.opt-item-row'));
      var items = itemRows.map(function(row) {
        var inputs = row.querySelectorAll('input');
        return { name: (inputs[0]?.value || '').trim(), price: parseInt(inputs[1]?.value)||0 };
      }).filter(function(i) { return i.name; });
      return {
        title:   (titleInput?.value || '').trim(),
        items: items,
        min_sel: parseInt(minInput?.value)||0,
        max_sel: parseInt(maxInput?.value)||0,
      };
    }).filter(function(g) { return g.title || g.items.length; });
  }

  // ── Recommendations ────────────────────────────────────────────────────
  function addRecommendation(selectedId, selectedName) {
    selectedId = selectedId || ''; selectedName = selectedName || '';
    var list = document.getElementById('recommendations-list-dyn');
    if (!list) return;
    if (list.children.length >= 5) {
      var limitMsg = document.getElementById('rec-limit-msg-dyn');
      if (limitMsg) limitMsg.style.display = 'block';
      return;
    }
    var limitMsg = document.getElementById('rec-limit-msg-dyn');
    if (limitMsg) limitMsg.style.display = 'none';
    _recCount++;
    var rid = 'rec-dyn-' + _recCount;
    var div = document.createElement('div');
    div.id = rid;
    div.style.cssText = 'display:flex;align-items:center;gap:8px;background:var(--bg);border-radius:10px;padding:10px 12px;border:1px solid var(--border)';
    div.innerHTML =
      '<span style="font-size:18px">🍽️</span>' +
      '<select style="flex:1;padding:7px 10px;border:1px solid var(--border);border-radius:8px;font-size:13px" onchange="GoBusiness.modules.catalogo._updateRecPreview(\'' + rid + '\',this)">' +
        '<option value="">Selecciona un producto de tu carta...</option>' +
      '</select>' +
      '<span id="rec-price-' + rid + '" style="font-size:12px;color:var(--primary);font-weight:700;min-width:60px;text-align:right"></span>' +
      '<button class="remove-row-btn" style="width:26px;height:26px;font-size:12px;background:var(--error);color:#fff;border:none;border-radius:6px;cursor:pointer" onclick="document.getElementById(\'' + rid + '\').remove()">×</button>';
    list.appendChild(div);
    var sel = div.querySelector('select');
    var loadItems = function(items) {
      items.forEach(function(item) {
        var opt = document.createElement('option');
        opt.value = item.id;
        opt.textContent = item.name + ' — $' + (item.price||0).toLocaleString('es-CL');
        opt.dataset.price = item.price||0;
        if (item.id === selectedId) opt.selected = true;
        sel.appendChild(opt);
      });
      if (selectedId) updateRecPreview(rid, sel);
    };
    var doLoad = function() {
      if (window._menuItemsCache && window._menuItemsCache.length > 0) {
        loadItems(window._menuItemsCache);
      } else if (window.storeData) {
        window.sb.from('menu_items').select('id,name,price').eq('store_id', window.storeData.id).eq('is_available',true).order('name').then(function(res) {
          window._menuItemsCache = (res.data||[]);
          loadItems(window._menuItemsCache);
        });
      }
    };
    setTimeout(doLoad, 50);
  }

  function updateRecPreview(rid, sel) {
    var el = document.getElementById('rec-price-' + rid);
    if (!el) return;
    var opt = sel.options[sel.selectedIndex];
    el.textContent = opt?.dataset?.price ? '$' + parseInt(opt.dataset.price).toLocaleString('es-CL') : '';
  }

  function getRecommendations() {
    var list = document.getElementById('recommendations-list-dyn');
    if (!list) return [];
    return Array.from(list.querySelectorAll('div[id^="rec-dyn-"]')).map(function(div) {
      var sel = div.querySelector('select');
      var opt = sel?.options[sel.selectedIndex];
      return sel?.value ? { id: sel.value, name: (opt?.textContent || '').split(' — ')[0] || '' } : null;
    }).filter(Boolean);
  }

  // ── Reset counters ────────────────────────────────────────────────────
  function resetCounters() {
    _variantCount = 0; _variantGroupCounter = 0; _variantItemCounter = 0;
    _subGroupCounter = 0; _subItemCounter = 0;
    _optGroupCount = 0; _optItemCount = 0; _recCount = 0;
  }

  // ── Upload helper (reuses global uploadToStorage) ──────────────────────
  async function uploadImage(file) {
    if (typeof window.uploadToStorage === 'function') {
      return await window.uploadToStorage(file, 'product-images', 'items');
    }
    // Fallback: return data URL (not ideal for production but works)
    return await new Promise(function(resolve) {
      var reader = new FileReader();
      reader.onload = function(e) { resolve(e.target.result); };
      reader.readAsDataURL(file);
    });
  }

  // ── SAVE ───────────────────────────────────────────────────────────────
  async function saveItem() {
    var name  = (document.getElementById('item-name-dyn')?.value || '').trim();
    var price = parseInt(document.getElementById('item-price-dyn')?.value);
    if (!name || !price) { showToast('Completa nombre y precio', 'error'); return; }
    var btn = document.getElementById('save-item-btn-dyn');
    btn.textContent = 'Guardando...'; btn.disabled = true;
    try {
      var st = storeType();
      var image_url = null;
      var imgFile = document.getElementById('item-img-input-dyn')?.files[0];
      if (imgFile) image_url = await uploadImage(imgFile);

      // Variants
      var variants = st === 'tienda'
        ? getVariantGroupsTienda().flatMap(function(g) { return g.items.map(function(i) { return { name: g.title + ': ' + i.name, price: i.price }; }); })
        : getVariants();
      var options = getOptions();
      var variantGroups = st === 'tienda' ? getVariantGroupsTienda() : null;

      // Extra fields per type
      var fval = function(id) { var el = document.getElementById(id); return el?.value?.trim() || null; };
      var fchk = function(id) { var el = document.getElementById(id); return el?.checked || false; };
      var extra = {};

      if (st === 'mercado') {
        extra.unidad        = fval('item-unit-dyn');
        extra.codigo_barras = fval('item-barcode-dyn');
        if (fchk('item-refrigerado-dyn')) extra.refrigerado = true;
      } else if (st === 'tienda') {
        extra.garantia   = fval('item-garantia-dyn');
        extra.dimensiones = fval('item-dimensions-dyn');
      } else if (st === 'farmacia') {
        extra.laboratorio = fval('item-laboratorio-dyn');
        extra.formato     = fval('item-formato-dyn');
        if (fchk('item-refrigerado-farm-dyn')) extra.refrigerado = true;
        if (fchk('item-controlado-dyn'))       extra.controlado  = true;
      }
      Object.keys(extra).forEach(function(k) { if (extra[k] == null) delete extra[k]; });

      var data = {
        store_id: window.storeData ? window.storeData.id : null,
        name: name, price: price,
        description: fval('item-desc-dyn'),
        emoji: storeEmoji(),
        is_popular: fchk('item-popular-dyn'),
        is_featured: fchk('item-featured-dyn'),
        discount_pct: calcDiscountPct(),
        original_price: (function() { var op = parseInt(fval('item-original-price-dyn'))||0; return op > price ? op : null; })(),
        contains_alcohol: fchk('item-alcohol-dyn'),
        is_available: true,
        category_id: (document.getElementById('item-category-dyn')?.value) || null,
        variants: variants.length ? JSON.stringify(variants) : null,
        options: options.length ? JSON.stringify(options) : null,
        recommendations: getRecommendations().length ? JSON.stringify(getRecommendations()) : null,
        variant_groups: variantGroups?.length ? JSON.stringify(variantGroups) : null,
        stock: fval('item-stock-dyn') ? parseInt(fval('item-stock-dyn')) : null,
        stock_min: fval('item-stock-min-dyn') ? parseInt(fval('item-stock-min-dyn')) : null,
        sku: fval('item-sku-dyn'),
        barcode: fval('item-barcode-dyn') || null,
        brand: fval('item-brand-dyn'),
        lot_number: fval('item-lot-dyn'),
        expiration_date: fval('item-expiration-dyn') || null,
        extra_info: Object.keys(extra).length ? extra : null,
        // Restaurante
        preparation_time: fval('item-prep-time-dyn') ? parseInt(fval('item-prep-time-dyn')) : null,
        calories: fval('item-calories-dyn') ? parseInt(fval('item-calories-dyn')) : null,
        allergens: Array.from(document.querySelectorAll('.allergen-check-dyn:checked')).map(function(c){return c.value;}).join(',') || null,
        tags: [fchk('item-vegano-dyn')?'vegano':null, fchk('item-vegetariano-dyn')?'vegetariano':null, fchk('item-picante-dyn')?'picante':null, fchk('item-sin-gluten-dyn')?'sin_gluten':null].filter(Boolean).join(',') || null,
        // Farmacia
        requires_prescription: fchk('item-receta-dyn'),
        active_ingredient: fval('item-principio-dyn'),
        isp_registry: fval('item-isp-dyn'),
      };
      if (image_url) data.image_url = image_url;

      var existingId = document.getElementById('item-id-dyn')?.value;
      var res;
      if (existingId) {
        res = await window.sb.from('menu_items').update(data).eq('id', existingId);
      } else {
        res = await window.sb.from('menu_items').insert(data);
      }
      if (res.error && /extra_info/.test(res.error.message||'')) {
        delete data.extra_info;
        res = existingId
          ? await window.sb.from('menu_items').update(data).eq('id', existingId)
          : await window.sb.from('menu_items').insert(data);
      }
      if (res.error) throw new Error(res.error.message);

      // Obtener el ID del producto (nuevo o existente)
      var productId = existingId || (res.data ? res.data.id : null);
      // Si es insert y no tenemos el ID, buscarlo
      if (!productId && !existingId) {
        var selRes = await window.sb.from('menu_items').select('id').eq('store_id', window.storeData.id).eq('name', data.name).order('created_at', { ascending: false }).limit(1);
        if (selRes.data && selRes.data.length) productId = selRes.data[0].id;
      }

      // ── Guardar asignaciones de grupos de variantes ──────────────────────
      if (productId) {
        await window.sb.from('menu_item_variant_groups').delete().eq('item_id', productId);
        var vgChecks = document.querySelectorAll('#variant-groups-selector input:checked');
        for (var v = 0; v < vgChecks.length; v++) {
          await window.sb.from('menu_item_variant_groups').insert({ item_id: productId, group_id: vgChecks[v].value }).then(function(){}, function(){});
        }
        // ── Guardar asignaciones de grupos de opciones ────────────────────
        await window.sb.from('menu_item_option_groups').delete().eq('item_id', productId);
        var ogChecks = document.querySelectorAll('#option-groups-selector input:checked');
        for (var o = 0; o < ogChecks.length; o++) {
          await window.sb.from('menu_item_option_groups').insert({ item_id: productId, group_id: ogChecks[o].value }).then(function(){}, function(){});
        }
      }

      showToast('Producto guardado');
      closeEditor();
      loadCatalog();
    } catch(e) { showToast('Error: ' + e.message, 'error'); }
    finally { btn.textContent = 'Guardar producto'; btn.disabled = false; }
  }

  // ── OPEN EDITOR ────────────────────────────────────────────────────────
  async function openEditor(id) {
    ensureModalHTML();
    resetCounters();
    _editingId = id || null;

    // Set title
    var titleEl = document.getElementById('item-modal-title-dyn');
    if (titleEl) titleEl.textContent = id ? 'Editar producto' : 'Nuevo producto';

    // Reset form
    document.getElementById('item-id-dyn').value = id || '';
    ['item-name-dyn','item-price-dyn','item-desc-dyn','item-original-price-dyn','item-sku-dyn','item-brand-dyn',
     'item-stock-dyn','item-stock-min-dyn','item-lot-dyn','item-expiration-dyn'].forEach(function(x) {
      var el = document.getElementById(x); if (el) el.value = '';
    });
    ['item-popular-dyn','item-featured-dyn','item-alcohol-dyn'].forEach(function(x) {
      var el = document.getElementById(x); if (el) el.checked = false;
    });
    // Reset image: clear file input + hide preview (NO tocar textContent del trigger — destruiría el <input> hijo)
    var imgInput = document.getElementById('item-img-input-dyn');
    if (imgInput) imgInput.value = '';
    var imgPrev = document.getElementById('item-img-preview-dyn');
    if (imgPrev) { imgPrev.src = ''; imgPrev.style.display = 'none'; }
    var imgTrigger = document.getElementById('item-img-trigger-dyn');
    if (imgTrigger) imgTrigger.style.borderColor = '';

    // Clear lists
    ['variants-list-dyn','options-list-dyn','recommendations-list-dyn','variant-groups-tienda-dyn'].forEach(function(x) {
      var el = document.getElementById(x); if (el) el.innerHTML = '';
    });
    var varPreview = document.getElementById('variants-preview-dyn');
    if (varPreview) varPreview.style.display = 'none';

    // Adapt labels & type section
    adaptLabels();
    showTypeSection();

    // Switch to basic tab
    switchTab('basico', document.querySelector('.item-tab-btn[data-tab="basico"]'));

    // Load categories
    if (window.storeData) {
      window.sb.from('menu_categories').select('*').eq('store_id', window.storeData.id).order('sort_order').then(function(res) {
        _categories = res.data || [];
        var catSel = document.getElementById('item-category-dyn');
        if (catSel) catSel.innerHTML = '<option value="">— Sin categoría —</option>' + _categories.map(function(c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');
      });
      // Cache menu items for recommendations
      window.sb.from('menu_items').select('id,name,price').eq('store_id', window.storeData.id).eq('is_available',true).order('name').then(function(res) {
        window._menuItemsCache = res.data || [];
      });

      // Load reusable groups + assigned groups for this product
      _loadGroupSelectors(id);
    }

    function _loadGroupSelectors(productId) {
      // Cargar grupos de variantes
      window.sb.from('variant_groups').select('*, variant_items(*)').eq('store_id', window.storeData.id).order('sort_order').then(function(res) {
        _allVariantGroups = res.data || [];
        // Cargar asignaciones actuales del producto
        var loadAssigned = productId ? window.sb.from('menu_item_variant_groups').select('group_id').eq('item_id', productId).then(function(r) {
          return new Set((r.data || []).map(function(a) { return a.group_id; }));
        }) : Promise.resolve(new Set());

        loadAssigned.then(function(assigned) {
          var container = document.getElementById('variant-groups-selector');
          var empty = document.getElementById('variant-groups-empty');
          if (!container) return;
          if (!_allVariantGroups.length) {
            container.innerHTML = '';
            if (empty) empty.style.display = 'block';
          } else {
            if (empty) empty.style.display = 'none';
            container.innerHTML = _allVariantGroups.map(function(g) {
              var items = g.variant_items || [];
              var preview = items.map(function(i) { return i.name + (i.price_modifier ? ' (+$' + i.price_modifier.toLocaleString('es-CL') + ')' : ''); }).join(', ');
              return '<label style="display:flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;padding:6px 10px;border:1.5px solid ' + (assigned.has(g.id) ? 'var(--primary)' : 'var(--border)') + ';border-radius:8px;background:' + (assigned.has(g.id) ? '#FFF5F2' : 'var(--surface)') + ';font-weight:600">' +
                '<input type="checkbox" value="' + g.id + '" ' + (assigned.has(g.id) ? 'checked' : '') + ' style="accent-color:var(--primary)"> ' +
                esc(g.name) + ' <span style="font-weight:400;color:var(--muted);font-size:11px">(' + preview + ')</span>' +
              '</label>';
            }).join('');
          }
        });
      });

      // Cargar grupos de opciones
      window.sb.from('option_groups').select('*, option_items(*)').eq('store_id', window.storeData.id).order('sort_order').then(function(res) {
        _allOptionGroups = res.data || [];
        var loadAssigned = productId ? window.sb.from('menu_item_option_groups').select('group_id').eq('item_id', productId).then(function(r) {
          return new Set((r.data || []).map(function(a) { return a.group_id; }));
        }) : Promise.resolve(new Set());

        loadAssigned.then(function(assigned) {
          var container = document.getElementById('option-groups-selector');
          var empty = document.getElementById('option-groups-empty');
          if (!container) return;
          if (!_allOptionGroups.length) {
            container.innerHTML = '';
            if (empty) empty.style.display = 'block';
          } else {
            if (empty) empty.style.display = 'none';
            container.innerHTML = _allOptionGroups.map(function(g) {
              var items = g.option_items || [];
              var preview = items.map(function(i) { return i.name + (i.surcharge ? ' (+$' + i.surcharge.toLocaleString('es-CL') + ')' : ''); }).join(', ');
              var reqLabel = g.is_required ? ' 🔒' : '';
              return '<label style="display:flex;align-items:center;gap:6px;font-size:12px;cursor:pointer;padding:6px 10px;border:1.5px solid ' + (assigned.has(g.id) ? 'var(--secondary)' : 'var(--border)') + ';border-radius:8px;background:' + (assigned.has(g.id) ? '#F5F0FF' : 'var(--surface)') + ';font-weight:600">' +
                '<input type="checkbox" value="' + g.id + '" ' + (assigned.has(g.id) ? 'checked' : '') + ' style="accent-color:var(--secondary)"> ' +
                esc(g.name) + reqLabel + ' <span style="font-weight:400;color:var(--muted);font-size:11px">(' + preview + ')</span>' +
              '</label>';
            }).join('');
          }
        });
      });
    }

    // If editing, load existing item
    if (id) {
      try {
        var res = await window.sb.from('menu_items').select('*').eq('id', id).single();
        var item = res.data;
        if (res.error || !item) { showToast('Error al cargar producto', 'error'); return; }

        document.getElementById('item-name-dyn').value = item.name || '';
        document.getElementById('item-price-dyn').value = item.price || '';
        document.getElementById('item-desc-dyn').value = item.description || '';
        var popularEl = document.getElementById('item-popular-dyn'); if (popularEl) popularEl.checked = item.is_popular || false;
        var featuredEl = document.getElementById('item-featured-dyn'); if (featuredEl) featuredEl.checked = item.is_featured || false;
        var origPriceEl = document.getElementById('item-original-price-dyn'); if (origPriceEl) { origPriceEl.value = item.original_price || ''; calcDiscountPreview(); }
        var alcoholEl = document.getElementById('item-alcohol-dyn'); if (alcoholEl) alcoholEl.checked = item.contains_alcohol || false;
        if (item.category_id && document.getElementById('item-category-dyn')) {
          document.getElementById('item-category-dyn').value = item.category_id;
        }

        // Stock & new fields
        var setV = function(id, v) { var el = document.getElementById(id); if (el && v != null) el.value = v; };
        var setC = function(id, v) { var el = document.getElementById(id); if (el) el.checked = !!v; };
        setV('item-stock-dyn', item.stock);
        setV('item-stock-min-dyn', item.stock_min);
        setV('item-sku-dyn', item.sku);
        setV('item-brand-dyn', item.brand);
        setV('item-barcode-dyn', item.barcode);
        setV('item-lot-dyn', item.lot_number);
        setV('item-expiration-dyn', item.expiration_date);

        // Extra info
        var xinfo = (typeof item.extra_info === 'string' ? (function(){try{return JSON.parse(item.extra_info)}catch(e){return {}}}()) : item.extra_info) || {};
        setV('item-unit-dyn', xinfo.unidad);
        setC('item-refrigerado-dyn', xinfo.refrigerado);
        setV('item-garantia-dyn', xinfo.garantia);
        setV('item-dimensions-dyn', xinfo.dimensiones);
        setV('item-laboratorio-dyn', xinfo.laboratorio);
        setV('item-formato-dyn', xinfo.formato);
        setV('item-principio-dyn', item.active_ingredient);
        setV('item-isp-dyn', item.isp_registry);
        setC('item-receta-dyn', item.requires_prescription);
        setC('item-refrigerado-farm-dyn', xinfo.refrigerado);
        setC('item-controlado-dyn', xinfo.controlado);

        // Restaurante fields
        setV('item-prep-time-dyn', item.preparation_time);
        setV('item-calories-dyn', item.calories);
        setC('item-vegano-dyn', (item.tags||'').includes('vegano'));
        setC('item-vegetariano-dyn', (item.tags||'').includes('vegetariano'));
        setC('item-picante-dyn', (item.tags||'').includes('picante'));
        setC('item-sin-gluten-dyn', (item.tags||'').includes('sin_gluten'));
        if (item.allergens) {
          item.allergens.split(',').forEach(function(a) {
            document.querySelectorAll('.allergen-check-dyn').forEach(function(cb) { if (cb.value === a.trim()) cb.checked = true; });
          });
        }

        // Image
        if (item.image_url) {
          var preview = document.getElementById('item-img-preview-dyn');
          if (preview) { preview.src = item.image_url; preview.style.display = 'block'; }
        }

        // Variants
        if (item.variant_groups && storeType() === 'tienda') {
          var groups = typeof item.variant_groups === 'string' ? (function(){ try { return JSON.parse(item.variant_groups); } catch(e) { return []; } })() : item.variant_groups;
          groups.forEach(function(g) {
            addVariantGroupTienda();
            var gid = _variantGroupCounter;
            var titleEl2 = document.getElementById('vg-title-dyn-' + gid);
            if (titleEl2) titleEl2.value = g.title || '';
            var itemsContainer = document.getElementById('vg-items-dyn-' + gid);
            if (itemsContainer) itemsContainer.innerHTML = '';
            (g.items||[]).forEach(function(i) { addVariantItem(gid, i.name, i.price); });
            (g.subGroups||[]).forEach(function(sg) {
              addSubVariantGroup(gid);
              var sgid = _subGroupCounter;
              var sgTitle = document.getElementById('sg-title-dyn-' + sgid);
              if (sgTitle) sgTitle.value = sg.title || '';
              var sgItems = document.getElementById('sg-items-dyn-' + sgid);
              if (sgItems) sgItems.innerHTML = '';
              (sg.items||[]).forEach(function(si) { addSubVariantItem(sgid, si.name, si.price); });
            });
          });
        } else if (item.variants) {
          var variants = typeof item.variants === 'string' ? (function(){ try { return JSON.parse(item.variants); } catch(e) { return []; } })() : item.variants;
          variants.forEach(function(v) { addVariantRow(v.name, v.price); });
        }

        // Options
        if (item.options) {
          var opts = typeof item.options === 'string' ? (function(){ try { return JSON.parse(item.options); } catch(e) { return []; } })() : item.options;
          opts.forEach(function(g) { addOptionGroup(g.title, g.items || [], g.min_sel||0, g.max_sel||0); });
        }

        // Recommendations
        if (item.recommendations) {
          var recs = typeof item.recommendations === 'string' ? (function(){ try { return JSON.parse(item.recommendations); } catch(e) { return []; } })() : item.recommendations;
          setTimeout(function() { recs.forEach(function(r) { addRecommendation(r.id, r.name); }); }, 400);
        }
      } catch(e) { showToast('Error: ' + e.message, 'error'); return; }
    }

    calcDiscountPreview();
    openModal('item-modal-dynamic');
  }

  function closeEditor() {
    closeModal('item-modal-dynamic');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GESTIÓN DE GRUPOS REUTILIZABLES (variantes + opciones)
  // ═══════════════════════════════════════════════════════════════════════════
  var _allVariantGroups = [];
  var _allOptionGroups = [];

  function _openGroupManager() {
    if (!window.storeData) return;
    // Cargar grupos existentes
    Promise.all([
      window.sb.from('variant_groups').select('*, variant_items(*)').eq('store_id', window.storeData.id).order('sort_order'),
      window.sb.from('option_groups').select('*, option_items(*)').eq('store_id', window.storeData.id).order('sort_order')
    ]).then(function(results) {
      _allVariantGroups = (results[0].data || []);
      _allOptionGroups = (results[1].data || []);
      _renderGroupManager();
    });
  }

  function _renderGroupManager() {
    var existing = document.getElementById('group-manager-modal');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay open';
    overlay.id = 'group-manager-modal';
    overlay.innerHTML =
      '<div class="modal" style="width:680px;max-height:85vh;overflow-y:auto">' +
        '<div class="modal-header">' +
          '<h3>📦 Gestionar grupos reutilizables</h3>' +
          '<button class="modal-close" onclick="GoBusiness.modules.catalogo._closeGroupManager()">✕</button>' +
        '</div>' +
        '<div style="display:flex;gap:4px;margin-bottom:16px;border-bottom:2px solid var(--border)">' +
          '<button class="item-tab-btn active" onclick="GoBusiness.modules.catalogo._switchGroupTab(\'vg\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;color:var(--muted)">🎨 Grupos de variantes</button>' +
          '<button class="item-tab-btn" onclick="GoBusiness.modules.catalogo._switchGroupTab(\'og\',this)" style="padding:8px 16px;border:none;background:none;font-weight:700;font-size:13px;cursor:pointer;border-bottom:2px solid transparent;margin-bottom:-2px;color:var(--muted)">➕ Grupos de opciones</button>' +
        '</div>' +
        '<div id="group-tab-vg">' + _renderVariantGroupsList() + '</div>' +
        '<div id="group-tab-og" style="display:none">' + _renderOptionGroupsList() + '</div>' +
      '</div>';
    document.body.appendChild(overlay);
  }

  function _closeGroupManager() {
    var el = document.getElementById('group-manager-modal');
    if (el) el.remove();
    loadCatalog(); // refresh catalog after group changes
  }

  function _switchGroupTab(tab, btn) {
    document.querySelectorAll('#group-manager-modal .item-tab-btn').forEach(function(b) { b.classList.remove('active'); b.style.borderBottomColor = 'transparent'; b.style.color = 'var(--muted)'; });
    btn.classList.add('active');
    btn.style.borderBottomColor = 'var(--primary)';
    btn.style.color = 'var(--primary)';
    document.getElementById('group-tab-vg').style.display = tab === 'vg' ? 'block' : 'none';
    document.getElementById('group-tab-og').style.display = tab === 'og' ? 'block' : 'none';
  }

  // ── Variant Groups ─────────────────────────────────────────────────────
  function _renderVariantGroupsList() {
    if (!_allVariantGroups.length) {
      return '<div style="text-align:center;padding:32px;color:var(--muted)">' +
        '<p style="font-size:48px;margin-bottom:12px">🎨</p>' +
        '<p style="margin-bottom:16px">No hay grupos de variantes creados</p>' +
        '<button class="btn btn-primary" onclick="GoBusiness.modules.catalogo._editVariantGroup()">+ Crear grupo</button>' +
        '</div>';
    }
    return '<div style="margin-bottom:12px"><button class="btn btn-primary btn-sm" onclick="GoBusiness.modules.catalogo._editVariantGroup()">+ Nuevo grupo</button></div>' +
      _allVariantGroups.map(function(g) {
        var items = g.variant_items || [];
        return '<div style="background:var(--bg);border-radius:12px;padding:14px;margin-bottom:10px;border:1px solid var(--border)">' +
          '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
            '<strong style="font-size:14px">' + esc(g.name) + '</strong>' +
            '<div style="display:flex;gap:6px">' +
              '<button class="btn btn-secondary btn-sm" onclick="GoBusiness.modules.catalogo._editVariantGroup(\'' + g.id + '\')">✏️</button>' +
              '<button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.catalogo._deleteVariantGroup(\'' + g.id + '\')">🗑</button>' +
            '</div>' +
          '</div>' +
          '<div style="display:flex;flex-wrap:wrap;gap:6px">' +
            items.map(function(i) { return '<span style="background:#fff;padding:4px 10px;border-radius:6px;font-size:12px;border:1px solid var(--border)">' + esc(i.name) + (i.price_modifier ? ' <strong style="color:var(--primary)">+$' + i.price_modifier.toLocaleString('es-CL') + '</strong>' : '') + '</span>'; }).join('') +
          '</div>' +
        '</div>';
      }).join('');
  }

  function _renderOptionGroupsList() {
    if (!_allOptionGroups.length) {
      return '<div style="text-align:center;padding:32px;color:var(--muted)">' +
        '<p style="font-size:48px;margin-bottom:12px">➕</p>' +
        '<p style="margin-bottom:16px">No hay grupos de opciones creados</p>' +
        '<button class="btn btn-primary" onclick="GoBusiness.modules.catalogo._editOptionGroup()">+ Crear grupo</button>' +
        '</div>';
    }
    return '<div style="margin-bottom:12px"><button class="btn btn-primary btn-sm" onclick="GoBusiness.modules.catalogo._editOptionGroup()">+ Nuevo grupo</button></div>' +
      _allOptionGroups.map(function(g) {
        var items = g.option_items || [];
        return '<div style="background:var(--bg);border-radius:12px;padding:14px;margin-bottom:10px;border:1px solid var(--border)">' +
          '<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">' +
            '<strong style="font-size:14px">' + esc(g.name) + '</strong>' +
            '<div style="display:flex;gap:6px">' +
              '<button class="btn btn-secondary btn-sm" onclick="GoBusiness.modules.catalogo._editOptionGroup(\'' + g.id + '\')">✏️</button>' +
              '<button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.catalogo._deleteOptionGroup(\'' + g.id + '\')">🗑</button>' +
            '</div>' +
          '</div>' +
          '<div style="font-size:11px;color:var(--muted);margin-bottom:6px">' +
            (g.is_required ? '🔒 Obligatorio' : '✅ Opcional') +
            (g.min_selections ? ' · Mín ' + g.min_selections : '') +
            (g.max_selections ? ' · Máx ' + g.max_selections : '') +
          '</div>' +
          '<div style="display:flex;flex-wrap:wrap;gap:6px">' +
            items.map(function(i) { return '<span style="background:#fff;padding:4px 10px;border-radius:6px;font-size:12px;border:1px solid var(--border)">' + esc(i.name) + (i.surcharge ? ' <strong style="color:var(--primary)">+$' + i.surcharge.toLocaleString('es-CL') + '</strong>' : '') + '</span>'; }).join('') +
          '</div>' +
        '</div>';
      }).join('');
  }

  // ── Editar/Crear Variant Group ──────────────────────────────────────────
  function _editVariantGroup(id) {
    var group = id ? _allVariantGroups.find(function(g) { return g.id === id; }) : null;
    var items = group ? (group.variant_items || []) : [];

    var existing = document.getElementById('vg-edit-modal');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay open';
    overlay.id = 'vg-edit-modal';
    overlay.innerHTML =
      '<div class="modal" style="width:500px;max-height:80vh;overflow-y:auto">' +
        '<div class="modal-header"><h3>' + (group ? 'Editar grupo' : 'Nuevo grupo de variantes') + '</h3>' +
          '<button class="modal-close" onclick="GoBusiness.modules.catalogo._closeVGEdit()">✕</button></div>' +
        '<div class="form-group"><label>Nombre del grupo *</label>' +
          '<input type="text" id="vg-name" value="' + esc(group ? group.name : '') + '" placeholder="Ej: Tamaño, Color, Material"></div>' +
        '<div style="margin-bottom:16px">' +
          '<label style="font-size:12px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:0.5px">Ítems</label>' +
          '<div id="vg-items-list">' +
            items.map(function(it, idx) {
              return '<div class="variant-row" style="display:flex;gap:8px;margin-bottom:8px">' +
                '<input type="text" placeholder="Nombre" value="' + esc(it.name) + '" style="flex:1;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
                '<input type="number" placeholder="+$" value="' + (it.price_modifier || 0) + '" style="width:90px;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
                '<button onclick="this.parentElement.remove()" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer">×</button>' +
                '</div>';
            }).join('') +
          '</div>' +
          '<button class="add-row-btn" onclick="GoBusiness.modules.catalogo._addVGItemRow()" style="margin-top:4px;padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">+ Agregar ítem</button>' +
        '</div>' +
        '<button class="btn-primary" onclick="GoBusiness.modules.catalogo._saveVariantGroup(\'' + (group ? group.id : '') + '\')">' + (group ? 'Guardar cambios' : 'Crear grupo') + '</button>' +
      '</div>';
    document.body.appendChild(overlay);
  }

  function _addVGItemRow() {
    var list = document.getElementById('vg-items-list');
    if (!list) return;
    var row = document.createElement('div');
    row.className = 'variant-row';
    row.style.cssText = 'display:flex;gap:8px;margin-bottom:8px';
    row.innerHTML = '<input type="text" placeholder="Nombre" style="flex:1;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<input type="number" placeholder="+$" value="0" style="width:90px;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<button onclick="this.parentElement.remove()" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer">×</button>';
    list.appendChild(row);
  }

  function _closeVGEdit() {
    var el = document.getElementById('vg-edit-modal');
    if (el) el.remove();
  }

  async function _saveVariantGroup(id) {
    var name = (document.getElementById('vg-name')?.value || '').trim();
    if (!name) { showToast('Ingresa un nombre para el grupo', 'error'); return; }
    var rows = document.querySelectorAll('#vg-items-list .variant-row');
    var items = [];
    rows.forEach(function(row) {
      var inputs = row.querySelectorAll('input');
      var n = (inputs[0]?.value || '').trim();
      if (n) items.push({ name: n, price_modifier: parseInt(inputs[1]?.value) || 0 });
    });
    if (!items.length) { showToast('Agrega al menos un ítem', 'error'); return; }

    if (id) {
      // Update existing
      await window.sb.from('variant_groups').update({ name: name }).eq('id', id);
      await window.sb.from('variant_items').delete().eq('group_id', id);
      var insertItems = items.map(function(it, idx) { return { group_id: id, name: it.name, price_modifier: it.price_modifier, sort_order: idx }; });
      await window.sb.from('variant_items').insert(insertItems);
    } else {
      // Create new
      var res = await window.sb.from('variant_groups').insert({ store_id: window.storeData.id, name: name }).select('id').single();
      if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
      var gid = res.data.id;
      var insertItems = items.map(function(it, idx) { return { group_id: gid, name: it.name, price_modifier: it.price_modifier, sort_order: idx }; });
      await window.sb.from('variant_items').insert(insertItems);
    }
    showToast('✅ Grupo guardado');
    _closeVGEdit();
    _openGroupManager(); // refresh
  }

  async function _deleteVariantGroup(id) {
    if (!confirm('¿Eliminar este grupo de variantes? Se desasignará de todos los productos.')) return;
    await window.sb.from('variant_items').delete().eq('group_id', id);
    await window.sb.from('variant_groups').delete().eq('id', id);
    showToast('Grupo eliminado');
    _openGroupManager();
  }

  // ── Editar/Crear Option Group ───────────────────────────────────────────
  function _editOptionGroup(id) {
    var group = id ? _allOptionGroups.find(function(g) { return g.id === id; }) : null;
    var items = group ? (group.option_items || []) : [];

    var existing = document.getElementById('og-edit-modal');
    if (existing) existing.remove();

    var overlay = document.createElement('div');
    overlay.className = 'modal-overlay open';
    overlay.id = 'og-edit-modal';
    overlay.innerHTML =
      '<div class="modal" style="width:500px;max-height:80vh;overflow-y:auto">' +
        '<div class="modal-header"><h3>' + (group ? 'Editar grupo' : 'Nuevo grupo de opciones') + '</h3>' +
          '<button class="modal-close" onclick="GoBusiness.modules.catalogo._closeOGEdit()">✕</button></div>' +
        '<div class="form-group"><label>Nombre del grupo *</label>' +
          '<input type="text" id="og-name" value="' + esc(group ? group.name : '') + '" placeholder="Ej: Acompañamientos, Extras, Salsas"></div>' +
        '<div class="form-row">' +
          '<div class="form-group"><label>Mín selecciones</label><input type="number" id="og-min" value="' + (group ? group.min_selections || 0 : 0) + '" min="0"></div>' +
          '<div class="form-group"><label>Máx selecciones</label><input type="number" id="og-max" value="' + (group ? group.max_selections || 0 : 0) + '" min="0"></div>' +
        '</div>' +
        '<div style="margin-bottom:16px">' +
          '<label style="display:flex;align-items:center;gap:8px;font-size:13px;font-weight:600;cursor:pointer">' +
            '<input type="checkbox" id="og-required" ' + (group && group.is_required ? 'checked' : '') + ' style="accent-color:var(--primary)"> 🔒 Grupo obligatorio</label>' +
        '</div>' +
        '<div style="margin-bottom:16px">' +
          '<label style="font-size:12px;font-weight:700;color:var(--muted);text-transform:uppercase;letter-spacing:0.5px">Ítems</label>' +
          '<div id="og-items-list">' +
            items.map(function(it, idx) {
              return '<div class="variant-row" style="display:flex;gap:8px;margin-bottom:8px">' +
                '<input type="text" placeholder="Nombre" value="' + esc(it.name) + '" style="flex:1;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
                '<input type="number" placeholder="+$" value="' + (it.surcharge || 0) + '" style="width:90px;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
                '<button onclick="this.parentElement.remove()" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer">×</button>' +
                '</div>';
            }).join('') +
          '</div>' +
          '<button class="add-row-btn" onclick="GoBusiness.modules.catalogo._addOGItemRow()" style="margin-top:4px;padding:6px 12px;background:var(--primary);color:#fff;border:none;border-radius:8px;font-size:12px;font-weight:700;cursor:pointer">+ Agregar ítem</button>' +
        '</div>' +
        '<button class="btn-primary" onclick="GoBusiness.modules.catalogo._saveOptionGroup(\'' + (group ? group.id : '') + '\')">' + (group ? 'Guardar cambios' : 'Crear grupo') + '</button>' +
      '</div>';
    document.body.appendChild(overlay);
  }

  function _addOGItemRow() {
    var list = document.getElementById('og-items-list');
    if (!list) return;
    var row = document.createElement('div');
    row.className = 'variant-row';
    row.style.cssText = 'display:flex;gap:8px;margin-bottom:8px';
    row.innerHTML = '<input type="text" placeholder="Nombre" style="flex:1;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<input type="number" placeholder="+$" value="0" style="width:90px;padding:8px 12px;border:1px solid var(--border);border-radius:8px;font-size:13px">' +
      '<button onclick="this.parentElement.remove()" style="width:30px;height:30px;background:var(--error);color:#fff;border:none;border-radius:6px;font-size:14px;cursor:pointer">×</button>';
    list.appendChild(row);
  }

  function _closeOGEdit() {
    var el = document.getElementById('og-edit-modal');
    if (el) el.remove();
  }

  async function _saveOptionGroup(id) {
    var name = (document.getElementById('og-name')?.value || '').trim();
    if (!name) { showToast('Ingresa un nombre para el grupo', 'error'); return; }
    var rows = document.querySelectorAll('#og-items-list .variant-row');
    var items = [];
    rows.forEach(function(row) {
      var inputs = row.querySelectorAll('input');
      var n = (inputs[0]?.value || '').trim();
      if (n) items.push({ name: n, surcharge: parseInt(inputs[1]?.value) || 0 });
    });
    var minSel = parseInt(document.getElementById('og-min')?.value) || 0;
    var maxSel = parseInt(document.getElementById('og-max')?.value) || 0;
    var required = document.getElementById('og-required')?.checked || false;

    if (id) {
      await window.sb.from('option_groups').update({ name: name, min_selections: minSel, max_selections: maxSel, is_required: required }).eq('id', id);
      await window.sb.from('option_items').delete().eq('group_id', id);
      if (items.length) {
        var insertItems = items.map(function(it, idx) { return { group_id: id, name: it.name, surcharge: it.surcharge, sort_order: idx }; });
        await window.sb.from('option_items').insert(insertItems);
      }
    } else {
      var res = await window.sb.from('option_groups').insert({ store_id: window.storeData.id, name: name, min_selections: minSel, max_selections: maxSel, is_required: required }).select('id').single();
      if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
      var gid = res.data.id;
      if (items.length) {
        var insertItems = items.map(function(it, idx) { return { group_id: gid, name: it.name, surcharge: it.surcharge, sort_order: idx }; });
        await window.sb.from('option_items').insert(insertItems);
      }
    }
    showToast('✅ Grupo guardado');
    _closeOGEdit();
    _openGroupManager();
  }

  async function _deleteOptionGroup(id) {
    if (!confirm('¿Eliminar este grupo de opciones? Se desasignará de todos los productos.')) return;
    await window.sb.from('option_items').delete().eq('group_id', id);
    await window.sb.from('menu_item_option_groups').delete().eq('group_id', id);
    await window.sb.from('option_groups').delete().eq('id', id);
    showToast('Grupo eliminado');
    _openGroupManager();
  }

  // ── Catalog actions ────────────────────────────────────────────────────
  function openCatModal() {
    var el = document.getElementById('cat-modal');
    if (el) {
      document.getElementById('cat-name').value = '';
      el.classList.add('open');
    } else {
      // Fallback: create simple prompt
      var name = prompt('Nombre de la categoría:');
      if (name) saveCategoryDirect(name);
    }
  }

  async function saveCategoryDirect(name) {
    if (!window.storeData) return;
    var res = await window.sb.from('menu_categories').insert({ store_id: window.storeData.id, name: name, sort_order: 1, is_visible: true });
    if (res.error) { showToast('Error: ' + res.error.message, 'error'); return; }
    showToast('Categoría creada');
    loadCatalog();
  }

  async function toggleItem(id, current) {
    await window.sb.from('menu_items').update({ is_available: !current }).eq('id', id);
    showToast('Producto actualizado');
    loadCatalog();
  }

  async function deleteItem(id) {
    if (!confirm('¿Eliminar este producto?')) return;
    var res = await window.sb.from('menu_items').delete().eq('id', id).select('id');
    if (res.error) { showToast('Error al eliminar: ' + res.error.message, 'error'); return; }
    if (!res.data?.length) { showToast('Sin permisos para eliminar este producto', 'error'); return; }
    showToast('Producto eliminado');
    loadCatalog();
  }

  async function deleteCategory(id) {
    if (!confirm('¿Eliminar esta categoría? Los productos quedarán en "Sin categoría".')) return;
    await window.sb.from('menu_items').update({ category_id: null }).eq('category_id', id);
    var res = await window.sb.from('menu_categories').delete().eq('id', id).select('id');
    if (res.error) { showToast('Error al eliminar: ' + res.error.message, 'error'); return; }
    if (!res.data?.length) { showToast('Sin permisos para eliminar esta categoría', 'error'); return; }
    showToast('Categoría eliminada');
    loadCatalog();
  }

  // ── REORDENAR CON FLECHAS ▲▼ + VISIBILIDAD ────────────────────────────

  // Obtener todos los nodos DOM de un bloque categoría (header + sus productos)
  function _getCatBlock(headerRow) {
    var nodes = [headerRow];
    var catId = headerRow.dataset.catId;
    var el = headerRow.nextElementSibling;
    while (el) {
      if (el.dataset && el.dataset.type === 'category') break; // siguiente categoría
      if (el.dataset && el.dataset.type === 'product' && el.dataset.catId === catId) {
        nodes.push(el);
      }
      el = el.nextElementSibling;
    }
    return nodes;
  }

  // Obtener el último nodo del bloque de una categoría (su último producto, o el header si no tiene)
  function _lastOfCatBlock(headerRow) {
    var block = _getCatBlock(headerRow);
    return block[block.length - 1];
  }

  // Mover categoría hacia arriba (header + todos sus productos)
  async function _moveCatUp(catId) {
    var row = document.querySelector('#menu-content .menu-cat-header[data-cat-id="' + catId + '"]');
    if (!row) return;
    var prevHeader = _prevCategoryRow(row);
    if (!prevHeader) return;
    // Mover todo el bloque justo antes del header de la categoría anterior
    var block = _getCatBlock(row);
    for (var i = 0; i < block.length; i++) {
      row.parentNode.insertBefore(block[i], prevHeader);
    }
    await _syncCatOrderFromDOM();
  }

  // Mover categoría hacia abajo (header + todos sus productos)
  async function _moveCatDown(catId) {
    var row = document.querySelector('#menu-content .menu-cat-header[data-cat-id="' + catId + '"]');
    if (!row) return;
    var nextHeader = _nextCategoryRow(row);
    if (!nextHeader) return;
    // Mover todo el bloque después del último elemento de la categoría siguiente
    var insertAfter = _lastOfCatBlock(nextHeader);
    var block = _getCatBlock(row);
    for (var i = 0; i < block.length; i++) {
      row.parentNode.insertBefore(block[i], insertAfter.nextSibling);
      insertAfter = block[i];
    }
    await _syncCatOrderFromDOM();
  }

  function _prevCategoryRow(row) {
    var el = row.previousElementSibling;
    while (el) {
      if (el.dataset && el.dataset.type === 'category') return el;
      el = el.previousElementSibling;
    }
    return null;
  }

  function _nextCategoryRow(row) {
    var el = row.nextElementSibling;
    while (el) {
      if (el.dataset && el.dataset.type === 'category') return el;
      el = el.nextElementSibling;
    }
    return null;
  }

  async function _syncCatOrderFromDOM() {
    var updates = [];
    document.querySelectorAll('#menu-content .menu-cat-header[data-type="category"]').forEach(function(el, i) {
      updates.push(window.sb.from('menu_categories').update({ sort_order: i }).eq('id', el.dataset.catId));
    });
    await Promise.all(updates);
    // Actualizar flechas de todas las categorías (primera/última)
    _refreshAllArrows();
  }

  // Mover producto hacia arriba (dentro de su categoría)
  async function _moveItemUp(itemId, catId) {
    var sel = catId
      ? '#menu-content .menu-item-row[data-item-id="' + itemId + '"][data-cat-id="' + catId + '"]'
      : '#menu-content .menu-item-row[data-item-id="' + itemId + '"][data-cat-id=""]';
    var row = document.querySelector(sel);
    if (!row) return;
    var prev = _prevItemRow(row, catId);
    if (!prev) return;
    row.parentNode.insertBefore(row, prev);
    await _syncItemOrderFromDOM(catId);
  }

  async function _moveItemDown(itemId, catId) {
    var sel = catId
      ? '#menu-content .menu-item-row[data-item-id="' + itemId + '"][data-cat-id="' + catId + '"]'
      : '#menu-content .menu-item-row[data-item-id="' + itemId + '"][data-cat-id=""]';
    var row = document.querySelector(sel);
    if (!row) return;
    var next = _nextItemRow(row, catId);
    if (!next) return;
    if (next.nextSibling) {
      row.parentNode.insertBefore(row, next.nextSibling);
    } else {
      row.parentNode.appendChild(row);
    }
    await _syncItemOrderFromDOM(catId);
  }

  function _prevItemRow(row, catId) {
    var el = row.previousElementSibling;
    while (el) {
      if (el.dataset && el.dataset.type === 'product' && el.dataset.catId === (catId||'')) return el;
      el = el.previousElementSibling;
    }
    return null;
  }

  function _nextItemRow(row, catId) {
    var el = row.nextElementSibling;
    while (el) {
      if (el.dataset && el.dataset.type === 'product' && el.dataset.catId === (catId||'')) return el;
      el = el.nextElementSibling;
    }
    return null;
  }

  async function _syncItemOrderFromDOM(catId) {
    var updates = [];
    var sel = catId
      ? '#menu-content .menu-item-row[data-type="product"][data-cat-id="' + catId + '"]'
      : '#menu-content .menu-item-row[data-type="product"][data-cat-id=""]';
    document.querySelectorAll(sel).forEach(function(el, i) {
      updates.push(window.sb.from('menu_items').update({ sort_order: i }).eq('id', el.dataset.itemId));
    });
    await Promise.all(updates);
    _refreshAllArrows();
  }

  // Refrescar ▲▼ de todos los elementos (visibilidad según primera/última posición)
  function _refreshAllArrows() {
    var container = document.getElementById('menu-content');
    if (!container) return;
    // Categorías
    var catHeaders = container.querySelectorAll('.menu-cat-header[data-type="category"]');
    catHeaders.forEach(function(el, i) {
      _setArrowState(el, i > 0, i < catHeaders.length - 1);
    });
    // Productos agrupados por categoría + huérfanos
    var seenCats = {};
    container.querySelectorAll('.menu-item-row[data-type="product"]').forEach(function(el) {
      var cid = el.dataset.catId || '';
      if (!(cid in seenCats)) {
        seenCats[cid] = container.querySelectorAll('.menu-item-row[data-type="product"][data-cat-id="' + cid + '"]');
      }
      var items = seenCats[cid];
      var idx = Array.prototype.indexOf.call(items, el);
      _setArrowState(el, idx > 0, idx < items.length - 1);
    });
  }

  function _setArrowState(row, hasUp, hasDown) {
    var buttons = row.querySelectorAll('.arrow-btn');
    if (buttons.length >= 2) {
      if (hasUp) { buttons[0].style.visibility = ''; buttons[0].disabled = false; }
      else { buttons[0].style.visibility = 'hidden'; }
      if (hasDown) { buttons[1].style.visibility = ''; buttons[1].disabled = false; }
      else { buttons[1].style.visibility = 'hidden'; }
    }
  }

  // Toggle visibilidad de categoría + todos sus productos
  async function _toggleCatVisibility(catId, currentVisible) {
    var newState = !currentVisible;
    await window.sb.from('menu_categories').update({ is_visible: newState }).eq('id', catId);
    // Sincronizar visibilidad de todos los productos de esta categoría
    await window.sb.from('menu_items').update({ is_available: newState }).eq('category_id', catId);
    loadCatalog();
  }

  // Editar nombre de categoría
  async function _editCategory(catId, currentName) {
    var newName = prompt('Nuevo nombre para la categoría:', currentName);
    if (!newName || !newName.trim() || newName.trim() === currentName) return;
    await window.sb.from('menu_categories').update({ name: newName.trim() }).eq('id', catId);
    showToast('Categoría renombrada');
    loadCatalog();
  }

  // ── LOAD CATALOG ───────────────────────────────────────────────────────
  async function loadCatalog() {
    if (!window.storeData) return;
    var menuContent = document.getElementById('menu-content');
    if (menuContent) menuContent.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

    var resCats = await window.sb.from('menu_categories').select('*').eq('store_id', window.storeData.id).order('sort_order');
    var resItems = await window.sb.from('menu_items').select('*').eq('store_id', window.storeData.id).order('sort_order');
    _categories = resCats.data || [];
    _items = resItems.data || [];

    // Update category selector
    var catSel = document.getElementById('item-category-dyn');
    if (catSel) catSel.innerHTML = '<option value="">— Sin categoría —</option>' + _categories.map(function(c) { return '<option value="' + c.id + '">' + esc(c.name) + '</option>'; }).join('');

    if (!_categories.length && !_items.length) {
      var typeUI = {
        restaurante: { icon: '🍽️', empty: 'Tu carta está vacía. Agrega categorías y platos.' },
        mercado:     { icon: '🛒', empty: 'Tu catálogo está vacío. Agrega categorías y productos.' },
        tienda:      { icon: '🏪', empty: 'Tu tienda está vacía. Agrega categorías y productos.' },
        farmacia:    { icon: '💊', empty: 'Tu catálogo está vacío. Agrega productos de salud.' },
        cafeteria:   { icon: '☕', empty: 'Tu carta está vacía. Agrega categorías y productos.' },
        licoreria:   { icon: '🍷', empty: 'Tu catálogo está vacío. Agrega productos.' },
        mascotas:    { icon: '🐾', empty: 'Tu catálogo está vacío. Agrega productos para mascotas.' },
        flores:      { icon: '💐', empty: 'Tu catálogo está vacío. Agrega arreglos florales.' },
      };
      var ui = typeUI[storeType()] || typeUI.restaurante;
      if (menuContent) {
        menuContent.innerHTML =
          '<div class="empty"><div class="empty-icon">' + ui.icon + '</div><p>' + ui.empty + '</p>' +
          '<button class="btn" style="margin-top:14px;background:linear-gradient(135deg,#7C3AED,#FF6B35);color:#fff" onclick="if(typeof openIAModal===\'function\')openIAModal();else GoBusiness.modules.catalogo._openIA()">🤖 Deja que la IA arme tu catálogo</button>' +
          '<p style="font-size:12px;color:var(--muted);margin-top:8px">Sube una foto de tu carta, un PDF o un link y la cargamos por ti</p></div>';
      }
      return;
    }

    var itemRow = function(item, catId, idx, total) {
      var upBtn = idx > 0
        ? '<button class="arrow-btn" onclick="GoBusiness.modules.catalogo._moveItemUp(\'' + item.id + '\',\'' + (catId||'') + '\')" title="Subir">▲</button>'
        : '<span class="arrow-btn" style="visibility:hidden">▲</span>';
      var downBtn = idx < total - 1
        ? '<button class="arrow-btn" onclick="GoBusiness.modules.catalogo._moveItemDown(\'' + item.id + '\',\'' + (catId||'') + '\')" title="Bajar">▼</button>'
        : '<span class="arrow-btn" style="visibility:hidden">▼</span>';
      return '<div class="menu-item-row' + (item.is_available ? '' : ' hidden-item') + '" data-type="product" data-item-id="' + item.id + '" data-cat-id="' + (catId || '') + '">' +
        '<div style="display:flex;flex-direction:column;gap:0;flex-shrink:0">' + upBtn + downBtn + '</div>' +
        (item.image_url
          ? '<img src="' + esc(item.image_url) + '" style="width:48px;height:48px;border-radius:12px;object-fit:cover;flex-shrink:0" onerror="this.outerHTML=\'<div class=&quot;menu-item-emoji&quot;>' + (item.emoji||'🍽️') + '</div>\'">'
          : '<div class="menu-item-emoji">' + (item.emoji||'🍽️') + '</div>') +
        '<div class="menu-item-info">' +
          '<div class="menu-item-name">' + esc(item.name) + ' ' + (item.is_popular?'⭐':'') + '</div>' +
          '<div class="menu-item-desc">' + esc(item.description||'') + '</div>' +
        '</div>' +
        '<div>' + fmtCLP(item.price) + ' ' + (item.discount_pct>0?'(-'+item.discount_pct+'%)':'') + ' ' + (item.is_featured?'[Home]':'') + '</div>' +
        '<span class="badge ' + (item.is_available?'badge-green':'badge-red') + '" style="margin:0 8px">' + (item.is_available?'Disponible':'No disponible') + '</span>' +
        '<button class="btn btn-sec btn-sm" onclick="GoBusiness.modules.catalogo._toggleItem(\'' + item.id + '\',' + item.is_available + ')">' + (item.is_available?'Ocultar':'Mostrar') + '</button>' +
        '<button class="btn btn-secondary btn-sm" onclick="GoBusiness.modules.catalogo._openEditor(\'' + item.id + '\')">✏️ Editar</button>' +
        '<button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.catalogo._deleteItem(\'' + item.id + '\')">Eliminar</button>' +
      '</div>';
    };

    var html = '';
    _categories.forEach(function(cat, catIdx) {
      var catItems = _items.filter(function(i) { return i.category_id === cat.id; });
      var upBtn = catIdx > 0
        ? '<button class="arrow-btn" onclick="GoBusiness.modules.catalogo._moveCatUp(\'' + cat.id + '\')" title="Subir categoría">▲</button>'
        : '<span class="arrow-btn" style="visibility:hidden">▲</span>';
      var downBtn = catIdx < _categories.length - 1
        ? '<button class="arrow-btn" onclick="GoBusiness.modules.catalogo._moveCatDown(\'' + cat.id + '\')" title="Bajar categoría">▼</button>'
        : '<span class="arrow-btn" style="visibility:hidden">▼</span>';
      html += '<div class="menu-cat-header' + (cat.is_visible ? '' : ' hidden-item') + '" data-type="category" data-cat-id="' + cat.id + '">' +
        '<div style="display:flex;flex-direction:column;gap:0;flex-shrink:0">' + upBtn + downBtn + '</div>' +
        '<button class="visibility-toggle' + (cat.is_visible ? '' : ' off') + '" onclick="GoBusiness.modules.catalogo._toggleCatVisibility(\'' + cat.id + '\',' + cat.is_visible + ')" title="Mostrar/ocultar categoría" style="font-size:10px;font-weight:700;min-width:52px">' + (cat.is_visible ? 'Visible' : 'Oculto') + '</button>' +
        '<strong>' + esc(cat.name) + '</strong><span style="color:var(--muted);font-size:13px">' + catItems.length + ' productos</span>' +
        '<div>' +
          '<button class="btn btn-secondary btn-sm" onclick="GoBusiness.modules.catalogo._editCategory(\'' + cat.id + '\',\'' + escAttr(cat.name) + '\')">✏️</button>' +
          '<button class="btn btn-danger btn-sm" onclick="GoBusiness.modules.catalogo._deleteCategory(\'' + cat.id + '\')">Eliminar</button>' +
        '</div>' +
      '</div>';
      html += catItems.map(function(item, i) { return itemRow(item, cat.id, i, catItems.length); }).join('');
    });

    var catIds = new Set(_categories.map(function(c) { return c.id; }));
    var orphans = _items.filter(function(i) { return !i.category_id || !catIds.has(i.category_id); });
    if (orphans.length) {
      if (_categories.length) html += '<div class="menu-cat-header" data-type="orphans"><strong>📦 Sin categoría</strong><span style="color:var(--muted);font-size:13px">' + orphans.length + ' productos — edítalos para asignarles una categoría</span></div>';
      html += orphans.map(function(item, i) { return itemRow(item, null, i, orphans.length); }).join('');
    }

    if (menuContent) {
      menuContent.innerHTML = html || '<div class="empty"><div class="empty-icon">' + storeEmoji() + '</div><p>Sin productos en esta categoría</p></div>';
    }
  }

  // ── IA fallback ────────────────────────────────────────────────────────
  function openIA() {
    if (typeof window.openIAModal === 'function') {
      window.openIAModal();
    } else {
      showToast('Asistente IA no disponible en este momento', 'error');
    }
  }

  // ── Render (entry point) ───────────────────────────────────────────────
  function render() {
    // The catalog renders into section-menu (or section-catalogo)
    // Ensure the section is visible
    var menuSection = document.getElementById('section-menu');
    if (menuSection) menuSection.style.display = 'block';
    var catalogoSection = document.getElementById('section-catalogo');
    if (catalogoSection) catalogoSection.style.display = 'block';

    // Ensure modal HTML exists
    ensureModalHTML();

    // Load catalog data
    loadCatalog();
  }

  function destroy() {
    // No cleanup needed — the HTML sections are static in aliados.html
  }

  // Expose public API
  var mod = {
    render: render,
    destroy: destroy,
    // Tab switching
    _switchTab: switchTab,
    // Variants
    _addVariantRow: addVariantRow,
    _updateVariantsPreview: updateVariantsPreview,
    _addVariantGroupTienda: addVariantGroupTienda,
    _addVariantItem: addVariantItem,
    _addSubVariantGroup: addSubVariantGroup,
    _addSubVariantItem: addSubVariantItem,
    // Options
    _addOptionGroup: addOptionGroup,
    _addOptionItem: addOptionItem,
    // Recommendations
    _addRecommendation: addRecommendation,
    _updateRecPreview: updateRecPreview,
    // Image
    _previewImage: previewImage,
    // Discount
    _calcDiscountPreview: calcDiscountPreview,
    // Save / Editor
    _saveItem: saveItem,
    _openEditor: openEditor,
    _closeEditor: closeEditor,
    // Group management
    _openGroupManager: _openGroupManager,
    _closeGroupManager: _closeGroupManager,
    _switchGroupTab: _switchGroupTab,
    _editVariantGroup: _editVariantGroup,
    _addVGItemRow: _addVGItemRow,
    _closeVGEdit: _closeVGEdit,
    _saveVariantGroup: _saveVariantGroup,
    _deleteVariantGroup: _deleteVariantGroup,
    _editOptionGroup: _editOptionGroup,
    _addOGItemRow: _addOGItemRow,
    _closeOGEdit: _closeOGEdit,
    _saveOptionGroup: _saveOptionGroup,
    _deleteOptionGroup: _deleteOptionGroup,
    // Catalog actions
    _toggleItem: toggleItem,
    _deleteItem: deleteItem,
    _deleteCategory: deleteCategory,
    _openCatModal: openCatModal,
    _toggleCatVisibility: _toggleCatVisibility,
    _editCategory: _editCategory,
    _moveCatUp: _moveCatUp,
    _moveCatDown: _moveCatDown,
    _moveItemUp: _moveItemUp,
    _moveItemDown: _moveItemDown,
    // IA
    _openIA: openIA,
    // Reload
    _loadCatalog: loadCatalog,
  };

  window.GoBusiness.modules.catalogo = mod;

})();
