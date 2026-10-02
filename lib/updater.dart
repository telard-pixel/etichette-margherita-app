import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'ui.dart';

class UpdateInfo {
  UpdateInfo(this.installedName, this.installedBuild, this.latestName, this.latestBuild);
  final String installedName;
  final int installedBuild;
  final String? latestName;
  final int? latestBuild;
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
    );
  }

  /// All'avvio e quando l'app torna in primo piano (al massimo ogni ora):
  /// se c'e' una versione nuova la propone.
  static Future<void> offerIfNew(BuildContext context, {bool onResume = false}) async {
    if (_installing) return;
    if (onResume && _lastCheck != null && DateTime.now().difference(_lastCheck!) < const Duration(hours: 1)) return;
    UpdateInfo info;
    try {
      info = await check();
    } catch (_) {
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
    if (yes == true && context.mounted) await install(context);
  }

  static Future<void> install(BuildContext context) async {
    if (_installing) return;
    _installing = true;
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
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/EtichetteMargherita.apk');
      if (await file.exists()) await file.delete();
      await Api.instance.download('/apk', file, onProgress: (v) => progress.value = v);
      dialog.close();
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) {
        // Di solito e' il permesso "installa app sconosciute" appena chiesto:
        // la stessa versione si potra' riproporre.
        _offeredBuild = null;
        problem = result.type == ResultType.permissionDenied
            ? 'Consenti "Installa app sconosciute" per Etichette, poi riprova da Altro › Aggiornamento'
            : 'Installazione non avviata: ${result.message}';
      }
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
