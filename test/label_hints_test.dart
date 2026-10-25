import 'package:etichette_margherita/label_hints.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testi presi dalle foto vere dell'archivio (25/10/2026) dove lotto o
/// scadenza erano stati saltati.
void main() {
  test('cornetto: lotto e scadenza stampati', () {
    final h = findLabelHints([
      'L. 03/0752026 5,0 Kg',
      'DA CONSUMARSI PREFERIBILMENTE ENTRO IL16/03/2027',
    ]);
    expect(h.lot, '03/0752026');
    expect(h.expiry, '16/03/2027');
    expect(h.complete, isTrue);
  });

  test('Schar: BBD con anno a due cifre', () {
    final h = findLabelHints(['PD 06/05/26 14:00:49', 'BBD 06/05/27 C']);
    expect(h.hasExpiry, isTrue);
    expect(h.expiry, '06/05/27');
  });

  test('timbro sul coperchio', () {
    final h = findLabelHints(['LR 331', '27/11/2028']);
    expect(h.lot, 'LR 331');
    expect(h.expiry, '27/11/2028');
  });

  test('cartellino del pane con spazi', () {
    expect(findLabelHints(['Data conf. lotto 21 10 26']).expiry, '21 10 26');
  });

  test('data sulla riga dopo la parola', () {
    final h = findLabelHints(['Da consumarsi entro:', '10/2027']);
    expect(h.expiry, '10/2027');
  });

  test('lotto con la parola intera', () {
    expect(findLabelHints(['Lotto: L261190']).lot, 'L261190');
    expect(findLabelHints(['LOT 2609622-000001']).lot, '2609622-000001');
  });

  test('niente lotto inventato da quantita o parole', () {
    expect(findLabelHints(['L 1,5 kg']).hasLot, isFalse);
    expect(findLabelHints(['Latte intero']).hasLot, isFalse);
    expect(findLabelHints(['INGREDIENTI: farina, latte']).hasLot, isFalse);
  });

  test('niente scadenza da numeri qualsiasi', () {
    expect(findLabelHints(['Energia 1553 kJ 372 kcal']).hasExpiry, isFalse);
    expect(findLabelHints(['(01)8032584213912']).hasExpiry, isFalse);
  });

  test('merge tiene quello trovato', () {
    final a = const LabelHints(lot: 'X1');
    final b = const LabelHints(expiry: '01/2027');
    final m = a.merge(b);
    expect(m.lot, 'X1');
    expect(m.expiry, '01/2027');
  });
}
