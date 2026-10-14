import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../platform/platform.dart' as platform;
import '../ui.dart';
import '../updater.dart';
import 'about.dart';
import 'login.dart';
import 'machines.dart';
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
      if (!platform.isWebApp) {
        final update = await Updater.check();
        if (mounted) setState(() => _update = update);
      }
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

  Future<void> _setNoNotices(bool value) async {
    setState(() => Api.noNotices = value);
    await Api.instance.setNoNotices(value);
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
          Text(detail, style: TextStyle(color: C.muted, fontSize: 12)),
        ]),
      );

  Widget _printerRow(Map<String, dynamic> h) {
    final printer = (h['stampante'] as Map?)?.cast<String, dynamic>() ?? {};
    final state = printerState(h);
    final name = printerName(printer);
    return _machine(name == 'Stampante' ? 'Stampante cucina' : name, state.ok, state.text);
  }

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
        _printerRow(h),
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
          MenuRow(icon: Symbols.picture_as_pdf_rounded, title: 'PDF', subtitle: 'Con foto e lotto interno, da stampare',
              onTap: () => Navigator.pop(context, '.pdf')),
          MenuRow(icon: Symbols.table_chart_rounded, title: 'Excel', subtitle: 'Un foglio per mese, con foto',
              onTap: () => Navigator.pop(context, '.xlsx')),
          MenuRow(icon: Symbols.description_rounded, title: 'CSV', subtitle: 'Tutte le colonne, senza foto',
              onTap: () => Navigator.pop(context, '.csv')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (ext != null && mounted) await _export(ext);
  }

  Future<void> _export(String extension) async {
    final status = ValueNotifier<String>('Preparo l\'esportazione…');
    final dialog = BlockingDialog.show(
      context,
      title: 'Esporta archivio',
      content: ValueListenableBuilder<String>(
        valueListenable: status,
        builder: (context, value, _) => Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(value)),
        ]),
      ),
    );
    String? problem;
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
      final names = (job['file'] as List).cast<String>().where((f) => f.endsWith(extension));
      if (names.isEmpty) throw ApiError(0, 'file $extension non trovato');
      final name = names.first;
      if (platform.isWebApp) {
        // Nel browser (soprattutto iPhone) un file passato in memoria spesso
        // non si salvava, senza errore: si chiede al server un link firmato
        // e lo si apre col tocco dell'utente (revisione 6/10/2026).
        final link = (await Api.instance.post('/admin/esporta/$id/${Uri.encodeComponent(name)}/link', {}))['url'] as String;
        dialog.close();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Esportazione pronta'),
            content: Text('$name è pronto. Il link vale 10 minuti.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () {
                  platform.openDownloadLink('$kServer$link');
                  Navigator.pop(context);
                },
                child: const Text('Scarica'),
              ),
            ],
          ),
        );
        return;
      }
      status.value = 'Scarico $name…';
      final data = await Api.instance.download('/admin/esporta/$id/$name');
      dialog.close();
      problem = await platform.deliverFile(name, data);
    } on ApiError catch (e) {
      problem = e.status == 401 ? null : e.message;
    } catch (e) {
      problem = 'Esportazione non riuscita: $e';
    } finally {
      dialog.close();
    }
    if (problem != null && mounted) toast(context, problem, error: true);
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
                    Icon(api.isAdmin ? Symbols.shield_rounded : Symbols.person_rounded, size: 14, color: C.muted),
                    const SizedBox(width: 4),
                    Text(api.isAdmin ? 'amministratore' : 'utente', style: TextStyle(fontSize: 12.5, color: C.muted)),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          if (api.isAdmin && _health != null) ...[_healthPanel(), const SizedBox(height: 12)],
          // Nella versione web non c'e' l'aggiornamento: a un utente normale
          // non resterebbe niente in questo riquadro.
          if (api.isAdmin || !platform.isWebApp) ...[
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (api.isAdmin) ...[
                MenuRow(
                  icon: Symbols.group_rounded,
                  title: 'Utenti',
                  subtitle: _users.isEmpty ? 'Accessi, telefoni e PIN' : '${_users.length} utenti · $online collegati',
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen()));
                    _load();
                  },
                ),
                divider,
                MenuRow(
                  icon: Symbols.dns_rounded,
                  title: 'Macchine e stampa',
                  subtitle: 'Stato, coda di stampa, riavvii',
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const MachinesScreen()));
                    _load();
                  },
                ),
                divider,
                MenuRow(
                  icon: Symbols.download_rounded,
                  title: 'Esporta archivio',
                  subtitle: 'PDF, Excel o CSV con foto e lotto interno',
                  onTap: _chooseExport,
                ),
                if (!platform.isWebApp) divider,
              ],
              if (!platform.isWebApp)
              MenuRow(
                icon: Symbols.system_update_rounded,
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
          ],
          Panel(
            padding: EdgeInsets.zero,
            child: MenuRow(
              icon: Symbols.notifications_off_rounded,
              title: 'Niente avvisi',
              subtitle: 'Nasconde i messaggi del server e quello sul motore AI occupato. Gli errori di invio restano',
              trailing: Switch(value: Api.noNotices, onChanged: _setNoNotices),
              onTap: () => _setNoNotices(!Api.noNotices),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: MenuRow(
              icon: Symbols.info_rounded,
              title: 'Informazioni',
              subtitle: 'Versione, dati salvati, licenze',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ),
          const SizedBox(height: 12),
          Panel(padding: EdgeInsets.zero, child: MenuRow(icon: Symbols.logout_rounded, title: 'Esci', danger: true, onTap: _logout)),
        ]),
      ),
    );
  }
}
