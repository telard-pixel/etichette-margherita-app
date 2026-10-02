import 'package:flutter/material.dart';

import '../ui.dart';
import '../updater.dart';
import 'archive.dart';
import 'capture.dart';
import 'expiring.dart';
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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Un'occhiata agli aggiornamenti a ogni avvio e quando l'app torna in
    // primo piano: in cucina resta aperta per giorni senza mai ripartire.
    WidgetsBinding.instance.addPostFrameCallback((_) => Updater.offerIfNew(context));
    _lifecycle = AppLifecycleListener(onResume: () {
      archiveChanged.value++;
      if (mounted) Updater.offerIfNew(context, onResume: true);
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _goTo(int tab) {
    // Ogni volta che si torna su una scheda i dati si rinfrescano (l'app puo'
    // restare aperta in cucina per giorni).
    archiveChanged.value++;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          const ArchiveScreen(),
          const ExpiringScreen(),
          CaptureScreen(onSent: () => _goTo(0)),
          const ManualLabelScreen(),
          const MoreScreen(),
        ]),
        bottomNavigationBar: _BottomNav(selected: _tab, onSelected: _goTo),
      );
}

/// Il menu in basso: cinque voci, con Scatta grande al centro.
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  static const _items = [
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Archivio'),
    (Icons.schedule_outlined, Icons.schedule, 'Scadenze'),
    (Icons.photo_camera_outlined, Icons.photo_camera, 'Scatta'),
    (Icons.sell_outlined, Icons.sell, 'Etichette'),
    (Icons.menu, Icons.menu, 'Altro'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0xFFE3E8EE), offset: Offset(0, -1))]),
        padding: EdgeInsets.fromLTRB(6, 4, 6, MediaQuery.of(context).padding.bottom + 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < _items.length; i++) Expanded(child: i == 2 ? _camera(i) : _item(i)),
        ]),
      );

  Widget _item(int i) {
    final (icon, iconOn, label) = _items[i];
    final on = selected == i;
    return Semantics(
      selected: on,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelected(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 52,
              height: 30,
              decoration: BoxDecoration(color: on ? C.infoBg : Colors.transparent, borderRadius: BorderRadius.circular(15)),
              child: Icon(on ? iconOn : icon, size: 22, color: on ? C.blue : C.muted),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 11.5, color: on ? C.navy : C.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }

  Widget _camera(int i) {
    final on = selected == i;
    return Semantics(
      selected: on,
      button: true,
      label: 'Scatta',
      child: GestureDetector(
        onTap: () => onSelected(i),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Transform.translate(
            offset: const Offset(0, -10),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: C.blue,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x591F5FD1), blurRadius: 16, offset: Offset(0, 6))],
              ),
              child: const Icon(Icons.photo_camera, color: Colors.white, size: 26),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -6),
            child: Text('Scatta',
                style: TextStyle(fontSize: 11.5, color: on ? C.navy : C.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
          ),
        ]),
      ),
    );
  }
}
