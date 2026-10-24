import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'home.dart';
import 'item.dart';

/// Motivi proposti per "Buttato": si sceglie con un tocco, "Altro" si scrive.
const _wasteReasons = ['Scaduto', 'Alterato (muffa, odore)', 'Confezione rovinata', 'Caduto o contaminato'];

/// Finito o Buttato (revisione 23/10/2026): la scheda esce dalle scadenze e
/// non torna nell'avviso di ogni mattina; "Buttato" va nel registro degli
/// scarti con il motivo. True se la scheda e' stata chiusa.
Future<bool> closeItem(BuildContext context, int itemId, {String? product}) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(product == null ? 'Scheda #$itemId' : '$product · #$itemId',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        MenuRow(
          icon: Symbols.check_circle_rounded,
          title: 'Finito',
          subtitle: 'Usato tutto: esce dalle scadenze',
          onTap: () => Navigator.pop(context, 'finito'),
        ),
        MenuRow(
          icon: Symbols.delete_rounded,
          title: 'Buttato',
          subtitle: 'Va nel registro degli scarti, con il motivo',
          danger: true,
          onTap: () => Navigator.pop(context, 'buttato'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (kind == null || !context.mounted) return false;
  String? reason;
  if (kind == 'buttato') {
    reason = await _askReason(context);
    if (reason == null || !context.mounted) return false;
  }
  final ok = await attempt(
      context, () => Api.instance.post('/schede/$itemId/chiusura', {'tipo': kind, if (reason != null) 'motivo': reason}));
  if (ok == null) return false;
  archiveChanged.value++;
  if (context.mounted) toast(context, kind == 'finito' ? 'Segnata come finita' : 'Segnata come buttata: $reason');
  return true;
}

Future<String?> _askReason(BuildContext context) async {
  final other = TextEditingController();
  final chosen = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Perché è stato buttato?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in _wasteReasons) ActionChip(label: Text(r), onPressed: () => Navigator.pop(context, r)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: other,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Altro motivo'),
          onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, other.text.trim().isEmpty ? null : other.text.trim()),
          child: const Text('Conferma'),
        ),
      ],
    ),
  );
  other.dispose();
  return chosen;
}

/// Annulla Finito/Buttato: la scheda torna nelle scadenze.
Future<bool> reopenItem(BuildContext context, int itemId) async {
  final ok = await attempt(context, () => Api.instance.delete('/schede/$itemId/chiusura'));
  if (ok == null) return false;
  archiveChanged.value++;
  if (context.mounted) toast(context, 'Scheda riaperta: torna nelle scadenze');
  return true;
}

/// Il riquadro nella scheda di un prodotto finito o buttato.
class ClosedCard extends StatelessWidget {
  const ClosedCard(this.closure, {super.key, required this.onReopen});
  final Map<String, dynamic> closure;
  final VoidCallback onReopen;
  @override
  Widget build(BuildContext context) {
    final wasted = closure['tipo'] == 'buttato';
    final who = closure['da'] as String?;
    final reason = closure['motivo'] as String?;
    return Panel(
      color: wasted ? C.badBg : C.okBg,
      border: Border.all(color: Colors.transparent),
      child: Row(children: [
        Icon(wasted ? Symbols.delete_rounded : Symbols.check_circle_rounded, color: wasted ? C.badFg : C.okFg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(wasted ? 'Buttato' : 'Finito',
                style: TextStyle(fontWeight: FontWeight.w700, color: wasted ? C.badFg : C.okFg)),
            Text(
              [
                whenArrived(closure['quando'] as String?),
                if (who != null && who.isNotEmpty) who,
                if (reason != null && reason.isNotEmpty) reason,
              ].join(' · '),
              style: TextStyle(fontSize: 12.5, color: C.ink),
            ),
          ]),
        ),
        TextButton(onPressed: onReopen, child: const Text('Riapri')),
      ]),
    );
  }
}

/// Richiamo di un lotto: le schede del fornitore con quel lotto e tutti i
/// lotti interni che ne derivano (preparazioni comprese), come /richiamo.
class RecallScreen extends StatefulWidget {
  const RecallScreen({super.key});
  @override
  State<RecallScreen> createState() => _RecallScreenState();
}

class _RecallScreenState extends State<RecallScreen> {
  final _code = TextEditingController();
  Map<String, dynamic>? _result;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _code.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() => _busy = true);
    final body = await attempt(context, () => Api.instance.get('/richiamo', {'lotto': code}));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (body != null) _result = body;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final cards = ((r?['schede'] as List?) ?? []).cast<Map<String, dynamic>>();
    final lots = ((r?['lotti'] as List?) ?? []).cast<Map<String, dynamic>>();
    return HeaderScaffold(
      header: const NavyHeader(title: 'Richiamo lotto', subtitle: 'Dove è stato usato un lotto', back: true),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(labelText: 'Lotto del fornitore o lotto interno'),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _busy ? null : _search,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Cerca'),
          ),
        ]),
        if (r != null) ...[
          const SizedBox(height: 16),
          if (cards.isEmpty && lots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(child: Text('Nessuna scheda e nessun lotto interno con «${r['lotto']}»',
                  textAlign: TextAlign.center, style: TextStyle(color: C.muted))),
            )
          else ...[
            SectionLabel('Schede del fornitore (${cards.length})'),
            const SizedBox(height: 6),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                if (cards.isEmpty)
                  Padding(padding: const EdgeInsets.all(14), child: Text('Nessuna', style: TextStyle(color: C.muted))),
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) divider,
                  MenuRow(
                    icon: Symbols.inventory_2_rounded,
                    title: '#${cards[i]['id']} · ${cards[i]['prodotto'] ?? '—'}',
                    subtitle: [
                      if (cards[i]['produttore'] != null) cards[i]['produttore'],
                      'scad. ${itDate(cards[i]['scadenza'] as String?)}',
                      'arrivata ${whenArrived(cards[i]['arrivata_alle'] as String?)}',
                    ].join(' · '),
                    onTap: () => openItem(context, cards[i]['id'] as int),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            SectionLabel('Lotti interni derivati (${lots.length})'),
            const SizedBox(height: 6),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (lots.isEmpty)
                  Padding(padding: const EdgeInsets.all(14), child: Text('Nessuno', style: TextStyle(color: C.muted))),
                for (var i = 0; i < lots.length; i++) ...[
                  if (i > 0) divider,
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        LotTag(lots[i]['codice'] as String),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(lots[i]['prodotto'] as String? ?? '(senza nome)',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        [
                          'prod. ${itDate(lots[i]['data_produzione'] as String?)}',
                          if (lots[i]['operatore'] != null) lots[i]['operatore'],
                          lots[i]['via'],
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: C.muted),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

/// Registro di quello che e' stato buttato, mese per mese (HACCP e sprechi).
class DisposalsScreen extends StatefulWidget {
  const DisposalsScreen({super.key});
  @override
  State<DisposalsScreen> createState() => _DisposalsScreenState();
}

class _DisposalsScreenState extends State<DisposalsScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>>? _rows;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthKey => '${_month.year}-${two(_month.month)}';

  Future<void> _load() async {
    final request = ++_request;
    setState(() => _error = null);
    try {
      final body = await Api.instance.get('/scarti', {'mese': _monthKey, 'tipo': 'buttato'});
      if (mounted && request == _request) {
        setState(() => _rows = (body['chiusure'] as List).cast<Map<String, dynamic>>());
      }
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    }
  }

  void _move(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _rows = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final now = DateTime.now();
    final current = _month.year == now.year && _month.month == now.month;
    return HeaderScaffold(
      header: NavyHeader(
        title: 'Registro scarti',
        subtitle: 'Prodotti buttati e motivo',
        back: true,
        bottom: Row(children: [
          IconButton(onPressed: () => _move(-1), icon: const Icon(Symbols.chevron_left_rounded), tooltip: 'Mese prima'),
          Expanded(
            child: Text('${two(_month.month)}/${_month.year}${rows == null ? '' : ' · ${rows.length} scarti'}',
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(
              onPressed: current ? null : () => _move(1),
              icon: const Icon(Symbols.chevron_right_rounded),
              tooltip: 'Mese dopo'),
        ]),
      ),
      body: rows == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(child: Text('Niente buttato in questo mese', style: TextStyle(color: C.muted))),
                  )
                else
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) divider,
                        InkWell(
                          onTap: rows[i]['scheda'] == null ? null : () => openItem(context, rows[i]['scheda'] as int),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(rows[i]['prodotto'] as String? ?? '(senza nome)',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  whenArrived(rows[i]['quando'] as String?),
                                  rows[i]['scheda'] == null ? 'scheda eliminata' : '#${rows[i]['scheda']}',
                                  if (rows[i]['lotto'] != null) 'lotto ${rows[i]['lotto']}',
                                  if (rows[i]['scadenza'] != null) 'scad. ${itDate(rows[i]['scadenza'] as String?)}',
                                  rows[i]['motivo'] ?? 'motivo non indicato',
                                  if (rows[i]['da'] != null) rows[i]['da'],
                                ].join(' · '),
                                style: TextStyle(fontSize: 12.5, color: C.muted),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
              ]),
            ),
    );
  }
}
