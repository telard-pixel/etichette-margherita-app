import 'package:camera/camera.dart';

import '../label_hints.dart';

/// Nel browser non c'e' un lettore di testo: lo scanner non si usa.
const bool canReadText = false;

class TextReader {
  int lastLineCount = 0;
  Future<LabelHints> readFile(String path) async => LabelHints.none;
  Future<LabelHints> readFrame(CameraImage image, CameraDescription camera) async => LabelHints.none;
  Future<void> close() async {}
}
