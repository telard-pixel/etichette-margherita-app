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

/// "Oggi 09:41", "Ieri 17:30", "28/09 11:05".
String whenArrived(String? iso) {
  if (iso == null) return '';
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final time = '${two(at.hour)}:${two(at.minute)}';
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Oggi $time';
  if (diff == 1) return 'Ieri $time';
  return '${two(at.day)}/${two(at.month)} $time';
}

/// Giorni da oggi alla scadenza (negativo = scaduta), null se manca.
int? daysTo(String? iso) {
  if (iso == null) return null;
  final d = DateTime.tryParse(iso);
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
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
