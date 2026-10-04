import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../ui.dart';
import 'home.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.expired = false});
  final bool expired;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  String _pin = '';
  bool _busy = false;
  String? _error;
  static const _maxPin = 12;

  @override
  void initState() {
    super.initState();
    if (widget.expired) _error = 'Accesso scaduto: rientra con nome e PIN';
    // L'ultimo nome usato su questo telefono, per non riscriverlo ogni volta.
    const FlutterSecureStorage().read(key: 'nome').then((v) {
      if (v != null && mounted && _name.text.isEmpty) setState(() => _name.text = v);
    });
  }

  void _key(String k) {
    setState(() {
      _error = null;
      if (k == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < _maxPin) {
        _pin += k;
      }
    });
  }

  Future<void> _login() async {
    if (_name.text.trim().isEmpty || _pin.length < 4) {
      setState(() => _error = 'Scrivi il nome e almeno 4 cifre del PIN');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.instance.login(_name.text.trim(), _pin);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiError ? e.message : 'Accesso non riuscito: $e';
        _pin = '';
        _busy = false;
      });
    }
  }

  Widget _keyButton(String k) => Padding(
        padding: const EdgeInsets.all(5),
        child: SizedBox(
          height: 60,
          child: OutlinedButton(
            onPressed: _busy ? null : () => _key(k),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 60)),
            child: k == '<'
                ? const Icon(Symbols.backspace_rounded, semanticLabel: 'Cancella')
                : Text(k, style: const TextStyle(fontSize: 22)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dots = _pin.length < 6 ? 6 : _pin.length;
    // In alto il riquadro blu notte: icone di stato chiare.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              decoration: BoxDecoration(
                color: C.navy,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(28, MediaQuery.of(context).padding.top + 48, 28, 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: C.sand,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Symbols.sell_rounded, color: C.onSand, size: 32),
                ),
                const SizedBox(height: 14),
                const Text('Etichette Margherita',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.5)),
                const SizedBox(height: 6),
                const Text('Archivio etichette, lotti interni e stampa',
                    style: TextStyle(color: C.onNavyMuted, fontSize: 14)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SectionLabel('Nome'),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(hintText: 'Nome e cognome'),
                ),
                const SizedBox(height: 18),
                const SectionLabel('PIN'),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < dots; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? C.ink : null,
                          border: i < _pin.length ? null : Border.all(color: const Color(0xFFA39B8F), width: 2),
                        ),
                      ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: C.badFg)),
                  ),
                const SizedBox(height: 12),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['', '0', '<'],
                ])
                  Row(children: [
                    for (final k in row) Expanded(child: k.isEmpty ? const SizedBox() : _keyButton(k)),
                  ]),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _login,
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Entra'),
                ),
                const SizedBox(height: 8),
                Text('Resti collegato su questo telefono per 90 giorni',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
