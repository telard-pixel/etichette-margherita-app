import 'dart:async';

import 'package:etichette_margherita/api.dart';
import 'package:etichette_margherita/screens/proposals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _p(int id, {String? lora = 'AB123', String? base = 'AB128', String? ruotata}) => {
      'scheda': id,
      'prodotto': 'Pomodoro',
      'lotto_attuale': null,
      'lora': lora,
      'base': base,
      'ruotata': ruotata,
      'creata': '2026-10-09T10:00:00+00:00',
    };

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('senza proposte non mostra niente', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(showPhoto: false, load: () async => [])));
    await tester.pumpAndSettle();
    expect(find.text('DA CONFERMARE'), findsNothing);
  });

  testWidgets('un pulsante per ciascun motore e "No, correggo io"', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(showPhoto: false, load: () async => [_p(7)])));
    await tester.pumpAndSettle();
    expect(find.text('DA CONFERMARE'), findsOneWidget);
    expect(find.text('Pomodoro'), findsOneWidget);
    expect(find.text('È AB123 (LoRA)'), findsOneWidget);
    expect(find.text('È AB128 (base)'), findsOneWidget);
    expect(find.text('No, correggo io'), findsOneWidget);
  });

  testWidgets('con un solo motore che legge, un solo pulsante di lotto', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(showPhoto: false, load: () async => [_p(7, lora: null)])));
    await tester.pumpAndSettle();
    expect(find.textContaining('(LoRA)'), findsNothing);
    expect(find.text('È AB128 (base)'), findsOneWidget);
  });

  testWidgets('con tre lettori un pulsante ciascuno, con chi ha letto cosa', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(showPhoto: false, load: () async => [_p(7, ruotata: 'ZZ999')])));
    await tester.pumpAndSettle();
    expect(find.text('È ZZ999 (foto ruotata)'), findsOneWidget);
    expect(find.text('È AB123 (LoRA)'), findsOneWidget);
    expect(find.text('È AB128 (base)'), findsOneWidget);
  });

  testWidgets('i lettori che concordano hanno un solo pulsante', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => [_p(7, lora: 'AB-123', base: 'ab123', ruotata: 'ZZ999')],
      answer: (id, choice) async {
        calls.add(choice);
        return {'ok': true, 'scelta': choice, 'lotto': 'AB-123'};
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('È AB-123 (LoRA e base)'), findsOneWidget);
    expect(find.textContaining('(base)'), findsNothing);
    await tester.tap(find.text('È AB-123 (LoRA e base)'));
    await tester.pumpAndSettle();
    expect(calls, ['lora']);
  });

  testWidgets('se ha letto solo la foto ruotata risponde ruotata', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => [_p(7, lora: null, base: null, ruotata: '8000729')],
      answer: (id, choice) async {
        calls.add(choice);
        return {'ok': true, 'scelta': choice, 'lotto': '8000729'};
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('È 8000729 (foto ruotata)'), findsOneWidget);
    await tester.tap(find.text('È 8000729 (foto ruotata)'));
    await tester.pumpAndSettle();
    expect(calls, ['ruotata']);
  });

  testWidgets('toccare un motore risponde e toglie la domanda', (tester) async {
    final calls = <String>[];
    var open = [_p(7)];
    var changed = 0;
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => open,
      answer: (id, choice) async {
        calls.add('$id:$choice');
        open = [];
        return {'ok': true, 'scelta': choice, 'lotto': 'AB123'};
      },
      onChanged: () => changed++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('È AB123 (LoRA)'));
    await tester.pumpAndSettle();
    expect(calls, ['7:lora']);
    expect(changed, 1);
    expect(find.text('È AB123 (LoRA)'), findsNothing);
  });

  testWidgets('se qualcuno ha già risposto lo dice e ricarica', (tester) async {
    var loads = 0;
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async {
        loads++;
        return loads == 1 ? [_p(7)] : [];
      },
      answer: (id, choice) async => throw ApiError(409, 'domanda già risolta'),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('È AB128 (base)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('domanda già risolta'), findsOneWidget);
    expect(loads, 2);
    expect(find.text('È AB128 (base)'), findsNothing);
  });

  testWidgets('"No, correggo io" risponde manuale e apre la scheda', (tester) async {
    final opened = <int>[];
    final calls = <String>[];
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => [_p(7)],
      answer: (id, choice) async {
        calls.add(choice);
        return {'ok': true, 'scelta': choice, 'lotto': null};
      },
      onCorrect: opened.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No, correggo io'));
    await tester.pumpAndSettle();
    expect(calls, ['manuale']);
    expect(opened, [7]);
  });

  testWidgets('nella scheda mostra solo la propria domanda', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host(LotProposalsPanel(
      onlyItem: 8,
      showPhoto: false,
      load: () async => [_p(7), _p(8)],
      answer: (id, choice) async {
        calls.add('$id:$choice');
        return {'ok': true};
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('No, correggo io'), findsOneWidget);
    await tester.tap(find.text('No, correggo io'));
    await tester.pumpAndSettle();
    expect(calls, ['8:manuale']);
  });

  testWidgets('ne mostra al massimo tre e conta le altre', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => [for (var i = 1; i <= 5; i++) _p(i)],
    )));
    await tester.pumpAndSettle();
    expect(find.text('No, correggo io'), findsNWidgets(3));
    expect(find.text('+2 da confermare'), findsOneWidget);
  });

  testWidgets('con un errore di rete tiene le domande che ha', (tester) async {
    var calls = 0;
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      refresh: const Duration(seconds: 1),
      load: () async {
        calls++;
        if (calls == 1) return [_p(7)];
        throw ApiError(0, 'Server non raggiungibile');
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('È AB123 (LoRA)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(calls, greaterThan(1));
    expect(find.text('È AB123 (LoRA)'), findsOneWidget);
  });

  testWidgets('una lettura vecchia non rimette una domanda già risolta', (tester) async {
    final slow = Completer<List<Map<String, dynamic>>>();
    var calls = 0;
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      refresh: const Duration(seconds: 1),
      load: () {
        calls++;
        if (calls == 1) return Future.value([_p(7)]);
        if (calls == 2) return slow.future;
        return Future.value(<Map<String, dynamic>>[]);
      },
      answer: (id, choice) async => {'ok': true, 'scelta': choice, 'lotto': 'AB123'},
    )));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1)); // parte la lettura lenta
    await tester.tap(find.text('È AB123 (LoRA)'));
    await tester.pumpAndSettle(); // risposta data: la domanda e' tolta
    slow.complete([_p(7)]); // arriva la lettura vecchia
    await tester.pumpAndSettle();
    expect(find.text('È AB123 (LoRA)'), findsNothing);
  });

  testWidgets('se il server non ha ancora le domande (404) non mostra niente', (tester) async {
    await tester.pumpWidget(_host(LotProposalsPanel(
      showPhoto: false,
      load: () async => throw ApiError(404, 'non trovato'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('DA CONFERMARE'), findsNothing);
  });
}
