import 'package:flutter/material.dart';

import 'api.dart';

/// Colori e forme dell'anteprima approvata (versione 2): blu notte, accento
/// blu, schede bianche con ombra leggera al posto dei bordi.
class C {
  static const navy = Color(0xFF0F1B2D);
  static const ground = Color(0xFFF4F6F9);
  static const line = Color(0xFFEDF0F4);
  static const border = Color(0xFFD3DAE3);
  static const muted = Color(0xFF5A6577);
  static const faint = Color(0xFF9AA6B8);
  static const onNavyMuted = Color(0xFFA9B6CA);
  static const blue = Color(0xFF1F5FD1);
  static const softBlue = Color(0xFF8FB1F0);
  static const chipBg = Color(0xFFEEF1F5);
  static const okBg = Color(0xFFE3F4EA), okFg = Color(0xFF17663A);
  static const warnBg = Color(0xFFFDF0DC), warnFg = Color(0xFF8A4204);
  static const badBg = Color(0xFFFBE4E2), badFg = Color(0xFFA12A21);
  static const infoBg = Color(0xFFE4ECFB), infoFg = Color(0xFF1A4FB0);
  static const green = Color(0xFF1E8E4E), red = Color(0xFFC0362C);
  static const statWarn = Color(0xFFF6C177), statBad = Color(0xFFF29C93);
}

const mono = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600);

const panelShadow = [
  BoxShadow(color: Color(0x0F0F1B2D), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0D0F1B2D), blurRadius: 16, offset: Offset(0, 6)),
];

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.blue, primary: C.blue, surface: Colors.white);
  final radius14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.ground,
    appBarTheme: const AppBarTheme(backgroundColor: C.navy, foregroundColor: Colors.white, elevation: 0),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.border)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.blue, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: radius14,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: C.navy,
        backgroundColor: Colors.white,
        side: const BorderSide(color: C.border),
        shape: radius14,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: C.navy,
      side: const BorderSide(color: C.border),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: C.navy),
      secondaryLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white),
      showCheckmark: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}

/// Il riquadro bianco con ombra leggera di tutte le schermate.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.onTap, this.onLongPress, this.border});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final inner = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: color == C.navy ? null : panelShadow,
        border: border,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: onTap == null && onLongPress == null ? inner : InkWell(onTap: onTap, onLongPress: onLongPress, child: inner),
      ),
    );
  }
}

/// L'intestazione blu notte: titolo grande, sottotitolo, eventuale freccia
/// indietro, azioni a destra e, sotto, i contatori.
class NavyHeader extends StatelessWidget {
  const NavyHeader({super.key, required this.title, this.subtitle, this.back = false, this.actions = const [], this.bottom});
  final String title;
  final String? subtitle;
  final bool back;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Container(
        color: C.navy,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 14, 20, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (back) ...[
              HeaderButton(icon: Icons.arrow_back, tooltip: 'Indietro', onPressed: () => Navigator.maybePop(context)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.2)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: C.onNavyMuted, fontSize: 13)),
                ],
              ]),
            ),
            for (final a in actions) ...[const SizedBox(width: 8), a],
          ]),
          if (bottom != null) ...[const SizedBox(height: 14), bottom!],
        ]),
      );
}

class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color ?? Colors.white.withValues(alpha: .08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(icon, color: Colors.white),
        ),
      );
}

/// I tre numeri sotto l'intestazione.
class StatStrip extends StatelessWidget {
  const StatStrip(this.stats, {super.key});
  final List<(String value, String label, Color color)> stats;
  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(stats[i].$1, style: TextStyle(color: stats[i].$3, fontSize: 22, fontWeight: FontWeight.w700)),
                Text(stats[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.onNavyMuted, fontSize: 11.5)),
              ]),
            ),
          ),
        ],
      ]);
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.bg, required this.fg, this.icon});
  final String text;
  final Color bg, fg;
  final IconData? icon;

  factory Pill.status(Map<String, dynamic> s) {
    if (s['in_archiviazione'] == true) {
      return const Pill('In archiviazione…', bg: C.infoBg, fg: C.infoFg, icon: Icons.cloud_upload_outlined);
    }
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
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );
}

/// Un codice lotto nel suo riquadrino grigio.
class LotTag extends StatelessWidget {
  const LotTag(this.code, {super.key, this.size = 12.5});
  final String code;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(6)),
        child: Text(code, style: mono.copyWith(fontSize: size, color: C.navy)),
      );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = C.muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: 11.5, letterSpacing: .9, fontWeight: FontWeight.w600, color: color));
}

class Initials extends StatelessWidget {
  const Initials(this.name, {super.key, this.size = 44, this.index = 0});
  final String name;
  final double size;
  final int index;
  static const _palette = [(C.infoBg, C.infoFg), (C.okBg, C.okFg), (C.warnBg, C.warnFg), (C.chipBg, Color(0xFF3B4656))];
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final text = words.isEmpty ? '?' : words.take(2).map((w) => w[0].toUpperCase()).join();
    final (bg, fg) = _palette[index % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: size * .34)),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

/// Riga di menu con icona in un quadratino, titolo, sottotitolo e freccia.
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final color = danger ? C.badFg : C.navy;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: danger ? C.badBg : C.chipBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          trailing ?? (danger || onTap == null ? const SizedBox() : const Icon(Icons.chevron_right, color: C.faint)),
        ]),
      ),
    );
  }
}

const divider = Divider(height: 1, thickness: 1, color: C.line);

/// Foto di una scheda dal server (con l'accesso dell'utente).
class ItemPhoto extends StatelessWidget {
  const ItemPhoto(this.itemId, {super.key, this.mini = false, this.fit = BoxFit.cover, this.cacheWidth});
  final int itemId;
  final bool mini;
  final BoxFit fit;
  /// Larghezza a cui decodificare: una foto da 2400 px in un riquadro alto
  /// 270 sono ~17 MB di memoria per niente sui telefoni economici.
  final int? cacheWidth;
  @override
  Widget build(BuildContext context) => Image.network(
        Api.instance.uri('/schede/$itemId/foto', mini ? {'mini': '1'} : null).toString(),
        headers: Api.instance.authHeaders,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (context, error, stack) => const PhotoPlaceholder(icon: Icons.image_not_supported_outlined),
        loadingBuilder: (context, child, progress) => progress == null ? child : const PhotoPlaceholder(),
      );
}

class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.icon = Icons.image_outlined});
  final IconData icon;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFFDCE3EC), Color(0xFFC9D3DF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(child: Icon(icon, color: const Color(0xFF7A8698))),
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
            SizedBox(width: 200, child: OutlinedButton(onPressed: onRetry, child: const Text('Riprova'))),
          ]),
        ),
      );
}

/// Schermata con l'intestazione blu notte e il contenuto sotto.
class HeaderScaffold extends StatelessWidget {
  const HeaderScaffold({super.key, required this.header, required this.body, this.bottom});
  final Widget header;
  final Widget body;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [header, Expanded(child: body)]),
        bottomNavigationBar: bottom,
      );
}

/// Finestra di attesa (download, esportazione): non si chiude con il tasto
/// Indietro e si chiude solo da sola, togliendo proprio se stessa. Un `pop()`
/// generico, se la finestra non c'era piu', toglieva la pagina sotto e
/// lasciava lo schermo nero.
class BlockingDialog {
  BlockingDialog._(this._navigator, this._route);
  final NavigatorState _navigator;
  final Route<void> _route;

  static BlockingDialog show(BuildContext context, {required String title, required Widget content}) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: AlertDialog(title: Text(title), content: content)),
    );
    navigator.push(route);
    return BlockingDialog._(navigator, route);
  }

  void close() {
    if (_route.isActive) _navigator.removeRoute(_route);
  }
}
