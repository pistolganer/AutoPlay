# AutoPlay – cómo instalarla en tu iPhone con un PC Windows

Solo hace falta hacerlo una vez (y renovarla cada 7 días con un clic).
Todo es gratis.

## Parte 1 – Crear la app en GitHub (unos 10 minutos)

GitHub tiene ordenadores Mac en la nube y los deja usar gratis. Ahí se compila la app.

1. Descomprime este zip en el PC.
2. Crea una cuenta gratis en https://github.com (si no tienes).
3. Arriba a la derecha pulsa **+ → New repository**.
   - Nombre: `AutoPlay`
   - Marca **Public** (así los Mac de GitHub son gratis e ilimitados)
   - Pulsa **Create repository**.
4. En la página del repositorio pulsa **uploading an existing file**.
5. Arrastra **todo el contenido** de la carpeta descomprimida (las carpetas `AutoPlay` y `.github`,
   y los archivos `project.yml` y `LEEME.md`). Pulsa **Commit changes**.
   - Si la carpeta `.github` no se ve: en el Explorador de Windows → Vista → marca «Elementos ocultos».
6. Ve a la pestaña **Actions**. Verás «Compilar AutoPlay» en marcha (tarda unos 5 minutos).
   - Si no arranca solo: pulsa «Compilar AutoPlay» → **Run workflow**.
7. Cuando salga el ✅ verde, entra en él y abajo, en **Artifacts**, descarga **AutoPlay-ipa**.
   Descomprímelo: dentro está **AutoPlay.ipa**.

Si sale una ❌ roja: entra, abre el paso que falló, copia el texto del error y pásamelo a Claude.

## Parte 2 – Instalarla en el iPhone con Sideloadly

1. Instala **iTunes** e **iCloud** para Windows descargados de la web de Apple
   (no los de Microsoft Store): https://support.apple.com/es-es/106372
2. Descarga **Sideloadly** desde https://sideloadly.io e instálalo.
3. Conecta el iPhone al PC con cable y pulsa «Confiar» en el iPhone.
4. Abre Sideloadly:
   - Arrastra **AutoPlay.ipa** a la ventana.
   - En «Apple account» pon tu Apple ID (si prefieres, crea un Apple ID secundario solo para esto).
   - Pulsa **Start** y escribe tu contraseña / código si lo pide.
5. En el iPhone:
   - **Ajustes → General → VPN y gestión de dispositivos** → toca tu Apple ID → **Confiar**.
   - **Ajustes → Privacidad y seguridad → Modo de desarrollador** → actívalo y reinicia.
6. Abre **AutoPlay** desde la pantalla de inicio. Acepta los permisos de ubicación, música y micrófono.

## Cada 7 días

Con un Apple ID gratuito la app deja de abrirse a los 7 días.
Conecta el iPhone y vuelve a pulsar **Start** en Sideloadly (no se borra nada).
En Sideloadly puedes activar «Auto refresh» para que lo haga solo si el PC y el iPhone
están en la misma Wi-Fi.

## Qué tiene la app

- Pantalla completa, sin barras, en horizontal, como la pantalla CarPlay de la foto.
- Mapa real de Apple con tu GPS, buscador, ruta giro a giro, hora de llegada, velocidad y voz en español.
- Botón para pasar la ruta a Google Maps o Waze.
- Música de Apple Music con carátula y controles; botón para abrir Spotify.
- Botón «Voz»: «llévame a…», «pon música», «siguiente», «pausa», «llama a Mamá», «abre Spotify».
- Teléfono con favoritos y teclado.
- Iconos: mantén pulsado un icono → «Cambiar icono» → elige una captura del icono original.
- La pantalla no se apaga mientras la usas.
