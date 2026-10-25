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

  test('mazzancolle: "Lotto:" e il codice in due colonne', () {
    final h = findLabelHints([
      'Prodotto e congelato il:',
      '05/12/2025',
      'Da consumarsi preferibilmente entro fine:',
      '12/2027',
      'Lotto:',
      '2533991502',
    ]);
    expect(h.lot, '2533991502');
    expect(h.expiry, '12/2027');
  });

  test('il codice letto prima della parola, saltando la data', () {
    expect(findLabelHints(['2533991502', 'Lotto:', '12/2027']).lot, '2533991502');
    expect(findLabelHints(['Lotto:', '12/2027', 'LK232DD-R']).lot, 'LK232DD-R');
  });

  test('"Lotto:" da solo senza un codice vicino non inventa niente', () {
    expect(findLabelHints(['Lotto:', 'vedi retro']).hasLot, isFalse);
  });

  test('funghi: data attaccata all\'ora del timbro', () {
    final h = findLabelHints(['LK 232 DD-R', '20/08/203009:11']);
    expect(h.expiry, '20/08/2030');
    expect(h.hasLot, isTrue);
  });

  test('l\'ora attaccata non rende data un numero qualsiasi', () {
    expect(findLabelHints(['Tel. 0376/655737']).hasExpiry, isFalse);
  });

  test('calamaro: lotto dopo altre parole, preferito alla data', () {
    final h = findLabelHints([
      'PRODOTTO IL: 26/01/2026',
      'LOTTO / CONGELATO IL : 27/01/2026',
      'DA CONSUMARSI PREFERIBILMENTE 01/2028',
      'ENTRO FINE',
      'Lotto rintracciabilità cliente : CR 260093',
    ]);
    expect(h.lot, 'CR 260093');
    expect(h.expiry, '01/2028');
  });

  test('calamaro: parole e codice in due colonne', () {
    expect(findLabelHints(['Lotto rintracciabilità cliente :', 'CR 260093']).lot, 'CR 260093');
  });

  test('Spinelli: mese in lettere', () {
    expect(findLabelHints(['DA CONSUMARSI', 'ENTRO IL', '01·NOV·26']).expiry, '01·NOV·26');
    expect(findLabelHints(['Scad. 15 GIU 2027']).expiry, '15 GIU 2027');
    expect(findLabelHints(['BBD 01-DEC-26']).expiry, '01-DEC-26');
  });

  test('il mese in lettere non scambia parole per date', () {
    expect(findLabelHints(['2 mele, 3 nove']).hasExpiry, isFalse);
    expect(findLabelHints(['Origine: Italia 100%']).hasExpiry, isFalse);
  });
}
