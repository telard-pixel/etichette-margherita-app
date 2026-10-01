import 'package:flutter/material.dart';

import '../updater.dart';
import 'archive.dart';
import 'capture.dart';
import 'manual_label.dart';
import 'more.dart';

/// Aumenta quando l'archivio va ricaricato (foto inviata, scheda corretta).
final archiveChanged = ValueNotifier<int>(0);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Un'occhiata agli aggiornamenti a ogni avvio, senza disturbare se non ce ne sono.
    WidgetsBinding.instance.addPostFrameCallback((_) => Updater.offerIfNew(context));
  }

  void _goTo(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          const ArchiveScreen(),
          CaptureScreen(onSent: () => _goTo(0)),
          const ManualLabelScreen(),
          const MoreScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Archivio'),
            NavigationDestination(icon: Icon(Icons.photo_camera_outlined), selectedIcon: Icon(Icons.photo_camera), label: 'Scatta'),
            NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'Etichette'),
            NavigationDestination(icon: Icon(Icons.menu), label: 'Altro'),
          ],
        ),
      );
}
