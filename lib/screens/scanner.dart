import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../error_report.dart';
import '../label_hints.dart';
import '../platform/text_reader.dart';
import '../ui.dart';

/// Come e' finito lo scanner: la foto scelta, oppure "usa la fotocamera del
/// telefono" se quella dell'app non parte (permesso negato, telefono strano).
class ScanOutcome {
  const ScanOutcome.photo(Uint8List this.photo, this.hints) : useSystemCamera = false;
  const ScanOutcome.systemCamera()
      : photo = null,
        hints = LabelHints.none,
        useSystemCamera = true;
  final Uint8List? photo;
  /// Lotto e scadenza trovati in questa foto (per le foto successive).
  final LabelHints hints;
  final bool useSystemCamera;
}

/// Scanner (25/10/2026): fotocamera dentro l'app con una cornice dove mettere
/// l'etichetta. Mentre inquadri, il telefono legge il testo e dice se vede
/// lotto e scadenza; dopo lo scatto controlla la foto vera e, se manca
/// qualcosa, propone di rifarla prima di inviarla.
///
/// Nell'archivio tre correzioni su quattro erano campi non trovati, spesso
/// perche' il timbro non era nella foto: qui lo si vede prima di inviare.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.before = LabelHints.none});

  /// Lotto e scadenza gia' trovati nelle altre foto dello stesso prodotto:
  /// la seconda foto (il fornitore sul retro) non deve per forza mostrarli.
  final LabelHints before;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  CameraDescription? _description;
  String? _error;
  final _reader = TextReader();

  /// Cosa vede adesso l'anteprima (solo l'ultimo fotogramma letto: se sposti
  /// il telefono il risultato vecchio non vale piu').
  LabelHints _live = LabelHints.none;
  bool _reading = false;
  /// Diagnostica: fotogrammi letti e righe di testo trovate. Se lo scanner si
  /// chiude senza aver letto niente, il server lo viene a sapere (dispose).
  int _frames = 0, _frameLines = 0, _photoLines = -1;
  bool _capturing = false;
  bool _torch = false;
  Timer? _nextRead;
  double _zoom = 1, _minZoom = 1, _maxZoom = 1, _zoomAtPinch = 1;

  /// Dopo lo scatto: la foto pronta da inviare e cosa ci ha trovato il telefono.
  Uint8List? _shot;
  LabelHints? _shotHints;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    if (_frames == 0 || _frameLines == 0 || _photoLines == 0) {
      ErrorReport.send(
          StateError('scanner senza testo: fotogrammi letti $_frames, righe $_frameLines, '
              'righe nella foto $_photoLines, anteprima ${_camera?.value.previewSize}'),
          null,
          where: 'scanner: riepilogo');
    }
    WidgetsBinding.instance.removeObserver(this);
    _nextRead?.cancel();
    _camera?.dispose();
    _reader.close();
    super.dispose();
  }

  /// La fotocamera va lasciata quando l'app passa in secondo piano (Android
  /// la toglie comunque) e ripresa al ritorno.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (camera == null) return;
      _nextRead?.cancel();
      _camera = null;
      camera.dispose();
    } else if (state == AppLifecycleState.resumed && _camera == null && _shot == null) {
      _start();
    }
  }

  /// La richiesta del permesso manda l'app in "inactive" e poi "resumed":
  /// senza questo si aprirebbe la fotocamera due volte.
  bool _starting = false;

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first);
      // La massima risoluzione: i lotti stampati sono minuscoli. La foto poi
      // si riduce a 2400 px come prima (vedi _shrink).
      final camera = CameraController(back, ResolutionPreset.max,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await camera.initialize();
      if (!mounted) {
        camera.dispose();
        return;
      }
      _minZoom = await camera.getMinZoomLevel();
      _maxZoom = min(await camera.getMaxZoomLevel(), 6);
      _zoom = _minZoom;
      setState(() {
        _camera = camera;
        _description = back;
        _error = null;
        _torch = false;
      });
      _scheduleRead(const Duration(milliseconds: 400));
    } catch (e) {
      if (mounted) setState(() => _error = e is CameraException ? (e.description ?? e.code) : '$e');
    } finally {
      _starting = false;
    }
  }

  /// Legge un fotogramma ogni tanto, non tutti: ognuno pesa quanto una foto.
  /// Lo stream si ferma appena arriva il fotogramma e riparte dopo la lettura.
  void _scheduleRead(Duration after) {
    _nextRead?.cancel();
    if (!canReadText) return;
    _nextRead = Timer(after, () {
      final camera = _camera;
      if (!mounted || camera == null || _capturing || _shot != null || camera.value.isStreamingImages) return;
      camera.startImageStream(_onFrame).catchError((_) {});
    });
  }

  Future<void> _onFrame(CameraImage frame) async {
    final camera = _camera;
    if (_reading || camera == null) return;
    _reading = true;
    try {
      await camera.stopImageStream();
      final hints = await _reader.readFrame(frame, _description!);
      _frames++;
      _frameLines += _reader.lastLineCount;
      if (mounted && !_capturing) setState(() => _live = hints);
    } catch (e, stack) {
      // Un fotogramma non letto non ferma niente, ma si segnala (una volta
      // per tipo di errore, vedi ErrorReport): nella 1.0.108 lo scanner non
      // leggeva niente e nessuno poteva sapere perche'.
      ErrorReport.send(e, stack, where: 'scanner: fotogramma');
    } finally {
      _reading = false;
      _scheduleRead(const Duration(milliseconds: 700));
    }
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _capturing) return;
    setState(() => _capturing = true);
    _nextRead?.cancel();
    try {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      final file = await camera.takePicture();
      final bytes = await compute(_shrink, await file.readAsBytes());
      if (!mounted) return;
      // La foto si vede subito; il controllo arriva dopo (hints null = in corso).
      setState(() {
        _shot = bytes;
        _shotHints = null;
        _capturing = false;
      });
      var hints = _live;
      try {
        hints = hints.merge(await _reader.readFile(file.path));
        _photoLines = _reader.lastLineCount;
      } catch (e, stack) {
        ErrorReport.send(e, stack, where: 'scanner: foto');
      }
      // Quello che il telefono non trova lo cerca anche il server, come
      // nella webapp: due lettori diversi sbagliano su foto diverse.
      if (!hints.merge(widget.before).complete) {
        try {
          hints = hints.merge(await Api.instance.checkPhoto(bytes));
        } catch (_) {}
      }
      if (mounted && _shot == bytes) setState(() => _shotHints = hints);
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      toast(context, 'Scatto non riuscito: $e', error: true);
      _scheduleRead(const Duration(milliseconds: 400));
    }
  }

  void _retake() {
    setState(() {
      _shot = null;
      _shotHints = null;
      _live = LabelHints.none;
    });
    if (_camera == null) {
      _start();
    } else {
      _scheduleRead(const Duration(milliseconds: 400));
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      setState(() => _torch = !_torch);
    } catch (_) {
      if (mounted) toast(context, 'Torcia non disponibile su questo telefono');
    }
  }

  /// Tocco sull'anteprima: mette a fuoco li' (il timbro piccolo sul coperchio).
  void _focusAt(TapUpDetails details, BoxConstraints box) {
    final camera = _camera;
    if (camera == null) return;
    final point = Offset(
      (details.localPosition.dx / box.maxWidth).clamp(0.0, 1.0),
      (details.localPosition.dy / box.maxHeight).clamp(0.0, 1.0),
    );
    camera.setFocusPoint(point).catchError((_) {});
    camera.setExposurePoint(point).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _shot != null ? _review() : _viewfinder()),
      );

  Widget _viewfinder() {
    final camera = _camera;
    if (_error != null) return _failed();
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    final preview = camera.value.previewSize!;
    return Stack(children: [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            onTapUp: (d) => _focusAt(d, box),
            onScaleStart: (_) => _zoomAtPinch = _zoom,
            onScaleUpdate: (d) {
              final zoom = (_zoomAtPinch * d.scale).clamp(_minZoom, _maxZoom);
              if ((zoom - _zoom).abs() < 0.05) return;
              _zoom = zoom;
              camera.setZoomLevel(zoom).catchError((_) {});
            },
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                // L'anteprima arriva in orizzontale: in verticale si scambiano i lati.
                child: SizedBox(width: preview.height, height: preview.width, child: CameraPreview(camera)),
              ),
            ),
          ),
        ),
      ),
      const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FramePainter()))),
      Positioned(
        top: 8,
        left: 8,
        right: 8,
        child: Row(children: [
          IconButton(
            tooltip: 'Chiudi',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Symbols.close_rounded, color: Colors.white),
          ),
          const Expanded(
            child: Text('Metti l\'etichetta nella cornice: devono vedersi lotto e scadenza',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
          IconButton(
            tooltip: _torch ? 'Spegni la torcia' : 'Accendi la torcia',
            onPressed: _toggleTorch,
            icon: Icon(_torch ? Symbols.flashlight_off_rounded : Symbols.flashlight_on_rounded, color: Colors.white),
          ),
        ]),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canReadText) ...[
            Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              _Found('Lotto', _live.lotLabel, earlier: widget.before.lotLabel),
              _Found('Scadenza', _live.expiry, earlier: widget.before.expiry),
            ]),
            const SizedBox(height: 6),
            Text(
              _live.merge(widget.before).complete
                  ? (_live.complete ? 'Si leggono lotto e scadenza' : 'Lotto e scadenza ci sono già nelle altre foto')
                  : 'Tocca per mettere a fuoco, allarga con due dita',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
          ],
          _Shutter(ready: _live.merge(widget.before).complete, busy: _capturing, onTap: _shoot),
        ]),
      ),
    ]);
  }

  Widget _failed() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Symbols.no_photography_rounded, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text('La fotocamera dell\'app non parte ($_error).',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, const ScanOutcome.systemCamera()),
              child: const Text('Usa la fotocamera del telefono'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla', style: TextStyle(color: Colors.white70)),
            ),
          ]),
        ),
      );

  Widget _review() => PhotoReview(
        photo: _shot!,
        hints: _shotHints,
        before: widget.before,
        onRetake: _retake,
        onUse: () => Navigator.pop(context, ScanOutcome.photo(_shot!, _shotHints ?? LabelHints.none)),
      );
}

/// La foto appena fatta, con cosa ci si legge: "Lotto ✓ / Scadenza ✓" oppure
/// "Non vedo il lotto", e i tasti Rifai / Usa. hints null = controllo in corso.
class PhotoReview extends StatelessWidget {
  const PhotoReview(
      {super.key, required this.photo, required this.hints, this.before = LabelHints.none, this.problem, required this.onRetake, required this.onUse});
  final Uint8List photo;
  final LabelHints? hints;
  /// Quello che c'era gia' nelle altre foto dello stesso prodotto.
  final LabelHints before;
  final String? problem;
  final VoidCallback onRetake, onUse;

  @override
  Widget build(BuildContext context) {
    final found = hints;
    final all = found?.merge(before);
    final missing = all == null ? const <String>[] : [if (!all.hasLot) 'il lotto', if (!all.hasExpiry) 'la scadenza'];
    final fromEarlier = found != null && !found.complete && all!.complete;
    final String message;
    if (problem != null) {
      message = problem!;
    } else if (found == null) {
      message = 'Controllo la foto…';
    } else if (fromEarlier) {
      message = 'Lotto e scadenza ci sono già nelle altre foto di questo prodotto: questa va bene così.';
    } else if (missing.isEmpty) {
      message = 'Si leggono lotto e scadenza. La lettura vera la fa il server dopo l\'invio.';
    } else {
      // Nessun avviso se manca qualcosa: nella prova su 142 schede era
      // sempre sbagliato. La lettura vera la fa il server dopo l'invio.
      message = '';
    }
    return Column(children: [
      Expanded(child: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(photo)))),
      Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (found != null)
            Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              _Found('Lotto', found.lotLabel, earlier: before.lotLabel),
              _Found('Scadenza', found.expiry, earlier: before.expiry),
            ])
          else if (problem == null)
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
          const SizedBox(height: 8),
          if (message.isNotEmpty)
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), minimumSize: const Size(0, 48)),
                onPressed: onRetake,
                icon: const Icon(Symbols.replay_rounded),
                label: const Text('Rifai'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.sand, foregroundColor: C.onSand, minimumSize: const Size(0, 48)),
                onPressed: onUse,
                icon: const Icon(Symbols.check_rounded),
                label: const Text('Usa la foto'),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

/// La foto come la mandava image_picker: lato lungo al massimo 2400 px,
/// JPEG qualita' 88, raddrizzata secondo l'EXIF. Gira in un isolate.
Uint8List _shrink(Uint8List data) {
  final decoded = img.decodeJpg(data);
  if (decoded == null) return data;
  var picture = img.bakeOrientation(decoded);
  const longest = 2400;
  if (max(picture.width, picture.height) > longest) {
    picture = picture.width >= picture.height
        ? img.copyResize(picture, width: longest, interpolation: img.Interpolation.average)
        : img.copyResize(picture, height: longest, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(picture, quality: 88);
}

/// "Lotto ✓ L261190" in verde, oppure "Lotto ?" in grigio.
class _Found extends StatelessWidget {
  const _Found(this.label, this.value, {this.earlier});
  final String label;
  final String? value;
  /// Il valore trovato in un'altra foto dello stesso prodotto.
  final String? earlier;
  @override
  Widget build(BuildContext context) {
    final ok = value != null || earlier != null;
    // Solo quello che si legge, in verde: niente indicatori grigi
    // "manca" (deciso il 25/10/2026 dopo la prova sull'archivio).
    if (!ok) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFF1F6B41) : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Symbols.check_circle_rounded : Symbols.help_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 6),
        Text(value != null ? '$label  $value' : (earlier != null ? '$label ✓ foto prima' : label),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.ready, required this.busy, required this.onTap});
  final bool ready, busy;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Scatta',
        child: GestureDetector(
          onTap: busy ? null : onTap,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ready ? const Color(0xFF5CC48A) : Colors.white, width: 5),
            ),
            padding: const EdgeInsets.all(5),
            child: DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? const Color(0xFF5CC48A) : Colors.white),
              child: busy ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 3)) : null,
            ),
          ),
        ),
      );
}

/// Scurisce tutto tranne la cornice dove va l'etichetta.
class _FramePainter extends CustomPainter {
  const _FramePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.86;
    final height = min(width * 4 / 3, size.height * 0.62);
    final frame = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.46), width: width, height: height),
      const Radius.circular(18),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(frame)),
      Paint()..color = Colors.black45,
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => false;
}
