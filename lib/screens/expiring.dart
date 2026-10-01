import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'item.dart';

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
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await Api.instance.get('/schede', {'scadenza_giorni': '$_days'});
      final items = (body['schede'] as List).cast<Map<String, dynamic>>()
        ..sort((a, b) => (a['scadenza'] as String? ?? '').compareTo(b['scadenza'] as String? ?? ''));
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _row(Map<String, dynamic> s) {
    final days = daysTo(s['scadenza']) ?? 0;
    final pill = days < 0
        ? Pill(daysLabel(days), bg: C.badBg, fg: C.badFg)
        : days <= 3
            ? Pill(daysLabel(days), bg: C.warnBg, fg: C.warnFg)
            : Pill(daysLabel(days), bg: C.infoBg, fg: C.infoFg);
    return Card(
      child: ListTile(
        title: Text(s['prodotto'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Scad. ${itDate(s['scadenza'])} · lotto ${s['lotto'] ?? '—'}'),
        trailing: pill,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemScreen(s['id'] as int))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? [];
    final expired = items.where((s) => (daysTo(s['scadenza']) ?? 0) < 0).toList();
    final soon = items.where((s) => (daysTo(s['scadenza']) ?? 99) >= 0 && (daysTo(s['scadenza']) ?? 99) <= 3).toList();
    final later = items.where((s) => (daysTo(s['scadenza']) ?? -1) > 3).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Scadenze')),
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
                      onSelected: (_) {
                        setState(() => _days = d);
                        _load();
                      },
                    ),
                ]),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(child: Text('Niente in scadenza', style: TextStyle(color: C.muted))),
                  ),
                for (final (title, color, list) in [
                  ('Scadute (ultima settimana)', C.badFg, expired),
                  ('Entro 3 giorni', C.warnFg, soon),
                  ('Entro $_days giorni', C.muted, later),
                ])
                  if (list.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SectionLabel(title, color: color),
                    const SizedBox(height: 8),
                    for (final s in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: _row(s)),
                  ],
              ]),
            ),
    );
  }
}
