import "package:flutter/material.dart";
import "dart:async";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";

class ChatScreen extends StatefulWidget {
  final String orderId;
  const ChatScreen({super.key, required this.orderId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scroll  = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _order;
  String? _userId;
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() { _pollTimer?.cancel(); super.dispose(); }

  Future<void> _init() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("id,name").eq("auth_id", user.id).single();
      _userId = u["id"] as String;
      final order = await _sb.from("orders")
        .select("id, status, stores(name,emoji)")
        .eq("id", widget.orderId)
        .single();
      if (mounted) setState(() { _order = order; _loading = false; });
      await _loadMessages();
      _subscribeRealtime();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadMessages());
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _sb.channel("chat_client_${widget.orderId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "chat_messages",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "order_id", value: widget.orderId),
        callback: (payload) async {
          await _loadMessages();
        },
      ).subscribe();
  }

  Future<void> _loadMessages() async {
    final result = await _sb.from("chat_messages").select("*, users(name)").eq("order_id", widget.orderId).order("created_at");
    if (mounted) { setState(() => _messages = List<Map<String, dynamic>>.from(result)); _scrollToBottom(); }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _userId == null) return;
    setState(() => _sending = true);
    try {
      final order = await _sb.from("orders").select("deliverer_id, deliverers(user_id)").eq("id", widget.orderId).single();
      final receiverId = order["deliverers"]?["user_id"] ?? order["client_id"];
      await _sb.from("chat_messages").insert({
        "order_id": widget.orderId,
        "sender_id": _userId,
        "receiver_id": receiverId,
        "message": text,
        "sender_type": "client",
      });
      _msgCtrl.clear();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  String _timeStr(String? d) {
    if (d == null) return "";
    final date = DateTime.parse(d).toLocal();
    return "${date.hour.toString().padLeft(2,"0")}:${date.minute.toString().padLeft(2,"0")}";
  }

  bool get _chatEnabled {
    // Chat habilitado desde que el pedido es aceptado hasta entregado
    if (_loading) return false;
    return true; // El repartidor asignado puede chatear en cualquier momento
  }

  @override
  Widget build(BuildContext context) {
    final riderName = _order?["deliverers"]?["users"]?["name"] ?? "Repartidor";
    final riderPhone = _order?["deliverers"]?["users"]?["phone"];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Chat con $riderName", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text(_chatEnabled ? "En línea" : "Chat disponible cuando el repartidor recoja el pedido", style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          if (riderPhone != null) IconButton(
            icon: const Icon(Icons.phone_outlined),
            onPressed: () {},
            tooltip: "Llamar al repartidor",
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : Column(children: [
            // Banner estado
            if (!_chatEnabled) Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.warning.withOpacity(0.1),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text("El chat se habilitará cuando el repartidor recoja tu pedido", style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w600))),
              ]),
            ),

            // Mensajes
            Expanded(
              child: _messages.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text("💬", style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text("Inicia la conversación", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(_chatEnabled ? "Puedes hablar con tu repartidor" : "Disponible cuando el repartidor recoja tu pedido", textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final isMe = m["sender_id"] == _userId;
                      final prevMsg = i > 0 ? _messages[i-1] : null;
                      final showSender = prevMsg == null || prevMsg["sender_id"] != m["sender_id"];
                      return Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                        if (showSender && !isMe) Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4, top: 8),
                          child: Text(m["users"]?["name"] ?? "Repartidor", style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w700)),
                        ),
                        Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                            decoration: BoxDecoration(
                              color: isMe ? AppColors.accent : AppColors.surface,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isMe ? 16 : 4),
                                bottomRight: Radius.circular(isMe ? 4 : 16),
                              ),
                              border: isMe ? null : Border.all(color: AppColors.border),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(m["message"] ?? "", style: TextStyle(color: isMe ? Colors.white : AppColors.textDark, fontSize: 14, height: 1.4)),
                              const SizedBox(height: 2),
                              Text(_timeStr(m["created_at"]), style: TextStyle(color: isMe ? Colors.white60 : AppColors.textLight, fontSize: 10)),
                            ]),
                          ),
                        ),
                      ]);
                    },
                  ),
            ),

            // Input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _msgCtrl,
                    enabled: _chatEnabled,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: _chatEnabled ? "Escribe un mensaje..." : "Chat no disponible aún",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                      filled: true,
                      fillColor: _chatEnabled ? AppColors.surface : AppColors.background,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _chatEnabled ? _send : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _chatEnabled ? AppColors.accent : AppColors.border,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ]),
            ),
          ]),
    );
  }
}
