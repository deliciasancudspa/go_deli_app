import "package:flutter/material.dart";
import "dart:async";
import "dart:math" as math;
import "dart:typed_data";
import "package:audioplayers/audioplayers.dart";
import "package:go_router/go_router.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/rider_provider.dart";
import "package:provider/provider.dart";

// Requires: ALTER TABLE chat_messages ALTER COLUMN order_id DROP NOT NULL;

class AdminChatScreen extends StatefulWidget {
  final String adminId;
  const AdminChatScreen({super.key, required this.adminId});
  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final _msgCtrl     = TextEditingController();
  final _scroll      = ScrollController();
  final _sb          = Supabase.instance.client;
  final _audioPlayer = AudioPlayer();
  List<Map<String, dynamic>> _messages = [];
  String? _userId;
  bool _loading  = true;
  bool _sending  = false;
  int  _prevMsgCount = 0;
  RealtimeChannel? _channel;
  late final Uint8List _beepWav;

  @override
  void initState() {
    super.initState();
    _beepWav = _buildBeepWav();
    _init();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _audioPlayer.dispose();
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final rider = context.read<RiderProvider>();
      _userId = rider.rider?["user_id"] as String?;
      if (_userId == null) {
        final user = _sb.auth.currentUser;
        if (user != null) {
          final u = await _sb.from("users").select("id").eq("auth_id", user.id).single();
          _userId = u["id"] as String;
        }
      }
      if (mounted) setState(() => _loading = false);
      await _loadMessages();
      _subscribeRealtime(); // Realtime ya cubre los nuevos mensajes, no se necesita polling
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = _sb.channel("admin_chat_${_userId}")
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: "public",
        table: "chat_messages",
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: "receiver_id", value: _userId ?? ""),
        callback: (_) => _loadMessages(),
      ).subscribe();
  }

  Future<void> _loadMessages() async {
    if (_userId == null) return;
    try {
      final result = await _sb.from("chat_messages")
        .select("*, users!chat_messages_sender_id_fkey(name)")
        .isFilter("order_id", null)
        .or("sender_id.eq.$_userId,receiver_id.eq.$_userId")
        .order("created_at", ascending: false);
      if (!mounted) return;
      final newList = List<Map<String, dynamic>>.from(result);
      if (newList.length > _prevMsgCount && _prevMsgCount > 0) {
        final newest = newList.first;
        if (newest["sender_id"] != _userId) {
          _audioPlayer.play(BytesSource(_beepWav));
        }
      }
      _prevMsgCount = newList.length;
      setState(() => _messages = newList);
      _scrollToBottom();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending || _userId == null) return;
    setState(() => _sending = true);
    try {
      await _sb.from("chat_messages").insert({
        "order_id": null,
        "sender_id": _userId,
        "receiver_id": widget.adminId,
        "message": text,
        "sender_type": "rider",
      });
      _msgCtrl.clear();
      await _loadMessages();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Error al enviar: $e"),
        backgroundColor: AppColors.error,
      ));
    }
    if (mounted) setState(() => _sending = false);
  }

  String _timeStr(String? d) {
    if (d == null) return "";
    final dt = DateTime.parse(d).toLocal();
    return "${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}";
  }

  static Uint8List _buildBeepWav() {
    const sampleRate = 22050;
    const freq       = 880.0;
    const numSamples = sampleRate * 150 ~/ 1000;
    final d = ByteData(44 + numSamples * 2);
    d..setUint8(0,0x52)..setUint8(1,0x49)..setUint8(2,0x46)..setUint8(3,0x46);
    d.setUint32(4, 36 + numSamples * 2, Endian.little);
    d..setUint8(8,0x57)..setUint8(9,0x41)..setUint8(10,0x56)..setUint8(11,0x45);
    d..setUint8(12,0x66)..setUint8(13,0x6d)..setUint8(14,0x74)..setUint8(15,0x20);
    d.setUint32(16, 16, Endian.little);
    d.setUint16(20, 1, Endian.little);
    d.setUint16(22, 1, Endian.little);
    d.setUint32(24, sampleRate, Endian.little);
    d.setUint32(28, sampleRate * 2, Endian.little);
    d.setUint16(32, 2, Endian.little);
    d.setUint16(34, 16, Endian.little);
    d..setUint8(36,0x64)..setUint8(37,0x61)..setUint8(38,0x74)..setUint8(39,0x61);
    d.setUint32(40, numSamples * 2, Endian.little);
    for (int i = 0; i < numSamples; i++) {
      final t   = i / sampleRate;
      final env = math.exp(-t * 20);
      final s   = (math.sin(2 * math.pi * freq * t) * env * 28000).round().clamp(-32768, 32767);
      d.setInt16(44 + i * 2, s, Endian.little);
    }
    return d.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Soporte Admin", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text("Equipo Go Rider", style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(children: [
              Expanded(
                child: _messages.isEmpty
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text("🛠️", style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text("Escribe tu mensaje al equipo de soporte", style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.w600)),
                    ]))
                  : ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) {
                        final m    = _messages[i];
                        final isMe = m["sender_id"] == _userId;
                        final above = (i + 1 < _messages.length) ? _messages[i + 1] : null;
                        final showName = !isMe && (above == null || above["sender_id"] != m["sender_id"]);
                        return Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
                          if (showName) Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 4, top: 8),
                            child: Text(m["users"]?["name"] ?? "Admin", style: const TextStyle(fontSize: 12, color: AppColors.textLight, fontWeight: FontWeight.w700)),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
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
