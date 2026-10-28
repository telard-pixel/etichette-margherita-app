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
  const LabelHints({this.lot, this.expiry, this.lotFromExpiry = false, this.lotIsExpiry = false});

  /// Il testo che sembra un lotto, come lo ha letto il telefono.
  final String? lot;

  /// Il testo che sembra una scadenza (una data o mese/anno).
  final String? expiry;

  /// Il lotto e' la scadenza stessa (mozzarelle Spinelli, o l'etichetta che
  /// dice "per il lotto vedere la data di scadenza"): stessa regola del
  /// server, lot_from_expiry in pipeline.py.
  final bool lotFromExpiry;

  /// La foto dice che il lotto e' la scadenza (il nome del produttore o la
  /// frase), anche se la data e' in un'altra foto: "LA PERLA" sulla
  /// confezione, "211026" sul sigillo (28/10/2026).
  final bool lotIsExpiry;

  bool get hasLot => lot != null;
  bool get hasExpiry => expiry != null;
  bool get complete => hasLot && hasExpiry;

  /// Unisce due letture: quello che una ha trovato resta, anche se l'altra no.
  LabelHints merge(LabelHints other) {
    final both = LabelHints(
      lot: lot ?? other.lot,
      expiry: expiry ?? other.expiry,
      lotFromExpiry: lot != null ? lotFromExpiry : other.lotFromExpiry,
      lotIsExpiry: lotIsExpiry || other.lotIsExpiry,
    );
    if (both.lot == null && both.expiry != null && both.lotIsExpiry) {
      return LabelHints(lot: both.expiry, expiry: both.expiry, lotFromExpiry: true, lotIsExpiry: true);
    }
    return both;
  }

  /// Come mostrarlo nell'indicatore "Lotto".
  String? get lotLabel => lotFromExpiry ? '= scadenza' : lot;

  static const none = LabelHints();
}

// Giorno/mese/anno con / . - o spazi (21/10/26, 06.05.2027, 21 10 26) e
// mese/anno (10/2027). L'anno a due cifre e' quello delle etichette vere.
// L'anno puo' essere attaccato all'ora: i timbri "20/08/2030 09:11" il
// lettore li da' come "20/08/203009:11" (funghi Sanfelici, 25/10/2026).
// 27/10/2026: anche "03\10\2027" (barra rovesciata) e "20/102026" (anno di 4
// cifre attaccato al mese; con 2 cifre no: "1/245" e' un lotto).
final _dayMonthYear = RegExp(
    r'(?<!\d)(0?[1-9]|[12]\d|3[01])\s?[/.\-\s\\]\s?(0?[1-9]|1[0-2])'
    r'(?:\s?[/.\-\s\\]\s?(?:20\d{2}(?=\d{1,2}[:.]\d{2})|(?:20\d{2}|\d{2})(?!\d))|20\d{2}(?!\d))');
// Mese in lettere: "01·NOV·26", "15 GIU 2027" (formaggio Spinelli, 25/10/2026).
final _dayNamedMonthYear = RegExp(
    r'(?<!\d)(0?[1-9]|[12]\d|3[01])\s?[\s./\-·]?\s?'
    r'(gen|feb|mar|apr|mag|giu|lug|ago|set|ott|nov|dic|jan|may|jun|jul|aug|sep|oct|dec)[a-z]*\.?'
    r'\s?[\s./\-·]?\s?(20\d{2}|\d{2})(?!\d)',
    caseSensitive: false);
final _monthYear = RegExp(r'(?<![\d/.\-])(0?[1-9]|1[0-2])\s?[/.\-]\s?(20\d{2})(?!\d)');

// Le parole che precedono la scadenza sulle etichette italiane ed europee.
final _expiryWord = RegExp(
    r'\b(scad\w*|entro|consumarsi|preferibilmente|tmc|bbd|best\s*before|exp\w*|use\s*by|mhd|dlc|ddm)\b',
    caseSensitive: false);

// Data compatta senza separatori, "211026" o "21102026" (bufala La Perla,
// 28/10/2026). Tante etichette hanno lotti di sei cifre, quindi vale solo
// vicino a una parola di scadenza o a "Data", mai vicino a "lotto".
final _compactDate = RegExp(r'(?<![\dA-Z])(0[1-9]|[12]\d|3[01])(0[1-9]|1[0-2])(?:20)?(2\d|3\d)(?![\dA-Z])',
    caseSensitive: false);
final _compactDateWord = RegExp(r'\bdata\b', caseSensitive: false);
final _anyLotWord = RegExp(r'\b(?:lott?o|lot|batch|l\.)', caseSensitive: false);

// "Lotto: X", "LOT X", "L. X", "L X": la parola e poi un codice con almeno una cifra.
final _lotWithWord = RegExp(r'\b(?:lotto|lot|l\.|l(?=[\s:]))[\s:.#n°]*([A-Z0-9][A-Z0-9/\-.]{0,18}[A-Z0-9])',
    caseSensitive: false);

// "Lotto rintracciabilita' cliente: CR 260093" (calamaro, 25/10/2026): altre
// parole tra "lotto" e i due punti, poi il codice.
final _lotWordsThenCode = RegExp(r'\blott?o?\b[^:\d]{0,45}:\s*([A-Z0-9][A-Z0-9/\-. ]{1,18}[A-Z0-9])',
    caseSensitive: false);

// "L261190", "LR331", "LK248": la L attaccata al codice fa parte del lotto.
final _lotGlued = RegExp(r'\bL(?!OT)[A-Z]{0,2}\s?\d{2,}[A-Z0-9/\-]*', caseSensitive: false);

// La riga che e' solo "Lotto:" / "LOT" / "L." senza codice.
final _lotWordAlone = RegExp(r'^\s*(?:lotto|lot|l\.)(?:\s*[:.#n°]*|\b[^\d]{0,45}[:.]?)\s*$', caseSensitive: false);

// Una riga che e' solo un codice: "2533991502", "LK232DD-R".
final _codeAlone = RegExp(r'^[A-Z0-9][A-Z0-9/\-. ]{2,24}[A-Z0-9]$', caseSensitive: false);

/// Produttori il cui lotto e' la data di scadenza: la stessa lista del server
/// (LOT_IS_EXPIRY_PRODUCERS in pipeline.py, chiesto dall'utente il 2/10/2026;
/// le bufale La Perla dal 28/10/2026).
const lotIsExpiryProducers = ['SPINELLI', 'LA PERLA'];

// "PER IL LOTTO DI PRODUZIONE VEDERE LA DATA DI SCADENZA" (come il server).
final _lotIsExpiryPhrase = RegExp(
    r'\bLOTTO\b.{0,40}?\b(?:VEDERE|VEDI|CORRISPONDE|COINCIDE)\b.{0,30}?\bSCADENZA\b',
    caseSensitive: false);

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
  // "211026" da solo: e' una data se nella stessa riga prima, o nella riga
  // sopra o sotto, c'e' "scadenza / entro / Data" e non c'e' "lotto".
  for (var i = 0; i < list.length && expiry == null; i++) {
    final m = _compactDate.firstMatch(list[i]);
    if (m == null) continue;
    final before = list[i].substring(0, m.start);
    if (_anyLotWord.hasMatch(before) || (_lot(list[i])?.contains(m.group(0)!) ?? false)) continue;
    bool marks(String s) => _expiryWord.hasMatch(s) || _compactDateWord.hasMatch(s);
    final near = [if (i > 0) list[i - 1], if (i + 1 < list.length) list[i + 1]];
    if (marks(before) || near.any((n) => marks(n) && !_anyLotWord.hasMatch(n))) {
      expiry = m.group(0);
    }
  }
  // Un codice che e' una data ("LOTTO / CONGELATO IL: 27/01/2026") vale
  // solo se non c'e' un lotto vero ("CR 260093") da qualche altra parte.
  String? dateLot;
  for (final line in list) {
    final found = _lot(line);
    if (found != null) {
      if (_date(found) == null) {
        lot ??= found;
      } else {
        dateLot ??= found;
      }
    }
    expiry ??= _date(line);
  }
  // "Lotto:" da solo e il codice in un'altra colonna (25/10/2026, le
  // mazzancolle: "Lotto:" a sinistra, 2533991502 a destra): il lettore li da'
  // come righe separate. Si guardano le due righe dopo e le due
  // prima, saltando le date (sono scadenze o date di produzione).
  for (var i = 0; i < list.length && lot == null; i++) {
    if (!_lotWordAlone.hasMatch(list[i])) continue;
    for (final j in [i + 1, i + 2, i - 1, i - 2]) {
      if (j < 0 || j >= list.length || _date(list[j]) != null || list[j] == expiry) continue;
      final code = _codeAlone.firstMatch(list[j]);
      if (code != null && code.group(0)!.contains(RegExp(r'\d'))) {
        lot = code.group(0);
        break;
      }
    }
  }
  lot ??= dateLot;
  final upper = list.join('\n').toUpperCase();
  final lotIsExpiry = lotIsExpiryProducers.any(upper.contains) || list.any(_lotIsExpiryPhrase.hasMatch);
  return LabelHints(lotIsExpiry: lotIsExpiry).merge(LabelHints(lot: lot, expiry: expiry));
}

String? _date(String line) {
  // Il lettore scambia la O dei mesi con lo zero: "25.0TT.26" (Spinelli).
  final fixed = line
      .replaceAll(RegExp(r'(?<=[\d.\-\s·/])0TT\b', caseSensitive: false), 'OTT')
      .replaceAll(RegExp(r'\bN0V\b', caseSensitive: false), 'NOV')
      .replaceAll(RegExp(r'\bAG0\b', caseSensitive: false), 'AGO');
  final m = _dayMonthYear.firstMatch(fixed) ?? _dayNamedMonthYear.firstMatch(fixed) ?? _monthYear.firstMatch(fixed);
  return m?.group(0)?.trim();
}

String? _lot(String line) {
  final glued = _lotGlued.firstMatch(line);
  if (glued != null) return glued.group(0)!.trim();
  final afterWords = _lotWordsThenCode.firstMatch(line);
  if (afterWords != null && afterWords.group(1)!.contains(RegExp(r'\d'))) return afterWords.group(1)!.trim();
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
