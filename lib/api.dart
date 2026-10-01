import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String kServer = 'https://etichette-margherita.duckdns.org';
const String kApi = '$kServer/app/api/v1';

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Il collegamento al server delle etichette: accesso, richieste JSON,
/// invio foto e download. Una sola istanza per tutta l'app.
class Api {
  Api._();
  static final Api instance = Api._();

  final _storage = const FlutterSecureStorage();
  final http.Client _client = http.Client();

  String? token;
  String userName = '';
  bool isAdmin = false;

  /// Chiamata quando il server dice che l'accesso non vale piu'.
  void Function()? onLoggedOut;

  Map<String, String> get authHeaders => {if (token != null) 'Authorization': 'Bearer $token'};

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$kApi$path').replace(queryParameters: (query == null || query.isEmpty) ? null : query);

  /// Rientra con l'accesso salvato. Senza rete si fida di quello salvato:
  /// la prima richiesta vera dira' se e' ancora valido.
  Future<bool> restore() async {
    token = await _storage.read(key: 'token');
    if (token == null) return false;
    userName = await _storage.read(key: 'nome') ?? '';
    isAdmin = await _storage.read(key: 'admin') == '1';
    // Qui un accesso scaduto porta gia' alla schermata di accesso: niente
    // secondo salto da onLoggedOut.
    final callback = onLoggedOut;
    onLoggedOut = null;
    try {
      final me = await get('/me');
      userName = me['utente']['nome'] as String;
      isAdmin = me['utente']['admin'] == true;
      await _saveUser();
      return true;
    } on ApiError catch (e) {
      if (e.status == 401) return false;
      return true;
    } finally {
      onLoggedOut = callback;
    }
  }

  Future<void> login(String name, String pin) async {
    final body = await post('/login', {'nome': name, 'pin': pin, 'dispositivo': await _deviceName()});
    token = body['token'] as String;
    userName = body['utente']['nome'] as String;
    isAdmin = body['utente']['admin'] == true;
    await _storage.write(key: 'token', value: token);
    await _saveUser();
  }

  /// "Samsung SM-A546B · Android 14": cosi' l'amministratore riconosce i
  /// telefoni collegati nella schermata Utenti.
  static Future<String> _deviceName() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.manufacturer.isEmpty ? '' : '${info.manufacturer[0].toUpperCase()}${info.manufacturer.substring(1)} ';
      return '$brand${info.model} · Android ${info.version.release}';
    } catch (_) {
      return 'Android';
    }
  }

  Future<void> _saveUser() async {
    await _storage.write(key: 'nome', value: userName);
    await _storage.write(key: 'admin', value: isAdmin ? '1' : '0');
  }

  Future<void> logout() async {
    try {
      await post('/logout', {});
    } catch (_) {}
    await _forget();
  }

  Future<void> _forget() async {
    token = null;
    await _storage.delete(key: 'token');
  }

  Future<Map<String, dynamic>> _decode(http.Response r) async {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      body = {'ok': false, 'errore': 'Risposta non valida dal server (${r.statusCode})'};
    }
    if (r.statusCode == 401 && token != null) {
      await _forget();
      onLoggedOut?.call();
    }
    if (r.statusCode >= 400 || body['ok'] != true) {
      throw ApiError(r.statusCode, body['errore']?.toString() ?? 'Errore ${r.statusCode}');
    }
    return body;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError(0, 'Il server non risponde: riprova tra poco');
    } on SocketException {
      throw ApiError(0, 'Server non raggiungibile: controlla la connessione');
    } on http.ClientException {
      throw ApiError(0, 'Server non raggiungibile: controlla la connessione');
    } on HandshakeException {
      throw ApiError(0, 'Connessione sicura non riuscita: riprova');
    }
  }

  static const _timeout = Duration(seconds: 30);

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) => _guard(
      () async => _decode(await _client.get(uri(path, query), headers: authHeaders).timeout(_timeout)));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) => _guard(() async => _decode(
      await _client
          .post(uri(path), headers: {...authHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout)));

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) => _guard(() async => _decode(
      await _client
          .patch(uri(path), headers: {...authHeaders, 'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout)));

  Future<Map<String, dynamic>> delete(String path) => _guard(
      () async => _decode(await _client.delete(uri(path), headers: authHeaders).timeout(_timeout)));

  /// Una foto al server: nuova scheda (`/foto`) o foto in piu' di una
  /// scheda (`/schede/ID/foto`).
  Future<Map<String, dynamic>> uploadPhoto(String path, File photo, {String caption = ''}) =>
      _guard(() async {
        final request = http.MultipartRequest('POST', uri(path))
          ..headers.addAll(authHeaders)
          ..files.add(await http.MultipartFile.fromPath('foto', photo.path, filename: 'foto.jpg'));
        if (caption.trim().isNotEmpty) request.fields['didascalia'] = caption.trim();
        final streamed = await _client.send(request).timeout(const Duration(minutes: 3));
        return _decode(await http.Response.fromStream(streamed));
      });

  /// Immagini e file (etichetta PNG, esportazioni): i byte, o un errore.
  Future<List<int>> bytes(String path, [Map<String, String>? query]) => _guard(() async {
        final r = await _client.get(uri(path, query), headers: authHeaders).timeout(const Duration(minutes: 2));
        if (r.statusCode >= 400) await _decode(r);
        return r.bodyBytes;
      });

  /// Scarica su file, con l'avanzamento (0..1, o null se non si sa).
  Future<File> download(String path, File target, {void Function(double?)? onProgress}) => _guard(() async {
        final request = http.Request('GET', uri(path))..headers.addAll(authHeaders);
        final response = await _client.send(request).timeout(const Duration(minutes: 1));
        if (response.statusCode >= 400) {
          await _decode(await http.Response.fromStream(response));
        }
        final total = response.contentLength;
        var done = 0;
        final sink = target.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            done += chunk.length;
            onProgress?.call(total != null && total > 0 ? done / total : null);
          }
        } finally {
          await sink.close();
        }
        return target;
      });
}
