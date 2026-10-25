/// Lettura del testo sul telefono, per lo scanner (25/10/2026): su Android
/// con ML Kit, senza internet; nel browser non c'e' e lo scanner fa a meno.
library;

export 'text_reader_native.dart' if (dart.library.js_interop) 'text_reader_web.dart';
