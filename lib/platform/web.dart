import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'pending.dart';

export 'pending.dart';

/// Versione per il browser (la pagina web dell'app).
const bool isWebApp = true;

/// "Chrome su Android", "Safari su iPhone"...: abbastanza per riconoscere
/// il dispositivo nella schermata Utenti.
Future<String> deviceName() async {
  final ua = web.window.navigator.userAgent;
  String browser = 'Browser';
  if (ua.contains('Edg/')) {
    browser = 'Edge';
  } else if (ua.contains('Chrome/')) {
    browser = 'Chrome';
  } else if (ua.contains('Firefox/')) {
    browser = 'Firefox';
  } else if (ua.contains('Safari/')) {
    browser = 'Safari';
  }
  String system = '';
  if (ua.contains('iPhone')) {
    system = 'iPhone';
  } else if (ua.contains('iPad')) {
    system = 'iPad';
  } else if (ua.contains('Android')) {
    system = 'Android';
  } else if (ua.contains('Windows')) {
    system = 'Windows';
  } else if (ua.contains('Mac OS')) {
    system = 'Mac';
  }
  return system.isEmpty ? '$browser (web)' : '$browser su $system (web)';
}

/// Nel browser gli errori di rete arrivano gia' come ClientException.
String? networkErrorMessage(Object error) => null;

/// Un file scaricato (esportazione): lo scarica il browser, come un
/// download qualsiasi.
Future<String?> deliverFile(String name, List<int> bytes) async {
  final blob = web.Blob([Uint8List.fromList(bytes).toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final link = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = name;
  web.document.body?.append(link);
  link.click();
  link.remove();
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  return null;
}

/// Il gesto "indietro" del browser (vedi tool/web_tweak.py) chiama questa
/// funzione invece di lasciare la pagina.
void onBrowserBack(void Function() back) {
  globalContext.setProperty('etichetteIndietro'.toJS, back.toJS);
}

/// Nel browser non c'e' niente da installare: la pagina si aggiorna da sola.
Future<String?> installApk(List<int> bytes) async => 'Nella versione web l\'app si aggiorna da sola';

/// Nel browser ci pensa la sua cache (le foto arrivano con ETag e
/// Cache-Control): qui non serve salvarle a parte.
Future<List<int>?> readPhotoCache(String key) async => null;

Future<void> writePhotoCache(String key, List<int> bytes) async {}

Future<void> forgetPhotoCache(String prefix) async {}


/// Il browser ha gia' la sua cache: nessun APK da pulire.
Future<void> cleanupDownloads() async {}

/// Carica la versione nuova della pagina (vedi Updater sul web).
void reloadPage() => web.window.location.reload();

/// Apre un link di scaricamento firmato dal server (esportazioni): sull'iPhone
/// un file passato al browser in memoria spesso non si salvava, un link vero
/// lo apre Safari stesso. Va chiamata direttamente dal tocco dell'utente.
Future<bool> openDownloadLink(String url) async {
  final link = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener';
  web.document.body?.append(link);
  link.click();
  link.remove();
  return true;
}

/// Il pannello "Condividi" del telefono con il file (28/10/2026): da li' si
/// salva su File, si manda con WhatsApp o Mail, o si chiude e si resta
/// nell'app. Aprire il PDF con un link, nella webapp messa nella schermata
/// Home dell'iPhone, lo mostrava a tutto schermo senza nessun tasto per
/// tornare indietro. False dove il browser non sa condividere file (il
/// computer): li' si usa il link. Va chiamata direttamente dal tocco.
bool shareFile(String name, List<int> bytes) {
  final type = name.endsWith('.pdf')
      ? 'application/pdf'
      : name.endsWith('.xlsx')
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv';
  final file = web.File([Uint8List.fromList(bytes).toJS].toJS, name, web.FilePropertyBag(type: type));
  final data = web.ShareData(files: [file].toJS);
  final navigator = web.window.navigator;
  if (!navigator.has('canShare') || !navigator.canShare(data)) return false;
  navigator.share(data).toDart.ignore(); // chiuso senza scegliere: va bene cosi'
  return true;
}

// Foto scattate e non ancora inviate, in IndexedDB: Safari sull'iPhone puo'
// ricaricare la pagina mentre la fotocamera e' aperta, e prima le foto (in
// memoria) andavano perse (revisione 6/10/2026).

Future<JSAny?> _done(web.IDBRequest request) {
  final completer = Completer<JSAny?>();
  request.onsuccess = ((web.Event _) => completer.complete(request.result)).toJS;
  request.onerror = ((web.Event _) => completer.completeError('IndexedDB')).toJS;
  return completer.future;
}

Future<web.IDBDatabase> _openDb() {
  final completer = Completer<web.IDBDatabase>();
  final request = web.window.indexedDB.open('etichette', 1);
  request.onupgradeneeded = ((web.Event _) {
    (request.result as web.IDBDatabase).createObjectStore('in_attesa');
  }).toJS;
  request.onsuccess = ((web.Event _) => completer.complete(request.result as web.IDBDatabase)).toJS;
  request.onerror = ((web.Event _) => completer.completeError('IndexedDB')).toJS;
  return completer.future;
}

Future<void> savePendingPhotos(List<Uint8List> photos, String caption, String batch, int? itemId) async {
  try {
    final db = await _openDb();
    final store = db.transaction('in_attesa'.toJS, 'readwrite').objectStore('in_attesa');
    if (photos.isEmpty) {
      await _done(store.delete('stato'.toJS));
      return;
    }
    final value = JSObject()
      ..setProperty('didascalia'.toJS, caption.toJS)
      ..setProperty('chiave'.toJS, batch.toJS)
      ..setProperty('scheda'.toJS, itemId?.toJS)
      ..setProperty('foto'.toJS, [for (final p in photos) p.toJS].toJS);
    await _done(store.put(value, 'stato'.toJS));
  } catch (_) {
    // navigazione privata o spazio pieno: le foto restano solo in memoria
  }
}

Future<PendingPhotos?> loadPendingPhotos() async {
  try {
    final db = await _openDb();
    final store = db.transaction('in_attesa'.toJS, 'readonly').objectStore('in_attesa');
    final value = await _done(store.get('stato'.toJS));
    if (value == null) return null;
    final object = value as JSObject;
    final photos = [
      for (final p in (object.getProperty<JSArray<JSUint8Array>>('foto'.toJS)).toDart) p.toDart,
    ];
    if (photos.isEmpty) return null;
    return PendingPhotos(
      photos,
      object.getProperty<JSString?>('didascalia'.toJS)?.toDart ?? '',
      object.getProperty<JSString?>('chiave'.toJS)?.toDart ?? '',
      object.getProperty<JSNumber?>('scheda'.toJS)?.toDartInt,
    );
  } catch (_) {
    return null;
  }
}

Future<void> clearPendingPhotos() => savePendingPhotos(const [], '', '', null);
