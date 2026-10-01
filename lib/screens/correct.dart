import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';

/// Come /correggi e /allergeni: ogni campo cambiato viene registrato con il
/// nome di chi l'ha cambiato.
class CorrectScreen extends StatefulWidget {
  const CorrectScreen(this.s, {super.key});
  final Map<String, dynamic> s;
  @override
  State<CorrectScreen> createState() => _CorrectScreenState();
}

class _CorrectScreenState extends State<CorrectScreen> {
  late final _product = TextEditingController(text: widget.s['prodotto'] ?? '');
  late final _lot = TextEditingController(text: widget.s['lotto'] ?? '');
  late final _producer = TextEditingController(text: widget.s['produttore'] ?? '');
  late String? _expiry = widget.s['scadenza'] as String?;
  late final Set<String> _allergens = _split(widget.s['allergeni'] as String?);
  late final _otherAllergens = TextEditingController(
      text: _split(widget.s['allergeni'] as String?).where((a) => !allergens.contains(a)).join(', '));
  bool _saving = false;

  static Set<String> _split(String? text) =>
      (text ?? '').split(',').map((a) => a.trim().toLowerCase()).where((a) => a.isNotEmpty).toSet();

  String get _allergenText {
    final all = [
      ...allergens.where(_allergens.contains),
      ..._split(_otherAllergens.text).where((a) => !allergens.contains(a)),
    ];
    return all.join(', ');
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_expiry ?? '') ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 10),
      helpText: 'Scadenza',
    );
    if (picked != null) setState(() => _expiry = isoDay(picked));
  }

  Future<void> _save() async {
    final s = widget.s;
    final changes = <String, dynamic>{};
    void check(String key, String value) {
      final old = (s[key] as String?) ?? '';
      if (value.trim() != old.trim()) changes[key] = value.trim();
    }

    check('prodotto', _product.text);
    check('lotto', _lot.text);
    check('produttore', _producer.text);
    if ((_expiry ?? '') != (s['scadenza'] ?? '')) changes['scadenza'] = _expiry ?? '';
    final before = _split(s['allergeni'] as String?);
    final after = _split(_allergenText);
    if (before.length != after.length || !before.containsAll(after)) {
      changes['allergeni'] = after.isEmpty ? '-' : _allergenText;
    }
    if (changes.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _saving = true);
    final result = await attempt(context, () => Api.instance.patch('/schede/${s['id']}', changes));
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) {
      if (result['cloud_in_sospeso'] == true) toast(context, 'Salvata. La copia sul cloud si aggiorna appena possibile.');
      Navigator.pop(context, true);
    }
  }

  Widget _field(String label, TextEditingController c, {bool isMono = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(label),
          const SizedBox(height: 6),
          TextField(controller: c, style: isMono ? mono : null, textCapitalization: TextCapitalization.sentences),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Correggi #${widget.s['id']}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          _field('Prodotto', _product),
          _field('Lotto', _lot, isMono: true),
          const SectionLabel('Scadenza'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(_expiry == null ? 'Scegli la data' : itDate(_expiry)),
              ),
            ),
            if (_expiry != null)
              IconButton(
                tooltip: 'Togli la scadenza',
                onPressed: () => setState(() => _expiry = null),
                icon: const Icon(Icons.close),
              ),
          ]),
          const SizedBox(height: 14),
          _field('Produttore', _producer),
          const SectionLabel('Allergeni'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in allergens)
              FilterChip(
                label: Text(a),
                selected: _allergens.contains(a),
                onSelected: (on) => setState(() => on ? _allergens.add(a) : _allergens.remove(a)),
              ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _otherAllergens,
            decoration: const InputDecoration(hintText: 'Altro (separati da virgola)'),
          ),
          const SizedBox(height: 18),
          const Text('Ogni modifica viene registrata con il tuo nome',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Salva'),
          ),
        ]),
      );
}
