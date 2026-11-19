// La lente dei campi di testo spenta nella versione web (19/11/2026, foto
// della #785): ogni TextField dell'app deve passare kTextMagnifier, se no
// sull'iPhone torna l'ovale disegnato male sopra la scheda.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ogni TextField passa magnifierConfiguration: kTextMagnifier', () {
    final missing = <String>[];
    var fields = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final match in RegExp(r'\bTextField\(').allMatches(text)) {
        fields++;
        // Gli argomenti del campo: fino alla parentesi che chiude TextField(.
        var depth = 0, end = match.end - 1;
        for (; end < text.length; end++) {
          final c = text[end];
          if (c == '(') depth++;
          if (c == ')' && --depth == 0) break;
        }
        final args = text.substring(match.end, end);
        if (!args.contains('magnifierConfiguration: kTextMagnifier')) {
          final line = '\n'.allMatches(text.substring(0, match.start)).length + 1;
          missing.add('${entity.path}:$line');
        }
      }
    }
    expect(fields, greaterThanOrEqualTo(17));
    expect(missing, isEmpty, reason: 'TextField senza kTextMagnifier');
  });
}
