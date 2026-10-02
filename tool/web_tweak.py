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
