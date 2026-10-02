import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'home.dart';
import 'item.dart';

enum Filter { all, today, review, app }

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
  Map<String, dynamic>? _summary;
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
      Filter.app => {'dall_app': '1'},
    };
  }

  /// Ogni caricamento ha un numero: vale solo la risposta dell'ultimo, cosi'
  /// una ricerca lenta ("ri") non copre quella appena scritta ("riso").
  int _request = 0;

  Future<void> _load() async {
    final request = ++_request;
    try {
      final body = await Api.instance.get('/schede', _query);
      var items = (body['schede'] as List).cast<Map<String, dynamic>>();
      final text = _search.text.trim();
      if (text.isNotEmpty && items.isEmpty && RegExp(r'\d').hasMatch(text)) {
        // "Riso 1/10": il nome contiene cifre, non e' un lotto.
        items = ((await Api.instance.get('/schede', {'cerca': text}))['schede'] as List).cast<Map<String, dynamic>>();
      }
      Map<String, dynamic>? summary;
      try {
        summary = await Api.instance.get('/riepilogo');
      } on ApiError {
        summary = _summary;
      }
      if (!mounted || request != _request) return;
      setState(() {
        _items = items;
        _summary = summary;
        _error = null;
        _loading = false;
      });
      _schedulePoll();
    } on ApiError catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      _schedulePoll(); // senza rete si riprova, piu' piano
    }
  }

  /// Finche' una foto e' in lettura, l'elenco si aggiorna da solo.
  ///
  /// Solo con l'Archivio davanti e l'app in primo piano (tornandoci si
  /// ricarica comunque). Ogni 5 secondi per i primi due minuti, poi ogni 20:
  /// se Qwen e' fermo una scheda resta "in lettura" per ore.
  int _pollRounds = 0;

  void _schedulePoll() {
    _poll?.cancel();
    if (!_items.any((s) => s['in_lavorazione'] == true)) {
      _pollRounds = 0;
      return;
    }
    final visible = currentTab.value == 0 &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (!visible) return;
    _pollRounds++;
    _poll = Timer(Duration(seconds: _pollRounds <= 24 ? 5 : 20), _load);
  }

  void _onSearch(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Widget _chip(String label, Filter f) {
    final on = _filter == f && _search.text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        labelStyle: TextStyle(color: on ? Colors.white : C.navy, fontWeight: FontWeight.w500),
        side: on ? BorderSide.none : const BorderSide(color: C.border),
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
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return HeaderScaffold(
      header: NavyHeader(
        title: 'Archivio',
        subtitle: s == null ? 'Etichette cucina' : 'Etichette cucina · ${s['totale']} schede',
        bottom: s == null
            ? null
            : StatStrip([
                ('${s['foto_oggi']}', 'foto oggi', Colors.white),
                ('${s['da_rivedere']}', 'da rivedere', C.statWarn),
                ('${(s['scadute'] ?? 0) + (s['entro_3'] ?? 0)}', 'in scadenza', C.statBad),
              ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: panelShadow),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cerca prodotto o lotto',
                prefixIcon: const Icon(Icons.search, color: C.muted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Cancella ricerca',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                          _load();
                        }),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _chip('Tutte', Filter.all),
              _chip('Oggi', Filter.today),
              _chip('Da rivedere', Filter.review),
              _chip('Dall\'app', Filter.app),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(child: _body()),
      ]),
    );
  }

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

String shortName(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first;
  return '${words.first} ${words[1][0].toUpperCase()}.';
}

class ItemTile extends StatelessWidget {
  const ItemTile(this.s, {super.key, this.onChanged});
  final Map<String, dynamic> s;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    // Durante il caricamento sul cloud la scheda e' gia' letta: si vede il prodotto.
    final reading = s['in_lavorazione'] == true && s['in_archiviazione'] != true;
    final who = s['dall_app'] == true ? '${shortName(s['inviata_da'])} · dall\'app' : shortName(s['inviata_da']);
    final internal = s['lotto_interno_codice'] as String?;
    return Panel(
      padding: const EdgeInsets.all(12),
      color: reading ? const Color(0xFFF5F8FF) : null,
      onTap: () async {
        await openItem(context, s['id'] as int);
        onChanged?.call();
      },
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 72, height: 72, child: ItemPhoto(s['id'] as int, mini: true)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(reading ? 'Foto in lettura' : (s['prodotto'] ?? 'Prodotto non letto'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Pill.status(s),
            ]),
            const SizedBox(height: 7),
            if (!reading)
              Row(children: [
                LotTag(s['lotto'] ?? '—'),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Scad. ${itDate(s['scadenza'])}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: C.muted)),
                ),
              ]),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                child: Text('${whenArrived(s['arrivata_alle'])} · $who',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
              ),
              if (internal != null) Text(internal, style: mono.copyWith(fontSize: 12, color: C.infoFg)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
