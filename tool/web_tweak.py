"""Ritocca i file web generati da `flutter create` (titolo, nomi, colori):
gira nella CI dopo `flutter create --platforms web`, senza dipendenze."""

import json
import pathlib
import re

web = pathlib.Path("web")
index = web / "index.html"
html = index.read_text()
html = re.sub(r"<title>.*?</title>", "<title>Etichette Margherita</title>", html, flags=re.S)
html = re.sub(r'<meta name="description" content="[^"]*">',
              '<meta name="description" content="Archivio etichette, lotti interni e stampa">', html)
html = re.sub(r'<meta name="apple-mobile-web-app-title" content="[^"]*">',
              '<meta name="apple-mobile-web-app-title" content="Etichette">', html)
if 'name="theme-color"' not in html:
    html = html.replace("</head>", '  <meta name="theme-color" content="#0F1B2D">\n</head>', 1)
html = html.replace('<html>', '<html lang="it">', 1)

# Diagnostica (2/10/2026, pagina bianca su iPhone): avvio, primo disegno ed
# errori del browser vanno nel log del server; se dopo 20 secondi non c'e'
# ancora niente sullo schermo, il motivo si legge sulla pagina invece del bianco.
DIAGNOSTICA = """
  <script>
  (function () {
    var started = Date.now(), drawn = false, problems = [];
    function send(what) {
      var body = JSON.stringify({ evento: what, secondi: Math.round((Date.now() - started) / 1000),
        ua: navigator.userAgent, schermo: innerWidth + 'x' + innerHeight + '@' + devicePixelRatio });
      try { navigator.sendBeacon('/app/api/v1/web-log', body); } catch (e) {}
    }
    function show() {
      var box = document.createElement('div');
      box.style.cssText = 'position:fixed;inset:0;background:#0F1B2D;color:#fff;font:16px -apple-system,sans-serif;padding:24px;overflow:auto;z-index:9';
      box.innerHTML = '<h2 style="margin-top:40px">La pagina non si è avviata</h2>'
        + '<p>Il browser non riesce a far partire l&#39;app. Il motivo è stato mandato al server.</p>'
        + '<pre style="white-space:pre-wrap;font-size:12px;color:#A9B6CA"></pre>'
        + '<button style="font-size:16px;padding:12px 18px;border-radius:10px;border:0;background:#1F5FD1;color:#fff" onclick="location.reload()">Riprova</button>';
      box.querySelector('pre').textContent = problems.join('\\n') || 'Nessun errore dal browser (forse memoria o grafica non supportata).';
      document.body.appendChild(box);
    }
    send('avvio');
    window.addEventListener('error', function (e) {
      var text = 'errore: ' + (e.message || e) + (e.filename ? ' @' + e.filename + ':' + e.lineno : '');
      problems.push(text); send(text);
    });
    window.addEventListener('unhandledrejection', function (e) {
      var r = e.reason, text = 'promessa: ' + (r && (r.stack || r.message) || r);
      problems.push(text); send(text);
    });
    window.addEventListener('flutter-first-frame', function () { drawn = true; send('primo-disegno'); });
    setTimeout(function () { if (!drawn) { send('nessun-disegno-dopo-20s'); show(); } }, 20000);
  })();
  </script>
"""
html = html.replace("</head>", DIAGNOSTICA + "</head>", 1)
index.write_text(html)

manifest_path = web / "manifest.json"
manifest = json.loads(manifest_path.read_text())
manifest.update({
    "name": "Etichette Margherita",
    "short_name": "Etichette",
    "description": "Archivio etichette, lotti interni e stampa",
    "background_color": "#0F1B2D",
    "theme_color": "#0F1B2D",
    "start_url": ".",
    "display": "standalone",
    "lang": "it",
})
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
print("web ritoccato")
