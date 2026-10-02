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
    window.addEventListener('flutter-first-frame', function () {
      drawn = true; send('primo-disegno');
      var loading = document.getElementById('caricamento');
      if (loading) loading.remove();
    });
    // Con la rete del telefono la prima apertura puo' metterci mezzo minuto:
    // l'avviso compare solo se dopo 90 secondi non c'e' ancora niente.
    setTimeout(function () { if (!drawn) { send('nessun-disegno-dopo-90s'); show(); } }, 90000);
  })();
  </script>
"""
html = html.replace("</head>", DIAGNOSTICA + "</head>", 1)

# Gesto "indietro" del browser (scorrimento da sinistra su iPhone, tasto
# indietro su Android): non deve uscire o ricaricare la pagina, ma fare
# l'indietro dell'app (chiudere la schermata aperta). Registrato prima di
# Flutter e in fase di cattura, cosi' la gestione di Flutter non lo vede:
# una voce "di guardia" nella cronologia resta sempre davanti alla pagina.
INDIETRO = """
  <script>
  (function () {
    history.pushState({ guardia: 1 }, '', location.href);
    window.addEventListener('popstate', function (e) {
      e.stopImmediatePropagation();
      history.pushState({ guardia: 1 }, '', location.href);
      if (typeof window.etichetteIndietro === 'function') window.etichetteIndietro();
    }, true);
  })();
  </script>
"""
html = html.replace("</head>", INDIETRO + "</head>", 1)

# Schermata di caricamento al posto della pagina bianca: la prima volta il
# browser scarica qualche MB (motore grafico e programma) prima di disegnare.
CARICAMENTO = """
  <div id="caricamento" style="position:fixed;inset:0;background:#0F1B2D;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;font:16px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;text-align:center;padding:24px">
    <img src="icons/Icon-192.png" width="88" height="88" alt="" style="border-radius:22px">
    <div style="font-size:22px;font-weight:700">Etichette Margherita</div>
    <div style="width:36px;height:36px;border:4px solid rgba(255,255,255,.2);border-top-color:#8FB1F0;border-radius:50%;animation:giro 0.9s linear infinite"></div>
    <div style="color:#A9B6CA;max-width:280px">Caricamento… la prima volta può richiedere qualche secondo in più.</div>
    <style>@keyframes giro{to{transform:rotate(360deg)}}@media (prefers-reduced-motion: reduce){#caricamento div{animation:none!important}}</style>
  </div>
"""
html = re.sub(r"<body[^>]*>", lambda m: m.group(0) + CARICAMENTO, html, count=1)
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
