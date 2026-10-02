import 'package:flutter/material.dart';

import '../api.dart';
import '../format.dart';
import '../ui.dart';

/// "Ultimo accesso: ora", "oggi 18:40", "ieri 21:15", "12/09".
String lastSeen(String? iso) {
  if (iso == null) return 'mai entrato';
  final at = DateTime.tryParse(iso)?.toLocal();
  if (at == null) return '';
  final now = DateTime.now();
  if (now.difference(at).inMinutes < 5) return 'ora';
  final days = calendarDays(at, now);
  final time = '${two(at.hour)}:${two(at.minute)}';
  if (days == 0) return 'oggi $time';
  if (days == 1) return 'ieri $time';
  return '${two(at.day)}/${two(at.month)}';
}

/// Il giorno (ora italiana) di un istante UTC del server.
String _localDay(String? iso) {
  final at = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return at == null ? '—' : '${two(at.day)}/${two(at.month)}/${at.year}';
}

/// Amministrazione: chi usa l'app, da quali telefoni, quando e' entrato.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>>? _users;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = await Api.instance.get('/admin/utenti');
      if (mounted) {
        setState(() {
          _users = (body['utenti'] as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _newUser() async {
    final created = await showDialog<bool>(context: context, builder: (_) => const _NewUserDialog());
    if (created == true) _load();
  }

  Widget _row(Map<String, dynamic> u, int index) {
    final active = u['attivo'] == true;
    final phones = (u['telefoni'] as List?)?.length ?? 0;
    final status = !active
        ? const Pill('disattivato', bg: C.chipBg, fg: Color(0xFF3B4656))
        : phones > 0
            ? Pill(phones == 1 ? '1 telefono' : '$phones telefoni', bg: C.okBg, fg: C.okFg, icon: Icons.smartphone)
            : const Pill('non collegato', bg: C.chipBg, fg: Color(0xFF3B4656));
    return InkWell(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => UserScreen(u, index: index)));
        _load();
      },
      child: Opacity(
        opacity: active ? 1 : .55,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Initials(u['nome'] as String, index: index),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(u['nome'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  if (u['admin'] == true) ...[
                    const SizedBox(width: 6),
                    const Pill('admin', bg: C.infoBg, fg: C.infoFg),
                  ],
                ]),
                const SizedBox(height: 3),
                Text('Ultimo accesso: ${lastSeen(u['ultimo_accesso'])} · ${u['foto_inviate'] ?? 0} foto dall\'app',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            status,
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return HeaderScaffold(
      header: NavyHeader(
        title: 'Utenti',
        subtitle: 'Chi usa l\'app e da quali telefoni',
        back: true,
        actions: [HeaderButton(icon: Icons.add, tooltip: 'Nuovo utente', color: C.blue, onPressed: _newUser)],
      ),
      body: users == null
          ? (_error != null ? ErrorRetry(_error!, _load) : const Center(child: CircularProgressIndicator()))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < users.length; i++) ...[
                      if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: divider),
                      _row(users[i], i),
                    ],
                  ]),
                ),
                const SizedBox(height: 10),
                const Text('Tocca un utente per vedere i telefoni, cambiare il PIN o scollegarlo',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: _newUser, icon: const Icon(Icons.add), label: const Text('Nuovo utente')),
              ]),
            ),
    );
  }
}

class _NewUserDialog extends StatefulWidget {
  const _NewUserDialog();
  @override
  State<_NewUserDialog> createState() => _NewUserDialogState();
}

class _NewUserDialogState extends State<_NewUserDialog> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  bool _admin = false;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await attempt(
      context,
      () => Api.instance.post('/admin/utenti', {'nome': _name.text.trim(), 'pin': _pin.text.trim(), 'admin': _admin}),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok != null) {
      toast(context, 'Utente creato: dagli nome e PIN');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nuovo utente'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome e cognome'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 12,
              decoration: const InputDecoration(labelText: 'PIN (almeno 4 cifre)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Amministratore'),
              value: _admin,
              onChanged: (v) => setState(() => _admin = v),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _busy ? null : _save,
            child: const Text('Crea'),
          ),
        ],
      );
}

/// Un utente: telefoni collegati, accessi, permessi, PIN, scollega.
class UserScreen extends StatefulWidget {
  const UserScreen(this.user, {super.key, this.index = 0});
  final Map<String, dynamic> user;
  final int index;
  @override
  State<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  late Map<String, dynamic> _u = widget.user;

  bool get _isMe => _u['nome'] == Api.instance.userName;
  int get _id => _u['id'] as int;

  Future<void> _reload() async {
    try {
      final body = await Api.instance.get('/admin/utenti');
      final fresh = (body['utenti'] as List).cast<Map<String, dynamic>>().where((u) => u['id'] == _id);
      if (fresh.isNotEmpty && mounted) setState(() => _u = fresh.first);
    } on ApiError {
      // resta quello di prima
    }
  }

  Future<void> _set(Map<String, dynamic> change, String done) async {
    final ok = await attempt(context, () => Api.instance.patch('/admin/utenti/$_id', change));
    if (ok != null && mounted) {
      toast(context, done);
      _reload();
    }
  }

  Future<void> _changePin() async {
    final pin = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nuovo PIN per ${_u['nome']}'),
        content: TextField(
          controller: pin,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: const InputDecoration(labelText: 'Almeno 4 cifre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, pin.text.trim()),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty || !mounted) return;
    await _set({'pin': value}, _isMe ? 'PIN cambiato' : 'PIN cambiato: dovrà rientrare con quello nuovo');
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Scollegare ${_u['nome']}?'),
        content: const Text('Esce da tutti i telefoni: dovrà rientrare con nome e PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: C.badFg),
            child: const Text('Scollega'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final ok = await attempt(context, () => Api.instance.post('/admin/utenti/$_id/scollega', {}));
    if (ok != null && mounted) {
      toast(context, 'Scollegato da ${ok['scollegati']} telefoni');
      _reload();
    }
  }

  Widget _stat(String value, String label) => Expanded(
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: C.muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final phones = ((_u['telefoni'] as List?) ?? []).cast<Map<String, dynamic>>();
    return HeaderScaffold(
      header: NavyHeader(
        title: _u['nome'] as String,
        subtitle: [
          _u['admin'] == true ? 'Amministratore' : 'Utente',
          if (_u['attivo'] != true) 'disattivato',
        ].join(' · '),
        back: true,
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            _stat('${_u['foto_inviate'] ?? 0}', 'foto dall\'app'),
            const SizedBox(width: 8),
            _stat('${phones.length}', phones.length == 1 ? 'telefono' : 'telefoni'),
            const SizedBox(width: 8),
            _stat(lastSeen(_u['ultimo_accesso']), 'ultimo accesso'),
          ]),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(padding: EdgeInsets.fromLTRB(14, 12, 14, 0), child: SectionLabel('Telefoni collegati')),
              if (phones.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Nessun telefono collegato', style: TextStyle(color: C.muted)),
                ),
              for (var i = 0; i < phones.length; i++) ...[
                if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: divider),
                MenuRow(
                  icon: Icons.smartphone,
                  title: phones[i]['telefono'] as String? ?? 'telefono',
                  subtitle: 'Ultimo uso ${lastSeen(phones[i]['ultimo_uso'])} · entrato il ${_localDay(phones[i]['entrato_il'] as String?)}',
                ),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                title: const Text('Amministratore'),
                subtitle: const Text('Utenti, esportazioni, elimina e rileggi schede'),
                value: _u['admin'] == true,
                onChanged: _isMe ? null : (v) => _set({'admin': v}, v ? 'Ora è amministratore' : 'Non è più amministratore'),
              ),
              divider,
              SwitchListTile(
                title: const Text('Attivo'),
                subtitle: const Text('Se spento non può più entrare'),
                value: _u['attivo'] == true,
                onChanged: _isMe ? null : (v) => _set({'attivo': v}, v ? 'Riattivato' : 'Disattivato e scollegato'),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(onPressed: _changePin, icon: const Icon(Icons.key_outlined), label: const Text('Cambia PIN')),
            ),
            if (!_isMe) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: C.badFg, side: const BorderSide(color: Color(0xFFEBC3BE))),
                  onPressed: phones.isEmpty ? null : _disconnect,
                  icon: const Icon(Icons.logout),
                  label: const Text('Scollega'),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          if (!_isMe)
            const Text('"Scollega" lo fa uscire da tutti i telefoni: dovrà rientrare con il PIN',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
      ),
    );
  }
}
