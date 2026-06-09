# Go Deli — Guía de despliegue de seguridad

Cambios aplicados en el código (este repo y go_deli_web) + pasos manuales
que debes ejecutar en Supabase / Google Cloud para activarlos.

## 1. Aplicar las políticas RLS

Archivo: [`supabase/rls_policies.sql`](rls_policies.sql)

1. **Primero en un branch/proyecto de prueba** de Supabase si es posible.
2. Abrir el SQL Editor del proyecto → pegar y ejecutar el script completo
   (es idempotente, puede re-ejecutarse).
3. Verificar con las consultas de la sección 14 del script.
4. Probar los flujos completos: registro cliente/rider/aliado, crear pedido,
   llamar rider, aceptar, entregar, chat, panel admin.

> ⚠️ El panel `aliados.html` fue actualizado para usar la RPC
> `get_rider_workload()` (incluida en el script). Despliega la nueva versión
> de los paneles **junto con** el script SQL — la versión vieja del panel
> dejaría de ver la carga de riders al activar RLS.

## 2. Secreto de las edge functions (anti-spam de notificaciones)

Las funciones `notify-client` y `notify-rider` ahora exigen el header
`x-webhook-secret`. Sin esto, cualquiera con la anon key podía mandar
push notifications arbitrarias a todos tus usuarios.

1. Generar un secreto: `openssl rand -hex 32`
2. En Supabase → Edge Functions → Secrets, añadir:
   `NOTIFY_WEBHOOK_SECRET=<el secreto>`
3. Re-desplegar ambas funciones:
   ```bash
   supabase functions deploy notify-client
   supabase functions deploy notify-rider
   ```
4. En Database → Webhooks, editar los dos webhooks y añadir el HTTP header:
   `x-webhook-secret: <el mismo secreto>`
5. Probar: cambiar el estado de un pedido y confirmar que llega el push.
   Una llamada directa con curl sin el header debe devolver **401**.

> Nota: si el secreto no está configurado en el entorno, las funciones siguen
> funcionando como antes (sin validar), para no romper producción a mitad de
> migración. No olvides el paso 2.

## 3. Restringir la API key de Google Maps

La key `AIzaSy...` está embebida en las apps (normal en móvil), pero debe
restringirse en Google Cloud Console → Credentials:

- **Restricción de aplicación**: huella SHA-1 del certificado Android +
  bundle ID de iOS (`Application restrictions`).
- **Restricción de API**: solo Maps SDK for Android/iOS, Geocoding API
  (las que uses).

Sin esto, cualquiera puede extraer la key del APK y consumir tu cuota.

## 4. Paneles web (go_deli_web)

- Se añadieron los helpers `esc()` / `jsq()` y se escaparon ~70
  interpolaciones de datos de usuario en `admin.html`, `aliados.html` y
  `web.html` → cierra XSS almacenado (un usuario con nombre malicioso podía
  ejecutar JS en la sesión del admin).
- El chequeo de rol del panel admin es solo client-side: la protección real
  la dan las políticas RLS del paso 1. **Sin RLS, los paneles no son seguros.**

## 4b. Bugs de integración corregidos (código vs base de datos real)

Validando el esquema de producción contra el código se encontró y corrigió:

- **Chat de soporte del admin roto**: `admin.html` leía la tabla `messages`,
  que **no existe** en la base de datos, mientras los riders escriben en
  `chat_messages` → el admin nunca veía esos mensajes. El panel fue migrado
  a `chat_messages` (chats directos = `order_id` null). Sin pasos manuales:
  basta desplegar el nuevo `admin.html`.
- **`service_providers.rating` no existía** → la app mostraba siempre "5.0".
  El script `rls_policies.sql` añade la columna (sección 13b).
- Resto del esquema verificado columna por columna contra producción: ✓.

## 5. Recomendación pendiente: recetas médicas con signed URLs

Hoy las recetas se suben al bucket `prescriptions` y se guarda una URL
pública (`getPublicUrl`) en `orders.prescription_url`. Cualquiera que
obtenga ese link puede ver la receta (dato médico sensible).

Mitigación actual: la URL solo es visible para los participantes del pedido
(RLS sobre `orders`) y la ruta es difícil de adivinar.

Mejora recomendada (siguiente iteración): hacer el bucket privado, guardar
solo la **ruta** del archivo y generar `createSignedUrl()` con expiración
en la app y en `aliados.html` al momento de mostrarla.

## 6. Firma de release para Play Store

Ambas apps (`android/app/build.gradle.kts` y
`go_rider_app/android/app/build.gradle.kts`) firman el release con la clave
de **debug**. Antes de publicar:

1. Generar keystore (guardarla FUERA del repo, con backup):
   ```bash
   keytool -genkey -v -keystore godeli-release.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias godeli
   ```
2. Crear `android/key.properties` (añadirlo a `.gitignore`) y configurar
   `signingConfigs` según la guía oficial de Flutter
   (docs.flutter.dev/deployment/android#sign-the-app).
3. Repetir para la app rider con su propio alias.

## 7. Checklist final

- [ ] RLS aplicado y flujos probados
- [ ] Paneles nuevos desplegados (Vercel u hosting actual)
- [ ] `NOTIFY_WEBHOOK_SECRET` configurado + funciones re-desplegadas
- [ ] Headers añadidos a los 2 Database Webhooks
- [ ] API key de Maps restringida
- [ ] Confirmar en Supabase → Authentication que el email confirm está
      configurado como quieres para producción
