import 'dart:math';

/// Una chiave per un'azione che non deve ripetersi se la risposta si perde (stampe, lotto a mano).
///
/// Il server, a una richiesta con la stessa chiave, risponde come la prima volta senza rifare il
/// lavoro: niente copie in piu', code doppie o un secondo lotto. La chiave resta la stessa finche'
/// la richiesta non riesce, e cambia se cambiano i dati (altre copie, altre schede).
class ActionKey {
  String? _key;
  String? _fingerprint;

  /// La chiave per una richiesta con questi dati.
  String forRequest(String fingerprint) {
    if (_key == null || _fingerprint != fingerprint) {
      _key = _newKey();
      _fingerprint = fingerprint;
    }
    return _key!;
  }

  /// La richiesta e' riuscita: la prossima azione e' un'altra.
  void done() {
    _key = null;
    _fingerprint = null;
  }
}

/// 24 caratteri fra a-z e 0-9: rientra nella regola del server (8-80 fra lettere, cifre, _ e -).
String _newKey() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
}
