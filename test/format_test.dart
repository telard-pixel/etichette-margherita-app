import 'package:flutter_test/flutter_test.dart';
import 'package:etichette_margherita/format.dart';
import 'package:etichette_margherita/screens/archive.dart' show shortName;
import 'package:etichette_margherita/screens/users.dart' show lastSeen;

/// Date e nomi come li legge la cucina (8/10/2026): scadenze e "oggi/ieri"
/// sbagliati di un giorno sono il guaio piu' facile, soprattutto col cambio
/// dell'ora.
void main() {
  group('date', () {
    test('itDate', () {
      expect(itDate('2026-10-01'), '01/10/2026');
      expect(itDate('2026-03-29T10:00:00+02:00'), '29/03/2026');
      expect(itDate(null), '—');
      expect(itDate(''), '—');
      expect(itDate('non una data'), 'non una data');
    });

    test('isoDay e addDays restano a mezzanotte anche col cambio d\'ora', () {
      expect(isoDay(DateTime(2026, 1, 5)), '2026-01-05');
      // 29/3/2026 e 25/10/2026: giorni di 23 e 25 ore in Italia.
      expect(isoDay(addDays(DateTime(2026, 3, 28), 1)), '2026-03-29');
      expect(isoDay(addDays(DateTime(2026, 3, 28), 2)), '2026-03-30');
      expect(isoDay(addDays(DateTime(2026, 10, 25), -1)), '2026-10-24');
      expect(isoDay(addDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
      expect(addDays(DateTime(2026, 3, 28, 23, 30), 1).hour, 0);
    });

    test('calendarDays conta i giorni di calendario, non le ore', () {
      expect(calendarDays(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 29, 1)), 1);
      expect(calendarDays(DateTime(2026, 3, 29), DateTime(2026, 3, 30)), 1);
      expect(calendarDays(DateTime(2026, 10, 25), DateTime(2026, 10, 26)), 1);
      expect(calendarDays(DateTime(2026, 10, 8), DateTime(2026, 10, 8, 23, 59)), 0);
      expect(calendarDays(DateTime(2026, 10, 8), DateTime(2026, 10, 1)), -7);
    });

    test('daysLabel', () {
      expect(daysLabel(-3), '3 giorni fa');
      expect(daysLabel(-1), 'ieri');
      expect(daysLabel(0), 'oggi');
      expect(daysLabel(1), 'domani');
      expect(daysLabel(5), 'tra 5 giorni');
    });

    test('daysTo', () {
      expect(daysTo(null), isNull);
      expect(daysTo('rotta'), isNull);
      expect(daysTo(isoDay(today())), 0);
      expect(daysTo(isoDay(addDays(today(), 3))), 3);
      expect(daysTo(isoDay(addDays(today(), -2))), -2);
    });

    test('whenArrived', () {
      final now = DateTime.now();
      final at = DateTime(now.year, now.month, now.day, 9, 41);
      expect(whenArrived(at.toUtc().toIso8601String()), 'Oggi 09:41');
      final yesterday = addDays(today(), -1).add(const Duration(hours: 17, minutes: 30));
      expect(whenArrived(yesterday.toUtc().toIso8601String()), 'Ieri 17:30');
      expect(whenArrived(null), '');
      expect(whenArrived('rotta'), '');
    });
  });

  group('nomi', () {
    test('shortName', () {
      expect(shortName('Michael De Pietro'), 'Michael D.');
      expect(shortName('  mario   rossi '), 'mario R.');
      expect(shortName('Damiano'), 'Damiano');
      expect(shortName(''), '');
      expect(shortName(null), '');
    });

    test('lastSeen', () {
      expect(lastSeen(null), 'mai entrato');
      expect(lastSeen('rotta'), '');
      expect(lastSeen(DateTime.now().toUtc().toIso8601String()), 'ora');
      final old = DateTime(2025, 9, 12, 10);
      expect(lastSeen(old.toUtc().toIso8601String()), '12/09');
    });
  });

  test('i 14 allergeni del regolamento', () {
    expect(allergens.length, 14);
    expect(allergens.toSet().length, 14);
  });
}
