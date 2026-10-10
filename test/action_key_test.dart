import 'package:etichette_margherita/action_key.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la chiave resta la stessa finche la richiesta non riesce', () {
    final k = ActionKey();
    final first = k.forRequest('lotto 7, 2 copie');
    expect(k.forRequest('lotto 7, 2 copie'), first);
  });

  test('cambia se cambiano i dati', () {
    final k = ActionKey();
    final first = k.forRequest('lotto 7, 2 copie');
    expect(k.forRequest('lotto 7, 3 copie'), isNot(first));
  });

  test('dopo la riuscita la prossima azione ha una chiave nuova', () {
    final k = ActionKey();
    final first = k.forRequest('x');
    k.done();
    expect(k.forRequest('x'), isNot(first));
  });

  test('la chiave rispetta la regola del server (8-80 fra lettere, cifre, _ e -)', () {
    final key = ActionKey().forRequest('x');
    expect(RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(key), isTrue);
    expect(key.length, 24);
  });

  test('due azioni diverse non condividono la chiave', () {
    expect(ActionKey().forRequest('x'), isNot(ActionKey().forRequest('x')));
  });
}
