import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

/// Nel browser non c'e' niente da installare: la pagina si aggiorna da sola.
Future<String?> installApk(List<int> bytes) async => 'Nella versione web l\'app si aggiorna da sola';
