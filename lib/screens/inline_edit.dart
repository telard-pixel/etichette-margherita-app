import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../format.dart';
import '../ui.dart';

/// Un campo della scheda che si corregge sul posto, come /correggi: si
/// tocca, diventa una casella di testo, ✓ salva e ✕ annulla.
class EditableField extends StatefulWidget {
  const EditableField({
    super.key,
    required this.label,
    required this.value,
    required this.onSave,
    this.enabled = true,
    this.mono = false,
    this.big = false,
    this.placeholder = '—',
    this.caps = TextCapitalization.sentences,
  });

  final String label;
  final String? value;
  /// Salva il nuovo valore; true se il server l'ha accettato.
  final Future<bool> Function(String value) onSave;
  final bool enabled;
  final bool mono;
  /// Il nome del prodotto: grande, senza etichetta sopra.
  final bool big;
  final String placeholder;
  final TextCapitalization caps;

  @override
  State<EditableField> createState() => _EditableFieldState();
}

class _EditableFieldState extends State<EditableField> {
  final _controller = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    _controller.text = widget.value ?? '';
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text == (widget.value ?? '').trim()) {
      setState(() => _editing = false);
      return;
    }
    setState(() => _saving = true);
    final ok = await widget.onSave(text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false; // se non e' passato si resta in modifica, col testo scritto
    });
  }

  TextStyle get _style => widget.big
      ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.2)
      : widget.mono
          ? mono.copyWith(fontSize: 15)
          : const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500);

  @override
  Widget build(BuildContext context) {
    final label = widget.big ? null : SectionLabel(widget.label);
    if (_editing) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) ...[label, const SizedBox(height: 6)],
        Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              style: _style,
              textCapitalization: widget.caps,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.big ? 'Nome del prodotto' : widget.label,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else ...[
            IconButton.filled(tooltip: 'Salva', onPressed: _save, icon: const Icon(Symbols.check_rounded)),
            IconButton(tooltip: 'Annulla', onPressed: () => setState(() => _editing = false), icon: const Icon(Symbols.close_rounded)),
          ],
        ]),
      ]);
    }
    final empty = widget.value == null || widget.value!.trim().isEmpty;
    final shown = empty ? widget.placeholder : widget.value!;
    return EditableTap(
      enabled: widget.enabled,
      onTap: _start,
      label: label,
      child: widget.mono && !empty
          ? LotTag(shown, size: 15)
          : Text(shown, style: _style.copyWith(color: empty ? C.faint : null)),
    );
  }
}

/// La parte "a riposo" di un campo modificabile: valore, matitina e tocco.
class EditableTap extends StatelessWidget {
  const EditableTap({super.key, required this.child, required this.onTap, this.label, this.enabled = true});
  final Widget child;
  final Widget? label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (label != null) ...[label!, const SizedBox(height: 5)],
                child,
              ]),
            ),
            if (enabled)
              Padding(
                padding: EdgeInsets.only(left: 6, top: 2),
                child: Icon(Symbols.edit_rounded, size: 17, color: C.faint),
              ),
          ]),
        ),
      );
}

/// Calendario per la scadenza. Una data letta male (2019, 2099) non deve
/// far chiudere l'app: il calendario parte da lei, qualunque sia.
Future<DateTime?> pickExpiry(BuildContext context, String? current) {
  final now = DateTime.now();
  final initial = DateTime.tryParse(current ?? '') ?? now;
  final first = DateTime(now.year - 3).isBefore(initial) ? DateTime(now.year - 3) : DateTime(initial.year);
  final last = DateTime(now.year + 10).isAfter(initial) ? DateTime(now.year + 10) : DateTime(initial.year + 1);
  return showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last, helpText: 'Scadenza');
}

Set<String> splitAllergens(String? text) =>
    (text ?? '').split(',').map((a) => a.trim().toLowerCase()).where((a) => a.isNotEmpty).toSet();

/// Foglio per gli allergeni: i quattordici del regolamento, altri a mano,
/// oppure "nessuno". Restituisce il testo da salvare ("-" = nessuno), o
/// null se si chiude senza salvare.
Future<String?> pickAllergens(BuildContext context, String? current) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AllergenSheet(current),
    );

class _AllergenSheet extends StatefulWidget {
  const _AllergenSheet(this.current);
  final String? current;
  @override
  State<_AllergenSheet> createState() => _AllergenSheetState();
}

class _AllergenSheetState extends State<_AllergenSheet> {
  late final Set<String> _chosen = splitAllergens(widget.current).where(allergens.contains).toSet();
  late final _other = TextEditingController(
      text: splitAllergens(widget.current).where((a) => !allergens.contains(a)).join(', '));

  String get _text => [
        ...allergens.where(_chosen.contains),
        ...splitAllergens(_other.text).where((a) => !allergens.contains(a)),
      ].join(', ');

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Allergeni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in allergens)
                FilterChip(
                  label: Text(a),
                  selected: _chosen.contains(a),
                  labelStyle: TextStyle(color: _chosen.contains(a) ? C.onSelected : C.ink),
                  onSelected: (on) => setState(() => on ? _chosen.add(a) : _chosen.remove(a)),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _other,
              decoration: const InputDecoration(hintText: 'Altro (separati da virgola)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, '-'),
                  child: const Text('Nessuno'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _text.isEmpty ? '-' : _text),
                  child: const Text('Salva'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('"Nessuno" = etichetta controllata, non dichiara allergeni',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
      );
}
