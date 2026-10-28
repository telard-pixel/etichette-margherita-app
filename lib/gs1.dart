/// I codici a barre GS1 (28/10/2026): un GS1-128 o un DataMatrix porta il
/// lotto (10) e la scadenza (17, "da consumarsi entro", o 15,
/// "preferibilmente entro") esatti, senza niente da interpretare. Nell'archivio
/// 140 schede su 678 ne hanno uno, 116 con il lotto.
///
/// E' la stessa lettura del server (barcodes.py): il codice si legge da
/// sinistra, identificatore per identificatore, perche' cercare "10" dentro il
/// codice trova la coda del numero prima.
library;

import 'label_hints.dart';

const _fixedLength = {
  '00': 18, '01': 14, '02': 14, '11': 6, '12': 6, '13': 6, '15': 6, '16': 6, '17': 6, '20': 2,
  '410': 13, '411': 13, '412': 13, '413': 13, '414': 13, '415': 13, '416': 13, '417': 13,
  '422': 3, '424': 3, '426': 3, '7003': 10,
};
// Peso, lunghezza, volume: "(3103)002214", sei cifre dopo l'identificatore.
final _measurement = RegExp(r'^3[1-6]\d\d$');
// Questi arrivano fino alla fine del codice o al separatore (FNC1).
const _variable = {'10', '21', '22', '240', '241', '242', '243', '30', '37', '400', '403'};
const _separator = '\x1d';
final _printed = RegExp(r'\(\s*(\d{2,4})\s*\)([^(]*)');

/// Lotto e scadenza di un codice GS1: il valore grezzo del lettore
/// ("0108001847003563...") o la riga stampata sotto le barre
/// ("(01)98001847003563(3103)002214(10)2366(15)261122").
LabelHints gs1Hints(String code) {
  final fields = _identifiers(code.replaceAll('（', '(').replaceAll('）', ')'));
  final lot = fields['10']?.trim();
  String? expiry;
  for (final id in ['17', '15']) {
    expiry ??= _date(fields[id]);
  }
  return LabelHints(lot: lot == null || lot.isEmpty ? null : lot, expiry: expiry);
}

/// Una riga di testo che e' la riga GS1 stampata: almeno due identificatori
/// fra parentesi, cosi' "(10)" da solo in un indirizzo non conta.
bool looksLikeGs1Line(String line) =>
    RegExp(r'\(\s*(?:01|10|1[57]|3\d{3})\s*\)').allMatches(line).length >= 2;

Map<String, String> _identifiers(String value) {
  if (value.contains('(')) {
    return {for (final m in _printed.allMatches(value)) m.group(1)!: m.group(2)!.trim()};
  }
  final fields = <String, String>{};
  var rest = value.startsWith(']') && value.length > 3 ? value.substring(3) : value;
  while (rest.length >= 2) {
    final id = _identifierAt(rest);
    if (id == null) break; // un identificatore sconosciuto: meglio niente che mezzo lotto
    final body = rest.substring(id.length);
    final width = _fixedLength[id] ?? (_measurement.hasMatch(id) ? 6 : null);
    if (width != null) {
      fields[id] = body.substring(0, width.clamp(0, body.length));
      rest = body.length > width ? body.substring(width) : '';
      continue;
    }
    final at = body.indexOf(_separator);
    fields[id] = at < 0 ? body : body.substring(0, at);
    rest = at < 0 ? '' : body.substring(at + 1);
  }
  return fields;
}

String? _identifierAt(String rest) {
  for (final width in [4, 3, 2]) {
    if (rest.length < width) continue;
    final c = rest.substring(0, width);
    if (_fixedLength.containsKey(c) || _variable.contains(c)) return c;
    if (width == 4 && _measurement.hasMatch(c)) return c;
  }
  return null;
}

/// AAMMGG, con giorno 00 = fine mese. Come la scriverebbe la cucina.
String? _date(String? digits) {
  if (digits == null || !RegExp(r'^\d{6}$').hasMatch(digits)) return null;
  final year = 2000 + int.parse(digits.substring(0, 2));
  final month = int.parse(digits.substring(2, 4));
  var day = int.parse(digits.substring(4, 6));
  if (month < 1 || month > 12) return null;
  final last = DateTime(year, month + 1, 0).day;
  if (day == 0) day = last;
  if (day > last) return null;
  return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
}
