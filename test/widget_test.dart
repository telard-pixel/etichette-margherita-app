import 'package:flutter_test/flutter_test.dart';
import 'package:etichette_margherita/format.dart';

void main() {
  test('data italiana', () {
    expect(itDate('2026-10-01'), '01/10/2026');
    expect(itDate(null), '—');
  });
}
