import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';
import 'correct.dart';
import 'home.dart';
import 'print.dart';

class ItemScreen extends StatefulWidget {
  const ItemScreen(this.itemId, {super.key});
  final int itemId;
  @override
  State<ItemScreen> createState() => _ItemScreenState();
}

class _ItemScreenState extends State<ItemScreen> {
  Map<String, dynamic>? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await Api.instance.get('/schede/${widget.itemId}');
      if (mounted) setState(() => _s = body['scheda'] as Map<String, dynamic>);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _addPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
    if (file == null || !mounted) return;
    final ok = await attempt(context, () => Api.instance.uploadPhoto('/schede/${widget.itemId}/foto', File(file.path)));
    if (ok != null && mounted) {
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
      Navigator.pop(context);
    }
  }

  void _openPhoto() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(backgroundColor: Colors.black),
            body: InteractiveViewer(maxScale: 6, child: Center(child: ItemPhoto(widget.itemId, fit: BoxFit.contain))),
          ),
        ),
      );

  Widget _kv(String k, String v, {bool isMono = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(k),
        const SizedBox(height: 3),
        SelectableText(v, style: isMono ? mono.copyWith(fontSize: 16) : const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ]);

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text('Scheda #${widget.itemId}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Altre azioni',
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
          ),
        ],
      ),
      body: s == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                GestureDetector(
                  onTap: _openPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 190,
                      child: Stack(fit: StackFit.expand, children: [
                        ItemPhoto(widget.itemId),
                        if ((s['foto_aggiuntive'] ?? 0) > 0)
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Pill('+${s['foto_aggiuntive']} foto', bg: C.infoBg, fg: C.infoFg),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${whenArrived(s['arrivata_alle'])} · ${s['inviata_da'] ?? ''}${s['dall_app'] == true ? ' · dall\'app' : ''}',
                    style: const TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(s['prodotto'] ?? 'Prodotto non letto',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        ),
                        Pill.status(s),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: _kv('Lotto', s['lotto'] ?? '—', isMono: true)),
                        Expanded(child: _kv('Scadenza', itDate(s['scadenza']))),
                      ]),
                      const SizedBox(height: 14),
                      _kv('Produttore', s['produttore'] ?? '—'),
                      const SizedBox(height: 14),
                      _kv('Allergeni', _allergens(s)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                if (s['lotto_interno'] != null) _InternalLotCard(s['lotto_interno'] as Map<String, dynamic>),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: s['in_lavorazione'] == true
                          ? null
                          : () async {
                              final changed = await Navigator.push<bool>(
                                  context, MaterialPageRoute(builder: (_) => CorrectScreen(s)));
                              if (changed == true) {
                                archiveChanged.value++;
                                _load();
                              }
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Correggi'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: s['lotto_interno'] == null
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => PrintScreen(s['lotto_interno'] as Map<String, dynamic>)),
                              ),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Etichetta'),
                    ),
                  ),
                ]),
              ]),
            ),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: C.navy, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.sell_outlined, color: C.softBlue, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('LOTTO INTERNO',
                  style: TextStyle(fontSize: 12, letterSpacing: .7, color: Color(0xFFB8C3D4), fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(lot['codice'] as String, style: mono.copyWith(fontSize: 20, color: Colors.white)),
            ]),
          ),
          Text('Prod. ${itDate(lot['data_produzione'])}',
              style: const TextStyle(fontSize: 12, color: Color(0xFFB8C3D4))),
        ]),
      );
}
