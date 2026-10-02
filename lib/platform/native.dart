import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

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
