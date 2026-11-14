# Splash Calabaza 🎃

Videojuego 3D para el navegador: elegí tu personaje (Almen, Carme, Facu o Indi), aplastá calabazas con **SPLiSH** (izquierda) y **SPLASH** (derecha), juntá monedas, rompé la calabaza gigante y terminá bailando en el escenario-calabaza.

- Funciona en celular, tablet y compu. Se puede instalar como app ("Agregar a pantalla de inicio").
- Modo solo y multijugador (2 a 4 jugadores) con código de partida o link de invitación.
- Sitio estático: no necesita compilar nada.

## Multijugador
Usa Supabase Realtime (presence), sin tablas. Completá `config.js` con la URL y la *anon key* del proyecto
(Supabase → Project Settings → API). La anon key es pública por diseño.

## Publicar
Importar el repo en Vercel (Framework: *Other*, sin build). Cada `git push` publica solo.

## Estructura
- `index.html` — el juego completo (Three.js)
- `config.js` — datos del servidor de partidas
- `vendor/` — Three.js r170 y supabase-js (copias locales, sin depender de CDNs)
- `icons/`, `manifest.webmanifest`, `sw.js` — app instalable y juego solo sin conexión
