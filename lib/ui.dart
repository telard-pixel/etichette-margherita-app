import 'package:flutter/material.dart';

import 'api.dart';

/// Colori dell'anteprima approvata: blu notte, accento blu, verde per "ok".
class C {
  static const navy = Color(0xFF0F1B2D);
  static const ground = Color(0xFFF3F5F8);
  static const line = Color(0xFFDCE2EA);
  static const border = Color(0xFFC9D1DC);
  static const muted = Color(0xFF556072);
  static const blue = Color(0xFF1F5FD1);
  static const softBlue = Color(0xFF8FB1F0);
  static const okBg = Color(0xFFE3F4EA), okFg = Color(0xFF17663A);
  static const warnBg = Color(0xFFFDF0DC), warnFg = Color(0xFF8A4204);
  static const badBg = Color(0xFFFBE4E2), badFg = Color(0xFFA12A21);
  static const infoBg = Color(0xFFE4ECFB), infoFg = Color(0xFF1A4FB0);
  static const green = Color(0xFF1E8E4E), red = Color(0xFFC0362C);
}

const mono = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.blue, primary: C.blue, surface: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.ground,
    appBarTheme: const AppBarTheme(
      backgroundColor: C.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: C.line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: C.navy,
        backgroundColor: Colors.white,
        side: const BorderSide(color: C.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: C.infoBg),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.icon});
  final String text;
  final Color bg, fg;
  final IconData? icon;

  factory Pill.status(Map<String, dynamic> s) {
    if (s['in_lavorazione'] == true) return const Pill('In lettura…', bg: C.infoBg, fg: C.infoFg, icon: Icons.sync);
    if (s['fallita'] == true) return const Pill('Non riuscita', bg: C.badBg, fg: C.badFg);
    if (s['da_rivedere'] == true) return const Pill('Da rivedere', bg: C.warnBg, fg: C.warnFg);
    return const Pill('Archiviata', bg: C.okBg, fg: C.okFg);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = C.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: 12, letterSpacing: .7, fontWeight: FontWeight.w600, color: color));
}

/// Foto di una scheda dal server (con l'accesso dell'utente).
class ItemPhoto extends StatelessWidget {
  const ItemPhoto(this.itemId, {super.key, this.mini = false, this.fit = BoxFit.cover});
  final int itemId;
  final bool mini;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => Image.network(
        Api.instance.uri('/schede/$itemId/foto', mini ? {'mini': '1'} : null).toString(),
        headers: Api.instance.authHeaders,
        fit: fit,
        errorBuilder: (context, error, stack) =>
            const ColoredBox(color: C.line, child: Center(child: Icon(Icons.image_not_supported_outlined, color: C.muted))),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const ColoredBox(color: C.line, child: SizedBox.expand()),
      );
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? C.badFg : C.navy));
}

/// Esegue una richiesta e mostra l'errore, se c'e'. Null se fallita.
Future<T?> attempt<T>(BuildContext context, Future<T> Function() call) async {
  try {
    return await call();
  } on ApiError catch (e) {
    if (context.mounted && e.status != 401) toast(context, e.message, error: true);
    return null;
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry(this.message, this.onRetry, {super.key});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: C.muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Riprova')),
          ]),
        ),
      );
}
