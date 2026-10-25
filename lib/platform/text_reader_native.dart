import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../label_hints.dart';

const bool canReadText = true;

/// ML Kit sul telefono: legge il testo di un fotogramma dell'anteprima o
/// della foto scattata e ci cerca lotto e scadenza.
class TextReader {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<LabelHints> readFile(String path) async =>
      findLabelHints(_lines(await _recognizer.processImage(InputImage.fromFilePath(path))));

  /// Un fotogramma NV21 dell'anteprima; null se il formato non e' quello atteso.
  Future<LabelHints?> readFrame(CameraImage image, CameraDescription camera) async {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (rotation == null || format == null || image.planes.length != 1) return null;
    final plane = image.planes.first;
    final input = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    return findLabelHints(_lines(await _recognizer.processImage(input)));
  }

  Future<void> close() => _recognizer.close();
}

Iterable<String> _lines(RecognizedText text) sync* {
  for (final block in text.blocks) {
    for (final line in block.lines) {
      yield line.text;
    }
  }
}
