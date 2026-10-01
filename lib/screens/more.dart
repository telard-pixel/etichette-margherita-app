import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../ui.dart';
import '../updater.dart';
import 'login.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});
  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  UpdateInfo? _update;
  Map<String, dynamic>? _health;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final update = await Updater.check();
      if (mounted) setState(() => _update = update);
    } catch (_) {}
    if (!Api.instance.isAdmin) return;
    try {
      final health = await Api.instance.get('/salute');
      final users = await Api.instance.get('/admin/utenti');
      if (!mounted) return;
      setState(() {
        _health = health;
        _users = (users['utenti'] as List).cast<Map<String, dynamic>>();
      });
    } on ApiError {
      // la schermata resta usabile anche senza stato
    }
  }

  Future<void> _logout() async {
    await Api.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Widget _machine(String name, bool? up, String detail) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(shape: BoxShape.circle, color: up == null ? C.muted : (up ? C.green : C.red)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 15))),
          Text(detail, style: const TextStyle(color: C.muted, fontSize: 13)),
        ]),
      );

  Widget _healthCard() {
    final h = _health!;
    final status = (h['stato'] as Map?)?.cast<String, dynamic>() ?? {};
    final checks = (status['checks'] as Map?)?.cast<String, dynamic>() ?? {};
    final counts = (status['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionLabel('Stato'),
          const SizedBox(height: 6),
          for (final m in (h['macchine'] as List).cast<Map<String, dynamic>>())
            _machine(m['nome'] as String, m['attiva'] as bool?, m['attiva'] == true ? 'attiva' : 'non risponde'),
          _machine('Stampante', h['stampante_collegata'] == true, h['stampante_collegata'] == true ? 'collegata' : 'non collegata'),
          if (checks.isNotEmpty) _machine('Backup', checks['backup_fresh'] as bool?, checks['backup_fresh'] == true ? 'recente' : 'vecchio'),
          if (counts.isNotEmpty)
            _machine('Archivio', (counts['failed'] ?? 0) == 0, '${counts['archived'] ?? 0} schede · ${counts['failed'] ?? 0} fallite'),
        ]),
      ),
    );
  }

  Future<void> _userDialog([Map<String, dynamic>? user]) async {
    final name = TextEditingController(text: user?['nome'] ?? '');
    final pin = TextEditingController();
    var admin = user?['admin'] == true;
    var active = user?['attivo'] ?? true;
    final isMe = user != null && user['nome'] == Api.instance.userName;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(user == null ? 'Nuovo utente' : user['nome'] as String),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome e cognome'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 12,
                decoration: InputDecoration(labelText: user == null ? 'PIN (almeno 4 cifre)' : 'Nuovo PIN (vuoto = invariato)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Amministratore'),
                value: admin,
                onChanged: isMe ? null : (v) => setDialog(() => admin = v),
              ),
              if (user != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Attivo'),
                  value: active,
                  onChanged: isMe ? null : (v) => setDialog(() => active = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final body = user == null
        ? {'nome': name.text.trim(), 'pin': pin.text.trim(), 'admin': admin}
        : {
            if (name.text.trim() != user['nome']) 'nome': name.text.trim(),
            if (pin.text.trim().isNotEmpty) 'pin': pin.text.trim(),
            'admin': admin,
            'attivo': active,
          };
    final result = await attempt(
      context,
      () => user == null ? Api.instance.post('/admin/utenti', body) : Api.instance.patch('/admin/utenti/${user['id']}', body),
    );
    if (result != null && mounted) {
      toast(context, user == null ? 'Utente creato: dagli nome e PIN' : 'Utente aggiornato');
      _load();
    }
  }

  Widget _usersCard() => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
          child: Column(children: [
            Row(children: [
              const Expanded(child: SectionLabel('Utenti app')),
              TextButton.icon(onPressed: () => _userDialog(), icon: const Icon(Icons.add), label: const Text('Nuovo')),
            ]),
            for (final u in _users)
              ListTile(
                contentPadding: const EdgeInsets.only(right: 4),
                leading: Icon(Icons.person_outline, color: u['attivo'] == true ? C.navy : C.muted),
                title: Text(u['nome'] as String,
                    style: TextStyle(color: u['attivo'] == true ? C.navy : C.muted,
                        decoration: u['attivo'] == true ? null : TextDecoration.lineThrough)),
                subtitle: u['admin'] == true ? const Text('amministratore') : null,
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _userDialog(u),
              ),
          ]),
        ),
      );

  Future<void> _export(String extension) async {
    final status = ValueNotifier<String>('Preparo l\'esportazione…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Esporta archivio'),
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (context, value, _) => Row(children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text(value)),
          ]),
        ),
      ),
    );
    void close() {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      final started = await Api.instance.post('/admin/esporta', {});
      final id = started['esportazione']['id'];
      Map<String, dynamic> job = started['esportazione'] as Map<String, dynamic>;
      for (var i = 0; i < 300 && job['stato'] == 'in_corso'; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        job = (await Api.instance.get('/admin/esporta/$id'))['esportazione'] as Map<String, dynamic>;
        final p = job['avanzamento'] as String? ?? '';
        status.value = p.isEmpty ? 'Preparo l\'esportazione…' : 'Raccolgo le foto: $p';
      }
      if (job['stato'] != 'pronta') throw ApiError(0, 'esportazione non riuscita');
      final name = (job['file'] as List).cast<String>().firstWhere((f) => f.endsWith(extension));
      status.value = 'Scarico $name…';
      final dir = await getTemporaryDirectory();
      final file = await Api.instance.download('/admin/esporta/$id/$name', File('${dir.path}/$name'));
      close();
      await OpenFilex.open(file.path);
    } on ApiError catch (e) {
      close();
      if (mounted) toast(context, e.message, error: true);
    } on StateError {
      close();
      if (mounted) toast(context, 'File $extension non trovato', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Api.instance;
    final update = _update;
    return Scaffold(
      appBar: AppBar(title: const Text('Altro')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined, size: 32),
              title: Text(api.userName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(api.isAdmin ? 'amministratore' : 'utente'),
            ),
          ),
          const SizedBox(height: 12),
          if (api.isAdmin && _health != null) ...[_healthCard(), const SizedBox(height: 12)],
          if (api.isAdmin) ...[_usersCard(), const SizedBox(height: 12)],
          if (api.isAdmin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Esporta archivio'),
                  const SizedBox(height: 10),
                  Row(children: [
                    for (final (label, ext) in const [('CSV', '.csv'), ('Excel', '.xlsx'), ('PDF', '.pdf')])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), padding: EdgeInsets.zero),
                            onPressed: () => _export(ext),
                            icon: const Icon(Icons.download, size: 18),
                            label: Text(label, style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            color: update?.available == true ? const Color(0xFFF6F9FF) : null,
            child: ListTile(
              title: Text(update?.available == true ? 'Aggiornamento disponibile' : 'App aggiornata',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(update == null
                  ? 'Controllo…'
                  : update.available
                      ? 'Versione ${update.latestName} · installata ${update.installedName}'
                      : 'Versione ${update.installedName}'),
              trailing: update?.available == true
                  ? FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: () => Updater.install(context),
                      child: const Text('Installa'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: C.badFg, side: const BorderSide(color: Color(0xFFE7B9B4))),
            onPressed: _logout,
            child: const Text('Esci'),
          ),
        ]),
      ),
    );
  }
}
