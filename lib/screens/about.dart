import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api.dart';
import '../platform/platform.dart' as platform;
import '../ui.dart';

/// Altro > Informazioni (8/10/2026): versione, server, cosa resta sul
/// telefono e cosa sul server, licenze dei componenti usati.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = '${info.version} (build ${info.buildNumber})');
    }, onError: (_) {});
  }

  Widget _section(String title, List<String> lines) => Panel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionLabel(title),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(padding: const EdgeInsets.only(top: 7), child: Dot(C.faint, size: 5)),
                const SizedBox(width: 10),
                Expanded(child: Text(line, style: const TextStyle(fontSize: 14, height: 1.4))),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => HeaderScaffold(
        header: const NavyHeader(title: 'Informazioni', back: true),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              MenuRow(
                icon: Symbols.sell_rounded,
                title: 'Etichette Margherita',
                subtitle: _version.isEmpty ? 'Versione…' : 'Versione $_version${platform.isWebApp ? ' · web' : ''}',
              ),
              divider,
              MenuRow(icon: Symbols.dns_rounded, title: 'Server', subtitle: Uri.parse(kServer).host),
            ]),
          ),
          const SizedBox(height: 12),
          _section('Sul server', const [
            'Le foto delle etichette e quello che si legge (prodotto, lotto, scadenza, produttore, allergeni).',
            'Chi ha mandato ogni foto e chi ha fatto ogni correzione, con data e ora.',
            'Nome, PIN (solo in forma cifrata, mai leggibile) e i telefoni collegati di ogni utente.',
            'Le foto restano anche sul cloud del ristorante; un backup cifrato si fa ogni settimana.',
          ]),
          const SizedBox(height: 12),
          _section(platform.isWebApp ? 'In questo browser' : 'Su questo telefono', [
            platform.isWebApp
                ? 'Il collegamento (non il PIN), salvato in questo browser: con "Esci" si cancella.'
                : 'Il collegamento (non il PIN), in un archivio cifrato del telefono: con "Esci" si cancella.',
            if (!platform.isWebApp) 'Le foto già viste, per non riscaricarle: il telefono le può togliere quando serve spazio.',
            'Le foto scattate e non ancora inviate, finché non partono.',
          ]),
          const SizedBox(height: 12),
          _section('Errori', const [
            'Se l\'app incontra un errore imprevisto, manda al server il messaggio d\'errore, la versione '
                'e il modello del telefono, per poterlo correggere. Niente foto, schede, nomi o PIN.',
          ]),
          const SizedBox(height: 12),
          Panel(
            padding: EdgeInsets.zero,
            child: MenuRow(
              icon: Symbols.description_rounded,
              title: 'Licenze',
              subtitle: 'I componenti open source usati dall\'app',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Etichette Margherita',
                applicationVersion: _version,
              ),
            ),
          ),
        ]),
      );
}
