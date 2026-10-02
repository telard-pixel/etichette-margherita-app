/// Le poche cose che sul telefono Android e nel browser si fanno in modo
/// diverso: lo stesso nome di funzione, due versioni scelte alla
/// compilazione (native.dart per Android, web.dart per la pagina web).
library;

export 'native.dart' if (dart.library.js_interop) 'web.dart';
