import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'platform/platform.dart' show readPhotoCache, writePhotoCache, forgetPhotoCache;

/// Colori e forme dell'anteprima approvata (versione 3, 4/10/2026): fondo
/// bianco caldo, inchiostro blu notte, accento beige sabbia; schede bianche
/// con un bordo sottile (piu' leggero da disegnare di un'ombra).
class C {
  /// Inchiostro: testi, chip scelte, riquadri scuri (lotto interno).
  static const navy = Color(0xFF1B2333);
  static const ground = Color(0xFFF6F5F2);
  static const line = Color(0xFFEFECE6);
  static const border = Color(0xFFE2DED6);
  static const cardBorder = Color(0xFFECE9E3);
  static const muted = Color(0xFF626B7A);
  static const faint = Color(0xFF9AA0AA);
  static const onNavyMuted = Color(0xFFA9B2C3);
  /// Accento come testo, icona o bordo sul chiaro: nocciola, leggibile.
  static const blue = Color(0xFF8C6239);
  /// Accento sui riquadri scuri.
  static const accentOnDark = Color(0xFFE6D3B3);
  /// Beige sabbia dei tasti pieni (Scatta, Stampa): sopra va l'inchiostro.
  static const sand = Color(0xFFD9C4A3);
  static const sandSoft = Color(0xFFEFE4D2);
  static const sandText = Color(0xFF7A5A2E);
  static const chipBg = Color(0xFFF2F0EB);
  static const okBg = Color(0xFFE4F2E9), okFg = Color(0xFF1F6B41);
  static const warnBg = Color(0xFFFDF1DE), warnFg = Color(0xFF8A4A00);
  static const badBg = Color(0xFFFCE7E2), badFg = Color(0xFFA3301B);
  static const infoBg = Color(0xFFE8EDF6), infoFg = Color(0xFF2D4A80);
  static const green = Color(0xFF1E8E4E), red = Color(0xFFC0362C);
  /// Contatori in alto: quale riquadro colorato usare (vedi [StatStrip]).
  static const statWarn = warnFg, statBad = badFg;
}

const kFont = 'PlusJakartaSans';

const mono = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600);

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: C.sand, primary: C.blue, surface: Colors.white);
  final radius14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    fontFamily: kFont,
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
        minimumSize: const Size.fromHeight(54),
        shape: radius14,
        elevation: 0,
        backgroundColor: C.sand,
        foregroundColor: C.navy,
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: C.navy,
        backgroundColor: Colors.white,
        side: const BorderSide(color: C.border),
        shape: radius14,
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w600),
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
        borderRadius: BorderRadius.circular(18),
        border: border ?? (color == C.navy ? null : Border.all(color: C.cardBorder)),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: onTap == null && onLongPress == null ? inner : InkWell(onTap: onTap, onLongPress: onLongPress, child: inner),
      ),
    );
  }
}

/// L'intestazione chiara (era blu notte fino al 4/10/2026): titolo grande,
/// sottotitolo, eventuale freccia indietro, azioni a destra e, sotto, i
/// contatori. Le icone di stato del telefono diventano scure.
class NavyHeader extends StatelessWidget {
  const NavyHeader({super.key, required this.title, this.subtitle, this.back = false, this.actions = const [], this.bottom});
  final String title;
  final String? subtitle;
  final bool back;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        child: Container(
          color: C.ground,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 14),
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
                      style: TextStyle(color: C.navy, fontSize: back ? 22 : 28, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.muted, fontSize: 13)),
                  ],
                ]),
              ),
              for (final a in actions) ...[const SizedBox(width: 8), a],
            ]),
            if (bottom != null) ...[const SizedBox(height: 14), bottom!],
          ]),
        ),
      );
}

class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.icon, required this.tooltip, required this.onPressed, this.color});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  @override
  /// Senza [color]: bianco col bordo, sull'intestazione chiara. Con un
  /// colore (sopra una foto, o un'azione in evidenza): icona bianca.
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: color ?? Colors.white,
            side: color == null ? const BorderSide(color: C.cardBorder) : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(icon, color: color == null ? C.navy : Colors.white),
        ),
      );
}

/// I tre numeri sotto l'intestazione: [C.statWarn] su un riquadro ambra,
/// [C.statBad] su uno rosato, gli altri su bianco.
class StatStrip extends StatelessWidget {
  const StatStrip(this.stats, {super.key});
  final List<(String value, String label, Color color)> stats;

  static (Color bg, Color fg, Border? border) _look(Color color) {
    if (color == C.statWarn) return (C.warnBg, C.warnFg, null);
    if (color == C.statBad) return (C.badBg, C.badFg, null);
    return (Colors.white, C.navy, Border.all(color: C.cardBorder));
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(builder: (context) {
              final (bg, fg, border) = _look(stats[i].$3);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(stats[i].$1, style: TextStyle(color: fg, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                  Text(stats[i].$2, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg == C.navy ? C.muted : fg, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              );
            }),
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
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: C.chipBg, borderRadius: BorderRadius.circular(8)),
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

/// Misure di una foto: miniatura (elenco), media (scheda e galleria, poche
/// centinaia di KB invece dei 3 MB dell'originale) e originale (solo quando
/// si ingrandisce nella galleria). Il server le prepara una volta sola.
enum PhotoSize { mini, media, full }

/// Foto gia' scaricate, per non riscaricarle a ogni scorrimento dell'elenco.
/// In memoria al massimo 150; sul telefono restano anche su disco.
final Map<String, Uint8List> _photoCache = {};
final Map<String, Future<Uint8List>> _photoLoading = {};

Future<Uint8List> _loadPhoto(int itemId, PhotoSize size, int? extraId) {
  final key = '$itemId:${extraId ?? 0}:${size.name}';
  final cached = _photoCache[key];
  if (cached != null) return Future.value(cached);
  return _photoLoading[key] ??= () async {
    final saved = await readPhotoCache(key);
    final List<int> data;
    if (saved != null) {
      data = saved;
    } else {
      final path = extraId == null ? '/schede/$itemId/foto' : '/schede/$itemId/foto/$extraId';
      data = await Api.instance.bytes(path, switch (size) {
        PhotoSize.mini => {'mini': '1'},
        PhotoSize.media => {'media': '1'},
        PhotoSize.full => null,
      });
      writePhotoCache(key, data);
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (_photoCache.length >= 150) _photoCache.remove(_photoCache.keys.first);
    _photoCache[key] = bytes;
    return bytes;
  }().whenComplete(() => _photoLoading.remove(key));
}

/// Gia' scaricata in questa misura? (Per mostrarla subito, senza attesa.)
Uint8List? _photoNow(int itemId, PhotoSize size, int? extraId) => _photoCache['$itemId:${extraId ?? 0}:${size.name}'];

/// Dimentica le foto di una scheda (foto aggiunta, scheda riletta).
void forgetItemPhoto(int itemId) {
  _photoCache.removeWhere((key, _) => key.startsWith('$itemId:'));
  forgetPhotoCache('$itemId:');
}

/// Foto di una scheda dal server (con l'accesso dell'utente). Scaricata
/// dall'app e mostrata dalla memoria: cosi' vale anche nel browser, dove
/// un'immagine con l'intestazione di accesso non sempre si carica.
///
/// Con [sharpen] (galleria a schermo intero) mostra subito la versione
/// media e intanto scarica l'originale, che la sostituisce appena arriva:
/// si vede subito, e ingrandendo si leggono anche le scritte piccole.
class ItemPhoto extends StatefulWidget {
  const ItemPhoto(this.itemId,
      {super.key, this.size = PhotoSize.media, this.fit = BoxFit.cover, this.cacheWidth, this.extraId, this.sharpen = false});
  final int itemId;
  /// Una delle foto in piu' della scheda (coperchio, retro), o la principale se null.
  final int? extraId;
  final PhotoSize size;
  final BoxFit fit;
  final bool sharpen;
  /// Larghezza a cui decodificare: una foto da 2400 px in un riquadro alto
  /// 270 sono ~17 MB di memoria per niente sui telefoni economici.
  final int? cacheWidth;
  @override
  State<ItemPhoto> createState() => _ItemPhotoState();
}

class _ItemPhotoState extends State<ItemPhoto> {
  Uint8List? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ItemPhoto old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId || old.extraId != widget.extraId || old.size != widget.size) {
      _data = null;
      _failed = false;
      _start();
    }
  }

  String get _key => '${widget.itemId}:${widget.extraId}:${widget.size.name}:${widget.sharpen}';

  void _start() {
    final w = widget;
    final key = _key;
    _data = _photoNow(w.itemId, w.size, w.extraId);
    if (_data == null) {
      _loadPhoto(w.itemId, w.size, w.extraId).then((d) {
        if (mounted && key == _key) setState(() => _data ??= d);
      }, onError: (_) {
        if (mounted && key == _key && _data == null) setState(() => _failed = true);
      });
    }
    if (w.sharpen && w.size != PhotoSize.full) {
      final sharp = _photoNow(w.itemId, PhotoSize.full, w.extraId);
      if (sharp != null) {
        _data = sharp;
      } else {
        _loadPhoto(w.itemId, PhotoSize.full, w.extraId).then((d) {
          if (mounted && key == _key) setState(() => _data = d);
        }, onError: (_) {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return PhotoPlaceholder(icon: _failed ? Icons.image_not_supported_outlined : Icons.image_outlined);
    }
    return Image.memory(
      data,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const PhotoPlaceholder(icon: Icons.image_not_supported_outlined),
    );
  }
}

class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({super.key, this.icon = Icons.image_outlined});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFF1EEE6),
        child: Center(child: Icon(icon, color: const Color(0xFFADA493))),
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

/// Una richiesta di stampa. Se il server ferma la raffica (anti-flood:
/// troppe copie in pochi minuti) chiede conferma e, con il sì, la rimanda
/// con "forza". Null se annullata o non riuscita.
Future<Map<String, dynamic>?> printRequest(BuildContext context, String path, Map<String, dynamic> body) async {
  try {
    return await Api.instance.post(path, body);
  } on ApiError catch (e) {
    if (!context.mounted) return null;
    if (e.status == 429 && e.body?['serve_conferma'] == true) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Tante stampe in pochi minuti'),
          content: Text(e.message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stampa lo stesso'),
            ),
          ],
        ),
      );
      if (yes != true || !context.mounted) return null;
      return attempt(context, () => Api.instance.post(path, {...body, 'forza': true}));
    }
    if (e.status != 401) toast(context, e.message, error: true);
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
  // SafeArea in basso: senza, l'ultima riga (es. un tasto) finiva sotto i
  // tasti di sistema di Android/iPhone e non si poteva toccare (3/10/2026).
  // Nelle schede del menu in basso il bordo l'ha gia' tolto il menu stesso.
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [header, Expanded(child: SafeArea(top: false, child: body))]),
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
