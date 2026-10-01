# Etichette Margherita (app Android)

App Flutter per l'archivio etichette della cucina: le stesse funzioni del gruppo
Telegram "Etichette cucina" (foto → lettura Qwen → scheda, lotto interno e
stampa, archivio e scadenze, amministrazione), sul server
`https://etichette-margherita.duckdns.org/app/api/v1` (repo telegram-label-archive,
`src/label_archive/app_api.py`).

- Si compila solo su GitHub Actions: ogni ramo viene controllato e compilato,
  `main` pubblica la Release e carica l'APK sul server, da cui l'app si aggiorna.
- La cartella `android/` contiene solo i file personalizzati (manifest, icone):
  il resto lo genera `flutter create` nella CI.
- Segreti della CI: `KEYSTORE_B64`, `KEYSTORE_PASSWORD` (chiave di firma, alias
  `etichette`), `APP_UPLOAD_TOKEN` (= `LABEL_ARCHIVE_APP_UPLOAD_TOKEN` sul server).
