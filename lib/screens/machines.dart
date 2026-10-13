import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../ui.dart';

/// Altro > Macchine e stampa (solo amministratori): stato di server, Qwen,
/// stampante e code, con i riavvii. Si aggiorna da sola ogni 5 secondi.
class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});
  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Ogni caricamento ha un numero e solo l'ultimo riprogramma il timer:
  /// prima un aggiornamento a mano durante quello automatico lasciava due
  /// catene di richieste ogni 5 secondi, e cosi' via (revisione 6/10/2026).
  int _request = 0;

  Future<void> _load() async {
    final request = ++_request;
    _timer?.cancel();
    try {
      final data = await Api.instance.get('/admin/macchine');
      if (mounted && request == _request) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted && request == _request) setState(() => _error = e.message);
    }
    if (mounted && request == _request) {
      _timer = Timer(const Duration(seconds: 5), () => appVisible ? _load() : _waitVisible());
    }
  }

  void _waitVisible() {
    final request = _request;
    _timer = Timer(const Duration(seconds: 5), () {
      if (request != _request || !mounted) return;
      appVisible ? _load() : _waitVisible();
    });
  }

  Future<void> _action(String action, String title, String detail) async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Riavvia'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final result = await attempt(context, () => Api.instance.post('/admin/macchine/$action', {}));
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      toast(context, result['gia_in_corso'] == true ? 'Era già in corso' : 'Riavvio avviato');
    }
    _load();
  }

  /// Nuovo IP o nome della stampante (13/10/2026): li prova e li salva il
  /// servizio di stampa su michyristo. Se non risponde chiede se salvare
  /// comunque.
  Future<void> _changePrinter(Map<String, dynamic> printer) async {
    if (_busy) return;
    final address = await showDialog<(String, int, String)>(
      context: context,
      builder: (context) => _PrinterAddressDialog(
        host: printer['indirizzo'] as String? ?? '',
        port: printer['porta'] as int? ?? 9100,
        name: printer['nome'] as String? ?? '',
      ),
    );
    if (address == null || !mounted) return;
    final (host, port, name) = address;
    final request = {'indirizzo': host, 'porta': port, 'nome': name};
    setState(() => _busy = true);
    Map<String, dynamic>? result;
    try {
      result = await Api.instance.post('/admin/stampante', request);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.body?['non_risponde'] == true) {
        final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('La stampante non risponde'),
            content: Text('$host:$port non risponde adesso. Salvare comunque?\n\n'
                'Le stampe non usciranno finché la stampante non sarà raggiungibile a questo indirizzo.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Salva comunque'),
              ),
            ],
          ),
        );
        if (sure == true && mounted) {
          result = await attempt(context,
              () => Api.instance.post('/admin/stampante', {...request, 'forza': true}));
        }
      } else if (e.status != 401) {
        toast(context, e.message, error: true);
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (result != null) {
      toast(context, '${result['nome'] ?? 'Stampante'} ora su ${result['indirizzo']}:${result['porta']}');
    }
    _load();
  }

  Future<void> _cancelPrint(String id) async {
    final ok = await attempt(context, () => Api.instance.post('/stampe/$id/annulla', {}));
    if (ok != null && mounted) toast(context, 'Stampa annullata');
    _load();
  }

  Widget _row(String name, bool? up, String detail, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Dot(up == null ? C.faint : (up ? C.green : C.red), size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(detail, style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          ?trailing,
        ]),
      );

  Widget _restartButton(String action, String title, String detail) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
        onPressed: _busy ? null : () => _action(action, title, detail),
        child: const Text('Riavvia', style: TextStyle(fontSize: 13)),
      );

  Widget _count(String value, String label, {Color? color}) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: C.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return HeaderScaffold(
      header: const NavyHeader(title: 'Macchine e stampa', subtitle: 'Si aggiorna da sola ogni 5 secondi', back: true),
      body: d == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(onRefresh: _load, child: _content(d)),
    );
  }

  Widget _content(Map<String, dynamic> d) {
    final machines = (d['macchine'] as List).cast<Map<String, dynamic>>();
    bool? up(String part) {
      for (final m in machines) {
        if ((m['nome'] as String).toLowerCase().contains(part)) return m['attiva'] as bool?;
      }
      return null;
    }

    final printer = (d['stampante'] as Map).cast<String, dynamic>();
    final printerOk = printer['raggiungibile'] == true && printer['in_linea'] == true && printer['carta'] != false;
    final printerDetail = printer['collegata'] != true
        ? 'non collegata'
        : printer['errore'] != null
            ? printer['errore'] as String
            : [
                printer['raggiungibile'] == true ? 'raggiungibile' : 'non raggiungibile',
                if (printer['in_linea'] == false) 'non in linea (sportello aperto?)',
                if (printer['carta'] == false) 'CARTA FINITA',
                if (printer['carta_quasi_finita'] == true) 'carta quasi finita',
              ].join(' · ');
    final reading = (d['letture'] as Map).cast<String, dynamic>();
    final waiting = (d['stampe_in_attesa'] as List).cast<Map<String, dynamic>>();
    final recent = (d['ultime_stampe_app'] as List).cast<Map<String, dynamic>>();
    final perPerson = (d['copie_ultimi_10_minuti'] as Map).cast<String, dynamic>();

    return ListView(padding: const EdgeInsets.all(16), children: [
      Panel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Macchine'),
          const SizedBox(height: 4),
          _row('Server (VPS)', up('rob-label'), 'bot, archivio, app e sito',
              trailing: _restartButton('riavvia-vps', 'Riavviare il server?',
                  'Bot, app e sito restano irraggiungibili per uno o due minuti. Le foto mandate intanto arrivano dopo.')),
          _row('Bot Etichette', true, 'il programma che legge e archivia',
              trailing: _restartButton('riavvia-bot', 'Riavviare il bot?',
                  'Il bot riparte in circa 30 secondi. Le stampe in attesa in quel momento si perdono.')),
          _row('Qwen (lettura etichette)', up('qwen'), 'su michyristo',
              trailing: _restartButton('riavvia-qwen', 'Riavviare Qwen?',
                  'Le letture si fermano per circa un minuto; nel frattempo il bot usa il lettore di riserva.')),
          _row('michyristo', up('qwen'), 'il PC con Qwen e il servizio di stampa',
              trailing: _restartButton('riavvia-michyristo', 'Riavviare michyristo?',
                  'Qwen e la stampa restano fermi per qualche minuto finché il PC non riparte.')),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Stampante'),
          const SizedBox(height: 4),
          _row(printerName(printer), printer['collegata'] != true ? null : printerOk, printerDetail,
              trailing: _restartButton('riavvia-stampa', 'Riavviare il servizio di stampa?',
                  'Riparte in pochi secondi. Serve se le stampe non escono ma la stampante è accesa.')),
          if (printer['collegata'] == true)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 4),
              child: Row(children: [
                Icon(Symbols.lan_rounded, size: 16, color: C.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    printer['indirizzo'] != null
                        ? 'Indirizzo ${printer['indirizzo']}:${printer['porta']}'
                        : 'Indirizzo non disponibile (servizio di stampa da aggiornare?)',
                    style: TextStyle(fontSize: 12.5, color: C.muted),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _changePrinter(printer),
                  child: const Text('Modifica', style: TextStyle(fontSize: 13)),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Lettura delle foto'),
          const SizedBox(height: 10),
          Row(children: [
            _count('${reading['in_coda']}', 'in coda'),
            _count('${reading['in_lettura']}', 'in lettura', color: C.blue),
            _count('${reading['in_archiviazione']}', 'in archivio'),
            _count('${reading['non_riuscite']}', 'non riuscite', color: (reading['non_riuscite'] ?? 0) > 0 ? C.badFg : null),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(14, 12, 14, 4), child: SectionLabel('Stampe in attesa')),
          if (waiting.isEmpty)
            Padding(padding: EdgeInsets.fromLTRB(14, 4, 14, 14), child: Text('Nessuna', style: TextStyle(color: C.muted))),
          for (final w in waiting)
            ListTile(
              dense: true,
              leading: Icon(w['fonte'] == 'telegram' ? Symbols.send_rounded : Symbols.phone_android_rounded, color: C.muted),
              title: Text('${w['prodotto'] ?? '—'} · ${w['lotto']}'),
              subtitle: Text([
                '${w['copie']} copie${(w['etichette'] ?? 1) > 1 ? ' × ${w['etichette']} etichette' : ''}',
                if ((w['chi'] ?? '').toString().isNotEmpty) w['chi'],
                w['stato'] == 'in_stampa' ? 'sto stampando' : (w['parte_tra_secondi'] != null ? 'parte tra ${w['parte_tra_secondi']} s' : 'in attesa nel gruppo'),
              ].join(' · ')),
              trailing: w['id'] != null && w['stato'] == 'in_attesa'
                  ? TextButton(onPressed: () => _cancelPrint(w['id'] as String), child: const Text('Annulla'))
                  : null,
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: EdgeInsets.zero,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(14, 12, 14, 4), child: SectionLabel('Copie stampate negli ultimi 10 minuti')),
          if (perPerson.isEmpty)
            Padding(padding: EdgeInsets.fromLTRB(14, 4, 14, 14), child: Text('Nessuna', style: TextStyle(color: C.muted))),
          for (final entry in perPerson.entries)
            ListTile(dense: true, title: Text(entry.key), trailing: Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.w700))),
          if (recent.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(14, 8, 14, 4), child: SectionLabel('Ultime stampe dall\'app')),
            for (final r in recent)
              ListTile(
                dense: true,
                title: Text(r['messaggio'] as String? ?? r['stato'] as String),
                subtitle: Text(r['chi'] as String? ?? ''),
                trailing: Icon(
                  r['stato'] == 'stampata' ? Symbols.check_circle_rounded : (r['stato'] == 'errore' ? Symbols.error_rounded : Symbols.cancel_rounded),
                  color: r['stato'] == 'stampata' ? C.okFg : (r['stato'] == 'errore' ? C.badFg : C.muted),
                ),
              ),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      Text('Il limite anti-flood chiede conferma oltre 20 copie dello stesso lotto o 60 per persona in 10 minuti.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
    ]);
  }
}

/// Il nome della stampante come lo manda il servizio di stampa (13/10/2026);
/// un servizio vecchio non lo manda.
String printerName(Map<String, dynamic> printer) {
  final name = (printer['nome'] as String? ?? '').trim();
  return name.isEmpty ? 'Stampante' : name;
}

/// Cosa non va nell'indirizzo della stampante scritto a mano, o null se va
/// bene: un IPv4 (192.168.20.24) o un nome di rete. Il servizio di stampa lo
/// ricontrolla comunque.
String? printerAddressError(String host, String port) {
  host = host.trim();
  if (host.isEmpty) return 'Scrivi l\'indirizzo';
  final looksLikeIp = RegExp(r'^[\d.]+$').hasMatch(host);
  if (looksLikeIp) {
    final parts = host.split('.');
    if (parts.length != 4 || parts.any((p) => p.isEmpty || p.length > 3 || int.parse(p) > 255)) {
      return 'IP non valido (es. 192.168.20.24)';
    }
    if (host == '0.0.0.0') return 'IP non valido (es. 192.168.20.24)';
  } else if (host.length > 253 ||
      !RegExp(r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$')
          .hasMatch(host)) {
    return 'Indirizzo non valido';
  }
  final p = int.tryParse(port.trim());
  if (p == null || p < 1 || p > 65535) return 'Porta non valida (di solito 9100)';
  return null;
}

/// Cosa non va nel nome della stampante, o null se va bene.
String? printerNameError(String name) {
  name = name.trim();
  if (name.isEmpty) return 'Scrivi il nome';
  if (name.length > 40) return 'Al massimo 40 caratteri';
  return null;
}

class _PrinterAddressDialog extends StatefulWidget {
  const _PrinterAddressDialog({required this.host, required this.port, required this.name});
  final String host;
  final int port;
  final String name;
  @override
  State<_PrinterAddressDialog> createState() => _PrinterAddressDialogState();
}

class _PrinterAddressDialogState extends State<_PrinterAddressDialog> {
  late final _host = TextEditingController(text: widget.host);
  late final _port = TextEditingController(text: '${widget.port}');
  late final _name = TextEditingController(text: widget.name);
  String? _error;
  String? _nameError;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final error = printerAddressError(_host.text, _port.text);
    final nameError = printerNameError(_name.text);
    if (error != null || nameError != null) {
      setState(() {
        _error = error;
        _nameError = nameError;
      });
      return;
    }
    Navigator.pop(context, (_host.text.trim(), int.parse(_port.text.trim()), _name.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Stampante'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Nome e IP della stampante nella rete del locale. Prima di salvare un IP nuovo si prova a collegarsi.',
              style: TextStyle(fontSize: 13, color: C.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 40,
            decoration: InputDecoration(labelText: 'Nome', hintText: 'Etichettatrice cucina', errorText: _nameError),
            onChanged: (_) => setState(() => _nameError = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _host,
            keyboardType: TextInputType.url,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9.\-]'))],
            decoration: InputDecoration(labelText: 'IP', hintText: '192.168.20.24', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 5,
            decoration: const InputDecoration(labelText: 'Porta', helperText: 'Di solito 9100'),
            onSubmitted: (_) => _save(),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _save,
            child: const Text('Salva'),
          ),
        ],
      );
}
