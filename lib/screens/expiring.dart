import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'home.dart';
import 'item.dart';

/// Scheda "Scadenze" del menu in basso: i prodotti in archivio con la
/// scadenza vicina, divisi in scaduti, entro 3 giorni ed entro N giorni.
class ExpiringScreen extends StatefulWidget {
  const ExpiringScreen({super.key});
  @override
  State<ExpiringScreen> createState() => _ExpiringScreenState();
}

class _ExpiringScreenState extends State<ExpiringScreen> {
  int _days = 7;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    archiveChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    archiveChanged.removeListener(_load);
    super.dispose();
  }

  int _request = 0;

  Future<void> _load() async {
    final request = ++_request;
    try {
      final body = await Api.instance.get('/schede', {'scadenza_giorni': '$_days'});
      final items = (body['schede'] as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['scadenza'] as String? ?? '').compareTo(b['scadenza'] as String? ?? ''));
      if (mounted && request == _request) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    }
  }

  Widget _row(Map<String, dynamic> s) {
    final days = daysTo(s['scadenza']) ?? 0;
    final pill = days < 0
        ? Pill(daysLabel(days), bg: C.badBg, fg: C.badFg)
        : days <= 3
            ? Pill(daysLabel(days), bg: C.warnBg, fg: C.warnFg)
            : Pill(daysLabel(days), bg: C.infoBg, fg: C.infoFg);
    return InkWell(
      onTap: () => openItem(context, s['id'] as int),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s['prodotto'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 5),
              Row(children: [
                LotTag(s['lotto'] ?? '—'),
                const SizedBox(width: 8),
                Text(itDate(s['scadenza']), style: const TextStyle(fontSize: 13, color: C.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          pill,
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    int left(Map<String, dynamic> s) => daysTo(s['scadenza']) ?? 999;
    final expired = items.where((s) => left(s) < 0).toList();
    final soon = items.where((s) => left(s) >= 0 && left(s) <= 3).toList();
    final later = items.where((s) => left(s) > 3 && left(s) <= _days).toList();
    final groups = [
      ('Scadute (ultima settimana)', C.badFg, expired),
      ('Entro 3 giorni', C.warnFg, soon),
      ('Entro $_days giorni', C.muted, later),
    ].where((g) => g.$3.isNotEmpty).toList();
    return HeaderScaffold(
      header: NavyHeader(
        title: 'Scadenze',
        subtitle: 'Prodotti in archivio con scadenza vicina',
        bottom: _items == null
            ? null
            : StatStrip([
                ('${expired.length}', 'scadute', C.statBad),
                ('${soon.length}', 'entro 3 giorni', C.statWarn),
                ('${soon.length + later.length}', 'entro $_days giorni', Colors.white),
              ]),
      ),
      body: _items == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Wrap(spacing: 8, children: [
                  for (final d in const [3, 7, 30])
                    ChoiceChip(
                      label: Text('$d giorni'),
                      selected: _days == d,
                      labelStyle: TextStyle(color: _days == d ? Colors.white : C.navy),
                      side: _days == d ? BorderSide.none : const BorderSide(color: C.border),
                      onSelected: (_) {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                ]),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('Niente in scadenza', style: TextStyle(color: C.muted))),
                  )
                else
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var g = 0; g < groups.length; g++) ...[
                        if (g > 0) divider,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                          child: SectionLabel(groups[g].$1, color: groups[g].$2),
                        ),
                        for (var i = 0; i < groups[g].$3.length; i++) ...[
                          if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: divider),
                          _row(groups[g].$3[i]),
                        ],
                      ],
                    ]),
                  ),
              ]),
            ),
    );
  }
}
