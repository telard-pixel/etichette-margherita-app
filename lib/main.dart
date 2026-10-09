import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'error_report.dart';
import 'platform/platform.dart' as platform;
import 'screens/home.dart';
import 'screens/login.dart';
import 'ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorReport.install();
  // Tema chiaro o scuro come il telefono (o il computer), gia' dal primo
  // disegno.
  C.dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  // Intestazioni chiare di giorno, scure di notte: icone di stato al contrario.
  SystemChrome.setSystemUIOverlayStyle(
    C.dark
        ? const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, statusBarBrightness: Brightness.dark)
        : const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark, statusBarBrightness: Brightness.light),
  );
  Api.onEngineNotice = (notice) {
    final messenger = messengerKey.currentState;
    if (messenger != null) showEngineNotice(messenger, notice);
  };
  runApp(const EtichetteApp());
  // Nella versione web il gesto "indietro" chiude la schermata aperta (se
  // ce n'e' una) invece di ricaricare la pagina.
  platform.onBrowserBack(() => navigatorKey.currentState?.maybePop());
}

class EtichetteApp extends StatelessWidget {
  const EtichetteApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Etichette Margherita',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        // Sul computer le foto della scheda e le liste si trascinano anche
        // col mouse (prima solo col dito: col mouse non si sfogliavano).
        scrollBehavior: const MaterialScrollBehavior().copyWith(dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        }),
        theme: appTheme(),
        darkTheme: appTheme(dark: true),
        themeMode: ThemeMode.system,
        builder: (context, child) {
          // Il telefono passa al tema scuro (o torna chiaro), anche con l'app
          // aperta: i colori di C cambiano e tutto si ridisegna.
          final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          if (dark != C.dark) {
            C.dark = dark;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final root = WidgetsBinding.instance.rootElement;
              if (root != null) _rebuildAll(root);
            });
          }
          return child!;
        },
        locale: const Locale('it'),
        supportedLocales: const [Locale('it')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const StartGate(),
      );
}

void _rebuildAll(Element element) {
  element.markNeedsBuild();
  element.visitChildren(_rebuildAll);
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
      Scaffold(backgroundColor: C.navy, body: const Center(child: CircularProgressIndicator(color: C.sand)));
}
