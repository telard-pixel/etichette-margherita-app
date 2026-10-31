# Etichette Margherita

App Flutter (Dart) dello scanner etichette per La Margherita: legge lotto e scadenza da codici a
barre GS1 e, come ripiego, dal testo OCR. Tutto in italiano (codice, commenti, risposte).

## Prima di toccare il codice

Leggi **[CONSTRAINTS.md](CONSTRAINTS.md)** e non abbassare mai quei paletti per far passare una
modifica. In breve: test verdi (`flutter test`, 76) e `flutter analyze` pulito; `pubspec.lock`
versionato (non aggiornare le librerie per caso); **correttezza = sicurezza alimentare** (il GS1
vince sempre sull'OCR, le euristiche OCR entrano solo con test positivo e negativo); scanner solo
verde senza falsi avvisi; report HACCP "formato A"; versione gestita dalla CI; `push` su `main` =
produzione (si rivede prima del merge). Flutter non è installato su questa macchina: i test girano
in CI.
