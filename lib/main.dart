import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Intestazioni blu notte in cima a ogni schermata: icone di stato chiare.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light),
  );
  runApp(const EtichetteApp());
}

class EtichetteApp extends StatelessWidget {
  const EtichetteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Etichette Margherita',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: appTheme(),
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const StartGate(),
      );
}

/// All'avvio: rientra con l'accesso salvato, altrimenti chiede nome e PIN.
class StartGate extends StatefulWidget {
  const StartGate({super.key});
  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  @override
  void initState() {
    super.initState();
    Api.instance.onLoggedOut = () {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen(expired: true)),
        (_) => false,
      );
    };
    _start();
  }

  Future<void> _start() async {
    final ok = await Api.instance.restore();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ok ? const HomeScreen() : const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(backgroundColor: C.navy, body: Center(child: CircularProgressIndicator(color: Colors.white)));
}
