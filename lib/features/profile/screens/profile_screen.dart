import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:go_router/go_router.dart";
import "package:image_picker/image_picker.dart";
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:shimmer/shimmer.dart";
import "package:supabase_flutter/supabase_flutter.dart";
import "package:url_launcher/url_launcher.dart";
import "../../../core/theme/app_theme.dart";
import "../../../providers/auth_provider.dart";

const _kDark   = AppColors.homeDark;
const _kOrange = AppColors.homeOrange;
const _kPurple = AppColors.homePurple;
const _kBorder = AppColors.homeCardBorder;

// ════════════════════════════════════════════════════════════════════════════
// PerfilScreen
// ════════════════════════════════════════════════════════════════════════════
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});
  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _user;
  bool _loading = true;
  int  _ordersCount = 0;
  int  _favsCount   = 0;
  int  _totalSaved  = 0;

  List<Map<String, dynamic>> _activeCoupons = [];
  List<Map<String, dynamic>> _addresses     = [];
  List<Map<String, dynamic>> _favorites     = [];

  bool _notificationsEnabled = true;
  bool _autoLocation         = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _autoLocation = p.getBool("auto_location") ?? false);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final authUser = _sb.auth.currentUser;
      if (authUser == null) { setState(() => _loading = false); return; }

      final u      = await _sb.from("users").select().eq("auth_id", authUser.id).single();
      final userId = u["id"] as String;

      final results = await Future.wait([
        _sb.from("orders").select("id").eq("client_id", userId),
        _sb.from("user_favorites").select("id").eq("user_id", userId),
        _sb.from("orders").select("discount").eq("client_id", userId).eq("status", "delivered"),
        _sb.from("user_coupons").select("*, coupons(*)").eq("user_id", userId).eq("used", false),
        _sb.from("user_addresses").select().eq("user_id", userId).order("is_default", ascending: false),
        _sb.from("user_favorites")
            .select("*, stores(id,name,emoji,category,rating,is_open)")
            .eq("user_id", userId),
      ]);

      final ordersRaw  = results[0] as List;
      final favIds     = results[1] as List;
      final delivered  = results[2] as List;
      final couponsRaw = results[3] as List;
      final addrsRaw   = results[4] as List;
      final favsRaw    = results[5] as List;

      int saved = 0;
      for (final o in delivered) {
        saved += ((o["discount"] as num?) ?? 0).toInt();
      }

      final now = DateTime.now();
      final active = couponsRaw.where((c) {
        final coupon = c["coupons"] as Map<String, dynamic>?;
        if (coupon == null || coupon["is_active"] != true) return false;
        final exp = coupon["expires_at"] as String?;
        if (exp != null && DateTime.tryParse(exp)?.isBefore(now) == true) return false;
        return true;
      }).toList();

      if (mounted) setState(() {
        _user                 = u;
        _ordersCount          = ordersRaw.length;
        _favsCount            = favIds.length;
        _totalSaved           = saved;
        _activeCoupons        = List<Map<String, dynamic>>.from(active);
        _addresses            = List<Map<String, dynamic>>.from(addrsRaw);
        _favorites            = List<Map<String, dynamic>>.from(favsRaw);
        _notificationsEnabled = u["notifications_enabled"] as bool? ?? true;
        _loading              = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(num p) => "\$${p.toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]}.")}";

  String _memberSince(String? createdAt) {
    if (createdAt == null) return "";
    try {
      final dt = DateTime.parse(createdAt);
      const months = ["enero","febrero","marzo","abril","mayo","junio","julio",
        "agosto","septiembre","octubre","noviembre","diciembre"];
      return "Cliente desde ${months[dt.month - 1]} ${dt.year}";
    } catch (_) { return ""; }
  }

  Future<void> _toggleNotifications(bool val) async {
    setState(() => _notificationsEnabled = val);
    try {
      await _sb.from("users").update({"notifications_enabled": val}).eq("id", _user!["id"]);
    } catch (_) {}
  }

  Future<void> _toggleAutoLocation(bool val) async {
    setState(() => _autoLocation = val);
    final p = await SharedPreferences.getInstance();
    await p.setBool("auto_location", val);
  }

  void _showEditProfile() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        user: _user!,
        onSaved: () {
          _load(silent: true);
          context.read<AuthProvider>().loadProfile();
        },
      ),
    );
  }

  void _showAddresses() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddressesSheet(
        userId: _user!["id"] as String,
        onChanged: () => _load(silent: true),
      ),
    );
  }

  void _showFavorites() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _FavoritesSheet(
        favorites: _favorites,
        onRemoved: () => _load(silent: true),
      ),
    );
  }

  void _showCoupons() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CouponsSheet(userId: _user!["id"] as String),
    );
  }

  void _showPayments() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _handle(),
          const SizedBox(height: 16),
          const Align(alignment: Alignment.centerLeft,
            child: Text("Métodos de pago",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          const SizedBox(height: 12),
          _payRow(Icons.payments_outlined, "Efectivo", "Pago al recibir"),
          const Divider(height: 1, indent: 16),
          _payRow(Icons.credit_card_outlined, "Tarjeta", "Crédito / Débito"),
          const Divider(height: 1, indent: 16),
          _payRow(Icons.account_balance_outlined, "Transferencia", "Bancaria"),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kPurple.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Text("ℹ️"),
              const SizedBox(width: 8),
              Expanded(child: Text("Los métodos de pago se seleccionan al realizar tu pedido.",
                style: TextStyle(color: _kPurple.withOpacity(0.8), fontSize: 12))),
            ]),
          ),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _payRow(IconData icon, String title, String sub) => ListTile(
    leading: Icon(icon, color: _kPurple),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
  );

  void _showSupportChat() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _handle(),
          const SizedBox(height: 16),
          const Text("Chat con soporte",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 8, height: 8,
              decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text("En línea · Respuesta en minutos",
              style: TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 20),
          _contactRow(
            color: const Color(0xFF25D366),
            icon: Icons.chat_rounded,
            label: "WhatsApp",
            sub: "Atención inmediata",
            onTap: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse("https://wa.me/56XXXXXXXXX?text=Hola%2C+necesito+ayuda");
              if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
          const SizedBox(height: 10),
          _contactRow(
            color: _kPurple,
            icon: Icons.email_outlined,
            label: "Email",
            sub: "soporte@godeli.cl",
            onTap: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse("mailto:soporte@godeli.cl");
              if (await canLaunchUrl(uri)) launchUrl(uri);
            },
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _contactRow({
    required Color color, required IconData icon,
    required String label, required String sub,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          Text(sub, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios, color: color, size: 14),
      ]),
    ),
  );

  Future<void> _rateApp() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Calificación disponible próximamente"),
        backgroundColor: _kPurple, duration: Duration(seconds: 2)),
    );
  }

  Future<void> _showTerms() async {
    final uri = Uri.parse("https://godeli.cl/terminos");
    if (await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Cerrar sesión", style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text("¿Seguro que deseas salir de Go Deli?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar")),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Salir",
              style: TextStyle(color: Color(0xFF8A0000), fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final auth = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await auth.signOut();
    if (mounted) context.go("/login");
  }

  // ─── build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildShimmer();
    if (_user == null) return _buildLoginPrompt();

    return Scaffold(
      backgroundColor: AppColors.homeBackground,
      body: RefreshIndicator(
        onRefresh: _load,
        color: _kOrange,
        child: CustomScrollView(
          slivers: [
            _buildSliverHeader(),
            SliverToBoxAdapter(child: Column(children: [
              if (_activeCoupons.isNotEmpty) _buildCouponBanner(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _buildSection("MI CUENTA", [
                    _menuTile(Icons.person_outline,       "Datos personales",  _showEditProfile),
                    _menuTile(Icons.location_on_outlined,  "Mis direcciones",   _showAddresses,
                      badge: _addresses.length),
                    _menuTile(Icons.credit_card_outlined,  "Métodos de pago",   _showPayments),
                    _menuTile(Icons.favorite_outline,      "Tiendas favoritas", _showFavorites,
                      badge: _favsCount),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection("PREFERENCIAS", [
                    _toggleTile(Icons.notifications_outlined, "Notificaciones",
                      _notificationsEnabled, _toggleNotifications),
                    _toggleTile(Icons.location_searching_outlined, "Ubicación automática",
                      _autoLocation, _toggleAutoLocation),
                  ]),
                  const SizedBox(height: 16),
                  _buildSection("SOPORTE", [
                    _menuTile(Icons.chat_bubble_outline, "Chat con soporte",    _showSupportChat),
                    _menuTile(Icons.local_offer_outlined, "Mis cupones",        _showCoupons,
                      badge: _activeCoupons.length),
                    _menuTile(Icons.star_outline,         "Calificar la app",   _rateApp),
                    _menuTile(Icons.description_outlined, "Términos y privacidad", _showTerms),
                  ]),
                  const SizedBox(height: 16),
                  _logoutButton(),
                  const SizedBox(height: 32),
                  const Text("Go Deli v1.0.0",
                    style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                  const SizedBox(height: 16),
                ]),
              ),
            ])),
          ],
        ),
      ),
    );
  }

  // ─── Header sliver ───────────────────────────────────────────────────────

  Widget _buildSliverHeader() {
    final name      = _user!["name"]       as String? ?? "Usuario";
    final email     = _user!["email"]      as String? ?? "";
    final avatarUrl = _user!["avatar_url"] as String?;
    final since     = _memberSince(_user!["created_at"] as String?);

    return SliverAppBar(
      expandedHeight: 272,
      pinned: true,
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: _kDark,
      title: Text(name,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      actions: [
        TextButton(
          onPressed: _showEditProfile,
          child: const Text("✏️ Editar",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Container(
          color: _kDark,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 56,
            left: 20, right: 20, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 68, height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: avatarUrl == null
                      ? const LinearGradient(
                          colors: [_kOrange, _kPurple],
                          begin: Alignment.topLeft, end: Alignment.bottomRight)
                      : null,
                  ),
                  child: avatarUrl != null
                    ? ClipOval(child: Image.network(avatarUrl,
                        fit: BoxFit.cover, width: 68, height: 68,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(name[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white,
                              fontSize: 28, fontWeight: FontWeight.w900)))))
                    : Center(child: Text(name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white,
                          fontSize: 28, fontWeight: FontWeight.w900))),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: GestureDetector(
                    onTap: _showEditProfile,
                    child: Container(
                      width: 22, height: 22,
                      decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Text(name,
                style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(email,
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11)),
              if (since.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(since,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
              ],
              const SizedBox(height: 14),
              // Stats row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _statItem(_ordersCount.toString(), "Pedidos"),
                  _vDivider(),
                  _statItem(_favsCount.toString(), "Favoritas"),
                  _vDivider(),
                  _statItem(_totalSaved > 0 ? _fmt(_totalSaved) : "\$0", "Ahorrado"),
                  _vDivider(),
                  _statItem("5.0 ⭐", "Mi rating"),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statItem(String value, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(value, style: const TextStyle(
          color: _kOrange, fontSize: 13, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
          color: Colors.white.withOpacity(0.5), fontSize: 10)),
    ],
  );

  Widget _vDivider() => Container(
    height: 28, width: 1, color: Colors.white.withOpacity(0.15));

  // ─── Coupon banner ────────────────────────────────────────────────────────

  Widget _buildCouponBanner() {
    final nextCoupon = _activeCoupons.firstWhere(
      (c) => (c["coupons"] as Map?)?["expires_at"] != null,
      orElse: () => _activeCoupons.first,
    );
    final coupon = nextCoupon["coupons"] as Map<String, dynamic>?;
    final discountLabel = coupon == null ? ""
        : coupon["discount_type"] == "percentage"
          ? "${coupon["discount_value"]}% de descuento"
          : "\$${coupon["discount_value"]} de descuento";
    final n = _activeCoupons.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        onTap: _showCoupons,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9E00FF), Color(0xFF6B00B3)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Text("🎁", style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Tienes $n cupón${n != 1 ? "es" : ""} disponible${n != 1 ? "s" : ""}",
                style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              if (discountLabel.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(discountLabel,
                  style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
              ],
            ])),
            const Icon(Icons.chevron_right, color: Colors.white),
          ]),
        ),
      ),
    );
  }

  // ─── Section / tile builders ──────────────────────────────────────────────

  Widget _buildSection(String title, List<Widget> tiles) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800,
            color: AppColors.textLight, letterSpacing: 0.8)),
      ),
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          children: tiles.asMap().entries.map((e) => Column(children: [
            e.value,
            if (e.key < tiles.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ])).toList(),
        ),
      ),
    ],
  );

  Widget _menuTile(IconData icon, String label, VoidCallback onTap, {int? badge}) =>
    ListTile(
      leading: _tileIcon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (badge != null && badge > 0)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _kPurple, borderRadius: BorderRadius.circular(10)),
            child: Text("$badge",
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        const Icon(Icons.chevron_right, color: AppColors.textLight, size: 18),
      ]),
      onTap: onTap,
    );

  Widget _toggleTile(IconData icon, String label, bool value, ValueChanged<bool> onChanged) =>
    ListTile(
      leading: _tileIcon(icon),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: _kPurple,
        activeTrackColor: _kPurple.withOpacity(0.3),
      ),
    );

  Widget _tileIcon(IconData icon) => Container(
    width: 36, height: 36,
    decoration: BoxDecoration(
      color: _kPurple.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10)),
    child: Icon(icon, color: _kPurple, size: 18),
  );

  Widget _logoutButton() => GestureDetector(
    onTap: _logout,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.logout, color: Color(0xFF8A0000), size: 18),
        SizedBox(width: 8),
        Text("Cerrar sesión",
          style: TextStyle(color: Color(0xFF8A0000), fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    ),
  );

  Widget _buildShimmer() => Scaffold(
    backgroundColor: AppColors.homeBackground,
    body: Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(children: [
        Container(height: 280, color: Colors.white),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
          Container(height: 48,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12))),
          const SizedBox(height: 12),
          Container(height: 130,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
          const SizedBox(height: 12),
          Container(height: 110,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
          const SizedBox(height: 12),
          Container(height: 130,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
        ])),
      ]),
    ),
  );

  Widget _buildLoginPrompt() => Scaffold(
    backgroundColor: AppColors.homeBackground,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text("👤", style: TextStyle(fontSize: 64)),
      const SizedBox(height: 16),
      const Text("Inicia sesión para ver tu perfil",
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textMedium)),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: () => context.go("/login"),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kOrange, minimumSize: const Size(200, 48)),
        child: const Text("Iniciar sesión"),
      ),
    ])),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// _EditProfileSheet
// ════════════════════════════════════════════════════════════════════════════
class _EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> user;
  final VoidCallback onSaved;
  const _EditProfileSheet({required this.user, required this.onSaved});
  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _sb        = Supabase.instance.client;
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  XFile? _pickedImage;
  bool   _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text  = widget.user["name"]  as String? ?? "";
    _phoneCtrl.text = widget.user["phone"] as String? ?? "";
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(
      source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (img != null && mounted) setState(() => _pickedImage = img);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      String? avatarUrl;
      if (_pickedImage != null) {
        final file   = File(_pickedImage!.path);
        final userId = widget.user["id"] as String;
        final path   = "avatar_$userId.jpg";
        await _sb.storage.from("avatars").upload(
          path, file,
          fileOptions: const FileOptions(upsert: true, contentType: "image/jpeg"),
        );
        final publicUrl = _sb.storage.from("avatars").getPublicUrl(path);
        // Cache buster so Flutter's image cache shows the new photo immediately
        avatarUrl = "$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}";
        // Clear Flutter's image cache for the old URL
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
      final updates = <String, dynamic>{
        "name":  _nameCtrl.text.trim(),
        "phone": _phoneCtrl.text.trim(),
      };
      if (avatarUrl != null) updates["avatar_url"] = avatarUrl;
      await _sb.from("users").update(updates).eq("id", widget.user["id"]);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al guardar: ${e.toString().split(":").first}"), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.user["avatar_url"] as String?;
    final name      = widget.user["name"]       as String? ?? "U";

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Align(alignment: Alignment.centerLeft,
            child: Text("Editar perfil",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
        const SizedBox(height: 20),
        // Avatar picker
        GestureDetector(
          onTap: _pickImage,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _pickedImage == null && avatarUrl == null
                  ? const LinearGradient(
                      colors: [_kOrange, _kPurple],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
              ),
              child: _pickedImage != null
                ? ClipOval(child: Image.file(File(_pickedImage!.path),
                    fit: BoxFit.cover, width: 80, height: 80))
                : avatarUrl != null
                  ? ClipOval(child: Image.network(avatarUrl,
                      fit: BoxFit.cover, width: 80, height: 80))
                  : Center(child: Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white,
                        fontSize: 32, fontWeight: FontWeight.w900))),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(color: _kOrange, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 6),
        const Text("Toca para cambiar foto",
          style: TextStyle(color: AppColors.textLight, fontSize: 12)),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: "Nombre completo",
              prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: "Teléfono",
              prefixIcon: Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: _kOrange),
            child: _saving
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text("Guardar cambios"),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: AppColors.textLight))),
          const SizedBox(height: 8),
        ])),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _AddressesSheet
// ════════════════════════════════════════════════════════════════════════════
class _AddressesSheet extends StatefulWidget {
  final String userId;
  final VoidCallback onChanged;
  const _AddressesSheet({required this.userId, required this.onChanged});
  @override
  State<_AddressesSheet> createState() => _AddressesSheetState();
}

class _AddressesSheetState extends State<_AddressesSheet> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _sb.from("user_addresses").select()
          .eq("user_id", widget.userId).order("is_default", ascending: false);
      if (mounted) setState(() {
        _addresses = List<Map<String, dynamic>>.from(data);
        _loading   = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  IconData _labelIcon(String? label) {
    if (label == "Casa")    return Icons.home_outlined;
    if (label == "Trabajo") return Icons.work_outline;
    return Icons.location_on_outlined;
  }

  Future<void> _addAddress() async {
    String label = "Casa";
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Nueva dirección"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: label,
            decoration: InputDecoration(
              labelText: "Tipo",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            items: ["Casa", "Trabajo", "Otro"]
              .map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
            onChanged: (v) => setD(() => label = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, maxLines: 2,
            decoration: InputDecoration(
              labelText: "Dirección completa",
              hintText: "Ej: Calle Los Pinos 123, Ancud",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              await _sb.from("user_addresses").insert({
                "user_id":    widget.userId,
                "label":      label,
                "address":    ctrl.text.trim(),
                "is_default": _addresses.isEmpty,
              });
              if (dCtx.mounted) Navigator.pop(dCtx);
              await _load();
              widget.onChanged();
            },
            child: const Text("Guardar"),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(
          children: [
            const Text("Mis direcciones",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            TextButton.icon(
              onPressed: _addAddress,
              icon: const Icon(Icons.add, size: 18),
              label: const Text("Agregar")),
          ],
        )),
        const Divider(height: 1),
        Flexible(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _addresses.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("📍", style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text("Sin direcciones guardadas",
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
                  SizedBox(height: 4),
                  Text("Agrega una dirección para pedir más rápido",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textLight, fontSize: 13)),
                ]))
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _addresses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final a         = _addresses[i];
                  final isDefault = a["is_default"] == true;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDefault ? _kPurple.withOpacity(0.5) : AppColors.border,
                        width: isDefault ? 2 : 1)),
                    child: Row(children: [
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _kPurple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10)),
                        child: Icon(_labelIcon(a["label"]), color: _kPurple, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(a["label"] ?? "Dirección",
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kPurple,
                                borderRadius: BorderRadius.circular(6)),
                              child: const Text("Principal",
                                style: TextStyle(
                                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(a["address"] ?? "",
                          style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
                      ])),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == "default") {
                            await _sb.from("user_addresses")
                                .update({"is_default": false}).eq("user_id", widget.userId);
                            await _sb.from("user_addresses")
                                .update({"is_default": true}).eq("id", a["id"]);
                          } else if (v == "delete") {
                            await _sb.from("user_addresses").delete().eq("id", a["id"]);
                          }
                          await _load();
                          widget.onChanged();
                        },
                        itemBuilder: (_) => [
                          if (!isDefault)
                            const PopupMenuItem(value: "default",
                              child: Text("Establecer como principal")),
                          const PopupMenuItem(value: "delete",
                            child: Text("Eliminar",
                              style: TextStyle(color: AppColors.error))),
                        ],
                      ),
                    ]),
                  );
                }),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _FavoritesSheet
// ════════════════════════════════════════════════════════════════════════════
class _FavoritesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> favorites;
  final VoidCallback onRemoved;
  const _FavoritesSheet({required this.favorites, required this.onRemoved});
  @override
  State<_FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<_FavoritesSheet> {
  final _sb = Supabase.instance.client;
  late List<Map<String, dynamic>> _favs;

  @override
  void initState() {
    super.initState();
    _favs = List.from(widget.favorites);
  }

  Future<void> _remove(Map<String, dynamic> fav) async {
    try {
      await _sb.from("user_favorites").delete().eq("id", fav["id"]);
      setState(() => _favs.removeWhere((f) => f["id"] == fav["id"]));
      widget.onRemoved();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Row(children: [
          const Text("Tiendas favoritas",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          Text("${_favs.length} tiendas",
            style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
        ])),
        const Divider(height: 1),
        Flexible(child: _favs.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text("❤️", style: TextStyle(fontSize: 48)),
                SizedBox(height: 12),
                Text("Sin tiendas favoritas",
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
              ]))
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              itemCount: _favs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final fav   = _favs[i];
                final store = fav["stores"] as Map<String, dynamic>? ?? {};
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    context.push("/store/${store["id"]}");
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(children: [
                      Text(store["emoji"] ?? "🍽️",
                        style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(store["name"] ?? "",
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        Text(store["category"] ?? "",
                          style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
                      ])),
                      IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.red, size: 22),
                        onPressed: () => _remove(fav),
                        tooltip: "Quitar de favoritos",
                      ),
                    ]),
                  ),
                );
              }),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _CouponsSheet
// ════════════════════════════════════════════════════════════════════════════
class _CouponsSheet extends StatefulWidget {
  final String userId;
  const _CouponsSheet({required this.userId});
  @override
  State<_CouponsSheet> createState() => _CouponsSheetState();
}

class _CouponsSheetState extends State<_CouponsSheet> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _coupons = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await _sb.from("user_coupons")
          .select("*, coupons(*)")
          .eq("user_id", widget.userId)
          .order("created_at", ascending: false);
      if (mounted) setState(() {
        _coupons = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  String _discountLabel(Map<String, dynamic> c) =>
    c["discount_type"] == "percentage"
      ? "${c["discount_value"]}% de descuento"
      : "\$${c["discount_value"]} de descuento";

  String _expiryLabel(String? expiresAt) {
    if (expiresAt == null) return "Sin vencimiento";
    try {
      final dt = DateTime.parse(expiresAt);
      const m = ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"];
      return "Vence ${dt.day} ${m[dt.month - 1]}. ${dt.year}";
    } catch (_) { return ""; }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Align(alignment: Alignment.centerLeft,
            child: Text("Mis cupones",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
        const Divider(height: 1),
        Flexible(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _coupons.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(40),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("🎁", style: TextStyle(fontSize: 48)),
                  SizedBox(height: 12),
                  Text("Sin cupones disponibles",
                    style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textLight)),
                ]))
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _coupons.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final uc     = _coupons[i];
                  final coupon = uc["coupons"] as Map<String, dynamic>? ?? {};
                  final used    = uc["used"] == true;
                  final exp     = coupon["expires_at"] as String?;
                  final expired = exp != null && DateTime.tryParse(exp)?.isBefore(now) == true;
                  final active  = !used && !expired && coupon["is_active"] == true;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? AppColors.surface : AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: active ? _kPurple.withOpacity(0.4) : AppColors.border,
                        width: active ? 2 : 1),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: (active ? _kPurple : AppColors.textLight).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.local_offer,
                          color: active ? _kPurple : AppColors.textLight, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(coupon["code"] ?? "",
                          style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16,
                            letterSpacing: 1.5,
                            color: active ? _kPurple : AppColors.textLight)),
                        Text(_discountLabel(coupon),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        Text(_expiryLabel(coupon["expires_at"]),
                          style: TextStyle(
                            color: active ? AppColors.textLight : AppColors.error,
                            fontSize: 11)),
                        if (used)
                          const Text("Usado",
                            style: TextStyle(color: AppColors.textLight, fontSize: 11)),
                      ])),
                      if (active)
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppColors.textLight, size: 18),
                          tooltip: "Copiar código",
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: coupon["code"] ?? ""));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Código copiado al portapapeles"),
                                duration: Duration(seconds: 2)));
                          },
                        ),
                    ]),
                  );
                }),
        ),
      ]),
    );
  }
}

// ─── shared helpers ────────────────────────────────────────────────────────
Widget _handle() => Container(
  margin: const EdgeInsets.symmetric(vertical: 12),
  width: 40, height: 4,
  decoration: BoxDecoration(
    color: AppColors.border, borderRadius: BorderRadius.circular(2)));
