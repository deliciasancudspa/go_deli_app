// ============================================================================
// Go Business 2.0 — Módulo Impresora (ESC/POS vía Web Serial API)
// ============================================================================
// Compatible con impresoras térmicas ESC/POS: Epson, Bixolon, Xprinter, etc.
// El cajón de billetes se conecta al puerto DK de la impresora (RJ12).
// Chrome/Edge Desktop 89+ requerido. No funciona en Firefox/Safari/móvil.
// ============================================================================
(function() {
  'use strict';

  var _port = null;
  var _writer = null;
  var _reader = null;
  var _connected = false;
  var _printerName = '';
  var _autoPrint = true;
  var _autoDrawer = false;  // abrir cajón al cobrar efectivo

  // ── Constantes ESC/POS ──────────────────────────────────────────────────
  var ESC = '\x1B';
  var GS  = '\x1D';
  var LF  = '\x0A';

  function _cmd(s) {
    // Codifica string + comandos ESC/POS a Uint8Array
    var encoder = new TextEncoder();
    return encoder.encode(s);
  }

  function _init()   { return _cmd(ESC + '@'); }                    // Inicializar
  function _cut()    { return _cmd(GS + 'V\x42\x00'); }             // Cortar papel
  function _pulse(pin, on, off) { return _cmd(ESC + 'p' + String.fromCharCode(pin) + String.fromCharCode(on) + String.fromCharCode(off)); }
  function _openDrawerCmd() { return _pulse(0, 25, 250); }         // Abrir cajón (pin 2)
  function _bold(on) { return _cmd(ESC + 'E' + (on ? '\x01' : '\x00')); }
  function _align(m) { return _cmd(ESC + 'a' + String.fromCharCode(m)); } // 0=izq 1=centro 2=der
  function _double(on) { return _cmd(ESC + '!' + (on ? '\x10' : '\x00')); }
  function _underline(on) { return _cmd(ESC + '-' + (on ? '\x01' : '\x00')); }
  function _line() { return _cmd('--------------------------------' + LF); }
  function _doubleLine() { return _cmd('================================' + LF); }

  function _concat(arrays) {
    var total = arrays.reduce(function(s, a) { return s + a.length; }, 0);
    var out = new Uint8Array(total);
    var offset = 0;
    arrays.forEach(function(a) { out.set(a, offset); offset += a.length; });
    return out;
  }

  // ── API Pública ─────────────────────────────────────────────────────────

  function isSupported() {
    return !!(navigator.serial);
  }

  function isConnected() {
    return _connected;
  }

  function getPrinterName() {
    return _printerName;
  }

  function getSettings() {
    return { autoPrint: _autoPrint, autoDrawer: _autoDrawer };
  }

  // ── Conectar ────────────────────────────────────────────────────────────
  async function connect() {
    if (!isSupported()) {
      throw new Error('Web Serial no soportado. Usa Chrome o Edge en desktop.');
    }

    try {
      // Solicitar puerto serial
      _port = await navigator.serial.requestPort();
      await _port.open({ baudRate: 9600 });

      _writer = _port.writable.getWriter();
      _printerName = 'Impresora ' + (_port.getInfo ? (_port.getInfo().usbProductName || 'Térmica') : 'Térmica');

      // Enviar comando de inicialización
      await _writer.write(_init());
      await _writer.write(_cmd(LF));

      _connected = true;
      _savePort();
      _notify();
      return { success: true, name: _printerName };
    } catch(e) {
      _connected = false;
      _port = null;
      _writer = null;
      throw e;
    }
  }

  // ── Reconectar a puerto guardado ────────────────────────────────────────
  async function reconnect() {
    if (!isSupported()) return false;
    try {
      var ports = await navigator.serial.getPorts();
      if (!ports.length) return false;

      for (var i = 0; i < ports.length; i++) {
        try {
          _port = ports[i];
          await _port.open({ baudRate: 9600 });
          _writer = _port.writable.getWriter();
          _printerName = 'Impresora ' + (_port.getInfo ? (_port.getInfo().usbProductName || 'Térmica') : 'Térmica');

          await _writer.write(_init());
          await _writer.write(_cmd(LF));

          _connected = true;
          _notify();
          return true;
        } catch(e) {
          // Este puerto no funciona, probar el siguiente
        }
      }
      return false;
    } catch(e) {
      return false;
    }
  }

  function _savePort() {
    // Los puertos se guardan automáticamente vía navigator.serial.getPorts()
  }

  // ── Desconectar ─────────────────────────────────────────────────────────
  async function disconnect() {
    try {
      if (_writer) { _writer.releaseLock(); _writer = null; }
      if (_port) { await _port.close(); _port = null; }
    } catch(e) { /* ignore */ }
    _connected = false;
    _printerName = '';
    _notify();
  }

  // ── Abrir cajón ────────────────────────────────────────────────────────
  async function openDrawer() {
    if (!_connected || !_writer) throw new Error('Impresora no conectada');
    try {
      await _writer.write(_init());
      await _writer.write(_openDrawerCmd());
      await _writer.write(_cmd(LF + LF));
      return true;
    } catch(e) {
      throw new Error('Error al abrir cajón: ' + e.message);
    }
  }

  // Abrir cajón de forma segura (traga errores, no interrumpe flujos)
  function safeOpenDrawer() {
    openDrawer().catch(function() { /* silencio — impresora no disponible */ });
  }

  // ── Imprimir ticket de venta ────────────────────────────────────────────
  async function printReceipt(order) {
    if (!_connected || !_writer) throw new Error('Impresora no conectada');

    var now  = new Date();
    var hora = now.toLocaleTimeString('es-CL', {hour:'2-digit',minute:'2-digit'});
    var fecha = now.toLocaleDateString('es-CL', {day:'2-digit',month:'2-digit',year:'numeric'});

    var storeName = (window.storeData && window.storeData.name) || 'Go Deli';
    var orderId   = ((order && order.id) || '').toString().slice(-8).toUpperCase();
    var items     = (order && order.items) || (order && order.order_items) || [];
    var subtotal  = (order && order.subtotal) || 0;
    var delivery  = (order && order.delivery_fee) || 0;
    var total     = (order && order.total) || 0;
    var payment   = _payLabel((order && order.payment_method) || 'cash');
    var mode      = _modeLabel((order && order.order_type) || 'dine_in');

    var parts = [];

    // Encabezado
    parts.push(_init());
    parts.push(_align(1));  // centro
    parts.push(_double(true));
    parts.push(_cmd(storeName + LF));
    parts.push(_double(false));
    parts.push(_cmd('Tu delivery favorito' + LF));
    parts.push(_cmd(fecha + '  ' + hora + LF));
    parts.push(_cmd('Pedido #' + orderId + LF));
    parts.push(_doubleLine());

    // Datos de la venta
    parts.push(_align(0));  // izquierda
    parts.push(_cmd('Modalidad: ' + mode + LF));
    parts.push(_cmd('Pago:      ' + payment + LF));
    parts.push(_line());

    // Items
    parts.push(_bold(true));
    parts.push(_cmd('Cant  Producto          Precio' + LF));
    parts.push(_bold(false));
    parts.push(_line());

    (items || []).forEach(function(it) {
      var qty = it.quantity || 1;
      var name = (it.item_name || it.name || 'Producto').substring(0, 18);
      var price = _fmt(it.item_price || it.price || 0);
      var lineTotal = _fmt((it.item_price || it.price || 0) * qty);
      parts.push(_cmd(qty + 'x ' + _padRight(name, 18) + ' $' + lineTotal + LF));
    });

    parts.push(_line());

    // Totales
    parts.push(_cmd(_padRight('Subtotal:', 20) + ' $' + _fmt(subtotal) + LF));
    if (delivery > 0) {
      parts.push(_cmd(_padRight('Delivery:', 20) + ' $' + _fmt(delivery) + LF));
    }
    parts.push(_double(true));
    parts.push(_cmd(_padRight('TOTAL:', 20) + ' $' + _fmt(total) + LF));
    parts.push(_double(false));
    parts.push(_doubleLine());

    // Footer
    parts.push(_align(1));
    parts.push(_cmd('¡Gracias por tu compra!' + LF));
    parts.push(_cmd('Go Deli — www.godeli.cl' + LF));
    parts.push(_cmd(LF + LF + LF));

    // Cortar
    parts.push(_cut());

    try {
      await _writer.write(_concat(parts));

      // La apertura de cajón ahora la controlan los módulos consumidores
      // (pos.js y caja.js) vía printer.safeOpenDrawer()

      return true;
    } catch(e) {
      throw new Error('Error al imprimir: ' + e.message);
    }
  }

  // ── Imprimir ticket de prueba ───────────────────────────────────────────
  async function printTestTicket() {
    if (!_connected || !_writer) throw new Error('Impresora no conectada');

    var parts = [];
    parts.push(_init());
    parts.push(_align(1));
    parts.push(_double(true));
    parts.push(_cmd('GO DELI' + LF));
    parts.push(_double(false));
    parts.push(_cmd('Ticket de prueba' + LF));
    parts.push(_cmd('Impresora conectada ✓' + LF));
    parts.push(_line());
    parts.push(_align(0));
    parts.push(_cmd('Modelo:   ' + _printerName + LF));
    parts.push(_cmd('Fecha:    ' + new Date().toLocaleDateString('es-CL') + LF));
    parts.push(_cmd('Hora:     ' + new Date().toLocaleTimeString('es-CL') + LF));
    parts.push(_line());
    parts.push(_align(1));
    parts.push(_cmd('¡Todo listo para vender!' + LF));
    parts.push(_cmd(LF + LF));
    parts.push(_cut());

    await _writer.write(_concat(parts));
    return true;
  }

  // ── HELPERS ─────────────────────────────────────────────────────────────
  function _fmt(n) {
    return Math.round(n || 0).toLocaleString('es-CL');
  }

  function _padRight(str, len) {
    var s = str || '';
    if (s.length >= len) return s;
    return s + ' '.repeat(len - s.length);
  }

  function _payLabel(m) {
    var labels = {cash:'Efectivo',debit:'Débito',credit:'Crédito',transfer:'Transferencia',mercado_pago:'Mercado Pago',webpay:'Webpay'};
    return labels[m] || (m || '—');
  }

  function _modeLabel(m) {
    var labels = {dine_in:'En local',pickup:'Retiro',delivery:'Delivery'};
    return labels[m] || (m || '—');
  }

  // ── Configuración ───────────────────────────────────────────────────────
  function setAutoPrint(on) {
    _autoPrint = !!on;
  }

  function setAutoDrawer(on) {
    _autoDrawer = !!on;
  }

  // ── Verificar soporte ───────────────────────────────────────────────────
  var _checked = false;
  function checkSupport() {
    if (_checked) return isSupported();
    _checked = true;
    return isSupported();
  }

  // ── Refrescar UI ────────────────────────────────────────────────────────
  function _notify() {
    try {
      if (window.GoBusiness.modules.pos && window.GoBusiness.modules.pos._refreshPrinterBar) {
        window.GoBusiness.modules.pos._refreshPrinterBar();
      }
      if (window.GoBusiness.modules.caja && window.GoBusiness.modules.caja._refreshPrinterBar) {
        window.GoBusiness.modules.caja._refreshPrinterBar();
      }
    } catch(e) {}
  }

  // ── Módulo ──────────────────────────────────────────────────────────────
  window.GoBusiness = window.GoBusiness || {};
  window.GoBusiness.modules = window.GoBusiness.modules || {};
  window.GoBusiness.modules.printer = {
    connect: connect,
    disconnect: disconnect,
    reconnect: reconnect,
    isConnected: isConnected,
    isSupported: isSupported,
    getPrinterName: getPrinterName,
    getSettings: getSettings,
    openDrawer: openDrawer,
    safeOpenDrawer: safeOpenDrawer,
    printReceipt: printReceipt,
    printTestTicket: printTestTicket,
    setAutoPrint: setAutoPrint,
    setAutoDrawer: setAutoDrawer,
    checkSupport: checkSupport
  };

})();

// ── Helper global para botones onclick ──────────────────────────────────
window._printerAction = function(action) {
  // Verificar soporte de Web Serial
  if (!(navigator && navigator.serial)) {
    alert('Web Serial no soportado en este navegador.\n\nUsa Chrome o Edge en desktop (Windows/Mac).\n\nLa impresora debe estar conectada por USB.');
    return;
  }
  var p = window.GoBusiness && window.GoBusiness.modules && window.GoBusiness.modules.printer;
  if (!p) {
    alert('Módulo de impresión no disponible.\n\nRecarga la página (F5) e intenta de nuevo.');
    return;
  }
  if (action === 'connect') {
    p.connect().then(function(r) {
      window.showToast && window.showToast('✅ ' + r.name + ' conectada');
    }).catch(function(e) {
      alert('Error al conectar:\n\n' + (e.message || 'Desconocido') + '\n\nAsegúrate de:\n1. Tener la impresora conectada por USB\n2. Seleccionar el puerto correcto\n3. Que ninguna otra app use la impresora');
    });
  } else if (action === 'openDrawer') {
    p.openDrawer().then(function() {
      window.showToast && window.showToast('💰 Cajón abierto');
    }).catch(function(e) {
      alert('Error al abrir cajón:\n\n' + (e.message || 'Desconocido'));
    });
  } else if (action === 'disconnect') {
    p.disconnect();
    window.showToast && window.showToast('Impresora desconectada');
  } else if (action === 'test') {
    p.printTestTicket().then(function() {
      window.showToast && window.showToast('🧪 Ticket de prueba enviado');
    }).catch(function(e) {
      alert('Error al imprimir:\n\n' + (e.message || 'Desconocido'));
    });
  }
};
