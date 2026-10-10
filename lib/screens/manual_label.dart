import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'home.dart';
import 'ingredients.dart';
import 'print.dart';

/// Come /etichetta: un lotto interno per un prodotto fatto in cucina, con la
/// data di produzione scelta (oggi o uno dei giorni prima).
class ManualLabelScreen extends StatefulWidget {
  const ManualLabelScreen({super.key});
  @override
  State<ManualLabelScreen> createState() => _ManualLabelScreenState();
}

class _ManualLabelScreenState extends State<ManualLabelScreen> {
  final _product = TextEditingController();
  // La data scelta a mano vale solo per il giorno in cui e' stata scelta:
  // su un telefono lasciato aperto in cucina, il mattino dopo "Oggi" deve
  // essere di nuovo oggi, non la data di ieri rimasta selezionata.
  DateTime? _picked;
  DateTime? _pickedOn;
  List<Map<String, dynamic>> _lots = [];
  List<String> _suggested = [];
  final List<Ingredient> _ingredients = [];
  bool _busy = false;

  static const _maxIngredients = 10;

  Future<void> _addIngredient() async {
    final picked = await pickIngredient(context);
    if (picked == null || !mounted) return;
    if (picked.itemId != null && _ingredients.any((i) => i.itemId == picked.itemId)) {
      toast(context, 'Ingrediente già aggiunto', error: true);
      return;
    }
    setState(() => _ingredients.add(picked));
  }

  static DateTime get _today => today();

  /// La data in vista e' sempre quella usata: a mezzanotte (o tornando
  /// sull'app il giorno dopo) si torna a "Oggi" ridisegnando la schermata.
  /// Prima la data cambiava solo dentro "Crea", senza che lo schermo lo
  /// mostrasse: scelto "Ieri" alle 23:55, il lotto delle 00:01 nasceva col
  /// giorno nuovo (revisione 6/10/2026).
  DateTime get _day => _picked ?? _today;

  Timer? _midnight;
  late final AppLifecycleListener _lifecycle;

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
    _midnight = Timer(next.difference(now), () {
      _dayChanged();
      _scheduleMidnight();
    });
  }

  void _dayChanged() {
    if (!mounted) return;
    final reset = _picked != null && _pickedOn != _today;
    setState(() {
      if (reset) _picked = null;
    });
    if (reset) {
      toast(context, 'È cambiato il giorno: la data di produzione è tornata a oggi');
      _load();
    }
  }

  @override
  void initState() {
    super.initState();
    archiveChanged.addListener(_load);
    _lifecycle = AppLifecycleListener(onResume: () {
      _dayChanged();
      _scheduleMidnight();
    });
    _scheduleMidnight();
    _load();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    _lifecycle.dispose();
    archiveChanged.removeListener(_load);
    _product.dispose();
    super.dispose();
  }

  int _request = 0;

  Future<void> _load() async {
    final request = ++_request;
    try {
      final body = await Api.instance.get('/lotti', {'giorno': isoDay(_day)});
      // Vale solo l'ultima richiesta: "Ieri" poi subito "Oggi" non deve
      // mostrare sotto "Oggi" i lotti di ieri.
      if (!mounted || request != _request) return;
      setState(() {
        _lots = (body['lotti'] as List).cast<Map<String, dynamic>>();
        _suggested = (body['suggeriti'] as List).cast<String>();
      });
    } on ApiError {
      // l'elenco del giorno e' solo un aiuto
    }
  }

  void _setDay(DateTime day) {
    setState(() {
      _picked = day == _today ? null : day;
      _pickedOn = _today;
    });
    _load();
  }

  Future<void> _otherDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: addDays(_today, -365),
      lastDate: _today,
      helpText: 'Data di produzione',
    );
    if (picked != null) _setDay(picked);
  }

  Future<void> _create({required bool print}) async {
    final product = _product.text.trim();
    if (product.isEmpty) {
      toast(context, 'Scrivi il prodotto', error: true);
      return;
    }
    setState(() => _busy = true);
    final body = await attempt(context, () => Api.instance.post('/lotti', {
          'data': isoDay(_day),
          'prodotto': product,
          if (_ingredients.isNotEmpty) 'ingredienti': [for (final i in _ingredients) i.toJson()],
        }));
    if (!mounted) return;
    setState(() => _busy = false);
    if (body == null) return;
    final lot = body['lotto_interno'] as Map<String, dynamic>;
    _product.clear();
    setState(_ingredients.clear);
    _load();
    if (print) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => PrintScreen(lot)));
    } else {
      toast(context, 'Creato il lotto ${lot['codice']}');
    }
  }

  Widget _dayChip(DateTime d) {
    final diff = calendarDays(d, _today);
    final title = diff == 0 ? 'Oggi' : (diff == 1 ? 'Ieri' : weekdays[d.weekday - 1]);
    final selected = d == _day;
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: () => _setDay(d),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          padding: EdgeInsets.zero,
          backgroundColor: selected ? C.selected : C.surface,
          foregroundColor: selected ? C.onSelected : C.ink,
          side: BorderSide(color: selected ? C.selected : C.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${d.day}/${d.month}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) addDays(_today, -i)];
    final isOther = !days.contains(_day);
    return HeaderScaffold(
      header: NavyHeader(title: 'Etichette', subtitle: 'Lotto interno per un prodotto fatto in cucina'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionLabel('Data di produzione'),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: [
              for (final d in days) _dayChip(d),
              OutlinedButton(
                onPressed: _otherDay,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                  padding: EdgeInsets.zero,
                  backgroundColor: isOther ? C.selected : C.surface,
                  foregroundColor: isOther ? C.onSelected : C.ink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(isOther ? '${_day.day}/${_day.month}/${_day.year % 100}' : 'Altra…',
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('Prodotto'),
          const SizedBox(height: 6),
          TextField(
            controller: _product,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(hintText: 'Es. Ragù di carne', counterText: ''),
          ),
          if (_suggested.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _suggested)
                ActionChip(label: Text(p), onPressed: () => setState(() => _product.text = p)),
            ]),
          ],
          const SizedBox(height: 18),
          const SectionLabel('Ingredienti (facoltativo)'),
          const SizedBox(height: 4),
          Text('Per le preparazioni: i lotti degli ingredienti vengono stampati sull\'etichetta.',
              style: TextStyle(fontSize: 12.5, color: C.muted)),
          const SizedBox(height: 8),
          if (_ingredients.isNotEmpty)
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final (index, ing) in _ingredients.indexed)
                  ListTile(
                    dense: true,
                    leading: Icon(ing.itemId != null ? Symbols.inventory_2_rounded : Symbols.edit_rounded, color: C.muted, size: 20),
                    title: Text(ing.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                    subtitle: Text(ing.lot ?? 'senza lotto', style: mono.copyWith(fontSize: 13, color: C.muted)),
                    trailing: IconButton(
                      tooltip: 'Togli',
                      icon: const Icon(Symbols.close_rounded),
                      onPressed: () => setState(() => _ingredients.removeAt(index)),
                    ),
                  ),
              ]),
            ),
          if (_ingredients.length < _maxIngredients) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _addIngredient,
              icon: const Icon(Symbols.add_rounded),
              label: const Text('Aggiungi ingrediente'),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : () => _create(print: true),
            icon: const Icon(Symbols.print_rounded),
            label: const Text('Crea e stampa'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _create(print: false),
            child: const Text('Crea solo il lotto'),
          ),
          const SizedBox(height: 22),
          SectionLabel('Lotti del ${itDate(isoDay(_day))}'),
          const SizedBox(height: 8),
          if (_lots.isEmpty)
            Text('Nessun lotto in questo giorno', style: TextStyle(color: C.muted))
          else
            Panel(padding: EdgeInsets.zero, 
              child: Column(children: [
                for (final lot in _lots.reversed)
                  ListTile(
                    title: Text(lot['prodotto'] ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${lot['codice']} · ${lot['operatore'] ?? ''}'
                        '${(lot['ingredienti'] as List? ?? []).isNotEmpty ? ' · ${(lot['ingredienti'] as List).length} ingredienti' : ''}', style: mono.copyWith(fontSize: 13, color: C.muted)),
                    trailing: const Icon(Symbols.print_rounded),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PrintScreen(lot))),
                  ),
              ]),
            ),
        ]),
      ),
    );
  }
}
