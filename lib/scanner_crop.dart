/// Quale pezzo della foto scattata si vedeva nell'anteprima dello scanner
/// (11/11/2026).
///
/// L'anteprima riempie lo schermo (`BoxFit.cover`) e ne taglia i lati: su un
/// telefono alto e stretto si vede poco piu' di meta' della larghezza che il
/// sensore fotografa. La foto salvata era invece tutto il sensore, quindi
/// diversa da quello che si era inquadrato nella cornice: piu' larga, con
/// l'etichetta piu' piccola e la roba intorno. Qui si calcola il rettangolo
/// da tenere perche' la foto sia quella che si vedeva.
library;

/// Rettangolo in pixel della foto: angolo in alto a sinistra e dimensioni.
class CropRect {
  const CropRect(this.left, this.top, this.width, this.height);
  final int left, top, width, height;

  @override
  bool operator ==(Object other) =>
      other is CropRect && other.left == left && other.top == top && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CropRect($left, $top, $width x $height)';
}

/// Sotto questa differenza non vale la pena ritagliare (e ricomprimere).
const double _minimumGain = 0.03;

/// Il pezzo di una foto [photoWidth] x [photoHeight] (gia' raddrizzata, in
/// verticale) che l'anteprima mostrava.
///
/// [streamAspect] e' larghezza/altezza dell'anteprima che arriva dalla
/// fotocamera, in verticale (di solito 9/16); [viewAspect] e' larghezza/altezza
/// dello spazio dove viene disegnata. Foto e anteprima hanno lo stesso centro
/// e lo stesso lato lungo: cambia solo quanto si vede ai lati.
///
/// Con il telefono in orizzontale (20/11/2026, segnalazione della #803) foto
/// e schermo sono girati di un quarto: e' lo stesso conto con i lati
/// scambiati. [streamAspect] resta quello verticale (lato corto/lato lungo).
///
/// Restituisce `null` quando non c'e' niente da ritagliare o non si puo'
/// sapere: foto e schermo girati diversamente, misure mancanti, differenza
/// minima. In quei casi la foto resta intera, che e' come funzionava prima.
CropRect? visibleInPreview({
  required int photoWidth,
  required int photoHeight,
  required double streamAspect,
  required double viewAspect,
}) {
  if (photoWidth <= 0 || photoHeight <= 0 || photoWidth == photoHeight) return null;
  if (!(streamAspect > 0) || !(viewAspect > 0) || !streamAspect.isFinite || !viewAspect.isFinite) return null;
  if (streamAspect >= 1) return null;
  if (photoWidth > photoHeight) {
    // Foto in orizzontale: vale solo con lo schermo in orizzontale anche lui.
    if (viewAspect <= 1) return null;
    final turned = visibleInPreview(
      photoWidth: photoHeight,
      photoHeight: photoWidth,
      streamAspect: streamAspect,
      viewAspect: 1 / viewAspect,
    );
    return turned == null ? null : CropRect(turned.top, turned.left, turned.height, turned.width);
  }
  // Foto in verticale con lo schermo in orizzontale: non si sa cosa si vedeva.
  if (viewAspect > 1) return null;

  // L'anteprima, misurata nei pixel della foto: alta quanto lei.
  final streamWidth = photoHeight * streamAspect;
  double width, height;
  if (viewAspect <= streamAspect) {
    // Schermo piu' stretto dell'anteprima: tutta l'altezza, lati tagliati.
    height = photoHeight.toDouble();
    width = height * viewAspect;
  } else {
    // Schermo piu' largo: tutta la larghezza dell'anteprima, tagliata sopra e sotto.
    width = streamWidth;
    height = width / viewAspect;
  }
  // Mai piu' della foto: quello che l'anteprima mostrava in piu' non c'e'.
  if (width > photoWidth) width = photoWidth.toDouble();
  if (height > photoHeight) height = photoHeight.toDouble();

  final w = width.round().clamp(1, photoWidth);
  final h = height.round().clamp(1, photoHeight);
  if (w >= photoWidth * (1 - _minimumGain) && h >= photoHeight * (1 - _minimumGain)) return null;
  return CropRect((photoWidth - w) ~/ 2, (photoHeight - h) ~/ 2, w, h);
}
