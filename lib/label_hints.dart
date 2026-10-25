/// Lo scanner (25/10/2026): nel testo letto dal telefono cerca qualcosa che
/// somigli a una scadenza e a un lotto, per dire alla cucina prima di
/// inviare se la foto li contiene. Non decide niente sulla scheda: la lettura
/// vera la fa il server. Qui basta capire "c'e' / non c'e'".
///
/// Nell'archivio il 21% delle schede ha avuto il lotto corretto a mano e il
/// 18% la scadenza, e in tre casi su quattro il campo non era stato trovato
/// affatto: spesso perche' il timbro non era nella foto.
library;

class LabelHints {
  const LabelHints({this.lot, this.expiry});

  /// Il testo che sembra un lotto, come lo ha letto il telefono.
  final String? lot;

  /// Il testo che sembra una scadenza (una data o mese/anno).
  final String? expiry;

  bool get hasLot => lot != null;
  bool get hasExpiry => expiry != null;
  bool get complete => hasLot && hasExpiry;

  /// Unisce due letture: quello che una ha trovato resta, anche se l'altra no.
  LabelHints merge(LabelHints other) => LabelHints(lot: lot ?? other.lot, expiry: expiry ?? other.expiry);

  static const none = LabelHints();
}

// Giorno/mese/anno con / . - o spazi (21/10/26, 06.05.2027, 21 10 26) e
// mese/anno (10/2027). L'anno a due cifre e' quello delle etichette vere.
final _dayMonthYear = RegExp(r'(?<!\d)(0?[1-9]|[12]\d|3[01])\s?[/.\-\s]\s?(0?[1-9]|1[0-2])\s?[/.\-\s]\s?(20\d{2}|\d{2})(?!\d)');
final _monthYear = RegExp(r'(?<![\d/.\-])(0?[1-9]|1[0-2])\s?[/.\-]\s?(20\d{2})(?!\d)');

// Le parole che precedono la scadenza sulle etichette italiane ed europee.
final _expiryWord = RegExp(
    r'\b(scad\w*|entro|consumarsi|preferibilmente|tmc|bbd|best\s*before|exp\w*|use\s*by|mhd|dlc|ddm)\b',
    caseSensitive: false);

// "Lotto: X", "LOT X", "L. X", "L X": la parola e poi un codice con almeno una cifra.
final _lotWithWord = RegExp(r'\b(?:lotto|lot|l\.|l(?=\s))[\s:.#n°]*([A-Z0-9][A-Z0-9/\-.]{0,18}[A-Z0-9])',
    caseSensitive: false);

// "L261190", "LR331", "LK248": la L attaccata al codice fa parte del lotto.
final _lotGlued = RegExp(r'\bL(?!OT)[A-Z]{0,2}\s?\d{2,}[A-Z0-9/\-]*', caseSensitive: false);

/// Cerca scadenza e lotto nelle righe lette da una foto.
LabelHints findLabelHints(Iterable<String> lines) {
  final list = [for (final l in lines) l.trim()].where((l) => l.isNotEmpty).toList();
  String? lot;
  String? expiry;
  // Prima la data vicina a "scadenza / entro / BBD": la prima data qualsiasi
  // puo' essere quella di produzione.
  for (var i = 0; i < list.length && expiry == null; i++) {
    if (!_expiryWord.hasMatch(list[i])) continue;
    expiry = _date(list[i].substring(_expiryWord.firstMatch(list[i])!.start)) ??
        (i + 1 < list.length ? _date(list[i + 1]) : null);
  }
  for (final line in list) {
    lot ??= _lot(line);
    expiry ??= _date(line);
  }
  return LabelHints(lot: lot, expiry: expiry);
}

String? _date(String line) {
  final m = _dayMonthYear.firstMatch(line) ?? _monthYear.firstMatch(line);
  return m?.group(0)?.trim();
}

String? _lot(String line) {
  final glued = _lotGlued.firstMatch(line);
  if (glued != null) return glued.group(0)!.trim();
  for (final m in _lotWithWord.allMatches(line)) {
    final code = m.group(1)!.trim();
    // Un codice senza cifre e' quasi sempre una parola ("L. Latte").
    if (!code.contains(RegExp(r'\d'))) continue;
    // "L 1,5 kg", "L 250 ml": e' una quantita', non un lotto.
    if (RegExp(r'^\d+([.,]\d+)?\s*(kg|g|ml|l|cl)\b', caseSensitive: false).hasMatch(code)) continue;
    return code;
  }
  return null;
}
