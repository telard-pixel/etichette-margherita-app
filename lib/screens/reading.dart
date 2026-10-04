import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../ui.dart';
import 'home.dart';
import 'item.dart';

/// Dopo l'invio: aspetta che Qwen legga la foto e apre la scheda.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.itemId, required this.photos});
  final int itemId;
  final int photos;
  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  Timer? _timer;
  int _checks = 0;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    archiveChanged.value++;
    _next();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Una domanda alla volta: con la rete lenta le risposte non si
  /// accavallano e la scheda si apre una volta sola.
  void _next() => _timer = Timer(const Duration(seconds: 3), _check);

  Future<void> _check() async {
    _checks++;
    if (_checks > 40 && !_slow && mounted) setState(() => _slow = true); // oltre 2 minuti
    try {
      final body = await Api.instance.get('/schede/${widget.itemId}');
      final s = body['scheda'] as Map<String, dynamic>;
      if (!mounted) return;
      // "In lavorazione" vale fino all'archiviazione: solo allora c'e' il
      // lotto interno da stampare.
      if (s['in_lavorazione'] != true) {
        archiveChanged.value++;
        // Si sostituisce proprio questa pagina, e solo se c'e' ancora: se
        // l'utente sta tornando indietro (o sopra c'e' una finestra) un
        // pushReplacement generico sostituiva la pagina sbagliata.
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          Navigator.of(context).replace(
            oldRoute: route,
            newRoute: MaterialPageRoute<void>(builder: (_) => ItemScreen(widget.itemId)),
          );
        }
        return;
      }
    } on ApiError catch (e) {
      if (e.status == 404) {
        // Scheda eliminata nel frattempo (dal gruppo o da un amministratore).
        if (mounted) {
          toast(context, 'La scheda #${widget.itemId} è stata eliminata', error: true);
          if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.pop(context, true);
        }
        return;
      }
      // senza rete si riprova al giro dopo
    }
    if (mounted) _next();
  }

  Widget _step(String title, String detail, {required bool done, required bool running}) {
    final color = done ? C.okFg : (running ? C.infoFg : const Color(0xFFA39B8F));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done || running ? color : C.surface,
          border: Border.all(color: color, width: 2),
        ),
        child: done
            ? const Icon(Symbols.check_rounded, size: 18, color: Colors.white)
            : running
                ? const Padding(
                    padding: EdgeInsets.all(6), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : null,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: done || running ? C.ink : C.muted)),
            const SizedBox(height: 3),
            Text(detail, style: TextStyle(fontSize: 13, color: C.muted)),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => HeaderScaffold(
        header: NavyHeader(title: 'Foto inviata', subtitle: 'Scheda #${widget.itemId}', back: true),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: 220, child: ItemPhoto(widget.itemId)),
          ),
          const SizedBox(height: 16),
          Panel(padding: EdgeInsets.zero, 
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _step('Ricevuta', 'Salvata sul server · ${widget.photos} foto', done: true, running: false),
                const SizedBox(height: 16),
                _step('Lettura etichetta', 'Qwen legge prodotto, lotto, scadenza e allergeni', done: false, running: true),
                const SizedBox(height: 16),
                _step('Scheda pronta', 'Con lotto interno da stampare', done: false, running: false),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Panel(padding: EdgeInsets.zero, 
            color: C.infoTint,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(children: [
                Icon(Symbols.send_rounded, color: C.infoFg, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('La foto compare anche nel gruppo Etichette cucina con il tuo nome')),
              ]),
            ),
          ),
          if (_slow)
            Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Ci sta mettendo più del solito: la scheda arriverà comunque in archivio e nel gruppo.',
                  style: TextStyle(color: C.warnFg)),
            ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continua a scattare'),
          ),
          const SizedBox(height: 8),
          Text('Puoi chiudere: la scheda arriva lo stesso',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );
}
