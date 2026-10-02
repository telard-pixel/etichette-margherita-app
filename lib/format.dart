/// Date e testi come li legge la cucina.
library;

String two(int n) => n.toString().padLeft(2, '0');

/// "2026-10-01" -> "01/10/2026"; null o vuoto -> "—".
String itDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String isoDay(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

const weekdays = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];

/// Giorni di calendario fra due date, senza farsi ingannare dall'ora
/// legale: in ora locale il giorno del cambio dura 23 o 25 ore e
/// `difference().inDays` sbaglia di uno. In UTC ogni giorno dura 24 ore.
int calendarDays(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// Oggi a mezzanotte (ora locale).
DateTime today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Un giorno di calendario prima/dopo, sempre a mezzanotte (aggiungere
/// `Duration(days: 1)` a un orario locale sbaglia nei giorni del cambio d'ora).
DateTime addDays(DateTime day, int days) => DateTime(day.year, day.month, day.day + days);

/// "Oggi 09:41", "Ieri 17:30", "28/09 11:05".
String whenArrived(String? iso) {
  if (iso == null) return '';
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final time = '${two(at.hour)}:${two(at.minute)}';
  final diff = calendarDays(at, DateTime.now());
  if (diff == 0) return 'Oggi $time';
  if (diff == 1) return 'Ieri $time';
  return '${two(at.day)}/${two(at.month)} $time';
}

/// Giorni da oggi alla scadenza (negativo = scaduta), null se manca.
int? daysTo(String? iso) {
  if (iso == null) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  return calendarDays(DateTime.now(), d);
}

String daysLabel(int days) {
  if (days < -1) return '${-days} giorni fa';
  if (days == -1) return 'ieri';
  if (days == 0) return 'oggi';
  if (days == 1) return 'domani';
  return 'tra $days giorni';
}

/// I quattordici allergeni del regolamento, come li scrive l'archivio.
const allergens = [
  'glutine', 'crostacei', 'uova', 'pesce', 'arachidi', 'soia', 'latte',
  'frutta a guscio', 'sedano', 'senape', 'sesamo', 'solfiti', 'lupini', 'molluschi',
];
