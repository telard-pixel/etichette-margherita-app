import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'platform/platform.dart' as platform;

const String kServer = 'https://etichette-margherita.duckdns.org';
const String kApi = '$kServer/app/api/v1';

class ApiError implements Exception {
  ApiError(this.status, this.message, [this.body]);
  final int status;
  final String message;
  /// La risposta del server, se c'era (es. "serve_conferma" dell'anti-flood).
  final Map<String, dynamic>? body;
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
    try {
      token = await _storage.read(key: 'token');
      userName = await _storage.read(key: 'nome') ?? '';
      isAdmin = await _storage.read(key: 'admin') == '1';
    } catch (_) {
      // Archivio cifrato illeggibile (es. telefono ripristinato da un
      // backup): si ricomincia dall'accesso invece di restare sulla rotella.
      try {
        await _storage.deleteAll();
      } catch (_) {}
      token = null;
      return false;
    }
    if (token == null) return false;
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
    final body = await post('/login', {'nome': name, 'pin': pin, 'dispositivo': await platform.deviceName()});
    token = body['token'] as String;
    userName = body['utente']['nome'] as String;
    isAdmin = body['utente']['admin'] == true;
    await _storage.write(key: 'token', value: token);
    await _saveUser();
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
    // Solo se il token rifiutato e' quello in uso: una richiesta lunga partita
    // prima di un nuovo accesso non deve buttare fuori quello nuovo.
    final sent = r.request?.headers['Authorization'];
    if (r.statusCode == 401 && token != null && (sent == null || sent == 'Bearer $token')) {
      await _forget();
      onLoggedOut?.call();
    }
    if (r.statusCode >= 400 || body['ok'] != true) {
      throw ApiError(r.statusCode, body['errore']?.toString() ?? 'Errore ${r.statusCode}', body);
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
    } on http.ClientException {
      throw ApiError(0, 'Server non raggiungibile: controlla la connessione');
    } catch (e) {
      final message = platform.networkErrorMessage(e);
      if (message != null) throw ApiError(0, message);
      rethrow;
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
  /// scheda (`/schede/ID/foto`). I byte della foto, non un file: cosi' vale
  /// anche nel browser.
  Future<Map<String, dynamic>> uploadPhoto(String path, Uint8List photo, {String caption = '', String? key}) =>
      _guard(() async {
        final request = http.MultipartRequest('POST', uri(path))
          ..headers.addAll(authHeaders)
          ..files.add(http.MultipartFile.fromBytes('foto', photo, filename: 'foto.jpg'));
        if (caption.trim().isNotEmpty) request.fields['didascalia'] = caption.trim();
        if (key != null) request.fields['chiave'] = key;
        final streamed = await _client.send(request).timeout(const Duration(minutes: 3));
        return _decode(await http.Response.fromStream(streamed));
      });

  /// Immagini e file (etichetta PNG, esportazioni): i byte, o un errore.
  Future<List<int>> bytes(String path, [Map<String, String>? query]) => _guard(() async {
        final r = await _client.get(uri(path, query), headers: authHeaders).timeout(const Duration(minutes: 2));
        if (r.statusCode >= 400) await _decode(r);
        return r.bodyBytes;
      });

  /// Scarica tutto in memoria, con l'avanzamento (0..1, o null se non si
  /// sa): esportazioni e aggiornamento.
  Future<Uint8List> download(String path, {void Function(double?)? onProgress}) => _guard(() async {
        final request = http.Request('GET', uri(path))..headers.addAll(authHeaders);
        final response = await _client.send(request).timeout(const Duration(minutes: 1));
        if (response.statusCode >= 400) {
          await _decode(await http.Response.fromStream(response));
        }
        final total = response.contentLength;
        final data = BytesBuilder(copy: false);
        // Se la rete si pianta a meta' non si resta appesi per sempre.
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          data.add(chunk);
          onProgress?.call(total != null && total > 0 ? data.length / total : null);
        }
        if (total != null && total > 0 && data.length != total) {
          throw ApiError(0, 'Download interrotto (${data.length} di $total byte): riprova');
        }
        return data.takeBytes();
      });
}
