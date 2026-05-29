import "package:flutter/material.dart";
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
  final _sb = Supabase.instance.client;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    try {
      final user = _sb.auth.currentUser;
      if (user == null) return;
      final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
      _userId = u["id"] as String;
      final order = await _sb.from("orders").select("*, stores(name,emoji)").eq("id", widget.orderId).single();
      final msgs = await _sb.from("chat_messages").select("*, users(name)").eq("order_id", widget.orderId).order("created_at");
      if (mounted) setState(() {
        _order = order;
        _messages = List<Map<String, dynamic>>.from(msgs);
        _loading = false;
      });
      _subscribeRealtime();
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _sb.channel("chat_${widget.orderId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "chat_messages",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "order_id", value: widget.orderId),
        callback: (payload) async {
          final msg = payload.newRecord;
          final user = await _sb.from("users").select("name").eq("id", msg["sender_id"]).single();
          msg["users"] = user;
          if (mounted) setState(() => _messages.add(msg));
          _scrollToBottom();
        },
      ).subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _userId == null) return;
    setState(() => _sending = true);
    try {
      await _sb.from("chat_messages").insert({
        "order_id": widget.orderId,
        "sender_id": _userId,
        "message": text,
        "sender_type": "client",
      });
      _msgCtrl.clear();
    } catch (_) {}
    setState(() => _sending = false);
  }

  String _timeStr(String? d) {
    if (d == null) return "";
    final date = DateTime.parse(d).toLocal();
    return "${date.hour.toString().padLeft(2,"0")}:${date.minute.toString().padLeft(2,"0")}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Chat con ${_order?["stores"]?["emoji"] ?? ""} ${_order?["stores"]?["name"] ?? "Tienda"}", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const Text("Pedido en curso", style: TextStyle(fontSize: 11, color: AppColors.textLight)),
        ]),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : Column(children: [
            Expanded(
              child: _messages.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.border),
                    const SizedBox(height: 12),
                    const Text("Inicia la conversacion", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                  ]))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) {
                      final m = _messages[i];
                      final isMe = m["sender_id"] == _userId;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.primary : AppColors.surface,
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
                            const SizedBox(height: 4),
                            Text(_timeStr(m["created_at"]), style: TextStyle(color: isMe ? Colors.white60 : AppColors.textLight, fontSize: 10)),
                          ]),
                        ),
                      );
                    },
                  ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _msgCtrl,
                    decoration: InputDecoration(
                      hintText: "Escribe un mensaje...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                    onFieldSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: _sending
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ]),
            ),
          ]),
    );
  }
}
