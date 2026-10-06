import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'pending.dart';

export 'pending.dart';

/// Versione Android.
const bool isWebApp = false;

/// "Samsung SM-A546B · Android 14": cosi' l'amministratore riconosce i
/// telefoni collegati nella schermata Utenti.
Future<String> deviceName() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final brand = info.manufacturer.isEmpty ? '' : '${info.manufacturer[0].toUpperCase()}${info.manufacturer.substring(1)} ';
    return '$brand${info.model} · Android ${info.version.release}';
  } catch (_) {
    return 'Android';
  }
}

/// Su Android il tasto indietro lo gestisce gia' l'app: niente da fare.
void onBrowserBack(void Function() back) {}

/// Un errore di rete detto in italiano, o null se non e' un errore di rete.
String? networkErrorMessage(Object error) {
  if (error is SocketException) return 'Server non raggiungibile: controlla la connessione';
  if (error is HandshakeException) return 'Connessione sicura non riuscita: riprova';
  return null;
}

/// Un file scaricato (esportazione): salvato e aperto con l'app adatta.
/// Il problema da dire all'utente, o null se e' andata.
Future<String?> deliverFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  final opened = await OpenFilex.open(file.path);
  if (opened.type == ResultType.noAppToOpen) {
    return 'Nessuna app sul telefono apre questo file (serve un lettore PDF o un foglio di calcolo)';
  }
  if (opened.type != ResultType.done) return 'File scaricato ma non aperto: ${opened.message}';
  return null;
}

/// L'APK dell'aggiornamento: salvata e passata all'installatore di Android.
/// Il problema da dire all'utente, o null se l'installazione e' partita.
Future<String?> installApk(List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/EtichetteMargherita.apk');
  if (await file.exists()) await file.delete();
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
  if (result.type == ResultType.done) return null;
  if (result.type == ResultType.permissionDenied) {
    return 'Consenti "Installa app sconosciute" per Etichette, poi riprova da Altro › Aggiornamento';
  }
  return 'Installazione non avviata: ${result.message}';
}

/// Foto delle schede salvate sul telefono (3/10/2026): riaprendo l'app non
/// si riscaricano. Una foto archiviata non cambia mai; le piu' vecchie oltre
/// le 600 si cancellano.
Directory? _photoDir;

Future<Directory> _photos() async =>
    _photoDir ??= await Directory('${(await getTemporaryDirectory()).path}/foto').create(recursive: true);

String _photoName(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

Future<List<int>?> readPhotoCache(String key) async {
  try {
    final file = File('${(await _photos()).path}/${_photoName(key)}');
    return await file.exists() ? await file.readAsBytes() : null;
  } catch (_) {
    return null;
  }
}

int _photoWrites = 0;

/// Scritta in un file temporaneo e poi rinominata: un'app chiusa a meta'
/// scrittura non lascia una foto troncata (revisione 6/10/2026).
Future<void> writePhotoCache(String key, List<int> bytes) async {
  try {
    final dir = await _photos();
    final name = _photoName(key);
    final temporary = File('${dir.path}/.$name.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename('${dir.path}/$name');
    if (++_photoWrites % 50 == 0) await _prunePhotos(dir);
  } catch (_) {
    // la cache e' solo un aiuto
  }
}

/// Le piu' vecchie oltre le 600 se ne vanno, senza bloccare l'interfaccia.
Future<void> _prunePhotos(Directory dir) async {
  final entries = <(File, DateTime)>[];
  await for (final entity in dir.list()) {
    if (entity is File) entries.add((entity, (await entity.stat()).modified));
  }
  if (entries.length <= 600) return;
  entries.sort((a, b) => a.$2.compareTo(b.$2));
  for (final (file, _) in entries.take(entries.length - 600)) {
    try {
      await file.delete();
    } catch (_) {}
  }
}

Future<void> forgetPhotoCache(String prefix) async {
  try {
    final dir = await _photos();
    final start = _photoName(prefix);
    await for (final entity in dir.list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith(start)) await entity.delete();
    }
  } catch (_) {}
}

/// L'APK di un aggiornamento gia' installato: 40-50 MB da non lasciare.
Future<void> cleanupDownloads() async {
  try {
    final file = File('${(await getTemporaryDirectory()).path}/EtichetteMargherita.apk');
    if (await file.exists()) await file.delete();
  } catch (_) {}
}

/// Su Android la pagina non si ricarica: c'e' l'aggiornamento dell'APK.
void reloadPage() {}

/// Su Android i file si scaricano e si aprono con deliverFile.
Future<bool> openDownloadLink(String url) async => false;

/// Foto scattate e non ancora inviate (con didascalia e chiave dell'invio):
/// se Android chiude l'app mentre la fotocamera e' aperta, al ritorno ci
/// sono ancora (revisione 6/10/2026). In una cartella dell'app, non nella
/// cache che il sistema puo' svuotare.
Future<Directory> _pendingDir() async =>
    Directory('${(await getApplicationSupportDirectory()).path}/in_attesa').create(recursive: true);

Future<void> savePendingPhotos(List<Uint8List> photos, String caption, String batch, int? itemId) async {
  try {
    final dir = await _pendingDir();
    await for (final entity in dir.list()) {
      await entity.delete();
    }
    if (photos.isEmpty) return;
    for (var i = 0; i < photos.length; i++) {
      await File('${dir.path}/$i.jpg').writeAsBytes(photos[i], flush: true);
    }
    await File('${dir.path}/info.json').writeAsString(
        jsonEncode({'didascalia': caption, 'chiave': batch, 'scheda': itemId, 'quante': photos.length}),
        flush: true);
  } catch (_) {}
}

Future<PendingPhotos?> loadPendingPhotos() async {
  try {
    final dir = await _pendingDir();
    final info = File('${dir.path}/info.json');
    if (!await info.exists()) return null;
    final data = jsonDecode(await info.readAsString()) as Map<String, dynamic>;
    final photos = <Uint8List>[];
    for (var i = 0; i < (data['quante'] as int? ?? 0); i++) {
      final file = File('${dir.path}/$i.jpg');
      if (await file.exists()) photos.add(await file.readAsBytes());
    }
    if (photos.isEmpty) return null;
    return PendingPhotos(photos, data['didascalia'] as String? ?? '', data['chiave'] as String? ?? '',
        data['scheda'] as int?);
  } catch (_) {
    return null;
  }
}

Future<void> clearPendingPhotos() => savePendingPhotos(const [], '', '', null);
