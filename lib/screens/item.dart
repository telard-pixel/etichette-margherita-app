import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'inline_edit.dart';
import 'home.dart';
import 'print.dart';

bool _opening = false;

/// Apre una scheda; un doppio tocco veloce non ne apre due.
Future<void> openItem(BuildContext context, int itemId) async {
  if (_opening) return;
  _opening = true;
  try {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ItemScreen(itemId)));
  } finally {
    _opening = false;
  }
}

class ItemScreen extends StatefulWidget {
  const ItemScreen(this.itemId, {super.key});
  final int itemId;
  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  Map<String, dynamic>? _s;
  String? _error;
  Timer? _poll;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    // Corretta altrove (su Telegram con /correggi, o da un altro telefono):
    // la scheda aperta si aggiorna da sola.
    archiveChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    archiveChanged.removeListener(_load);
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    _poll?.cancel();
    try {
      final body = await Api.instance.get('/schede/${widget.itemId}');
      if (!mounted || request != _request) return;
      final s = body['scheda'] as Map<String, dynamic>;
      setState(() => _s = s);
      // Rimessa in coda (foto aggiunta, riletta) o ancora in archiviazione:
      // la scheda si aggiorna da sola finche' non e' pronta, poi compare il
      // lotto interno e si puo' stampare.
      if (s['in_lavorazione'] == true) _poll = Timer(const Duration(seconds: 5), _load);
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    }
  }

  Future<void> _addPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final ok = await attempt(context, () => Api.instance.uploadPhoto('/schede/${widget.itemId}/foto', bytes));
    if (ok != null && mounted) {
      forgetItemPhoto(widget.itemId);
      toast(context, 'Foto aggiunta: la scheda viene riletta');
      archiveChanged.value++;
      _load();
    }
  }

  Future<void> _reexamine() async {
    final ok = await attempt(context, () => Api.instance.post('/schede/${widget.itemId}/riesamina', {}));
    if (ok != null && mounted) {
      toast(context, 'Rimessa in coda: Qwen la rilegge');
      archiveChanged.value++;
      _load();
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare la scheda #${widget.itemId}?'),
        content: const Text('Le foto vanno nel cestino del cloud, da dove si possono ancora recuperare.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: C.badFg),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await attempt(context, () => Api.instance.delete('/schede/${widget.itemId}'));
    if (ok != null && mounted) {
      archiveChanged.value++;
      toast(context, 'Scheda #${widget.itemId} eliminata');
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) Navigator.of(context).removeRoute(route);
    }
  }

  /// La foto principale e quelle in piu' (coperchio, retro...): si sfogliano.
  List<int?> get _photoIds => [null, ...((_s?['foto_extra'] as List?) ?? []).cast<int>()];
  int _photoPage = 0;

  void _openPhoto(int index) => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => PhotoGallery(itemId: widget.itemId, ids: _photoIds, initial: index)),
      );

  /// Salva uno o piu' campi (come /correggi: ogni modifica resta registrata
  /// con il nome di chi l'ha fatta) e mostra subito la scheda aggiornata.
  Future<bool> _save(Map<String, dynamic> changes) async {
    final result = await attempt(context, () => Api.instance.patch('/schede/${widget.itemId}', changes));
    if (result == null || !mounted) return false;
    _request++; // un caricamento gia' in volo non riporta i valori di prima
    setState(() => _s = result['scheda'] as Map<String, dynamic>);
    archiveChanged.value++;
    toast(context, result['cloud_in_sospeso'] == true ? 'Salvato. Il cloud si aggiorna appena possibile.' : 'Salvato');
    return true;
  }

  /// Foto di un giorno passato: si chiede se stampare con lotto e data di
  /// allora o aprire un lotto nuovo con la data di oggi ("apertura"), che
  /// tiene il lotto del fornitore. Come nel gruppo Telegram.
  Future<void> _printLabel(Map<String, dynamic> lot) async {
    var chosen = lot;
    final day = lot['data_produzione'] as String? ?? '';
    final todayIso = isoDay(today());
    if (lot['scheda'] != null && day.compareTo(todayIso) < 0) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('La foto è del ${itDate(day)}: come stampo l\'etichetta?',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            MenuRow(
              icon: Icons.event,
              title: 'Tieni il ${itDate(day)}',
              subtitle: 'Lotto interno ${lot['codice']}',
              onTap: () => Navigator.pop(context, 'tieni'),
            ),
            MenuRow(
              icon: Icons.fiber_new_outlined,
              title: 'Apertura oggi ${itDate(todayIso)}',
              subtitle: 'Lotto interno nuovo con la data di oggi'
                  '${lot['lotto_fornitore'] != null ? ' · lotto fornitore ${lot['lotto_fornitore']}' : ''}',
              onTap: () => Navigator.pop(context, 'apertura'),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'apertura') {
        final body = await attempt(context, () => Api.instance.post('/schede/${widget.itemId}/apertura', {}));
        if (body == null || !mounted) return;
        chosen = body['lotto_interno'] as Map<String, dynamic>;
      }
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PrintScreen(chosen)));
  }

  Future<void> _editExpiry(Map<String, dynamic> s) async {
    final current = s['scadenza'] as String?;
    var choice = 'scegli';
    if (current != null) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            MenuRow(icon: Icons.event, title: 'Cambia la data', onTap: () => Navigator.pop(context, 'scegli')),
            MenuRow(icon: Icons.event_busy, title: 'Togli la scadenza', subtitle: 'L\'etichetta non ne ha una',
                onTap: () => Navigator.pop(context, 'togli')),
            const SizedBox(height: 8),
          ]),
        ),
      );
      if (picked == null || !mounted) return;
      choice = picked;
    }
    if (choice == 'togli') {
      await _save({'scadenza': ''});
      return;
    }
    final date = await pickExpiry(context, current);
    if (date == null || !mounted || isoDay(date) == current) return;
    await _save({'scadenza': isoDay(date)});
  }

  Future<void> _editAllergens(Map<String, dynamic> s) async {
    final value = await pickAllergens(context, s['allergeni'] as String?);
    if (value == null || !mounted) return;
    final unchanged = value == '-'
        ? s['allergeni_nessuno'] == true
        : splitAllergens(value).length == splitAllergens(s['allergeni'] as String?).length &&
            splitAllergens(value).containsAll(splitAllergens(s['allergeni'] as String?)) &&
            s['allergeni_a_mano'] == true;
    if (unchanged) return;
    await _save({'allergeni': value});
  }

  Widget _menu() => PopupMenuButton<String>(
        tooltip: 'Altre azioni',
        style: IconButton.styleFrom(backgroundColor: const Color(0x8C0F1B2D)),
        icon: const Icon(Icons.more_horiz, color: Colors.white),
        onSelected: (v) {
          if (v == 'foto') _addPhoto();
          if (v == 'riesamina') _reexamine();
          if (v == 'elimina') _delete();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'foto', child: Text('Aggiungi una foto')),
          if (Api.instance.isAdmin) const PopupMenuItem(value: 'riesamina', child: Text('Fai rileggere a Qwen')),
          if (Api.instance.isAdmin) const PopupMenuItem(value: 'elimina', child: Text('Elimina scheda')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final top = MediaQuery.of(context).padding.top;
    final editable = s != null && s['in_lavorazione'] != true;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Scheda #${widget.itemId}')),
        body: _error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      // Una fascia scura sotto l'orologio: scorrendo, la foto non finisce
      // sotto le icone di stato del telefono (3/10/2026).
      body: Stack(children: [
        RefreshIndicator(
        onRefresh: _load,
        // In fondo lo spazio dei tasti di sistema: "Stampa etichetta" restava
        // sotto la barra di Android (3/10/2026).
        child: ListView(padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 24), children: [
          SizedBox(
            height: 270 + top,
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                itemCount: _photoIds.length,
                onPageChanged: (page) => setState(() => _photoPage = page),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _openPhoto(i),
                  child: ItemPhoto(widget.itemId, extraId: _photoIds[i], cacheWidth: 1200),
                ),
              ),
              Positioned(
                top: top + 12,
                left: 16,
                child: HeaderButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Indietro',
                  color: const Color(0x8C0F1B2D),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
              Positioned(top: top + 12, right: 16, child: _menu()),
              if (_photoIds.length > 1) ...[
                // Quante foto e quale si sta guardando: si sfogliano col dito.
                Positioned(
                  right: 16,
                  bottom: 34,
                  child: Pill('${_photoPage + 1} / ${_photoIds.length} · scorri', bg: const Color(0x990F1B2D), fg: Colors.white),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 38,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < _photoIds.length; i++)
                      Container(
                        width: i == _photoPage ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i == _photoPage ? Colors.white : Colors.white54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ]),
                ),
              ],
            ]),
          ),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '#${s['id']} · ${whenArrived(s['arrivata_alle'])} · ${s['inviata_da'] ?? ''}${s['dall_app'] == true ? ' · app' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: C.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Pill.status(s),
                    ]),
                    const SizedBox(height: 4),
                    EditableField(
                      label: 'Prodotto',
                      value: s['prodotto'] as String?,
                      big: true,
                      placeholder: 'Prodotto non letto',
                      enabled: editable,
                      onSave: (v) => _save({'prodotto': v}),
                    ),
                    const SizedBox(height: 10),
                    EditableField(
                      label: 'Lotto',
                      value: s['lotto'] as String?,
                      mono: true,
                      caps: TextCapitalization.characters,
                      enabled: editable,
                      onSave: (v) => _save({'lotto': v}),
                    ),
                    const SizedBox(height: 10),
                    EditableTap(
                      label: const SectionLabel('Scadenza'),
                      enabled: editable,
                      onTap: () => _editExpiry(s),
                      child: Text(itDate(s['scadenza']),
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                              color: s['scadenza'] == null ? C.faint : null)),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: divider),
                    EditableField(
                      label: 'Produttore',
                      value: s['produttore'] as String?,
                      enabled: editable,
                      onSave: (v) => _save({'produttore': v}),
                    ),
                    const SizedBox(height: 10),
                    EditableTap(
                      label: const SectionLabel('Allergeni'),
                      enabled: editable,
                      onTap: () => _editAllergens(s),
                      child: Text(_allergens(s), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      editable
                          ? 'Tocca un campo per correggerlo: la modifica resta registrata con il tuo nome'
                          : 'Si potrà correggere quando la lettura è finita',
                      style: const TextStyle(fontSize: 12, color: C.muted),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (s['lotto_interno'] != null) _InternalLotCard(s['lotto_interno'] as Map<String, dynamic>),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: s['lotto_interno'] == null ? null : () => _printLabel(s['lotto_interno'] as Map<String, dynamic>),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Stampa etichetta'),
                ),
              ]),
            ),
          ),
        ]),
      ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.of(context).padding.top,
          child: const ColoredBox(color: Color(0xCC0F1B2D)),
        ),
      ]),
    );
  }

  String _allergens(Map<String, dynamic> s) {
    if (s['allergeni_nessuno'] == true) return 'Nessuno (verificato a mano)';
    final main = (s['allergeni'] as String?)?.trim();
    final traces = (s['tracce'] as String?)?.trim();
    final parts = <String>[
      if (main != null && main.isNotEmpty) main,
      if (traces != null && traces.isNotEmpty) 'Tracce: $traces',
    ];
    final text = parts.isEmpty ? 'Nessuno letto' : parts.join('\n');
    return s['allergeni_a_mano'] == true ? '$text (inseriti a mano)' : text;
  }
}

class _InternalLotCard extends StatelessWidget {
  const _InternalLotCard(this.lot);
  final Map<String, dynamic> lot;
  @override
  Widget build(BuildContext context) => Panel(
        color: C.navy,
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: C.softBlue.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.sell_outlined, color: C.softBlue, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LOTTO INTERNO',
                  style: TextStyle(fontSize: 11, letterSpacing: .9, color: C.onNavyMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(lot['codice'] as String, style: mono.copyWith(fontSize: 20, color: Colors.white)),
            ]),
          ),
          Text('Prod. ${itDate(lot['data_produzione'])}', style: const TextStyle(fontSize: 12, color: C.onNavyMuted)),
        ]),
      );
}


/// Le foto della scheda a tutto schermo: si sfogliano col dito e si
/// ingrandiscono con due dita.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery({super.key, required this.itemId, required this.ids, this.initial = 0});
  final int itemId;
  final List<int?> ids;
  final int initial;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.ids.length > 1 ? 'Foto ${_page + 1} di ${widget.ids.length}' : 'Foto'),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.ids.length,
          onPageChanged: (page) => setState(() => _page = page),
          itemBuilder: (context, i) => InteractiveViewer(
            maxScale: 6,
            child: Center(child: ItemPhoto(widget.itemId, extraId: widget.ids[i], fit: BoxFit.contain)),
          ),
        ),
      );
}
