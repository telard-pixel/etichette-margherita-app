import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api.dart';
import 'platform/platform.dart' as platform;
import 'ui.dart';

class UpdateInfo {
  UpdateInfo(this.installedName, this.installedBuild, this.latestName, this.latestBuild,
      {this.apkSha256, this.webBuild, this.notice});
  final String installedName;
  final int installedBuild;
  final String? latestName;
  final int? latestBuild;
  /// Impronta dell'APK sul server: il file scaricato si controlla prima di
  /// installarlo (revisione 6/10/2026).
  final String? apkSha256;
  /// La versione web pubblicata (per la pagina aperta da giorni).
  final int? webBuild;
  /// Un avviso del server da mostrare una volta (es. manutenzione notturna).
  final Map<String, dynamic>? notice;
  bool get available => latestBuild != null && latestBuild! > installedBuild;
}

/// Aggiornamento dell'app: la CI carica ogni nuova APK sul server, l'app la
/// scarica da li' (con l'accesso dell'utente) e la fa installare ad Android.
class Updater {
  /// L'ultima versione gia' proposta e quando si e' controllato: la stessa
  /// versione si propone una volta sola, ma una piu' nuova si propone anche
  /// se l'app e' rimasta aperta per giorni.
  static int? _offeredBuild;
  static DateTime? _lastCheck;
  static bool _installing = false;

  static Future<UpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final body = await Api.instance.get('/version');
    _lastCheck = DateTime.now();
    return UpdateInfo(
      info.version,
      int.tryParse(info.buildNumber) ?? 0,
      body['app_ultima_versione'] as String?,
      body['app_ultima_build'] as int?,
      apkSha256: body['app_apk_sha256'] as String?,
      webBuild: body['web_ultima_build'] as int?,
      notice: body['avviso'] is Map ? (body['avviso'] as Map).cast<String, dynamic>() : null,
    );
  }

  static bool _cleaned = false;

  /// La pagina web aperta da giorni (o salvata sulla Home dell'iPhone) non
  /// si ricarica mai da sola: se sul server c'e' una versione piu' nuova di
  /// quella in uso, si propone di ricaricare (revisione 6/10/2026).
  static Future<void> _offerWebReload(BuildContext context, UpdateInfo info) async {
    final web = info.webBuild;
    if (web == null || info.installedBuild == 0 || web <= info.installedBuild || web == _offeredBuild) return;
    _offeredBuild = web;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Versione nuova'),
        content: const Text('È uscita una versione nuova dell\'app. Ricarico la pagina?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Più tardi')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ricarica'),
          ),
        ],
      ),
    );
    if (yes == true) platform.reloadPage();
  }

  /// All'avvio e quando l'app torna in primo piano (al massimo ogni ora):
  /// se c'e' una versione nuova la propone.
  static Future<void> offerIfNew(BuildContext context, {bool onResume = false}) async {
    if (_installing) return;
    if (!_cleaned) {
      _cleaned = true;
      platform.cleanupDownloads();
    }
    // Foto scattate e non inviate, un invio o una stampa in corso:
    // l'installazione chiuderebbe l'app. Si riprova al prossimo ritorno.
    if (unsavedWork.value > 0) {
      _lastCheck = null;
      return;
    }
    if (onResume && _lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(hours: 1)) return;
    UpdateInfo info;
    try {
      info = await check();
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await _showNotice(context, info.notice);
    if (!context.mounted || unsavedWork.value > 0) return;
    if (platform.isWebApp) return _offerWebReload(context, info);
    // Un aggiornamento gia' tentato e non installato (di solito: firma
    // diversa, Android dice "in conflitto con un pacchetto esistente"): si
    // spiega cosa fare invece di riscaricarlo a ogni avvio.
    final tried = int.tryParse(await Api.instance.readSetting('aggiornamento_tentato') ?? '');
    if (tried != null && info.installedBuild >= tried) {
      await Api.instance.writeSetting('aggiornamento_tentato', null);
    } else if (tried != null && tried == info.latestBuild && _offeredBuild != tried) {
      _offeredBuild = tried;
      if (!context.mounted) return;
      final again = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Aggiornamento non installato'),
          // Revisione 31/10/2026: "in conflitto" vuol dire firma diversa, cioe' un APK che non e'
          // nostro. Disinstallare toglierebbe proprio il controllo che lo ha fermato.
          content: Text('La versione ${info.latestName} è stata scaricata ma non si è installata. '
              'Se Android ha detto "in conflitto con un pacchetto esistente", NON disinstallare '
              'Etichette: avvisa l\'amministratore, l\'aggiornamento non è firmato da noi.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Ok')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Riprova')),
          ],
        ),
      );
      if (again == true && context.mounted) await install(context, info);
      return;
    }
    if (!info.available || info.latestBuild == _offeredBuild || !context.mounted) return;
    _offeredBuild = info.latestBuild;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiornamento disponibile'),
        content: Text('Versione ${info.latestName} (installata ${info.installedName}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Più tardi')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Installa')),
        ],
      ),
    );
    if (yes == true && context.mounted) await install(context, info);
  }

  /// Un avviso del server (manutenzione e simili, 8/10/2026): una finestra,
  /// una volta sola per avviso su questo telefono o browser.
  static Future<void> _showNotice(BuildContext context, Map<String, dynamic>? notice) async {
    final id = notice?['id'] as String?;
    if (notice == null || id == null || id.isEmpty || Api.noNotices) return;
    if (await Api.instance.readSetting('avviso_visto') == id || !context.mounted) return;
    await Api.instance.writeSetting('avviso_visto', id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.build_circle_outlined, size: 32),
        title: Text(notice['titolo'] as String? ?? 'Avviso'),
        content: SingleChildScrollView(child: Text(notice['testo'] as String? ?? '')),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
  }

  static Future<void> install(BuildContext context, [UpdateInfo? info]) async {
    if (_installing) return;
    _installing = true;
    if (info == null) {
      // Dal menu Altro: l'impronta serve sempre, la si chiede al server (31/10/2026).
      try {
        info = await check();
      } catch (_) {
        _installing = false;
        if (context.mounted) toast(context, 'Non riesco a controllare l\'aggiornamento: riprova', error: true);
        return;
      }
      if (!context.mounted) {
        _installing = false;
        return;
      }
    }
    final progress = ValueNotifier<double?>(null);
    final dialog = BlockingDialog.show(
      context,
      title: 'Scarico l\'aggiornamento…',
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (context, value, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: value),
          if (value != null) ...[
            const SizedBox(height: 8),
            Text('${(value * 100).round()}%'),
          ],
        ]),
      ),
    );
    String? problem;
    try {
      final apk = await Api.instance.download('/apk', onProgress: (v) => progress.value = v);
      dialog.close();
      final expected = info.apkSha256;
      // Senza impronta dal server non si installa (31/10/2026): prima un file troncato andava
      // dritto all'installatore.
      if (expected == null || expected.isEmpty || sha256.convert(apk).toString() != expected) {
        // Download troncato o rovinato per strada: non lo si installa.
        throw ApiError(0, 'Il file scaricato non è integro: riprova');
      }
      if (info.latestBuild != null) {
        await Api.instance.writeSetting('aggiornamento_tentato', '${info.latestBuild}');
      }
      problem = await platform.installApk(apk);
      // Di solito e' il permesso "installa app sconosciute" appena chiesto:
      // la stessa versione si potra' riproporre.
      if (problem != null) _offeredBuild = null;
    } on ApiError catch (e) {
      problem = 'Download non riuscito: ${e.message}';
    } catch (e) {
      // Qualunque altro errore (memoria piena, permessi): la finestra non
      // deve restare aperta per sempre.
      problem = 'Aggiornamento non riuscito: $e';
    } finally {
      dialog.close();
      _installing = false;
    }
    if (problem != null && context.mounted) toast(context, problem, error: true);
  }
}
