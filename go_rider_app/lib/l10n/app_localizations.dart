import 'package:flutter/material.dart';

/// Localización manual de la app GoRider.
///
/// Cada getter devuelve la traducción según el locale activo.
/// El español (es) es el idioma base y fallback.
/// Inglés (en) y portugués (pt) son traducciones agregadas.
///
/// Uso:
///   Text(AppLocalizations.of(context)!.dashboardOnline)
///   Text(AppLocalizations.of(context)!.t('dashboardHello', {'name': 'Juan'}))
class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  /// Interpolación simple: reemplaza {key} por valores del mapa args.
  String t(String base, [Map<String, String>? args]) {
    var text = base;
    if (args != null) {
      args.forEach((k, v) => text = text.replaceAll('{$k}', v));
    }
    return text;
  }

  /// Helper: elige la traducción según locale, fallback a español.
  String _tr(Map<String, String> map) =>
      map[locale.languageCode] ?? map['es']!;

  // ═══════════════════════════════════════════════════════════════════
  // AUTH
  // ═══════════════════════════════════════════════════════════════════
  String get email => _tr({'es': 'Correo electrónico', 'en': 'Email', 'pt': 'E-mail'});
  String get password => _tr({'es': 'Contraseña', 'en': 'Password', 'pt': 'Senha'});
  String get signIn => _tr({'es': 'Entrar', 'en': 'Sign in', 'pt': 'Entrar'});
  String get signUp => _tr({'es': 'Registrarse', 'en': 'Register', 'pt': 'Cadastrar'});
  String get loginWelcome => _tr({'es': 'Bienvenido de vuelta', 'en': 'Welcome back', 'pt': 'Bem-vindo de volta'});
  String get loginSubtitle => _tr({'es': 'Inicia sesión para empezar a entregar', 'en': 'Sign in to start delivering', 'pt': 'Faça login para começar a entregar'});
  String get loginNoAccount => _tr({'es': '¿No tienes cuenta?', 'en': "Don't have an account?", 'pt': 'Não tem conta?'});
  String get loginRegister => _tr({'es': 'Regístrate', 'en': 'Register', 'pt': 'Cadastre-se'});
  String get loginForgotPassword => _tr({'es': '¿Olvidaste tu contraseña?', 'en': 'Forgot your password?', 'pt': 'Esqueceu sua senha?'});
  String get loginSendReset => _tr({'es': 'Enviar enlace', 'en': 'Send link', 'pt': 'Enviar link'});
  String get loginResetSent => _tr({'es': 'Si el correo existe, recibirás un enlace para restablecer tu contraseña.', 'en': 'If the email exists, you will receive a password reset link.', 'pt': 'Se o e-mail existir, você receberá um link para redefinir sua senha.'});
  String get registerTitle => _tr({'es': 'Regístrate como repartidor', 'en': 'Register as a delivery driver', 'pt': 'Cadastre-se como entregador'});
  String get registerStep1 => _tr({'es': 'Datos personales', 'en': 'Personal info', 'pt': 'Dados pessoais'});
  String get registerStep2 => _tr({'es': 'Vehículo', 'en': 'Vehicle', 'pt': 'Veículo'});
  String get registerStep3 => _tr({'es': 'Banco', 'en': 'Bank', 'pt': 'Banco'});
  String get registerStep4 => _tr({'es': 'Contrato', 'en': 'Contract', 'pt': 'Contrato'});
  String get registerFullName => _tr({'es': 'Nombre completo', 'en': 'Full name', 'pt': 'Nome completo'});
  String get registerRut => _tr({'es': 'RUT (Ej: 12.345.678-9)', 'en': 'RUT (Chilean ID)', 'pt': 'RUT (ID chileno)'});
  String get registerPhone => _tr({'es': 'Teléfono (+56 9...)', 'en': 'Phone (+56 9...)', 'pt': 'Telefone (+56 9...)'});
  String get registerVehicleType => _tr({'es': 'Tipo de vehículo', 'en': 'Vehicle type', 'pt': 'Tipo de veículo'});
  String get registerVehiclePlate => _tr({'es': 'Patente', 'en': 'License plate', 'pt': 'Placa'});
  String get registerBank => _tr({'es': 'Banco', 'en': 'Bank', 'pt': 'Banco'});
  String get registerAccountType => _tr({'es': 'Tipo de cuenta', 'en': 'Account type', 'pt': 'Tipo de conta'});
  String get registerAccountNumber => _tr({'es': 'Número de cuenta', 'en': 'Account number', 'pt': 'Número da conta'});
  String get registerAccountHolder => _tr({'es': 'Titular de la cuenta', 'en': 'Account holder', 'pt': 'Titular da conta'});
  String get registerHolderRut => _tr({'es': 'RUT del titular', 'en': "Holder's RUT", 'pt': 'RUT do titular'});
  String get registerContractTitle => _tr({'es': 'Contrato de prestación de servicios', 'en': 'Service agreement', 'pt': 'Contrato de prestação de serviços'});
  String get registerAcceptContract => _tr({'es': 'He leído y acepto el contrato de prestación de servicios', 'en': 'I have read and accept the service agreement', 'pt': 'Li e aceito o contrato de prestação de serviços'});
  String get registerAcceptData => _tr({'es': 'Autorizo el tratamiento de mis datos personales', 'en': 'I authorize the processing of my personal data', 'pt': 'Autorizo o tratamento dos meus dados pessoais'});
  String get registerAcceptTerms => _tr({'es': 'Acepto los términos y condiciones de GoRider', 'en': 'I accept GoRider terms and conditions', 'pt': 'Aceito os termos e condições do GoRider'});
  String get registerSignHere => _tr({'es': 'Firma aquí', 'en': 'Sign here', 'pt': 'Assine aqui'});
  String get registerSignatureDone => _tr({'es': '✅ Firma capturada', 'en': '✅ Signature captured', 'pt': '✅ Assinatura capturada'});
  String get registerSignButton => _tr({'es': 'Firmar contrato ✍️', 'en': 'Sign contract ✍️', 'pt': 'Assinar contrato ✍️'});
  String get registerNext => _tr({'es': 'Siguiente', 'en': 'Next', 'pt': 'Próximo'});
  String get registerBack => _tr({'es': 'Atrás', 'en': 'Back', 'pt': 'Voltar'});
  String get registerSubmit => _tr({'es': 'Enviar solicitud', 'en': 'Submit application', 'pt': 'Enviar solicitação'});
  String get splashLoading => _tr({'es': 'Preparando todo...', 'en': 'Getting ready...', 'pt': 'Preparando...'});

  // ═══════════════════════════════════════════════════════════════════
  // PENDING SCREEN
  // ═══════════════════════════════════════════════════════════════════
  String get pendingTitle => _tr({'es': 'Cuenta en revisión', 'en': 'Account under review', 'pt': 'Conta em revisão'});
  String get pendingSubtitle => _tr({'es': 'Tu solicitud está siendo revisada por nuestro equipo.', 'en': 'Your application is being reviewed by our team.', 'pt': 'Sua solicitação está sendo revisada por nossa equipe.'});
  String get pendingStep1 => _tr({'es': 'Solicitud enviada', 'en': 'Application submitted', 'pt': 'Solicitação enviada'});
  String get pendingStep2 => _tr({'es': 'Revisión de documentos', 'en': 'Document review', 'pt': 'Revisão de documentos'});
  String get pendingStep3 => _tr({'es': 'Cuenta activada', 'en': 'Account activated', 'pt': 'Conta ativada'});
  String get pendingSignOut => _tr({'es': 'Cerrar sesión', 'en': 'Sign out', 'pt': 'Sair'});

  // ═══════════════════════════════════════════════════════════════════
  // DASHBOARD
  // ═══════════════════════════════════════════════════════════════════
  String dashboardHello(String name) => _tr({'es': 'Hola, $name!', 'en': 'Hi, $name!', 'pt': 'Olá, $name!'});
  String get dashboardOnline => _tr({'es': 'En línea', 'en': 'Online', 'pt': 'Online'});
  String get dashboardOffline => _tr({'es': 'Desconectado', 'en': 'Offline', 'pt': 'Offline'});
  String get dashboardOfflineBanner => _tr({'es': 'Sin conexión — el GPS y las notificaciones no funcionarán', 'en': 'No connection — GPS and notifications will not work', 'pt': 'Sem conexão — o GPS e as notificações não funcionarão'});
  String get dashboardNoOrders => _tr({'es': 'Sin pedidos asignados', 'en': 'No orders assigned', 'pt': 'Sem pedidos atribuídos'});
  String get dashboardActivateOnline => _tr({'es': 'Activa tu modo online para recibir pedidos cerca de ti', 'en': 'Go online to receive orders near you', 'pt': 'Fique online para receber pedidos perto de você'});
  String get dashboardTodaySummary => _tr({'es': 'Resumen de hoy', 'en': "Today's summary", 'pt': 'Resumo de hoje'});
  String get dashboardOrders => _tr({'es': 'Pedidos', 'en': 'Orders', 'pt': 'Pedidos'});
  String get dashboardEarned => _tr({'es': 'Ganado', 'en': 'Earned', 'pt': 'Ganho'});
  String get dashboardToReceive => _tr({'es': 'A recibir', 'en': 'To receive', 'pt': 'A receber'});
  String get dashboardToRemit => _tr({'es': 'A rendir', 'en': 'To remit', 'pt': 'A entregar'});
  String get dashboardActiveOrders => _tr({'es': 'Pedidos activos', 'en': 'Active orders', 'pt': 'Pedidos ativos'});
  String get dashboardViewDetails => _tr({'es': 'Ver detalles', 'en': 'View details', 'pt': 'Ver detalhes'});
  String get dashboardDemand => _tr({'es': 'Demanda', 'en': 'Demand', 'pt': 'Demanda'});
  String get dashboardPerformance => _tr({'es': 'Desempeño', 'en': 'Performance', 'pt': 'Desempenho'});
  String get heatmapNeedOnline => _tr({'es': 'Activa el modo online para ver la demanda en tu zona', 'en': 'Go online to see demand in your area', 'pt': 'Fique online para ver a demanda na sua área'});
  String get heatmapNoData => _tr({'es': 'No hay pedidos pendientes en tu zona en este momento', 'en': 'No pending orders in your area right now', 'pt': 'Sem pedidos pendentes na sua área no momento'});
  String get heatmapError => _tr({'es': 'Error al cargar datos de demanda. Intenta de nuevo.', 'en': 'Error loading demand data. Try again.', 'pt': 'Erro ao carregar dados de demanda. Tente novamente.'});
  String get toggleOnlineGpsOff => _tr({'es': 'Activa el GPS de tu dispositivo para conectarte', 'en': 'Turn on your device GPS to go online', 'pt': 'Ative o GPS do seu dispositivo para ficar online'});
  String get toggleOnlineLocationDenied => _tr({'es': 'Concede permiso de ubicación para conectarte', 'en': 'Grant location permission to go online', 'pt': 'Conceda permissão de localização para ficar online'});
  String get dashboardEarnedDiff => _tr({'es': '+\\\$ {amount} (hace {mins} min)', 'en': '+\\\$ {amount} ({mins} min ago)', 'pt': '+\\\$ {amount} (há {mins} min)'});

  // ═══════════════════════════════════════════════════════════════════
  // NOTIFICATIONS / OFFERS
  // ═══════════════════════════════════════════════════════════════════
  String get notifOffers => _tr({'es': 'Ofertas de pedidos', 'en': 'Order offers', 'pt': 'Ofertas de pedidos'});
  String get notifEmpty => _tr({'es': 'Sin ofertas pendientes', 'en': 'No pending offers', 'pt': 'Sem ofertas pendentes'});
  String get notifNewOffer => _tr({'es': 'Nueva oferta de pedido', 'en': 'New order offer', 'pt': 'Nova oferta de pedido'});
  String get notifTimeToRespond => _tr({'es': 'Tiempo para responder', 'en': 'Time to respond', 'pt': 'Tempo para responder'});
  String get notifAccept => _tr({'es': 'Aceptar', 'en': 'Accept', 'pt': 'Aceitar'});
  String get notifReject => _tr({'es': 'Rechazar', 'en': 'Reject', 'pt': 'Recusar'});
  String get notifCash => _tr({'es': 'Efectivo', 'en': 'Cash', 'pt': 'Dinheiro'});
  String get notifCard => _tr({'es': 'Tarjeta', 'en': 'Card', 'pt': 'Cartão'});
  String get notifCollectCash => _tr({'es': 'Cobrar \\\$ {amount} en efectivo al cliente', 'en': 'Collect \\\$ {amount} cash from customer', 'pt': 'Cobrar \\\$ {amount} em dinheiro do cliente'});

  // ═══════════════════════════════════════════════════════════════════
  // ORDERS
  // ═══════════════════════════════════════════════════════════════════
  String get ordersTitle => _tr({'es': 'Mis pedidos', 'en': 'My orders', 'pt': 'Meus pedidos'});
  String get ordersEmpty => _tr({'es': 'Sin pedidos aún', 'en': 'No orders yet', 'pt': 'Sem pedidos ainda'});
  String get ordersStatusPending => _tr({'es': 'Pendiente', 'en': 'Pending', 'pt': 'Pendente'});
  String get ordersStatusAccepted => _tr({'es': 'Aceptado', 'en': 'Accepted', 'pt': 'Aceito'});
  String get ordersStatusPreparing => _tr({'es': 'Preparando', 'en': 'Preparing', 'pt': 'Preparando'});
  String get ordersStatusReady => _tr({'es': 'Listo', 'en': 'Ready', 'pt': 'Pronto'});
  String get ordersStatusAssigned => _tr({'es': 'Asignado', 'en': 'Assigned', 'pt': 'Atribuído'});

  // ═══════════════════════════════════════════════════════════════════
  // ORDER DETAIL
  // ═══════════════════════════════════════════════════════════════════
  String get orderPickup => _tr({'es': 'Ve al restaurante', 'en': 'Go to the restaurant', 'pt': 'Vá ao restaurante'});
  String get orderDeliver => _tr({'es': 'Lleva al cliente', 'en': 'Deliver to customer', 'pt': 'Entregue ao cliente'});
  String get orderOnTheWay => _tr({'es': 'En camino', 'en': 'On the way', 'pt': 'A caminho'});
  String get orderPickedUp => _tr({'es': 'Pedido recogido', 'en': 'Order picked up', 'pt': 'Pedido retirado'});
  String get orderDelivered => _tr({'es': 'Entregado', 'en': 'Delivered', 'pt': 'Entregue'});
  String get orderCancelled => _tr({'es': 'Cancelado', 'en': 'Cancelled', 'pt': 'Cancelado'});
  String get orderReturned => _tr({'es': 'Devuelto', 'en': 'Returned', 'pt': 'Devolvido'});
  String get orderConfirmPickup => _tr({'es': 'Recogí el pedido', 'en': 'I picked up the order', 'pt': 'Retirei o pedido'});
  String get orderConfirmDelivery => _tr({'es': 'Confirmar entrega', 'en': 'Confirm delivery', 'pt': 'Confirmar entrega'});
  String get orderShowCode => _tr({'es': 'Muestra el código al restaurante', 'en': 'Show code to restaurant', 'pt': 'Mostre o código ao restaurante'});
  String get orderPickupCode => _tr({'es': 'Código de retiro', 'en': 'Pickup code', 'pt': 'Código de retirada'});
  String get orderCodeHint => _tr({'es': 'Pide al cliente el código de 4 dígitos', 'en': 'Ask the customer for the 4-digit code', 'pt': 'Peça ao cliente o código de 4 dígitos'});
  String get orderCodeAttempts => _tr({'es': '{n}/3 intentos fallidos', 'en': '{n}/3 failed attempts', 'pt': '{n}/3 tentativas falhas'});
  String get orderCodeAlternative => _tr({'es': 'Confirmar entrega sin código', 'en': 'Confirm delivery without code', 'pt': 'Confirmar entrega sem código'});
  String get orderNotFound => _tr({'es': 'Pedido no encontrado', 'en': 'Order not found', 'pt': 'Pedido não encontrado'});
  String get orderSharingLocation => _tr({'es': 'Compartiendo ubicación en tiempo real', 'en': 'Sharing real-time location', 'pt': 'Compartilhando localização em tempo real'});
  String get orderDeliveryConfirmed => _tr({'es': 'Entrega confirmada!', 'en': 'Delivery confirmed!', 'pt': 'Entrega confirmada!'});
  String get orderRouteToStore => _tr({'es': '🛵 Ruta a la tienda', 'en': '🛵 Route to store', 'pt': '🛵 Rota para a loja'});
  String get orderRouteToClient => _tr({'es': '🚀 Ruta al cliente', 'en': '🚀 Route to customer', 'pt': '🚀 Rota para o cliente'});
  String get orderYou => _tr({'es': 'Tú', 'en': 'You', 'pt': 'Você'});
  String get orderClient => _tr({'es': 'Cliente', 'en': 'Customer', 'pt': 'Cliente'});
  String get orderStatusPickupDesc => _tr({'es': 'Dirígete al restaurante y muestra el código de retiro', 'en': 'Go to the restaurant and show the pickup code', 'pt': 'Vá ao restaurante e mostre o código de retirada'});
  String get orderStatusPickedUpDesc => _tr({'es': 'Lleva el pedido al cliente', 'en': 'Take the order to the customer', 'pt': 'Leve o pedido ao cliente'});
  String get orderStatusOnWayDesc => _tr({'es': 'Pide el código de entrega al cliente', 'en': 'Ask the customer for the delivery code', 'pt': 'Peça o código de entrega ao cliente'});
  String get orderStatusDeliveredDesc => _tr({'es': 'Entrega completada', 'en': 'Delivery completed', 'pt': 'Entrega concluída'});
  String get orderStatusCancelledDesc => _tr({'es': 'Pedido cancelado', 'en': 'Order cancelled', 'pt': 'Pedido cancelado'});
  String get orderOpenInMaps => _tr({'es': 'Abrir en Google Maps', 'en': 'Open in Google Maps', 'pt': 'Abrir no Google Maps'});
  String get orderQueued => _tr({'es': 'En cola — tienes otro pedido en curso por delante', 'en': 'Queued — you have another order ahead', 'pt': 'Na fila — você tem outro pedido em andamento'});
  String get orderRiderFee => _tr({'es': 'Tu pago', 'en': 'Your pay', 'pt': 'Seu pagamento'});
  String get orderTip => _tr({'es': 'Propina', 'en': 'Tip', 'pt': 'Gorjeta'});
  String get orderTotal => _tr({'es': 'Total del pedido', 'en': 'Order total', 'pt': 'Total do pedido'});

  // ═══════════════════════════════════════════════════════════════════
  // INCIDENT / CONTINGENCY
  // ═══════════════════════════════════════════════════════════════════
  String get incidentTitle => _tr({'es': 'Reportar incidente', 'en': 'Report incident', 'pt': 'Reportar incidente'});
  String get incidentVehicle => _tr({'es': 'Vehículo averiado', 'en': 'Vehicle breakdown', 'pt': 'Veículo quebrado'});
  String get incidentAccident => _tr({'es': 'Accidente de tránsito', 'en': 'Traffic accident', 'pt': 'Acidente de trânsito'});
  String get incidentMedical => _tr({'es': 'Emergencia médica', 'en': 'Medical emergency', 'pt': 'Emergência médica'});
  String get incidentRobbed => _tr({'es': 'Pedido robado', 'en': 'Order stolen', 'pt': 'Pedido roubado'});
  String get incidentDamaged => _tr({'es': 'Pedido dañado', 'en': 'Order damaged', 'pt': 'Pedido danificado'});
  String get incidentNote => _tr({'es': 'Nota adicional (opcional)', 'en': 'Additional note (optional)', 'pt': 'Nota adicional (opcional)'});
  String get incidentSubmit => _tr({'es': 'Reportar', 'en': 'Report', 'pt': 'Reportar'});
  String get storeClosed => _tr({'es': 'Tienda cerrada', 'en': 'Store closed', 'pt': 'Loja fechada'});
  String get storeClosedDesc => _tr({'es': 'La tienda no está abierta o no tiene el pedido listo.', 'en': 'Store is closed or order is not ready.', 'pt': 'A loja está fechada ou o pedido não está pronto.'});
  String get delayNotify => _tr({'es': 'Avisar demora', 'en': 'Notify delay', 'pt': 'Avisar atraso'});
  String get delayDesc => _tr({'es': 'Informa al cliente que el pedido se retrasará.', 'en': 'Let the customer know the order will be delayed.', 'pt': 'Informe ao cliente que o pedido vai atrasar.'});
  String get returnTitle => _tr({'es': 'Devolver pedido', 'en': 'Return order', 'pt': 'Devolver pedido'});
  String get returnNotFound => _tr({'es': 'Cliente no localizado', 'en': 'Customer not found', 'pt': 'Cliente não localizado'});
  String get returnRejected => _tr({'es': 'Cliente rechazó el pedido', 'en': 'Customer rejected order', 'pt': 'Cliente recusou o pedido'});
  String get returnNote => _tr({'es': 'Nota de devolución (opcional)', 'en': 'Return note (optional)', 'pt': 'Nota de devolução (opcional)'});
  String get sosTitle => _tr({'es': '¿Cliente agresivo?', 'en': 'Aggressive customer?', 'pt': 'Cliente agressivo?'});
  String get sosDescription => _tr({'es': 'Esto enviará una alerta inmediata al equipo de soporte con tu ubicación.', 'en': 'This will send an immediate alert to the support team with your location.', 'pt': 'Isso enviará um alerta imediato à equipe de suporte com sua localização.'});
  String get sosSend => _tr({'es': 'Enviar alerta', 'en': 'Send alert', 'pt': 'Enviar alerta'});

  // ═══════════════════════════════════════════════════════════════════
  // EARNINGS
  // ═══════════════════════════════════════════════════════════════════
  String get earningsTitle => _tr({'es': 'Mis ganancias', 'en': 'My earnings', 'pt': 'Meus ganhos'});
  String get earningsWeek => _tr({'es': 'Semana', 'en': 'Week', 'pt': 'Semana'});
  String get earningsTotal => _tr({'es': 'Total ganado', 'en': 'Total earned', 'pt': 'Total ganho'});
  String get earningsCompleted => _tr({'es': 'pedidos completados', 'en': 'completed orders', 'pt': 'pedidos concluídos'});
  String get earningsToReceive => _tr({'es': 'A recibir', 'en': 'To receive', 'pt': 'A receber'});
  String get earningsToRemit => _tr({'es': 'A rendir', 'en': 'To remit', 'pt': 'A entregar'});
  String get earningsDelivery => _tr({'es': 'Ganancias por delivery', 'en': 'Delivery earnings', 'pt': 'Ganhos por delivery'});
  String get earningsTips => _tr({'es': 'Propinas recibidas', 'en': 'Tips received', 'pt': 'Gorjetas recebidas'});
  String get earningsWithdraw => _tr({'es': 'Retirar ganancias', 'en': 'Withdraw earnings', 'pt': 'Sacar ganhos'});
  String get earningsWithdrawTitle => _tr({'es': 'Retirar ganancias', 'en': 'Withdraw earnings', 'pt': 'Sacar ganhos'});
  String get earningsWithdrawMin => _tr({'es': 'Mínimo \$2.000 para retirar', 'en': 'Minimum \$2,000 to withdraw', 'pt': 'Mínimo \$2.000 para sacar'});
  String get earningsWithdrawFee => _tr({'es': 'Comisión por retiro: \$990', 'en': 'Withdrawal fee: \$990', 'pt': 'Taxa de saque: \$990'});
  String get earningsWithdrawNet => _tr({'es': 'Recibirás: \$', 'en': 'You will receive: \$', 'pt': 'Você receberá: \$'});
  String get earningsWithdrawConfirm => _tr({'es': 'Confirmar retiro', 'en': 'Confirm withdrawal', 'pt': 'Confirmar saque'});
  String get earningsWithdrawDone => _tr({'es': 'Solicitud enviada. El admin la revisará pronto.', 'en': 'Request sent. Admin will review shortly.', 'pt': 'Solicitação enviada. O admin revisará em breve.'});
  String get earningsHistory => _tr({'es': 'Historial de retiros', 'en': 'Withdrawal history', 'pt': 'Histórico de saques'});
  String get earningsNoHistory => _tr({'es': 'Sin retiros aún', 'en': 'No withdrawals yet', 'pt': 'Sem saques ainda'});

  // ═══════════════════════════════════════════════════════════════════
  // PERFORMANCE
  // ═══════════════════════════════════════════════════════════════════
  String get perfTitle => _tr({'es': 'Mi desempeño', 'en': 'My performance', 'pt': 'Meu desempenho'});
  String get perfTopPercentile => _tr({'es': 'Top {p}% de riders', 'en': 'Top {p}% of riders', 'pt': 'Top {p}% dos entregadores'});
  String get perfDeliveries => _tr({'es': 'Entregas totales', 'en': 'Total deliveries', 'pt': 'Entregas totais'});
  String get perfEarnings => _tr({'es': 'Ganancias totales', 'en': 'Total earnings', 'pt': 'Ganhos totais'});
  String get perfDistance => _tr({'es': 'Distancia recorrida', 'en': 'Distance traveled', 'pt': 'Distância percorrida'});
  String get perfAcceptance => _tr({'es': 'Tasa de aceptación', 'en': 'Acceptance rate', 'pt': 'Taxa de aceitação'});
  String get perfCompletion => _tr({'es': 'Tasa de completación', 'en': 'Completion rate', 'pt': 'Taxa de conclusão'});
  String get perfOnTime => _tr({'es': 'A tiempo', 'en': 'On time', 'pt': 'No prazo'});
  String get perfRating => _tr({'es': 'Calificación', 'en': 'Rating', 'pt': 'Avaliação'});
  String get perfTips => _tr({'es': 'Propinas recibidas', 'en': 'Tips received', 'pt': 'Gorjetas recebidas'});
  String get perfKm => _tr({'es': 'km', 'en': 'km', 'pt': 'km'});

  // ═══════════════════════════════════════════════════════════════════
  // CHALLENGES / HEATMAP
  // ═══════════════════════════════════════════════════════════════════
  String get challengeActive => _tr({'es': '🏆 Desafíos activos', 'en': '🏆 Active challenges', 'pt': '🏆 Desafios ativos'});
  String get challengeProgress => _tr({'es': '{n}/{t} pedidos', 'en': '{n}/{t} orders', 'pt': '{n}/{t} pedidos'});
  String get challengeBonus => _tr({'es': 'Bono: \$', 'en': 'Bonus: \$', 'pt': 'Bônus: \$'});
  String get heatmapDemand => _tr({'es': 'Demanda', 'en': 'Demand', 'pt': 'Demanda'});
  String get heatmapHigh => _tr({'es': 'Alta', 'en': 'High', 'pt': 'Alta'});
  String get heatmapMedium => _tr({'es': 'Media', 'en': 'Medium', 'pt': 'Média'});
  String get heatmapLow => _tr({'es': 'Baja', 'en': 'Low', 'pt': 'Baixa'});
  String get heatmapPendingOrders => _tr({'es': '{n} pedidos esperando', 'en': '{n} orders waiting', 'pt': '{n} pedidos esperando'});
  String get heatmapPotentialEarnings => _tr({'es': '~\$ ganancia potencial', 'en': '~\$ potential earnings', 'pt': '~\$ ganho potencial'});

  // ═══════════════════════════════════════════════════════════════════
  // PROFILE
  // ═══════════════════════════════════════════════════════════════════
  String get profileTitle => _tr({'es': 'Mi perfil', 'en': 'My profile', 'pt': 'Meu perfil'});
  String get profileApproved => _tr({'es': 'Repartidor aprobado', 'en': 'Approved driver', 'pt': 'Entregador aprovado'});
  String get profileUnderReview => _tr({'es': 'En revisión', 'en': 'Under review', 'pt': 'Em revisão'});
  String get profileSuspended => _tr({'es': 'Suspendido', 'en': 'Suspended', 'pt': 'Suspenso'});
  String get profileVehicle => _tr({'es': 'Mi vehículo', 'en': 'My vehicle', 'pt': 'Meu veículo'});
  String get profileBankInfo => _tr({'es': 'Datos bancarios', 'en': 'Bank information', 'pt': 'Dados bancários'});
  String get profileSignOut => _tr({'es': 'Cerrar sesión', 'en': 'Sign out', 'pt': 'Sair'});
  String get profileChangePassword => _tr({'es': 'Cambiar contraseña', 'en': 'Change password', 'pt': 'Mudar senha'});
  String get profileLanguage => _tr({'es': 'Idioma', 'en': 'Language', 'pt': 'Idioma'});
  String get profileDarkMode => _tr({'es': 'Modo oscuro', 'en': 'Dark mode', 'pt': 'Modo escuro'});
  String get profileSystemTheme => _tr({'es': 'Tema del sistema', 'en': 'System theme', 'pt': 'Tema do sistema'});
  String get profileAdminChat => _tr({'es': 'Mensaje directo', 'en': 'Direct message', 'pt': 'Mensagem direta'});
  String get profileAdminWhatsApp => _tr({'es': 'WhatsApp Admin', 'en': 'Admin WhatsApp', 'pt': 'WhatsApp Admin'});
  String get profileEditVehicle => _tr({'es': 'Editar vehículo', 'en': 'Edit vehicle', 'pt': 'Editar veículo'});
  String get profileEditBank => _tr({'es': 'Editar datos bancarios', 'en': 'Edit bank info', 'pt': 'Editar dados bancários'});
  String get profileRatings => _tr({'es': 'Mis calificaciones', 'en': 'My ratings', 'pt': 'Minhas avaliações'});
  String get profileRatingBased => _tr({'es': 'Basado en {n} calificaciones', 'en': 'Based on {n} ratings', 'pt': 'Baseado em {n} avaliações'});
  String get profileNoRatings => _tr({'es': 'Sin calificaciones aún', 'en': 'No ratings yet', 'pt': 'Sem avaliações ainda'});
  String get profileCurrentPassword => _tr({'es': 'Contraseña actual', 'en': 'Current password', 'pt': 'Senha atual'});
  String get profileNewPassword => _tr({'es': 'Nueva contraseña', 'en': 'New password', 'pt': 'Nova senha'});
  String get profileConfirmPassword => _tr({'es': 'Confirmar nueva contraseña', 'en': 'Confirm new password', 'pt': 'Confirmar nova senha'});
  String get profilePasswordChanged => _tr({'es': 'Contraseña actualizada correctamente', 'en': 'Password updated successfully', 'pt': 'Senha atualizada com sucesso'});

  // ═══════════════════════════════════════════════════════════════════
  // CHAT
  // ═══════════════════════════════════════════════════════════════════
  String get chatPlaceholder => _tr({'es': 'Escribe un mensaje...', 'en': 'Type a message...', 'pt': 'Escreva uma mensagem...'});
  String get chatSend => _tr({'es': 'Enviar', 'en': 'Send', 'pt': 'Enviar'});
  String get chatAdmin => _tr({'es': 'Admin Go Deli', 'en': 'Go Deli Admin', 'pt': 'Admin Go Deli'});
  String get chatClient => _tr({'es': 'Cliente', 'en': 'Customer', 'pt': 'Cliente'});

  // ═══════════════════════════════════════════════════════════════════
  // VOICE NAVIGATION
  // ═══════════════════════════════════════════════════════════════════
  String get voiceNavActive => _tr({'es': 'Navegación por voz activada', 'en': 'Voice navigation active', 'pt': 'Navegação por voz ativada'});
  String get voiceNavInactive => _tr({'es': 'Activar navegación por voz', 'en': 'Activate voice navigation', 'pt': 'Ativar navegação por voz'});
  String get voiceNavStarting => _tr({'es': 'Iniciando navegación.', 'en': 'Starting navigation.', 'pt': 'Iniciando navegação.'});
  String get voiceNavArrived => _tr({'es': 'Has llegado a tu destino.', 'en': 'You have arrived at your destination.', 'pt': 'Você chegou ao seu destino.'});

  // ═══════════════════════════════════════════════════════════════════
  // LOCATION DISCLOSURE (Google Play prominent disclosure)
  // ═══════════════════════════════════════════════════════════════════
  String get locDisclosureTitle => _tr({
    'es': 'Ubicación en segundo plano',
    'en': 'Background location',
    'pt': 'Localização em segundo plano',
  });
  String get locDisclosureBody => _tr({
    'es': 'Go Rider recopila datos de ubicación para asignarte pedidos cercanos y permitir el seguimiento de tus entregas en tiempo real, incluso cuando la app está en segundo plano o cerrada.',
    'en': 'Go Rider collects location data to assign nearby orders and enable real-time delivery tracking, even when the app is in the background or closed.',
    'pt': 'O Go Rider coleta dados de localização para atribuir pedidos próximos e permitir o rastreamento de entregas em tempo real, mesmo quando o app está em segundo plano ou fechado.',
  });
  String get locDisclosureBullet1 => _tr({
    'es': '📍 Tu ubicación se comparte con el sistema de despacho para encontrar pedidos cercanos.',
    'en': '📍 Your location is shared with the dispatch system to find nearby orders.',
    'pt': '📍 Sua localização é compartilhada com o sistema de despacho para encontrar pedidos próximos.',
  });
  String get locDisclosureBullet2 => _tr({
    'es': '🛵 Los clientes pueden ver tu ubicación en el mapa durante la entrega activa.',
    'en': '🛵 Customers can see your location on the map during active delivery.',
    'pt': '🛵 Os clientes podem ver sua localização no mapa durante a entrega ativa.',
  });
  String get locDisclosureBullet3 => _tr({
    'es': '📍 La ubicación se actualiza en segundo plano aunque la app esté minimizada.',
    'en': '📍 Location updates in the background even when the app is minimized.',
    'pt': '📍 A localização é atualizada em segundo plano mesmo com o app minimizado.',
  });
  String get locDisclosureNote => _tr({
    'es': 'Puedes desactivar la ubicación en cualquier momento desde Ajustes del dispositivo. Mientras estés desconectado, no se compartirá tu ubicación.',
    'en': 'You can turn off location at any time in your device Settings. While offline, your location will not be shared.',
    'pt': 'Você pode desativar a localização a qualquer momento nos Ajustes do dispositivo. Enquanto estiver offline, sua localização não será compartilhada.',
  });
  String get locDisclosureAccept => _tr({
    'es': 'Entendido, continuar',
    'en': 'Got it, continue',
    'pt': 'Entendido, continuar',
  });

  // ═══════════════════════════════════════════════════════════════════
  // BOTTOM NAV
  // ═══════════════════════════════════════════════════════════════════
  String get bottomNavHome => _tr({'es': 'Inicio', 'en': 'Home', 'pt': 'Início'});
  String get bottomNavOrders => _tr({'es': 'Pedidos', 'en': 'Orders', 'pt': 'Pedidos'});
  String get bottomNavEarnings => _tr({'es': 'Ganancias', 'en': 'Earnings', 'pt': 'Ganhos'});
  String get bottomNavProfile => _tr({'es': 'Perfil', 'en': 'Profile', 'pt': 'Perfil'});

  // ═══════════════════════════════════════════════════════════════════
  // COMMON / GENERIC
  // ═══════════════════════════════════════════════════════════════════
  String get cancel => _tr({'es': 'Cancelar', 'en': 'Cancel', 'pt': 'Cancelar'});
  String get save => _tr({'es': 'Guardar', 'en': 'Save', 'pt': 'Salvar'});
  String get accept => _tr({'es': 'Aceptar', 'en': 'Accept', 'pt': 'Aceitar'});
  String get reject => _tr({'es': 'Rechazar', 'en': 'Reject', 'pt': 'Recusar'});
  String get confirm => _tr({'es': 'Confirmar', 'en': 'Confirm', 'pt': 'Confirmar'});
  String get close => _tr({'es': 'Cerrar', 'en': 'Close', 'pt': 'Fechar'});
  String get back => _tr({'es': 'Volver', 'en': 'Back', 'pt': 'Voltar'});
  String get error => _tr({'es': 'Error', 'en': 'Error', 'pt': 'Erro'});
  String get loading => _tr({'es': 'Cargando...', 'en': 'Loading...', 'pt': 'Carregando...'});
  String get noConnection => _tr({'es': 'Sin conexión', 'en': 'No connection', 'pt': 'Sem conexão'});
  String get gps => _tr({'es': 'GPS', 'en': 'GPS', 'pt': 'GPS'});
}

/// Delegate que registra [AppLocalizations] en el widget tree.
class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['es', 'en', 'pt'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
