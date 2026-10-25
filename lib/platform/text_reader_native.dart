import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../label_hints.dart';

const bool canReadText = true;

/// ML Kit sul telefono: legge il testo di un fotogramma dell'anteprima o
/// della foto scattata e ci cerca lotto e scadenza.
class TextReader {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Quante righe ha letto l'ultima volta: 0 righe con una foto piena di
  /// scritte vuol dire che il lettore non funziona, non che manca il lotto.
  int lastLineCount = 0;

  Future<LabelHints> readFile(String path) async =>
      _hints(await _recognizer.processImage(InputImage.fromFilePath(path)));

  /// Un fotogramma dell'anteprima. Alcuni telefoni lo danno in NV21 (un
  /// piano), altri in YUV_420_888 (tre piani) anche se si chiede NV21: il
  /// secondo si converte. Lancia un errore se il formato e' un altro, cosi'
  /// lo scanner lo segnala invece di non leggere niente in silenzio
  /// (1.0.108 su Android: nessun fotogramma letto).
  Future<LabelHints> readFrame(CameraImage image, CameraDescription camera) async {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation90deg;
    final Uint8List bytes;
    final int bytesPerRow;
    if (image.planes.length == 1) {
      bytes = image.planes.first.bytes;
      bytesPerRow = image.planes.first.bytesPerRow;
    } else if (image.planes.length == 3) {
      bytes = _yuv420ToNv21(image);
      bytesPerRow = image.width;
    } else {
      throw StateError('fotogramma non leggibile: formato ${image.format.raw}, ${image.planes.length} piani');
    }
    final input = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: bytesPerRow,
      ),
    );
    return _hints(await _recognizer.processImage(input));
  }

  LabelHints _hints(RecognizedText text) {
    final lines = [
      for (final block in text.blocks)
        for (final line in block.lines) line.text,
    ];
    lastLineCount = lines.length;
    return findLabelHints(lines);
  }

  Future<void> close() => _recognizer.close();
}

/// YUV_420_888 (Y, U, V separati, con righe e pixel che possono avere
/// spaziatura) in NV21 (Y e poi V/U alternati), il formato che ML Kit vuole.
Uint8List _yuv420ToNv21(CameraImage image) {
  final width = image.width, height = image.height;
  final y = image.planes[0], u = image.planes[1], v = image.planes[2];
  final out = Uint8List(width * height + 2 * (width ~/ 2) * (height ~/ 2));
  var i = 0;
  for (var row = 0; row < height; row++) {
    final start = row * y.bytesPerRow;
    out.setRange(i, i + width, y.bytes, start);
    i += width;
  }
  final uvRowStride = u.bytesPerRow;
  final uvPixelStride = u.bytesPerPixel ?? 1;
  for (var row = 0; row < height ~/ 2; row++) {
    for (var col = 0; col < width ~/ 2; col++) {
      final at = row * uvRowStride + col * uvPixelStride;
      out[i++] = v.bytes[at];
      out[i++] = u.bytes[at];
    }
  }
  return out;
}
