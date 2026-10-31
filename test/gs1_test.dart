import 'package:etichette_margherita/api.dart' show hintsFromPhotoCheck;
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

  // Revisione 31/10/2026.
  test('un Code128 che non e\' GS1 non da\' lotto ne\' scadenza', () {
    expect(isGs1Code('1023456789'), isFalse);
    expect(isGs1Code('1726031512345'), isFalse);
    expect(gs1HintsFromCodes(['1023456789', '1726031512345']).hasLot, isFalse);
    expect(gs1HintsFromCodes(['1726031512345']).hasExpiry, isFalse);
    expect(isGs1Code('0112345678901232'), isFalse); // cifra di controllo sbagliata
  });

  test('i GS1 veri si riconoscono', () {
    expect(isGs1Code('01980018470035633103002214102366\x1d15261122'), isTrue);
    expect(isGs1Code(']C10198001847003563172611001026A7'), isTrue);
    expect(isGs1Code('0198001847003563172611001026A7'), isTrue);
    expect(isGs1Code('172612311026A7'), isTrue); // due identificatori completi, senza GTIN
    final h = gs1HintsFromCodes(['1023456789', '0198001847003563172611001026A7']);
    expect(h.lot, '26A7');
    expect(h.expiry, '30/11/2026');
  });

  test('separatore in testa o dopo un campo fisso', () {
    final h = gs1Hints('\x1d0198001847003563\x1d1726113010AB12');
    expect(h.expiry, '30/11/2026');
    expect(h.lot, 'AB12');
  });

  test('identificatore sconosciuto o data impossibile: niente', () {
    expect(gs1Hints('0198001847003563991234').hasLot, isFalse);
    expect(gs1Hints('(01)98001847003563(17)261332').hasExpiry, isFalse);
    expect(gs1Hints('(01)98001847003563(17)261301').hasExpiry, isFalse);
  });

  test('il lotto stampato finisce al primo spazio', () {
    expect(gs1Hints('(01)98001847003563(10)AB12 500g').lot, 'AB12');
  });

  test('webapp: il codice letto dal server vince sulle righe di testo', () {
    final h = hintsFromPhotoCheck({
      'codici': [
        {'lotto': '2366', 'scadenza': '22/11/2026'},
      ],
      'righe': ['LOTTO: 9999', 'Scad. 24/08/26'],
    });
    expect(h.lot, '2366');
    expect(h.expiry, '22/11/2026');
    // Una risposta di forma strana non fa cadere niente.
    expect(hintsFromPhotoCheck({'codici': 'x', 'righe': null}).hasLot, isFalse);
  });
}
