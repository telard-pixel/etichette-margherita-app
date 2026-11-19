/// Doppio collegamento al server (19/11/2026). Il server e' sulla VM di casa,
/// dietro il CGNAT: da fuori ci si arriva solo da un ponte. L'app Android ne
/// ha due: Tailscale Funnel (preferito: da 2 a 5 volte piu' svelto di zrok
/// nella prova del 19/11) e zrok (riserva, quello usato dal 17/11). Stesso
/// server dietro tutti e due: l'accesso e le schede sono le stesse.
///
/// La versione web non cambia strada: parla solo con il sito da cui e' stata
/// aperta (un altro indirizzo sarebbe un'altra origine, con un altro accesso
/// e altre foto in attesa).
///
/// Niente Flutter qui dentro: la scelta della strada si prova da sola.
library;

/// Tailscale Funnel sulla VM (porta 10000: la 443 e' di Caddy).
const String kServerFunnel = 'https://roberto-vm.taile84bd0.ts.net:10000';

/// zrok, la strada del 17/11/2026: resta come riserva.
const String kServerZrok = 'https://etichettemargherita.shares.zrok.io';

/// Quale ponte usare. Si parte sempre dal primo (il preferito). Se una
/// richiesta sul ponte in uso non arriva al server, si passa all'altro; dal
/// ponte di riserva si torna a riprovare il preferito dopo [retryPreferredAfter],
/// non a ogni richiesta: niente salti avanti e indietro con la rete che va e
/// viene.
class ServerRoutes {
  ServerRoutes(List<String> bases, {DateTime Function()? clock, this.retryPreferredAfter = const Duration(minutes: 10)})
      : bases = List.unmodifiable(bases),
        _clock = clock ?? DateTime.now {
    if (this.bases.isEmpty) throw ArgumentError('serve almeno un indirizzo del server');
  }

  final List<String> bases;
  final Duration retryPreferredAfter;
  final DateTime Function() _clock;

  int _active = 0;
  DateTime? _fallbackSince;

  /// Il ponte da usare adesso.
  String get current {
    final since = _fallbackSince;
    if (_active != 0 && since != null && !_clock().isBefore(since.add(retryPreferredAfter))) {
      _active = 0;
      _fallbackSince = null;
    }
    return bases[_active];
  }

  /// Sul ponte di riserva (per la schermata "Info").
  bool get onFallback {
    current; // fa scattare il ritorno al preferito, se e' ora
    return _active != 0;
  }

  /// Una richiesta mandata su [base] non e' arrivata al server. Se [base] era
  /// il ponte in uso si passa al successivo. Ritorna il ponte su cui
  /// riprovare, o null se non ce n'e' un altro (un solo indirizzo, o [base]
  /// sconosciuto).
  ///
  /// Con piu' richieste partite insieme sullo stesso ponte caduto solo la
  /// prima sposta la scelta: le altre trovano gia' il ponte nuovo e non la
  /// rimandano indietro.
  String? failed(String base) {
    final index = bases.indexOf(base);
    if (bases.length < 2 || index < 0) return null;
    if (index == _active) {
      _active = (index + 1) % bases.length;
      _fallbackSince = _active == 0 ? null : _clock();
    }
    final next = bases[_active];
    return next == base ? null : next;
  }
}

/// Una richiesta sul ponte in uso. Se non arriva al server ([unreachable]) il
/// ponte e' segnato come caduto: le richieste dopo vanno sull'altro. Con
/// [retry] la stessa richiesta si rifa' subito, una volta sola, sull'altro
/// ponte. Gli altri errori (quelli che il server ha risposto) passano senza
/// toccare la scelta.
Future<T> routedCall<T>(
  ServerRoutes routes,
  bool retry,
  bool Function(Object error) unreachable,
  Future<T> Function(String base) call,
) async {
  final base = routes.current;
  try {
    return await call(base);
  } catch (e) {
    if (!unreachable(e)) rethrow;
    final other = routes.failed(base);
    if (other == null || !retry) rethrow;
    try {
      return await call(other);
    } catch (e2) {
      if (unreachable(e2)) routes.failed(other);
      rethrow;
    }
  }
}

/// Una risposta che non viene dal server delle etichette ma dal ponte (zrok o
/// Funnel): la loro pagina di errore o di avviso, mai il JSON del server. Il
/// server risponde sempre JSON alle sue richieste, anche negli errori; una
/// pagina HTML, o un 502/503/504 senza JSON, vuol dire che la richiesta si e'
/// fermata nel ponte.
bool isBridgeResponse(int status, String? contentType, {required bool isJson}) {
  if (isJson) return false;
  final type = (contentType ?? '').toLowerCase();
  return status == 502 || status == 503 || status == 504 || type.startsWith('text/html');
}
