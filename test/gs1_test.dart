import 'package:etichette_margherita/gs1.dart';
import 'package:etichette_margherita/label_hints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('riga stampata della pancetta Segata (scheda #706)', () {
    final h = gs1Hints('(01)98001847003563(3103)002214(10)2366(15)261122');
    expect(h.lot, '2366');
    expect(h.expiry, '22/11/2026');
  });

  test('valore grezzo del lettore, con il separatore e senza', () {
    var h = gs1Hints('01980018470035633103002214102366\x1d15261122');
    expect(h.lot, '2366');
    expect(h.expiry, '22/11/2026');
    h = gs1Hints(']C10198001847003563172611001026A7');
    expect(h.expiry, '30/11/2026'); // giorno 00 = fine mese
    expect(h.lot, '26A7');
  });

  test('un codice che non e\' GS1 non da\' niente', () {
    expect(gs1Hints('8001847003563').hasLot, isFalse);
    expect(gs1Hints('(17)2609').hasExpiry, isFalse);
  });

  test('la riga GS1 letta nel testo vince sul resto', () {
    final h = findLabelHints([
      'LOTTO:2366',
      'DA CONSUMARSI PREF ENTRO IL: 24/08/26',
      '(01)98001847003563(3103)002214(10)2366(15)261122',
    ]);
    expect(h.expiry, '22/11/2026');
    expect(h.lot, '2366');
    expect(looksLikeGs1Line('Via Roma (10) Trento'), isFalse);
  });
}
