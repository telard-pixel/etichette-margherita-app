import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'expiring.dart';
import 'home.dart';
import 'item.dart';

enum Filter { all, today, review, expiring }

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  final _search = TextEditingController();
  Timer? _debounce, _poll;
  Filter _filter = Filter.all;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    archiveChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    archiveChanged.removeListener(_load);
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Map<String, String> get _query {
    final text = _search.text.trim();
    if (text.isNotEmpty) {
      // Un lotto ha cifre; un prodotto di solito no.
      return RegExp(r'\d').hasMatch(text) ? {'lotto': text} : {'cerca': text};
    }
    return switch (_filter) {
      Filter.all => {},
      Filter.today => {'giorno': isoDay(DateTime.now())},
      Filter.review => {'da_rivedere': '1'},
      Filter.expiring => {'scadenza_giorni': '7'},
    };
  }

  Future<void> _load() async {
    try {
      final body = await Api.instance.get('/schede', _query);
      var items = (body['schede'] as List).cast<Map<String, dynamic>>();
      final text = _search.text.trim();
      if (text.isNotEmpty && items.isEmpty && RegExp(r'\d').hasMatch(text)) {
        // "Riso 1/10": il nome contiene cifre, non e' un lotto.
        items = ((await Api.instance.get('/schede', {'cerca': text}))['schede'] as List).cast<Map<String, dynamic>>();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
      _schedulePoll();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Finche' una foto e' in lettura, l'elenco si aggiorna da solo.
  void _schedulePoll() {
    _poll?.cancel();
    if (_items.any((s) => s['in_lavorazione'] == true)) {
      _poll = Timer(const Duration(seconds: 4), _load);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Widget _chip(String label, Filter f) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _filter == f && _search.text.isEmpty,
          showCheckmark: false,
          selectedColor: C.navy,
          labelStyle: TextStyle(color: _filter == f && _search.text.isEmpty ? Colors.white : C.navy),
          onSelected: (_) {
            _search.clear();
            setState(() {
              _filter = f;
              _loading = true;
            });
            _load();
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Archivio'),
          actions: [
            IconButton(
              tooltip: 'Scadenze',
              icon: const Icon(Icons.schedule),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpiringScreen())),
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cerca prodotto o lotto',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Cancella ricerca',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _load();
                          setState(() {});
                        }),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _chip('Tutte', Filter.all),
                _chip('Oggi', Filter.today),
                _chip('Da rivedere', Filter.review),
                _chip('In scadenza', Filter.expiring),
              ],
            ),
          ),
          Expanded(child: _body()),
        ]),
      );

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return ErrorRetry(_error!, () {
        setState(() => _loading = true);
        _load();
      });
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              Center(child: Text('Nessuna scheda', style: TextStyle(color: C.muted))),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => ItemTile(_items[i], onChanged: _load),
            ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile(this.s, {super.key, this.onChanged});
  final Map<String, dynamic> s;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final reading = s['in_lavorazione'] == true;
    final who = s['dall_app'] == true ? '${s['inviata_da']} · dall\'app' : '${s['inviata_da'] ?? ''}';
    return Card(
      color: reading ? const Color(0xFFF6F9FF) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ItemScreen(s['id'] as int)));
          onChanged?.call();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 64, height: 64, child: ItemPhoto(s['id'] as int, mini: true)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(reading ? 'Foto in lettura' : (s['prodotto'] ?? 'Prodotto non letto'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Pill.status(s),
                ]),
                const SizedBox(height: 5),
                if (!reading)
                  Text.rich(
                    TextSpan(style: const TextStyle(fontSize: 13, color: C.muted), children: [
                      const TextSpan(text: 'Lotto '),
                      TextSpan(text: s['lotto'] ?? '—', style: mono.copyWith(color: C.navy)),
                      TextSpan(text: ' · Scad. ${itDate(s['scadenza'])}'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 3),
                Text('#${s['id']} · ${whenArrived(s['arrivata_alle'])} · $who',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
