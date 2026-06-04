import "package:flutter/material.dart";
import "dart:async";
import "package:go_router/go_router.dart";
import "package:provider/provider.dart";
import "package:url_launcher/url_launcher.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";

class RiderChatScreen extends StatefulWidget {
  final String orderId;
  const RiderChatScreen({super.key, required this.orderId});
  @override
  State<RiderChatScreen> createState() => _RiderChatScreenState();
}

class _RiderChatScreenState extends State<RiderChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scroll  = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _order;
  String? _userId;
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;
  RealtimeChannel? _channel;
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final rider = context.read<RiderProvider>();
      _userId = rider.rider?["user_id"] as String?;
      if (_userId == null) {
        // Fallback: get user_id from auth
        final user = _sb.auth.currentUser;
        if (user != null) {
          final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
          _userId = u["id"] as String;
        }
      }
      final order = await _sb.from("orders")
        .select("id, status, client_id, deliverer_id, stores(name,emoji), users!client_id(name,phone)")
        .eq("id", widget.orderId)
        .single();
      if (mounted) setState(() { _order = order; _loading = false; });
      await _loadMessages();
      _subscribeRealtime();
      _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _loadMessages());
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = _sb.channel("rider_chat_${widget.orderId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "chat_messages",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "order_id", value: widget.orderId),
        callback: (_) => _loadMessages(),
      ).subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final result = await _sb.from("chat_messages")
        .select("*, users(name)")
        .eq("order_id", widget.orderId)
        .order("created_at");
      if (mounted) {
        setState(() => _messages = List<Map<String, dynamic>>.from(result));
        _scrollToBottom();
      }
    } catch (_) {}
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
      final clientId = _order?["client_id"] as String?;
      await _sb.from("chat_messages").insert({
        "order_id": widget.orderId,
        "sender_id": _userId,
        "receiver_id": clientId,
        "message": text,
        "sender_type": "rider",
      });
      _msgCtrl.clear();
      await _loadMessages();
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  String _timeStr(String? d) {
    if (d == null) return "";
    final date = DateTime.parse(d).toLocal();
    return "${date.hour.toString().padLeft(2, "0")}:${date.minute.toString().padLeft(2, "0")}";
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse("tel:$phone");
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final clientName  = _order?["users"]?["name"] ?? "Cliente";
    final clientPhone = _order?["users"]?["phone"] as String?;
    final storeEmoji  = _order?["stores"]?["emoji"] ?? "🍽️";
    final storeName   = _order?["stores"]?["name"] ?? "";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go("/order/${widget.orderId}")),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Chat con $clientName", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (storeName.isNotEmpty) Text("$storeEmoji $storeName", style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          if (clientPhone != null) IconButton(
            icon: const Icon(Icons.phone_outlined),
            onPressed: () => _call(clientPhone),
            tooltip: "Llamar al cliente",
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
        : Column(children: [
            Expanded(
              child: _messages.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text("💬", style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text("Inicia la conversación", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text("Puedes hablar con $clientName", style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final isMe = m["sender_id"] == _userId;
                      final prev = i > 0 ? _messages[i - 1] : null;
                      final showName = !isMe && (prev == null || prev["sender_id"] != m["sender_id"]);
                      return Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                        if (showName) Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4, top: 8),
                          child: Text(m["users"]?["name"] ?? "Cliente", style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w700)),
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
              ),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _msgCtrl,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onFieldSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: "Escribe un mensaje...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
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
