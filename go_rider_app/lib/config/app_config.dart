class AppConfig {
  static const String supabaseUrl = "https://yxseolcaububyifhksud.supabase.co";
  // ⚠️ Verificar: esta clave parece truncada. La clave anónima de Supabase
  // normalmente es un JWT largo (eyJ...). Si hay errores de auth, revisar
  // en Supabase Dashboard → Settings → API → anon/public key.
  static const String supabaseAnonKey = "sb_publishable_wc8oyi80Iu2RPgJr-9zS4g_DJ3l-3nV";
  static const String googleMapsApiKey = "AIzaSyB2MmFbdc9HsUxuGWgPXA0rwZqGvynrevM";
  static const String appName = "Go Rider";
  static const double riderCommissionPct = 15.0;
  // ⚠️ Configurar con el número real de WhatsApp de soporte (código país + número, sin + ni espacios)
  static const String adminWhatsApp = "56955201833";
}
