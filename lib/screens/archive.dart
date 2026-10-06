import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'home.dart';
import 'item.dart';
import 'multi_print.dart';

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

  /// L'elenco va a pagine (Tutte, Da rivedere, Dall'app): scorrendo in fondo
  /// arrivano le schede piu' vecchie, fino alla prima. Prima si fermava alle
  /// ultime 50 (4/10/2026).
  static const _page = 50;
  /// Quante schede chiedere ricaricando: quelle gia' mostrate scorrendo, cosi'
  /// un aggiornamento non riporta l'elenco alle prime 50.
  int _wanted = _page;
  /// Il server ne ha ancora di piu' vecchie.
  bool _more = false;
  bool _loadingMore = false;
  String? _moreError;
  /// Server di prima delle pagine (manda solo le ultime 50): le schede piu'
  /// vecchie si prendono giorno per giorno con ?giorno=, che non ha limite.
  /// Il prossimo giorno da chiedere, andando indietro.
  DateTime? _dayCursor;
  /// Schede scelte per la stampa di piu' etichette (tenendo premuta una
  /// scheda si entra nella selezione), nell'ordine in cui sono state scelte.
  final Map<int, Map<String, dynamic>> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(Map<String, dynamic> s) {
    if (s['in_lavorazione'] == true) {
      toast(context, 'Questa scheda è ancora in lettura: si potrà stampare quando è pronta');
      return;
    }
    setState(() {
      final id = s['id'] as int;
      if (_selected.remove(id) == null) _selected[id] = s;
    });
  }

  bool _printing = false;

  /// La selezione si svuota solo se la stampa e' partita: chiudendo il
  /// foglio o con "Annulla" restano scelte (revisione 6/10/2026).
  Future<void> _printSelection() async {
    if (_printing) return;
    setState(() => _printing = true);
    final started = await printSelected(context, _selected.values.toList());
    if (!mounted) return;
    setState(() {
      _printing = false;
      if (started) _selected.clear();
    });
  }

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

  /// Vanno a pagine, dalla scheda piu' nuova: la ricerca, Tutte, Da
  /// rivedere e Dall'app. Oggi no: e' gia' tutta.
  bool get _paged => _search.text.trim().isNotEmpty || _filter != Filter.today;

  /// La richiesta che ha dato l'elenco in vista: per un lotto senza
  /// risultati e' la ricerca per nome ("Riso 1/10"), e le pagine dopo
  /// devono continuare quella.
  Map<String, String> _shown = {};

  /// Si ricomincia dalla prima pagina (altro filtro, altra ricerca).
  void _restart() {
    _wanted = _page;
    _more = false;
    _moreError = null;
    _dayCursor = null;
  }

  /// Il server non sa ancora andare a pagine: niente "altre" nella risposta.
  bool _byDay(Map<String, dynamic> body) =>
      _search.text.trim().isEmpty && _filter == Filter.all && !body.containsKey('altre');

  /// Ogni caricamento ha un numero: vale solo la risposta dell'ultimo, cosi'
  /// una ricerca lenta ("ri") non copre quella appena scritta ("riso").
  int _request = 0;

  Future<void> _load() async {
    final request = ++_request;
    try {
      final paged = _paged;
      var query = _query;
      var body = await Api.instance.get('/schede', {...query, if (paged) 'quanti': '$_wanted'});
      var items = (body['schede'] as List).cast<Map<String, dynamic>>();
      final text = _search.text.trim();
      if (text.isNotEmpty && items.isEmpty && RegExp(r'\d').hasMatch(text)) {
        // "Riso 1/10": il nome contiene cifre, non e' un lotto.
        query = {'cerca': text};
        body = await Api.instance.get('/schede', {...query, 'quanti': '$_wanted'});
        items = (body['schede'] as List).cast<Map<String, dynamic>>();
      }
      if (text.isNotEmpty && !body.containsKey('altre')) {
        // Server di prima delle pagine: le sue 50 dalla piu' vecchia; almeno
        // in vista le piu' nuove vanno in cima.
        items = [...items]..sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      }
      Map<String, dynamic>? summary;
      try {
        summary = await Api.instance.get('/riepilogo');
      } on ApiError {
        summary = _summary;
      }
      if (!mounted || request != _request) return;
      final byDay = paged && _byDay(body);
      if (byDay && _wanted > _page && items.isNotEmpty) {
        // Ricaricando, il server vecchio rimanda solo le ultime 50: quelle
        // piu' vecchie gia' mostrate scorrendo restano in fondo.
        final fresh = {for (final s in items) s['id']};
        final cutoff = items.map((s) => s['id'] as int).reduce((a, b) => a < b ? a : b);
        items = [...items, ..._items.where((s) => !fresh.contains(s['id']) && (s['id'] as int) < cutoff)];
      }
      final total = (summary?['totale'] as num?)?.toInt() ?? 0;
      setState(() {
        _items = items;
        _shown = query;
        _summary = summary;
        _error = null;
        _loading = false;
        _more = paged && (body['altre'] == true || (byDay && items.isNotEmpty && items.length < total));
      });
      _schedulePoll();
      _warmUp(items);
    } on ApiError catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      _schedulePoll(); // senza rete si riprova, piu' piano
    }
  }

  /// Le prime schede si aprono di solito subito: le loro foto medie si
  /// scaricano gia' adesso, due alla volta, dopo le miniature in vista.
  /// Le gia' scaricate costano solo un controllo in memoria.
  Future<void> _warmUp(List<Map<String, dynamic>> items) async {
    final ids = [
      for (final s in items.take(8))
        if (s['in_lavorazione'] != true) s['id'] as int,
    ];
    await Future<void>.delayed(const Duration(milliseconds: 800));
    for (var i = 0; i < ids.length && mounted; i += 2) {
      await Future.wait([for (final id in ids.skip(i).take(2)) prefetchPhoto(id, PhotoSize.media)]);
    }
  }

  /// La pagina dopo l'ultima scheda in elenco, arrivati in fondo.
  Future<void> _loadMore() async {
    if (!_more || _loadingMore || _items.isEmpty || !_paged) return;
    final request = _request;
    final last = _items.last['id'] as int;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      // Gia' visto che il server e' vecchio: avanti per giorni.
      if (await _olderByDay(request) != null) return;
      final body = await Api.instance.get('/schede', {..._shown, 'quanti': '$_page', 'prima_di': '$last'});
      if (!mounted || request != _request) return;
      if (_byDay(body)) {
        // Server vecchio: ha ignorato "prima_di". Si va per giorni.
        await _olderByDay(request, force: true);
        return;
      }
      // Solo quelle piu' vecchie dell'ultima: se intanto l'elenco e' stato
      // ricaricato con piu' schede, niente doppioni.
      final oldest = _items.last['id'] as int;
      final older = (body['schede'] as List).cast<Map<String, dynamic>>().where((s) => (s['id'] as int) < oldest);
      setState(() {
        _items = [..._items, ...older];
        _wanted = _items.length;
        _more = body['altre'] == true;
      });
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _moreError = e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Server vecchio: le schede piu' vecchie dell'ultima in elenco, un giorno
  /// alla volta all'indietro (una settimana di richieste insieme), finche' ne
  /// arrivano almeno 20 o sono tutte. null se il server sa andare a pagine.
  Future<List<Map<String, dynamic>>?> _olderByDay(int request, {bool force = false}) async {
    if (_dayCursor == null && !force) return null;
    final seen = {for (final s in _items) s['id']};
    var day = _dayCursor ?? DateTime.tryParse('${_items.last['giorno']}') ?? today();
    day = DateTime(day.year, day.month, day.day);
    final found = <Map<String, dynamic>>[];
    var emptyDays = 0;
    // 60 giorni di fila senza schede: l'archivio e' finito.
    while (found.length < 20 && emptyDays < 60) {
      final days = [for (var i = 0; i < 7; i++) addDays(day, -i)];
      final bodies = await Future.wait(days.map((d) => Api.instance.get('/schede', {'giorno': isoDay(d)})));
      if (!mounted || request != _request) return found;
      for (final body in bodies) {
        final rows = (body['schede'] as List).cast<Map<String, dynamic>>().where((s) => !seen.contains(s['id'])).toList();
        emptyDays = rows.isEmpty ? emptyDays + 1 : 0;
        for (final s in rows) {
          seen.add(s['id']);
          found.add(s);
        }
      }
      day = addDays(day, -7);
    }
    found.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final total = (_summary?['totale'] as num?)?.toInt() ?? 0;
    setState(() {
      _dayCursor = day;
      _items = [..._items, ...found];
      _wanted = _items.length;
      _more = found.isNotEmpty && _items.length < total;
    });
    return found;
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
    // Con tante schede gia' scorse si rilegge solo la prima pagina (dove
    // stanno quelle in lettura) e la si unisce: prima si richiedevano tutte,
    // ogni 5 secondi (revisione 6/10/2026).
    final refresh = _paged && _items.length > _page ? _refreshTop : _load;
    _poll = Timer(Duration(seconds: _pollRounds <= 24 ? 5 : 20), refresh);
  }

  Future<void> _refreshTop() async {
    final request = _request;
    try {
      final body = await Api.instance.get('/schede', {..._shown, 'quanti': '$_page'});
      if (!mounted || request != _request) return;
      final fresh = (body['schede'] as List).cast<Map<String, dynamic>>();
      if (fresh.isNotEmpty) {
        final oldest = fresh.map((s) => s['id'] as int).reduce((a, b) => a < b ? a : b);
        setState(() => _items = [...fresh, ..._items.where((s) => (s['id'] as int) < oldest)]);
      }
    } on ApiError {
      // si riprova al giro dopo
    }
    if (mounted && request == _request) _schedulePoll();
  }

  void _onSearch(String _) {
    setState(_restart);
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
        labelStyle: TextStyle(color: on ? C.onSelected : C.ink, fontWeight: FontWeight.w500),
        side: on ? BorderSide.none : BorderSide(color: C.border),
        onSelected: (_) {
          _search.clear();
          setState(() {
            _filter = f;
            _loading = true;
            _restart();
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
      bottom: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _printing ? null : _printSelection,
                  icon: const Icon(Symbols.print_rounded),
                  label: Text(_selected.length == 1 ? 'Stampa 1 etichetta' : 'Stampa ${_selected.length} etichette'),
                ),
              ),
            )
          : null,
      header: _selecting
          ? NavyHeader(
              title: _selected.length == 1 ? '1 selezionata' : '${_selected.length} selezionate',
              subtitle: 'Tocca altre schede per aggiungerle',
              actions: [
                HeaderButton(
                  icon: Symbols.select_all_rounded,
                  tooltip: 'Seleziona tutte quelle in elenco',
                  onPressed: () => setState(() {
                    for (final s in _items) {
                      if (s['in_lavorazione'] != true) _selected[s['id'] as int] = s;
                    }
                  }),
                ),
                HeaderButton(icon: Symbols.close_rounded, tooltip: 'Annulla selezione', onPressed: () => setState(_selected.clear)),
              ],
            )
          : NavyHeader(
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Cerca prodotto o lotto',
              prefixIcon: Icon(Symbols.search_rounded, color: C.muted),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: C.border)),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Cancella ricerca',
                      icon: const Icon(Symbols.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(_restart);
                        _load();
                      }),
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
        if (!_selecting)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(children: [
              Icon(Symbols.touch_app_rounded, size: 15, color: C.faint),
              SizedBox(width: 6),
              Expanded(
                child: Text('Tieni premuta una scheda per stamparne più insieme',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
              ),
            ]),
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
          ? ListView(children: [
              SizedBox(height: 80),
              Center(child: Text('Nessuna scheda', style: TextStyle(color: C.muted))),
            ])
          : NotificationListener<ScrollNotification>(
              // Vicino al fondo arriva la pagina dopo, senza toccare nulla.
              onNotification: (n) {
                if (n.metrics.extentAfter < 800 && _moreError == null) _loadMore();
                return false;
              },
              child: ListView.separated(
                // Le schede poco sotto lo schermo si preparano gia' (foto
                // comprese): scorrendo compaiono pronte.
                scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: _items.length + (_more ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => i == _items.length
                    ? _moreFooter()
                    : ItemTile(
                        _items[i],
                        onChanged: _load,
                        selected: _selected.containsKey(_items[i]['id']),
                        selecting: _selecting,
                        onSelect: () => _toggle(_items[i]),
                      ),
              ),
            ),
    );
  }

  /// In fondo all'elenco: la rotella mentre arrivano le schede piu' vecchie,
  /// o il tasto per caricarle (anche dopo un errore di rete).
  Widget _moreFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    return Column(children: [
      if (_moreError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_moreError!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: C.muted)),
        ),
      TextButton.icon(
        onPressed: () {
          setState(() => _moreError = null);
          _loadMore();
        },
        icon: const Icon(Symbols.expand_more_rounded),
        label: const Text('Carica schede più vecchie'),
      ),
    ]);
  }
}

String shortName(String? name) {
  final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '';
  if (words.length == 1) return words.first;
  return '${words.first} ${words[1][0].toUpperCase()}.';
}

class ItemTile extends StatelessWidget {
  const ItemTile(this.s, {super.key, this.onChanged, this.selected = false, this.selecting = false, this.onSelect});
  final Map<String, dynamic> s;
  final VoidCallback? onChanged;
  final bool selected;
  final bool selecting;
  /// Tenere premuto (o toccare, durante la selezione) sceglie la scheda per
  /// la stampa di piu' etichette.
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    // Durante il caricamento sul cloud la scheda e' gia' letta: si vede il prodotto.
    final reading = s['in_lavorazione'] == true && s['in_archiviazione'] != true;
    final who = s['dall_app'] == true ? '${shortName(s['inviata_da'])} · dall\'app' : shortName(s['inviata_da']);
    final internal = s['lotto_interno_codice'] as String?;
    return Panel(
      padding: const EdgeInsets.all(12),
      color: selected ? C.sandSoft : (reading ? C.readingTint : null),
      border: selected ? Border.all(color: C.blue, width: 2) : null,
      onLongPress: onSelect,
      onTap: selecting
          ? onSelect
          : () async {
              await openItem(context, s['id'] as int);
              onChanged?.call();
            },
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(width: 76, height: 76, child: ItemPhoto(s['id'] as int, size: PhotoSize.mini, cacheWidth: 228)),
          ),
          if (selecting)
            Positioned(
              top: 4,
              left: 4,
              child: Icon(
                selected ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded,
                fill: selected ? 1 : 0,
                color: selected ? C.blue : Colors.white,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(reading ? 'Foto in lettura' : (s['prodotto'] ?? 'Prodotto non letto'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -.2)),
              ),
              const SizedBox(width: 8),
              Pill.status(s),
            ]),
            const SizedBox(height: 7),
            if (!reading)
              Row(children: [
                Flexible(child: LotTag(s['lotto'] ?? '—')),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Scad. ${itDate(s['scadenza'])}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: C.muted)),
                ),
              ]),
            const SizedBox(height: 7),
            Row(children: [
              Expanded(
                child: Text('${whenArrived(s['arrivata_alle'])} · $who',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
              ),
              if (internal != null) Text(internal, style: mono.copyWith(fontSize: 12, color: C.sandText)),
            ]),
          ]),
        ),
      ]),
    );
  }
}
