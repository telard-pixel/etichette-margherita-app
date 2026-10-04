import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../ui.dart';

/// Anteprima dell'etichetta e stampa. Come nel bot: la stampa parte dopo
/// qualche secondo e si puo' annullare; premere di nuovo somma le copie.
class PrintScreen extends StatefulWidget {
  const PrintScreen(this.lot, {super.key});
  final Map<String, dynamic> lot;
  @override
  State<PrintScreen> createState() => _PrintScreenState();
}

class _PrintScreenState extends State<PrintScreen> {
  Uint8List? _png;
  String? _error;
  int _copies = 1;
  Map<String, dynamic>? _job;
  Timer? _poll;
  bool? _printerReady;

  int get _lotId => widget.lot['id'] as int;

  @override
  void initState() {
    super.initState();
    _loadLabel();
    _checkPrinter();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadLabel() async {
    try {
      final data = await Api.instance.bytes('/lotti/$_lotId/etichetta.png');
      if (mounted) setState(() => _png = Uint8List.fromList(data));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _checkPrinter() async {
    try {
      final body = await Api.instance.get('/salute');
      if (mounted) setState(() => _printerReady = body['stampante_collegata'] == true);
    } on ApiError {
      // non decisivo: lo dira' la stampa
    }
  }

  bool get _waiting => _job != null && (_job!['stato'] == 'in_attesa' || _job!['stato'] == 'in_stampa');

  /// Cambia a ogni azione: una risposta del controllo periodico partita
  /// prima di "Annulla" non deve rimettere in pagina il conto alla rovescia.
  int _generation = 0;
  bool _sending = false;

  Future<void> _print() async {
    if (_sending) return; // doppio tocco = una sola richiesta
    setState(() => _sending = true);
    final body = await printRequest(context, '/lotti/$_lotId/stampa', {'copie': _copies});
    if (mounted) setState(() => _sending = false);
    if (body == null || !mounted) return;
    _generation++;
    setState(() => _job = body['stampa'] as Map<String, dynamic>);
    _follow();
  }

  void _follow() {
    _poll?.cancel();
    final generation = _generation;
    _poll = Timer(const Duration(seconds: 1), () async {
      final id = _job?['id'];
      if (id == null) return;
      try {
        final body = await Api.instance.get('/stampe/$id');
        if (!mounted || generation != _generation) return;
        setState(() => _job = body['stampa'] as Map<String, dynamic>);
        if (!_waiting) {
          _announce();
          return;
        }
      } on ApiError catch (e) {
        if (e.status == 404) {
          // Il server e' ripartito e la coda in memoria non c'e' piu'.
          if (mounted) {
            setState(() => _job = null);
            toast(context, 'Stato della stampa perso (server riavviato): controlla la stampante', error: true);
          }
          return;
        }
        // altrimenti si riprova al secondo dopo
      }
      if (mounted && generation == _generation) _follow();
    });
  }

  Future<void> _action(String action) async {
    final id = _job?['id'];
    if (id == null || _sending) return;
    _poll?.cancel();
    _generation++;
    setState(() => _sending = true);
    final body = await attempt(context, () => Api.instance.post('/stampe/$id/$action', {}));
    if (!mounted) return;
    setState(() => _sending = false);
    if (body == null) {
      _follow(); // azione non riuscita: si torna a seguire la stampa
      return;
    }
    setState(() => _job = body['stampa'] as Map<String, dynamic>);
    if (_waiting) {
      _follow();
    } else {
      _announce();
    }
  }

  void _announce() {
    final job = _job;
    if (job == null || !mounted) return;
    switch (job['stato']) {
      case 'stampata':
        toast(context, 'Stampate ${job['copie']} etichette');
      case 'annullata':
        toast(context, 'Stampa annullata');
      case 'errore':
        toast(context, 'Stampa non riuscita: ${job['messaggio']}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HeaderScaffold(
        header: NavyHeader(title: 'Etichetta', subtitle: '${widget.lot['codice'] ?? ''} · ${widget.lot['prodotto'] ?? ''}', back: true),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: C.border),
              boxShadow: [BoxShadow(color: C.line, offset: Offset(0, 2))],
            ),
            padding: const EdgeInsets.all(10),
            child: _png != null
                ? Image.memory(_png!, filterQuality: FilterQuality.none, gaplessPlayback: true)
                : SizedBox(
                    height: 160,
                    child: Center(
                      child: _error != null
                          ? Text(_error!, textAlign: TextAlign.center)
                          : const CircularProgressIndicator(),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text('Anteprima come esce dalla stampante',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 16),
          Panel(padding: EdgeInsets.zero, 
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                const Expanded(child: Text('Copie', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                IconButton.outlined(
                  tooltip: 'Meno',
                  onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                  icon: const Icon(Symbols.remove_rounded),
                ),
                SizedBox(
                  width: 44,
                  child: Text('$_copies', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                IconButton.outlined(
                  tooltip: 'Più',
                  onPressed: _copies < 20 ? () => setState(() => _copies++) : null,
                  icon: const Icon(Symbols.add_rounded),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _printerReady == null ? C.muted : (_printerReady! ? C.green : C.red),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _printerReady == null
                  ? 'Stampante: controllo…'
                  : (_printerReady! ? 'Stampante collegata' : 'Stampante non collegata'),
              style: TextStyle(color: C.muted),
            ),
          ]),
          const SizedBox(height: 20),
          if (_waiting) _queueCard() else
            FilledButton.icon(
              onPressed: _png == null || _sending ? null : _print,
              icon: const Icon(Symbols.print_rounded),
              label: Text(_copies == 1 ? 'Stampa' : 'Stampa $_copies copie'),
            ),
          const SizedBox(height: 8),
          Text('Premere più volte somma le copie (massimo 20)',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      );

  Widget _queueCard() {
    final job = _job!;
    final printing = job['stato'] == 'in_stampa';
    final seconds = job['parte_tra_secondi'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              printing ? 'Stampo ${job['copie']} copie…' : 'Stampo ${job['copie']} copie tra $seconds s',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const Icon(Symbols.print_rounded, color: C.accentOnDark),
        ]),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: printing ? null : (1 - seconds / 8).clamp(0, 1).toDouble(),
          backgroundColor: const Color(0xFF2E3748),
          color: C.accentOnDark,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: C.badFg),
              onPressed: printing || _sending ? null : () => _action('annulla'),
              child: const Text('Annulla'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: printing || _sending ? null : () => _action('ora'),
              child: const Text('Stampa ora'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextButton(
          onPressed: printing || _sending ? null : _print,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: Text('Aggiungi altre $_copies'),
        ),
      ]),
    );
  }
}
