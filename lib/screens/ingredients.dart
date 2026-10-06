import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../ui.dart';

/// Preparazioni (es. cotoletta): un ingrediente da mettere sull'etichetta.
/// Da una scheda dell'archivio il bot prende prodotto e lotto com'erano in
/// quel momento; a mano, nome e lotto scritti.
class Ingredient {
  const Ingredient({required this.name, this.lot, this.itemId});
  final String name;
  final String? lot;
  final int? itemId;

  Map<String, dynamic> toJson() => itemId != null ? {'scheda': itemId} : {'nome': name, if (lot != null) 'lotto': lot};
}

/// Il lotto che il bot usera' per una scheda: quello del fornitore, o se
/// manca il lotto interno della scheda.
String? cardLot(Map<String, dynamic> item) {
  final lot = (item['lotto'] as String?)?.trim();
  if (lot != null && lot.isNotEmpty) return lot;
  // Nell'elenco delle schede il codice arriva come "lotto_interno_codice"
  // ("lotto_interno" c'e' solo aprendo la scheda): prima l'ingrediente
  // risultava "senza lotto" anche quando ce l'aveva (revisione 6/10/2026).
  return item['lotto_interno_codice'] as String? ?? (item['lotto_interno'] as Map?)?['codice'] as String?;
}

Future<Ingredient?> pickIngredient(BuildContext context) => showModalBottomSheet<Ingredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _IngredientSheet(),
    );

class _IngredientSheet extends StatefulWidget {
  const _IngredientSheet();
  @override
  State<_IngredientSheet> createState() => _IngredientSheetState();
}

class _IngredientSheetState extends State<_IngredientSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _lot = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _manual = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    final text = _search.text.trim();
    try {
      var items = ((await Api.instance.get('/schede', text.isEmpty ? {} : {'cerca': text}))['schede'] as List)
          .cast<Map<String, dynamic>>();
      if (text.isNotEmpty && items.isEmpty && RegExp(r'\d').hasMatch(text)) {
        items = ((await Api.instance.get('/schede', {'lotto': text}))['schede'] as List).cast<Map<String, dynamic>>();
      }
      if (!mounted || request != _request) return;
      setState(() {
        // Solo le schede archiviate hanno un lotto sicuro da riportare.
        _items = items.where((i) => i['stato'] == 'archived').take(40).toList();
        _loading = false;
      });
    } on ApiError {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  void _addManual() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Scrivi il nome dell\'ingrediente', error: true);
      return;
    }
    final lot = _lot.text.trim();
    Navigator.pop(context, Ingredient(name: name, lot: lot.isEmpty ? null : lot));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.8;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(children: [
              const Expanded(child: Text('Aggiungi ingrediente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              TextButton(
                onPressed: () => setState(() => _manual = !_manual),
                child: Text(_manual ? 'Dall\'archivio' : 'Scrivi a mano'),
              ),
            ]),
          ),
          if (_manual)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Ingrediente', hintText: 'Es. Pane grattugiato SG', counterText: ''),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _lot,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Lotto (facoltativo)', counterText: ''),
                  onSubmitted: (_) => _addManual(),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _addManual, child: const Text('Aggiungi')),
              ]),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _search,
                onChanged: _searchChanged,
                decoration: const InputDecoration(prefixIcon: Icon(Symbols.search_rounded), hintText: 'Cerca prodotto o lotto'),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(child: Text('Nessuna scheda trovata', style: TextStyle(color: C.muted)))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            final lot = cardLot(item);
                            final name = (item['prodotto'] as String?)?.trim();
                            return ListTile(
                              title: Text(name == null || name.isEmpty ? 'Scheda #${item['id']}' : name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  lot ?? 'senza lotto',
                                  if ((item['produttore'] ?? '').toString().isNotEmpty) item['produttore'],
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: C.muted),
                              ),
                              trailing: Icon(Symbols.add_circle_rounded, color: C.ink),
                              onTap: () => Navigator.pop(
                                context,
                                Ingredient(name: name == null || name.isEmpty ? 'Scheda #${item['id']}' : name, lot: lot, itemId: item['id'] as int),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ]),
      ),
    );
  }
}
