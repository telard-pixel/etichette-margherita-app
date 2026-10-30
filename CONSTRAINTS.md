# Paletti del progetto (CONSTRAINTS.md)

App Flutter dello scanner etichette (La Margherita). Regole che una modifica non deve mai
abbassare per "far passare" qualcosa. Chi lavora qui (persona o agente) legge questo file prima
di toccare il codice. Ogni numero ha un perché. Scritto il 30/10/2026.

## Il minimo (non negoziabile)

- **Test verdi**: `flutter test` — oggi **63 test** in 6 file (`label_hints_test` da solo ne ha 27).
  Un test che fallisce si aggiusta o si capisce; **non si cancella e non si mette `skip`**.
- **Analisi pulita**: `flutter analyze --no-fatal-infos` senza errori.
- **Librerie bloccate**: `pubspec.lock` è versionato apposta (10/10/2026) — le librerie sono quelle
  provate. Non aggiornarle per caso: si cambia `pubspec.yaml` e si prende il lock dalla CI.
- **La CI deve essere verde** prima che arrivi agli utenti.

## Correttezza = sicurezza alimentare (la regola più importante)

Una **data di scadenza o un lotto sbagliati** su un'etichetta alimentare sono un rischio vero.
Perciò:

- **Il codice a barre GS1 vince sempre sul testo OCR.** Lotto e scadenza letti dal GS1-128 o dal
  DataMatrix sono esatti; l'OCR è un ripiego. La precedenza "GS1 > testo" deve restare identica in
  `lib/gs1.dart`, `lib/label_hints.dart`, `lib/platform/text_reader_native.dart` e `lib/api.dart`.
- **Le euristiche OCR non devono indovinare.** Chi legge date/lotti malmessi (la barra persa, il
  lotto a puntini con la L letta C/I) deve tenere le sue guardie: la data "a barra persa" vale solo
  con l'altra barra presente e l'anno a 4 cifre; un EAN accanto alla data non è un lotto. Ogni nuova
  euristica entra **con il suo test** (positivo e negativo), come già fatto per olio Aldi / asparagi
  Orogel. Mai allargare una regex senza un test che fissi cosa NON deve pescare.
- Il parsing GS1 legge gli identificatori **da sinistra** (come il server `barcodes.py`): non cercare
  "10"/"17" dentro il codice, prenderebbe la coda del numero prima.

## Comportamento dello scanner e dei report

- **Scanner: solo il verde, niente falsi avvisi.** Lo scanner segnala solo quando è sicuro; non deve
  tornare a dare avvisi/rossi su letture incerte (regressione da evitare).
- **Report HACCP**: formato in produzione = "formato A". Niente colonna **Stato**, niente
  **riepilogo**, niente **responsabile HACCP**. Intestazione fissa: La Margherita, Via Santa
  Margherita 6, Montichiari.

## Versione e pubblicazione

- Il numero di versione lo dà la **CI** (`1.0.<numero di run>`), non si scrive a mano. Il
  `version: 1.0.0+1` nel `pubspec.yaml` è solo un segnaposto.
- **`push` su `main` = produzione**: la CI firma l'APK (keystore nei segreti), lo carica sul server
  (l'app si aggiorna da lì) e pubblica la release. Quindi il controllo si fa **prima** del merge, su
  ramo/PR. Non si spinge su `main` roba non rivista.

## Da misurare, non ancora un cancello

- I test girano in CI; **in locale su questa macchina Flutter non è installato**, quindi qui non si
  può lanciare `flutter test` — ci si fida della CI o si prova sul telefono/web.

## Eccezioni

| Cosa | Perché | Chi | Scade |
|------|--------|-----|-------|
| (nessuna al 30/10/2026) | — | — | — |
