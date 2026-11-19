// Doppio ponte verso il server (19/11/2026): Funnel preferito, zrok riserva.
import 'package:etichette_margherita/server_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const funnel = 'https://funnel.example';
  const zrok = 'https://zrok.example';

  group('ServerRoutes', () {
    late DateTime now;
    late ServerRoutes routes;

    setUp(() {
      now = DateTime(2026, 11, 19, 18);
      routes = ServerRoutes([funnel, zrok], clock: () => now);
    });

    test('si parte dal preferito', () {
      expect(routes.current, funnel);
      expect(routes.onFallback, isFalse);
    });

    test('il preferito cade: si passa alla riserva e si riprova li', () {
      expect(routes.failed(funnel), zrok);
      expect(routes.current, zrok);
      expect(routes.onFallback, isTrue);
    });

    test('sulla riserva si resta 10 minuti, poi si riprova il preferito', () {
      routes.failed(funnel);
      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(routes.current, zrok);
      now = now.add(const Duration(seconds: 1));
      expect(routes.current, funnel);
      expect(routes.onFallback, isFalse);
    });

    test('il preferito ancora giu dopo i 10 minuti: altri 10 sulla riserva', () {
      routes.failed(funnel);
      now = now.add(const Duration(minutes: 10));
      expect(routes.current, funnel);
      expect(routes.failed(funnel), zrok);
      now = now.add(const Duration(minutes: 5));
      expect(routes.current, zrok);
    });

    test('cade anche la riserva: si torna al preferito, senza attesa', () {
      routes.failed(funnel);
      expect(routes.failed(zrok), funnel);
      expect(routes.current, funnel);
      expect(routes.onFallback, isFalse);
    });

    test('richieste partite insieme sul ponte caduto: solo la prima sposta la scelta', () {
      expect(routes.failed(funnel), zrok);
      // La seconda, partita anche lei su Funnel, non deve rimandare su Funnel.
      expect(routes.failed(funnel), zrok);
      expect(routes.current, zrok);
    });

    test('un errore vecchio sul preferito non sposta chi e gia sulla riserva', () {
      routes.failed(funnel);
      now = now.add(const Duration(minutes: 3));
      routes.failed(funnel);
      // Il conto dei 10 minuti parte dalla prima caduta, non si allunga.
      now = now.add(const Duration(minutes: 7));
      expect(routes.current, funnel);
    });

    test('un solo indirizzo (versione web): nessun altro ponte', () {
      final web = ServerRoutes(['https://sito.example']);
      expect(web.failed('https://sito.example'), isNull);
      expect(web.current, 'https://sito.example');
    });

    test('un indirizzo sconosciuto non cambia niente', () {
      expect(routes.failed('https://altro.example'), isNull);
      expect(routes.current, funnel);
    });

    test('nessun indirizzo: errore subito', () {
      expect(() => ServerRoutes([]), throwsArgumentError);
    });
  });

  group('routedCall', () {
    late ServerRoutes routes;
    late List<String> tried;
    bool unreachable(Object e) => e is _Down;

    setUp(() {
      routes = ServerRoutes([funnel, zrok], clock: () => DateTime(2026, 11, 19, 18));
      tried = [];
    });

    Future<String> Function(String) answer(Set<String> down) => (base) async {
          tried.add(base);
          if (down.contains(base)) throw _Down();
          return 'ok da $base';
        };

    test('tutto bene: una richiesta sola, sul preferito', () async {
      expect(await routedCall(routes, true, unreachable, answer({})), 'ok da $funnel');
      expect(tried, [funnel]);
    });

    test('preferito giu e richiesta ripetibile: rifatta sulla riserva, una volta', () async {
      expect(await routedCall(routes, true, unreachable, answer({funnel})), 'ok da $zrok');
      expect(tried, [funnel, zrok]);
      expect(routes.current, zrok);
    });

    test('preferito giu e richiesta non ripetibile: errore, ma la prossima va sulla riserva', () async {
      await expectLater(routedCall(routes, false, unreachable, answer({funnel})), throwsA(isA<_Down>()));
      expect(tried, [funnel]);
      expect(routes.current, zrok);
      expect(await routedCall(routes, false, unreachable, answer({funnel})), 'ok da $zrok');
    });

    test('giu tutti e due: errore dopo due tentativi, mai di piu', () async {
      await expectLater(routedCall(routes, true, unreachable, answer({funnel, zrok})), throwsA(isA<_Down>()));
      expect(tried, [funnel, zrok]);
      // Caduta anche la riserva: la prossima riprova dal preferito.
      expect(routes.current, funnel);
    });

    test('un errore del server (non del ponte) passa e non cambia ponte', () async {
      Future<String> serverError(String base) async {
        tried.add(base);
        throw StateError('PIN sbagliato');
      }

      await expectLater(routedCall(routes, true, unreachable, serverError), throwsStateError);
      expect(tried, [funnel]);
      expect(routes.current, funnel);
    });

    test('la riserva risponde con un errore del server: passa, la scelta resta sulla riserva', () async {
      Future<String> call(String base) async {
        tried.add(base);
        if (base == funnel) throw _Down();
        throw StateError('scheda non trovata');
      }

      await expectLater(routedCall(routes, true, unreachable, call), throwsStateError);
      expect(tried, [funnel, zrok]);
      expect(routes.current, zrok);
    });

    test('un solo indirizzo: niente secondo tentativo', () async {
      final web = ServerRoutes(['https://sito.example']);
      await expectLater(routedCall(web, true, unreachable, answer({'https://sito.example'})), throwsA(isA<_Down>()));
      expect(tried, ['https://sito.example']);
    });
  });

  group('isBridgeResponse', () {
    test('la pagina del ponte (HTML o 502/503/504 senza JSON) vuol dire non arrivata', () {
      expect(isBridgeResponse(502, 'text/plain', isJson: false), isTrue);
      expect(isBridgeResponse(503, null, isJson: false), isTrue);
      expect(isBridgeResponse(504, 'text/plain', isJson: false), isTrue);
      expect(isBridgeResponse(404, 'text/html; charset=utf-8', isJson: false), isTrue);
      expect(isBridgeResponse(200, 'TEXT/HTML', isJson: false), isTrue);
    });

    test('una risposta JSON viene sempre dal server, anche se e un errore', () {
      expect(isBridgeResponse(502, 'application/json', isJson: true), isFalse);
      expect(isBridgeResponse(503, 'text/html', isJson: true), isFalse);
      expect(isBridgeResponse(401, 'application/json', isJson: true), isFalse);
    });

    test('altri errori senza JSON non sono del ponte', () {
      expect(isBridgeResponse(500, 'text/plain', isJson: false), isFalse);
      expect(isBridgeResponse(404, 'text/plain', isJson: false), isFalse);
      expect(isBridgeResponse(413, null, isJson: false), isFalse);
    });
  });
}

class _Down implements Exception {}
