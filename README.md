# 🔥 Mapa colaborativo de incendios — Valle del Tiétar

Web **gratis** y **en un solo archivo** para emergencias por incendio en **todo el
Valle del Tiétar** (Ávila) y su entorno: La Adrada, Piedralaves, Casavieja, Sotillo
de la Adrada, Arenas de San Pedro, Candeleda, Mombeltrán, Pedro Bernardo, Lanzahíta,
Burgohondo, El Tiemblo, Cebreros, San Martín de Valdeiglesias, Pelayos de la Presa,
Villa del Prado… y todos los pueblos del valle.

Cualquiera puede, sin registrarse, avisar y ver en **tiempo real** sobre un mapa:

🔥 Focos de incendio · ⚠️ Carreteras cortadas · 🆘 Necesito ayuda ·
🤝 Ofrezco ayuda · ✅ Zonas seguras · 🏠 Refugios · 💧 Puntos de agua

> ⚠️ **No sustituye a los servicios de emergencia. Ante peligro, llama al 112.**

Todo está en **`index.html`**. No hay que instalar ni compilar nada.

---

## Ponerlo en vivo con GitHub Pages (gratis)
1. En este repo: **Settings → Pages**.
2. En **Source**, elige **"Deploy from a branch"**.
3. Branch: **`main`** · Carpeta: **`/ (root)`** · **Save**.
4. Espera ~1 min y recarga. Tu web estará en:
   **https://estebangamboa-12.github.io/incendi-/**

## Para que TODOS colaboren (gratis, ~5 min)
1. Crea una base de datos gratis en **[supabase.com](https://supabase.com)**.
2. *SQL Editor* → pega **`supabase.sql`** → **RUN**.
3. Copia tus 2 claves en *Settings → API*: **Project URL** y la clave **anon public**.
4. Pégalas arriba del `<script>` en `index.html`:
   ```js
   const SUPABASE_URL = "https://xxxx.supabase.co";
   const SUPABASE_ANON_KEY = "eyJhbGciOi...";
   ```
5. Guarda el cambio y GitHub Pages se actualiza solo.

## ¿Cómo funciona?
- **Mapa:** Leaflet + OpenStreetMap (gratis, sin API key).
- **Datos y tiempo real:** Supabase (plan gratuito).
- **Anti-abusos:** cualquiera puede añadir y marcar como resuelto, pero nadie
  puede borrar ni reescribir los avisos de otros (regla de seguridad RLS).

Hecho con cariño para ayudar. Cuídate mucho. 💪
