-- Seed rider_features_config con defaults
-- Todos los features ACTIVOS por defecto excepto navegación por voz (requiere flutter_tts en el APK)
INSERT INTO public.config (key, value)
SELECT 'rider_features_config', '{"ratings_enabled":true,"tips_enabled":true,"challenges_enabled":true,"heatmap_enabled":true,"instant_pay_enabled":true,"voice_nav_enabled":false}'
WHERE NOT EXISTS (SELECT 1 FROM public.config WHERE key = 'rider_features_config');
