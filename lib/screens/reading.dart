import 'dart:async';

import 'package:flutter/material.dart';

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
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    _checks++;
    if (_checks > 40 && !_slow) setState(() => _slow = true); // oltre 2 minuti
    try {
      final body = await Api.instance.get('/schede/${widget.itemId}');
      final s = body['scheda'] as Map<String, dynamic>;
      if (s['in_lavorazione'] != true && mounted) {
        _timer?.cancel();
        archiveChanged.value++;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ItemScreen(widget.itemId)));
      }
    } on ApiError {
      // senza rete si riprova al giro dopo
    }
  }

  Widget _step(String title, String detail, {required bool done, required bool running}) {
    final color = done ? C.okFg : (running ? C.blue : const Color(0xFF8A96A8));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done || running ? color : Colors.white,
          border: Border.all(color: color, width: 2),
        ),
        child: done
            ? const Icon(Icons.check, size: 18, color: Colors.white)
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
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: done || running ? C.navy : C.muted)),
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(fontSize: 13, color: C.muted)),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Foto inviata · #${widget.itemId}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(height: 220, child: ItemPhoto(widget.itemId)),
          ),
          const SizedBox(height: 16),
          Card(
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
          Card(
            color: const Color(0xFFF6F9FF),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(children: [
                Icon(Icons.send, color: C.blue, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('La foto compare anche nel gruppo Etichette cucina con il tuo nome')),
              ]),
            ),
          ),
          if (_slow)
            const Padding(
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
          const Text('Puoi chiudere: la scheda arriva lo stesso',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );
}
