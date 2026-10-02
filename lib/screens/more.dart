import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../api.dart';
import '../ui.dart';
import '../updater.dart';
import 'login.dart';
import 'users.dart';

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
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uscire da questo telefono?'),
        content: const Text('Per rientrare serviranno nome e PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Esci')),
        ],
      ),
    );
    if (sure != true) return;
    await Api.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Widget _machine(String name, bool? up, String detail) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Dot(up == null ? C.faint : (up ? C.green : C.red)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14.5))),
          Text(detail, style: const TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );

  Widget _healthPanel() {
    final h = _health!;
    final status = (h['stato'] as Map?)?.cast<String, dynamic>() ?? {};
    final checks = (status['checks'] as Map?)?.cast<String, dynamic>() ?? {};
    final counts = (status['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionLabel('Stato'),
        const SizedBox(height: 4),
        for (final m in (h['macchine'] as List).cast<Map<String, dynamic>>())
          _machine(m['nome'] as String, m['attiva'] as bool?, m['attiva'] == true ? 'attivo' : 'non risponde'),
        _machine('Stampante cucina', h['stampante_collegata'] == true, h['stampante_collegata'] == true ? 'collegata' : 'non collegata'),
        if (checks.isNotEmpty) _machine('Backup', checks['backup_fresh'] as bool?, checks['backup_fresh'] == true ? 'recente' : 'vecchio'),
        if (counts.isNotEmpty)
          _machine('Archivio', (counts['failed'] ?? 0) == 0, '${counts['archived'] ?? 0} schede · ${counts['failed'] ?? 0} fallite'),
      ]),
    );
  }

  Future<void> _chooseExport() async {
    final ext = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Esporta archivio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          MenuRow(icon: Icons.picture_as_pdf_outlined, title: 'PDF', subtitle: 'Con foto e lotto interno, da stampare',
              onTap: () => Navigator.pop(context, '.pdf')),
          MenuRow(icon: Icons.table_chart_outlined, title: 'Excel', subtitle: 'Un foglio per mese, con foto',
              onTap: () => Navigator.pop(context, '.xlsx')),
          MenuRow(icon: Icons.description_outlined, title: 'CSV', subtitle: 'Tutte le colonne, senza foto',
              onTap: () => Navigator.pop(context, '.csv')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (ext != null && mounted) await _export(ext);
  }

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
      // Con l'accesso scaduto la finestra l'ha gia' chiusa il ritorno alla
      // schermata di accesso.
      if (e.status != 401) close();
      if (mounted) toast(context, e.message, error: true);
    } on StateError {
      close();
      if (mounted) toast(context, 'File $extension non trovato', error: true);
    } catch (e) {
      close();
      if (mounted) toast(context, 'Esportazione non riuscita: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Api.instance;
    final update = _update;
    final online = _users.where((u) => (u['telefoni'] as List?)?.isNotEmpty == true).length;
    return HeaderScaffold(
      header: const NavyHeader(title: 'Altro'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            child: Row(children: [
              Initials(api.userName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(api.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Icon(api.isAdmin ? Icons.shield_outlined : Icons.person_outline, size: 14, color: C.muted),
                    const SizedBox(width: 4),
                    Text(api.isAdmin ? 'amministratore' : 'utente', style: const TextStyle(fontSize: 12.5, color: C.muted)),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (api.isAdmin && _health != null) ...[_healthPanel(), const SizedBox(height: 12)],
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (api.isAdmin) ...[
                MenuRow(
                  icon: Icons.group_outlined,
                  title: 'Utenti',
                  subtitle: _users.isEmpty ? 'Accessi, telefoni e PIN' : '${_users.length} utenti · $online collegati',
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen()));
                    _load();
                  },
                ),
                divider,
                MenuRow(
                  icon: Icons.download_outlined,
                  title: 'Esporta archivio',
                  subtitle: 'PDF, Excel o CSV con foto e lotto interno',
                  onTap: _chooseExport,
                ),
                divider,
              ],
              MenuRow(
                icon: Icons.system_update_outlined,
                title: update?.available == true ? 'Aggiornamento disponibile' : 'Aggiornamento',
                subtitle: update == null
                    ? 'Controllo…'
                    : update.available
                        ? 'Versione ${update.latestName} · installata ${update.installedName}'
                        : 'Versione ${update.installedName} · aggiornata',
                trailing: update?.available == true
                    ? FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: () => Updater.install(context),
                        child: const Text('Installa'),
                      )
                    : null,
                onTap: update?.available == true ? () => Updater.install(context) : _load,
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Panel(padding: EdgeInsets.zero, child: MenuRow(icon: Icons.logout, title: 'Esci', danger: true, onTap: _logout)),
        ]),
      ),
    );
  }
}
