import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../action_key.dart';
import '../api.dart';
import '../format.dart';
import '../ui.dart';

/// Stampa di piu' etichette insieme: scelta di copie e, se tra le schede ci
/// sono foto di giorni passati, una sola domanda per tutte (tenere le date di
/// allora o aprire lotti nuovi con la data di oggi). Poi la coda: parte dopo
/// qualche secondo e si puo' annullare. true se la stampa e' partita.
///
/// Una sola alla volta: con la rete lenta un secondo tocco su "Stampa"
/// mandava una seconda coda e le etichette uscivano doppie (revisione 6/10/2026).
bool _printingSelection = false;

/// Se la risposta si perde e si preme di nuovo, il server non crea una seconda coda (stessa chiave).
final _multiPrintKey = ActionKey();

Future<bool> printSelected(BuildContext context, List<Map<String, dynamic>> cards) async {
  if (_printingSelection) return false;
  _printingSelection = true;
  final busy = UnsavedFlag()..set(true);
  try {
    return await _printSelected(context, cards);
  } finally {
    _printingSelection = false;
    busy.set(false);
  }
}

Future<bool> _printSelected(BuildContext context, List<Map<String, dynamic>> cards) async {
  final todayIso = isoDay(today());
  final old = cards.where((s) => (s['giorno'] as String? ?? todayIso).compareTo(todayIso) < 0).length;
  final options = await showModalBottomSheet<(int, bool)>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PrintOptionsSheet(count: cards.length, old: old),
  );
  if (options == null || !context.mounted) return false;
  final ids = [for (final s in cards) s['id'] as int];
  final key = _multiPrintKey.forRequest('${ids.join(',')}:${options.$1}:${options.$2}');
  final body = await printRequest(context, '/stampe-multiple', {
    'schede': ids,
    'copie': options.$1,
    'apertura': options.$2,
    'chiave': key,
  });
  if (body == null) return false;
  _multiPrintKey.done();
  if (!context.mounted) return true;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => _MultiPrintScreen(body['stampa'] as Map<String, dynamic>, cards)),
  );
  return true;
}

class _PrintOptionsSheet extends StatefulWidget {
  const _PrintOptionsSheet({required this.count, required this.old});
  final int count;
  final int old;
  @override
  State<_PrintOptionsSheet> createState() => _PrintOptionsSheetState();
}

class _PrintOptionsSheetState extends State<_PrintOptionsSheet> {
  int _copies = 1;
  bool? _opening; // null = non ancora scelto (solo se ci sono foto vecchie)

  @override
  Widget build(BuildContext context) {
    final needsChoice = widget.old > 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Stampa ${widget.count} etichette', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Row(children: [
            const Expanded(child: Text('Copie per etichetta', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
            IconButton.outlined(
              tooltip: 'Meno',
              onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
              icon: const Icon(Symbols.remove_rounded),
            ),
            SizedBox(
              width: 40,
              child: Text('$_copies', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            IconButton.outlined(
              tooltip: 'Più',
              onPressed: _copies < 20 ? () => setState(() => _copies++) : null,
              icon: const Icon(Symbols.add_rounded),
            ),
          ]),
          if (needsChoice) ...[
            const SizedBox(height: 16),
            Text(
              widget.old == widget.count
                  ? 'Sono tutte foto di giorni passati: come le stampo?'
                  : '${widget.old} su ${widget.count} sono foto di giorni passati: come le stampo?',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _Choice(
              icon: Symbols.event_rounded,
              title: 'Tieni le date di allora',
              subtitle: 'Ognuna con il suo lotto interno e la data della foto',
              selected: _opening == false,
              onTap: () => setState(() => _opening = false),
            ),
            const SizedBox(height: 8),
            _Choice(
              icon: Symbols.fiber_new_rounded,
              title: 'Apertura oggi ${itDate(isoDay(today()))}',
              subtitle: 'Lotti interni nuovi con la data di oggi, con il lotto del fornitore',
              selected: _opening == true,
              onTap: () => setState(() => _opening = true),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: needsChoice && _opening == null ? null : () => Navigator.pop(context, (_copies, _opening == true)),
            icon: const Icon(Symbols.print_rounded),
            label: Text(_copies == 1 ? 'Stampa' : 'Stampa ($_copies copie ciascuna)'),
          ),
        ]),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? C.sandSoft : C.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? C.blue : C.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(icon, color: selected ? C.blue : C.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: C.muted)),
                ]),
              ),
              Icon(selected ? Symbols.radio_button_checked_rounded : Symbols.radio_button_unchecked_rounded, color: selected ? C.blue : C.faint),
            ]),
          ),
        ),
      );
}

class _MultiPrintScreen extends StatefulWidget {
  const _MultiPrintScreen(this.job, this.cards);
  final Map<String, dynamic> job;
  final List<Map<String, dynamic>> cards;
  @override
  State<_MultiPrintScreen> createState() => _MultiPrintScreenState();
}

class _MultiPrintScreenState extends State<_MultiPrintScreen> {
  late Map<String, dynamic> _job = widget.job;
  Timer? _poll;
  int _generation = 0;
  bool _sending = false;

  bool get _waiting => _job['stato'] == 'in_attesa' || _job['stato'] == 'in_stampa';

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _follow() {
    _poll?.cancel();
    final generation = _generation;
    _poll = Timer(const Duration(seconds: 1), () async {
      try {
        final body = await Api.instance.get('/stampe/${_job['id']}');
        if (!mounted || generation != _generation) return;
        setState(() => _job = body['stampa'] as Map<String, dynamic>);
        if (!_waiting) return;
      } on ApiError catch (e) {
        if (e.status == 404) {
          if (mounted) setState(() => _job = {..._job, 'stato': 'errore', 'messaggio': 'stato perso (server riavviato)'});
          return;
        }
      } catch (_) {
        // Una risposta di forma inattesa: si riprova, invece di fermare il controllo (31/10/2026).
      }
      if (mounted && generation == _generation) _follow();
    });
  }

  Future<void> _action(String action) async {
    if (_sending) return;
    _poll?.cancel();
    _generation++;
    setState(() => _sending = true);
    final body = await attempt(context, () => Api.instance.post('/stampe/${_job['id']}/$action', {}));
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (body != null) _job = body['stampa'] as Map<String, dynamic>;
    });
    if (_waiting) _follow();
  }

  @override
  Widget build(BuildContext context) {
    final count = (_job['lotti'] as List?)?.length ?? widget.cards.length;
    final waiting = _job['stato'] == 'in_attesa';
    final printing = _job['stato'] == 'in_stampa';
    final seconds = _job['parte_tra_secondi'] as int? ?? 0;
    final (icon, color, title) = switch (_job['stato']) {
      'stampata' => (Symbols.check_circle_rounded, C.okFg, 'Stampate'),
      'annullata' => (Symbols.cancel_rounded, C.muted, 'Stampa annullata'),
      'errore' => (Symbols.error_rounded, C.badFg, 'Stampa non riuscita'),
      _ => (Symbols.print_rounded, C.blue, printing ? 'Stampo…' : 'Stampo tra $seconds s'),
    };
    return HeaderScaffold(
      header: NavyHeader(title: 'Stampa etichette', subtitle: '$count etichette · ${_job['copie']} copie ciascuna', back: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Panel(
          child: Column(children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if ((_job['messaggio'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(_job['messaggio'] as String, textAlign: TextAlign.center, style: TextStyle(color: C.muted)),
            ],
            if (waiting) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: (1 - seconds / 8).clamp(0, 1).toDouble(), minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: C.badFg),
                    onPressed: _sending ? null : () => _action('annulla'),
                    child: const Text('Annulla'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(onPressed: _sending ? null : () => _action('ora'), child: const Text('Stampa ora'))),
              ]),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < widget.cards.length; i++) ...[
              if (i > 0) divider,
              ListTile(
                dense: true,
                title: Text(widget.cards[i]['prodotto'] as String? ?? 'Prodotto non letto'),
                subtitle: Text('#${widget.cards[i]['id']} · lotto ${widget.cards[i]['lotto'] ?? '—'}'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
