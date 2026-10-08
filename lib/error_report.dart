import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'platform/platform.dart' as platform;

/// Gli errori imprevisti dell'app finiscono nel log del server (8/10/2026):
/// prima un errore sul telefono restava sul telefono e lo si scopriva solo se
/// qualcuno lo raccontava. Stesso indirizzo della diagnostica della pagina
/// web, aperto e limitato dal server; dentro c'e' solo l'errore, la versione
/// e il tipo di telefono: niente schede, foto, nomi o PIN.
class ErrorReport {
  static String _version = '';
  static int _sent = 0;
  static final Set<String> _seen = {};

  /// Al massimo tante segnalazioni per avvio: un errore che si ripete a ogni
  /// disegno non deve riempire il log (ne' consumare dati).
  static const _maxPerRun = 10;

  static void install() {
    PackageInfo.fromPlatform().then((info) => _version = '${info.version}+${info.buildNumber}', onError: (_) {});
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      send(details.exception, details.stack, where: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      send(error, stack);
      return false; // resta anche il comportamento normale (log di sistema)
    };
  }

  static Future<void> send(Object error, StackTrace? stack, {String? where}) async {
    // Un server che non risponde o un accesso scaduto non sono errori dell'app.
    if (error is ApiError || error is TimeoutException || error is http.ClientException) return;
    final text = error.toString();
    final key = text.length > 200 ? text.substring(0, 200) : text;
    if (_sent >= _maxPerRun || !_seen.add(key)) return;
    _sent++;
    final lines = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(12).join(' | ');
    final body = jsonEncode({
      'evento': 'errore-app',
      'piattaforma': platform.isWebApp ? 'web' : 'android',
      'versione': _version,
      'dispositivo': await platform.deviceName(),
      'dove': ?where,
      'errore': text.length > 600 ? '${text.substring(0, 600)}…' : text,
      'stack': lines.length > 900 ? lines.substring(0, 900) : lines,
    });
    try {
      await http
          .post(Uri.parse('$kApi/web-log'), headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // senza rete la segnalazione si perde: non deve diventare un altro errore
    }
  }
}
