import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

/// «Qual è il lotto giusto?»: le domande aperte quando il LoRA e il modello
/// base non coincidono (9/10/2026), le stesse del gruppo Telegram. Un
/// pulsante per ciascun motore, oppure «No, correggo io».
///
/// Autonomo: il caricamento, la risposta e l'apertura della scheda si
/// passano come parametri (nei test, senza rete).
class LotProposalsPanel extends StatefulWidget {
  const LotProposalsPanel({
    super.key,
    this.onlyItem,
    this.showPhoto = true,
    this.load,
    this.answer,
    this.onCorrect,
    this.onChanged,
    this.reloadOn,
    this.refresh = const Duration(seconds: 30),
    this.maxShown = 3,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 6),
  });

  /// Solo la domanda di questa scheda (dentro la scheda); null = tutte.
  final int? onlyItem;
  final bool showPhoto;
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<Map<String, dynamic>> Function(int itemId, String choice)? answer;

  /// Dopo «No, correggo io»: apre la scheda per scrivere il lotto. Null =
  /// non fare niente (si e' gia' dentro la scheda).
  final void Function(int itemId)? onCorrect;

  /// Dopo una risposta: l'elenco delle schede va ricaricato.
  final VoidCallback? onChanged;
  final Listenable? reloadOn;
  final Duration refresh;
  final int maxShown;

  /// Attorno al riquadro quando c'e' (senza domande non occupa niente).
  final EdgeInsets padding;

  @override
  State<LotProposalsPanel> createState() => _LotProposalsPanelState();
}

class _LotProposalsPanelState extends State<LotProposalsPanel> {
  List<Map<String, dynamic>> _items = [];
  int? _busy;
  Timer? _timer;

  Future<List<Map<String, dynamic>>> _fetch() async {
    final load = widget.load;
    if (load != null) return load();
    final body = await Api.instance.get('/proposte');
    return (body['proposte'] as List).cast<Map<String, dynamic>>();
  }

  /// Numero dell'ultima richiesta partita: una risposta vecchia, arrivata dopo una piu' recente (o
  /// dopo la risposta di una persona), non deve rimettere a posto domande gia' risolte.
  int _request = 0;

  Future<void> _reload() async {
    final mine = ++_request;
    try {
      var list = await _fetch();
      if (mine != _request) return;
      final only = widget.onlyItem;
      if (only != null) list = list.where((p) => p['scheda'] == only).toList();
      if (mounted) setState(() => _items = list);
    } on ApiError catch (e) {
      if (mine != _request) return;
      // Server di prima delle domande (404) o accesso non valido (401, 403): niente riquadro.
      // Con la rete assente o lenta (status 0) o un errore del server si tiene quello che c'e'.
      if (mounted && (e.status == 401 || e.status == 403 || e.status == 404)) setState(() => _items = []);
    } catch (_) {
      // errore imprevisto: si tiene quello che c'e' e si riprova al giro dopo
    }
  }

  @override
  void initState() {
    super.initState();
    widget.reloadOn?.addListener(_reload);
    _timer = Timer.periodic(widget.refresh, (_) => _reload());
    _reload();
  }

  @override
  void dispose() {
    widget.reloadOn?.removeListener(_reload);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _respond(Map<String, dynamic> p, String choice) async {
    if (_busy != null) return;
    final id = p['scheda'] as int;
    setState(() => _busy = id);
    try {
      final send = widget.answer ?? (int i, String c) => Api.instance.post('/proposte/$i/risposta', {'scelta': c});
      final done = await attempt<Map<String, dynamic>>(context, () => send(id, choice));
      if (!mounted) return;
      if (done == null) {
        // 409 (qualcuno ha gia' risposto) o altro errore: si riallinea.
        await _reload();
        return;
      }
      _request++; // una lettura partita prima di questa risposta non vale piu'
      setState(() => _items = _items.where((x) => x['scheda'] != id).toList());
      widget.onChanged?.call();
      if (choice == 'manuale') {
        widget.onCorrect?.call(id);
      } else {
        toast(context, 'Lotto ${done['lotto']} confermato');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final shown = _items.take(widget.maxShown).toList();
    final more = _items.length - shown.length;
    return Padding(
      padding: widget.padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.only(bottom: 6), child: SectionLabel('Da confermare')),
        for (final p in shown) Padding(padding: const EdgeInsets.only(bottom: 8), child: _card(p)),
        if (more > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+$more da confermare', style: TextStyle(fontSize: 13, color: C.muted)),
          ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final id = p['scheda'] as int;
    final labels = {for (final (key, label) in _readers) key: label};
    final busy = _busy != null;
    return Panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.showPhoto)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 64, height: 64, child: ItemPhoto(id, size: PhotoSize.mini, cacheWidth: 192)),
            ),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((p['prodotto'] as String?) ?? 'Scheda $id', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Lotto non sicuro: i lettori non coincidono', style: TextStyle(fontSize: 13, color: C.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in lotCandidates(p))
                FilledButton.tonal(
                  onPressed: busy ? null : () => _respond(p, _choicePriority.firstWhere(c.sources.contains)),
                  child: Text('È ${c.lot} (${c.sources.map((k) => labels[k]).join(' e ')})'),
                ),
              OutlinedButton(onPressed: busy ? null : () => _respond(p, 'manuale'), child: const Text('No, correggo io')),
            ]),
          ]),
        ),
      ]),
    );
  }
}

String _fold(String value) => value.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

/// Chi legge cosa, nell'ordine in cui lo si mostra.
const _readers = [('ruotata', 'foto ruotata'), ('lora', 'LoRA'), ('base', 'base')];

/// Quale risposta scrive il lotto letto da piu' lettori insieme.
const _choicePriority = ['lora', 'base', 'ruotata'];

/// I lotti letti, ciascuno una volta, con chi li ha letti.
List<({String lot, List<String> sources})> lotCandidates(Map<String, dynamic> p) {
  final groups = <({String lot, List<String> sources})>[];
  for (final (key, _) in _readers) {
    final lot = p[key] as String?;
    if (lot == null || lot.isEmpty) continue;
    final i = groups.indexWhere((g) => _fold(g.lot) == _fold(lot));
    if (i >= 0) {
      groups[i].sources.add(key);
    } else {
      groups.add((lot: lot, sources: [key]));
    }
  }
  return groups;
}
