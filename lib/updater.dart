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
  static bool _offered = false;

  static Future<UpdateInfo> check() async {
    final info = await PackageInfo.fromPlatform();
    final body = await Api.instance.get('/version');
    return UpdateInfo(
      info.version,
      int.tryParse(info.buildNumber) ?? 0,
      body['app_ultima_versione'] as String?,
      body['app_ultima_build'] as int?,
    );
  }

  /// All'avvio: se c'e' una versione nuova la propone, una volta sola.
  static Future<void> offerIfNew(BuildContext context) async {
    if (_offered) return;
    _offered = true;
    UpdateInfo info;
    try {
      info = await check();
    } catch (_) {
      return;
    }
    if (!info.available || !context.mounted) return;
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
    final progress = ValueNotifier<double?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Scarico l\'aggiornamento…'),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (context, value, _) => LinearProgressIndicator(value: value),
        ),
      ),
    );
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/EtichetteMargherita.apk');
      if (await file.exists()) await file.delete();
      await Api.instance.download('/apk', file, onProgress: (v) => progress.value = v);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && context.mounted) {
        toast(context, 'Installazione non avviata: ${result.message}', error: true);
      }
    } on ApiError catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        toast(context, 'Download non riuscito: ${e.message}', error: true);
      }
    }
  }
}
