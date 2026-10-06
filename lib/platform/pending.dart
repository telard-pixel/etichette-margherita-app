import 'dart:typed_data';

/// Foto scattate e non ancora inviate, salvate per non perderle se il
/// telefono chiude l'app (o Safari ricarica la pagina) mentre la fotocamera
/// e' aperta. [itemId]: la scheda a cui andavano aggiunte, se non era una
/// scheda nuova.
class PendingPhotos {
  PendingPhotos(this.photos, this.caption, this.batch, this.itemId);
  final List<Uint8List> photos;
  final String caption;
  final String batch;
  final int? itemId;
}
