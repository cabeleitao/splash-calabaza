# Splash Calabaza 🎃

Videojuego 3D para el navegador: elegí tu personaje (Almen, Carme, Facu o Indi), aplastá calabazas con **SPLiSH** (izquierda) y **SPLASH** (derecha), juntá monedas, rompé la calabaza gigante y terminá bailando en el escenario-calabaza.

- Funciona en celular, tablet y compu. Se puede instalar como app ("Agregar a pantalla de inicio").
- Modo solo y multijugador (2 a 4 jugadores) con código de partida o link de invitación.
- Sitio estático: no necesita compilar nada.

## Servidor (Supabase, proyecto `splash-calabaza`)
- **Partidas en vivo:** Supabase Realtime (presence + broadcast), con reconexión automática.
- **Cuentas sin mail:** usuario y contraseña propios del juego (contraseña cifrada con bcrypt). Amigos con solicitud
  y aceptación; cada uno ve solo las partidas por empezar de sus amigos. Monedas acumuladas por cuenta y tienda
  (personajes ocultos, martillos, músicas). Todo con funciones de base de datos: las tablas no se leen desde el navegador.
- El esquema completo está en `supabase/schema.sql`. La configuración (URL y clave pública) en `config.js`.
- Si un chico se olvida la contraseña, un adulto puede borrar la cuenta desde Supabase (tabla `sc_users`) y crearla de nuevo.

## Publicar
Importar el repo en Vercel (Framework: *Other*, sin build). Cada `git push` publica solo.

## Estructura
- `index.html` — el juego completo (Three.js)
- `config.js` — datos del servidor de partidas
- `vendor/` — Three.js r170 y supabase-js (copias locales, sin depender de CDNs)
- `icons/`, `manifest.webmanifest`, `sw.js` — app instalable y juego solo sin conexión
