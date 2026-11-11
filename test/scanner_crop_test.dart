import 'package:flutter_test/flutter_test.dart';
import 'package:etichette_margherita/scanner_crop.dart';

/// La foto dello scanner deve essere quella che si vedeva nella cornice
/// (11/11/2026): prima era tutto il sensore, molto piu' larga dell'anteprima.
void main() {
  group('visibleInPreview', () {
    test('telefono alto e stretto: si tengono tutta l\'altezza e il centro', () {
      // Foto 3000x4000 (3:4), anteprima 9:16, schermo 9:19,5 come l'Oppo
      // della segnalazione: si vedeva circa il 62% della larghezza.
      final rect = visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 9 / 16, viewAspect: 9 / 19.5);
      expect(rect, isNotNull);
      expect(rect!.height, 4000);
      expect(rect.top, 0);
      expect(rect.width, 1846);
      // Centrato: lo stesso margine a sinistra e a destra.
      expect(rect.left, (3000 - 1846) ~/ 2);
      expect(rect.left + rect.width, lessThanOrEqualTo(3000));
    });

    test('schermo piu\' largo dell\'anteprima: si taglia sopra e sotto', () {
      // Tablet 3:4 con anteprima 9:16: larghezza dell'anteprima, altezza ridotta.
      final rect = visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 9 / 16, viewAspect: 3 / 4);
      expect(rect, const CropRect(375, 500, 2250, 3000));
    });

    test('non si tiene mai piu\' della foto', () {
      // Foto 9:16 e anteprima 3:4: l'anteprima e' piu' larga della foto.
      final rect = visibleInPreview(photoWidth: 2250, photoHeight: 4000, streamAspect: 3 / 4, viewAspect: 0.7);
      expect(rect, isNotNull);
      expect(rect!.width, 2250);
      expect(rect.left, 0);
      expect(rect.top + rect.height, lessThanOrEqualTo(4000));
    });

    test('niente ritaglio quando non serve o non si puo\' sapere', () {
      // Schermo e foto con la stessa forma: la foto resta intera.
      expect(visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 3 / 4, viewAspect: 3 / 4), isNull);
      // Differenza sotto il 3%: non si ricomprime per cosi' poco.
      expect(visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 3 / 4, viewAspect: 0.74), isNull);
      // Foto in orizzontale: le misure dell'anteprima non valgono.
      expect(visibleInPreview(photoWidth: 4000, photoHeight: 3000, streamAspect: 9 / 16, viewAspect: 0.46), isNull);
      // Misure mancanti o senza senso.
      expect(visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 0, viewAspect: 0.46), isNull);
      expect(visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 9 / 16, viewAspect: double.nan), isNull);
      expect(visibleInPreview(photoWidth: 0, photoHeight: 0, streamAspect: 9 / 16, viewAspect: 0.46), isNull);
      // Anteprima in orizzontale: non e' il caso dello scanner.
      expect(visibleInPreview(photoWidth: 3000, photoHeight: 4000, streamAspect: 16 / 9, viewAspect: 0.46), isNull);
    });
  });
}
