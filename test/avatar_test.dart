import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:etichette_margherita/ui.dart';

/// La foto profilo non deve mai cambiare l'impaginazione (12/11/2026):
/// con o senza foto il cerchio occupa esattamente la misura chiesta.
void main() {
  Widget host(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: Center(child: child));

  testWidgets('senza foto restano le iniziali, nella misura chiesta', (tester) async {
    await tester.pumpWidget(host(const Avatar('Mario Rossi', userId: 7, size: 16)));
    expect(find.text('MR'), findsOneWidget);
    expect(tester.getSize(find.byType(Avatar)), const Size(16, 16));
  });

  testWidgets('scheda arrivata da Telegram: iniziali, stessa misura di Initials', (tester) async {
    await tester.pumpWidget(host(const Avatar('Capo')));
    expect(find.text('C'), findsOneWidget);
    expect(tester.getSize(find.byType(Avatar)), const Size(44, 44));
    expect(tester.getSize(find.byType(Initials)), const Size(44, 44));
  });
}
