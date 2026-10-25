import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../api.dart';
import '../platform/platform.dart' as platform;
import '../ui.dart';
import 'home.dart';
import 'reading.dart';
import 'scanner.dart';

/// Foto di un'etichetta: una o piu' foto dello stesso prodotto (il coperchio
/// col lotto, il retro col produttore), come un album su Telegram.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.onSent});
  final VoidCallback onSent;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();
  final _caption = TextEditingController();
  /// Le foto scelte, gia' lette in memoria (sul telefono e nel browser).
  final List<Uint8List> _photos = [];
  bool _sending = false;
  String _progress = '';
  static const _maxPhotos = 5;
  /// Foto non inviate o invio in corso: niente proposta di aggiornamento.
  final _unsaved = UnsavedFlag();

  @override
  void initState() {
    super.initState();
    _caption.addListener(_remember);
    _recover();
  }

  @override
  void dispose() {
    _unsaved.set(false);
    // Se c'era un salvataggio in attesa (l'ultimo pezzo del nome), lo si fa ora.
    final pendingWrite = _rememberTimer?.isActive ?? false;
    _rememberTimer?.cancel();
    if (pendingWrite) _writePending();
    _caption.removeListener(_remember);
    _caption.dispose();
    super.dispose();
  }

  /// Foto e nome restano salvati finche' non sono inviati: se il telefono
  /// chiude l'app (Android) o Safari ricarica la pagina (iPhone) mentre la
  /// fotocamera e' aperta, al ritorno ci sono ancora (revisione 6/10/2026).
  ///
  /// Le foto si salvano subito (`now`); il nome dopo una pausa nella scrittura, non a ogni
  /// tasto: ogni salvataggio cancella e riscrive tutte le foto, e le scritture si accavallavano
  /// (una cancellava i file mentre l'altra li scriveva). Ora vanno una alla volta.
  void _remember({bool now = false}) {
    _unsaved.set(_photos.isNotEmpty || _sending);
    _rememberTimer?.cancel();
    if (now) {
      _writePending();
    } else {
      _rememberTimer = Timer(const Duration(milliseconds: 700), _writePending);
    }
  }

  Timer? _rememberTimer;
  Future<void> _saving = Future.value();

  void _writePending() {
    final photos = List.of(_photos);
    final caption = _caption.text;
    final batch = _batchKey ?? '';
    _saving = _saving.then((_) =>
        photos.isEmpty ? platform.clearPendingPhotos() : platform.savePendingPhotos(photos, caption, batch, null));
  }

  void _changed(VoidCallback change) {
    setState(change);
    _remember(now: true);
  }

  /// Al ritorno: le foto salvate prima (vedi _remember) e, su Android, quella
  /// appena scattata se il sistema aveva chiuso l'app. Una foto scattata da
  /// una scheda ("Aggiungi una foto") torna alla sua scheda, non qui.
  Future<void> _recover() async {
    final pending = await platform.loadPendingPhotos();
    if (pending != null && pending.itemId == null && mounted && _photos.isEmpty) {
      setState(() {
        _photos.addAll(pending.photos.take(_maxPhotos));
        if (_caption.text.isEmpty) _caption.text = pending.caption;
        _batchKey = pending.batch.isEmpty ? null : pending.batch;
      });
      _remember(now: true);
    }
    if (platform.isWebApp) return; // solo Android chiude l'app mentre fotografa
    try {
      final lost = await _picker.retrieveLostData();
      if (lost.isEmpty || lost.files == null) return;
      final bytes = [for (final f in lost.files!) await f.readAsBytes()];
      final forCard = int.tryParse(await Api.instance.readSetting('scatto_per_scheda') ?? '');
      await Api.instance.writeSetting('scatto_per_scheda', null);
      if (!mounted) return;
      if (forCard != null) {
        await _offerToCard(forCard, bytes);
      } else {
        _changed(() => _photos.addAll(bytes.take(_maxPhotos - _photos.length)));
      }
    } catch (_) {}
  }

  /// Una foto scattata dalla scheda #id mentre Android chiudeva l'app: si
  /// chiede dove va, invece di farla finire in una scheda nuova senza dirlo.
  Future<void> _offerToCard(int itemId, List<Uint8List> bytes) async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Foto ritrovata'),
        content: Text('Questa foto era per la scheda #$itemId, ma l\'app si era chiusa. Dove la metto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'via'), child: const Text('Buttala')),
          TextButton(onPressed: () => Navigator.pop(context, 'nuova'), child: const Text('Scheda nuova')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, 'scheda'),
            child: Text('Alla scheda #$itemId'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'nuova') {
      _changed(() => _photos.addAll(bytes.take(_maxPhotos - _photos.length)));
    } else if (choice == 'scheda') {
      final key = _newKey();
      for (var i = 0; i < bytes.length; i++) {
        final ok = await attempt(context, () => Api.instance.uploadPhoto('/schede/$itemId/foto', bytes[i], key: '$key-$i'));
        if (ok == null) return;
      }
      forgetItemPhoto(itemId);
      archiveChanged.value++;
      if (mounted) toast(context, 'Foto aggiunta alla scheda #$itemId');
    }
  }

  Future<void> _take(ImageSource source) async {
    try {
      // 2400 px bastano a leggere lotti minuscoli e pesano un quinto dell'originale.
      if (source == ImageSource.gallery) {
        if (_photos.length >= _maxPhotos) {
          toast(context, 'Hai già $_maxPhotos foto: togline una per aggiungerne altre');
          return;
        }
        final files = await _picker.pickMultiImage(maxWidth: 2400, maxHeight: 2400, imageQuality: 88, limit: _maxPhotos);
        final room = _maxPhotos - _photos.length;
        final bytes = [for (final f in files.take(room)) await f.readAsBytes()];
        if (!mounted) return;
        _changed(() => _photos.addAll(bytes));
        if (files.length > room) toast(context, 'Ho preso ${bytes.length} foto su ${files.length}: il massimo è $_maxPhotos per scheda');
      } else {
        // Su Android lo scanner (25/10/2026): cornice e controllo di lotto e
        // scadenza prima di inviare. Nel browser resta la fotocamera del
        // telefono, che li' fa foto migliori dell'anteprima del browser.
        if (!platform.isWebApp) {
          final outcome = await Navigator.push<ScanOutcome>(
            context,
            MaterialPageRoute(builder: (_) => const ScannerScreen()),
          );
          if (!mounted || outcome == null) return;
          if (!outcome.useSystemCamera) {
            _changed(() => _photos.add(outcome.photo!));
            return;
          }
        }
        final file = await _picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
        if (file != null) {
          final bytes = await file.readAsBytes();
          if (!mounted) return;
          // Nella webapp la foto passa dal controllo del server, con la
          // stessa schermata dello scanner Android (25/10/2026). "Rifai" non
          // riapre da solo la fotocamera: il browser lo permette solo dopo
          // un tocco, quindi si torna qui e si riscatta.
          if (platform.isWebApp) {
            final use = await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => PhotoCheckScreen(photo: bytes)),
            );
            if (!mounted) return;
            if (use != true) {
              toast(context, 'Foto scartata: scattala di nuovo');
              return;
            }
          }
          _changed(() => _photos.add(bytes));
        }
      }
    } catch (e) {
      if (mounted) toast(context, 'Fotocamera non disponibile: $e', error: true);
    }
  }

  /// La scheda gia' creata dal primo invio e quante foto sono gia' arrivate:
  /// se la seconda foto non passa (rete in cucina), "Invia" riprende da li'
  /// invece di creare una scheda doppia con la prima foto.
  int? _sentItem;
  int _sentCount = 0;
  Object? _twin;
  /// Chiave di questo invio: se la risposta del server si perde e si
  /// ripreme "Invia", il server riconosce le foto gia' arrivate.
  String? _batchKey;

  static String _newKey() {
    final r = Random.secure();
    return List.generate(20, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
  }

  Future<void> _send() async {
    if (_sentItem == null && _caption.text.trim().isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Manca il nome del prodotto'),
          content: const Text('Senza nome la scheda resta "da rivedere" finché non lo scrivi. Inviare lo stesso?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Scrivo il nome')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Invia lo stesso')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    _batchKey ??= _newKey();
    _changed(() {
      _sending = true;
      _progress = 'Invio foto ${_sentCount + 1} di ${_photos.length}…';
    });
    try {
      if (_sentItem == null) {
        final first = await Api.instance.uploadPhoto('/foto', _photos.first, caption: _caption.text, key: '$_batchKey-0');
        _sentItem = first['scheda'] as int;
        _sentCount = 1;
        _twin = first['stessa_foto_di'];
      }
      final itemId = _sentItem!;
      while (_sentCount < _photos.length) {
        setState(() => _progress = 'Invio foto ${_sentCount + 1} di ${_photos.length}…');
        // La nota va anche qui: se e' stata scritta dopo un invio a meta', la
        // scheda la prende (il server la usa solo se la scheda non ne ha).
        await Api.instance.uploadPhoto('/schede/$itemId/foto', _photos[_sentCount],
            caption: _caption.text, key: '$_batchKey-$_sentCount');
        _sentCount++;
      }
      final count = _photos.length;
      final twin = _twin;
      _changed(() {
        _photos.clear();
        _caption.clear();
        _sending = false;
        _sentItem = null;
        _sentCount = 0;
        _twin = null;
        _batchKey = null;
      });
      if (!mounted) return;
      if (twin != null) toast(context, 'Attenzione: questa foto era già stata inviata (scheda #$twin)');
      final again = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ReadingScreen(itemId: itemId, photos: count)),
      );
      if (again != true) widget.onSent();
    } catch (e) {
      // Qualunque errore (rete, foto sparita dalla cache): i tasti tornano
      // attivi e si puo' riprovare.
      if (!mounted) return;
      _changed(() => _sending = false);
      final message = e is ApiError ? e.message : 'errore imprevisto ($e)';
      final partial = _sentItem != null
          ? ' La scheda #$_sentItem è già creata con $_sentCount foto: "Invia" manda solo le altre.'
          : ' Le foto restano qui, riprova.';
      toast(context, 'Non inviata: $message.$partial', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => HeaderScaffold(
        header: NavyHeader(title: 'Nuova foto', subtitle: 'Una o più foto dello stesso prodotto'),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_photos.isEmpty)
              _BigCameraButton(onTap: () => _take(ImageSource.camera))
            else
              SizedBox(
                height: 260,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length + (_photos.length < _maxPhotos ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    if (i == _photos.length) {
                      return SizedBox(
                        width: 120,
                        child: OutlinedButton(
                          onPressed: _sending ? null : () => _take(ImageSource.camera),
                          child: const Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Symbols.add_a_photo_rounded),
                            SizedBox(height: 6),
                            Text('Altra foto\nstesso prodotto', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                          ]),
                        ),
                      );
                    }
                    return Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_photos[i], width: 190, height: 260, fit: BoxFit.cover, cacheWidth: 400),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filled(
                          tooltip: 'Togli questa foto',
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          // Una foto cambiata prima che la scheda esista vuole una
                          // chiave nuova: con la vecchia il server riconosceva
                          // "lo stesso invio" e teneva la foto tolta (6/10/2026).
                          onPressed: _sending || i < _sentCount
                              ? null
                              : () => _changed(() {
                                    _photos.removeAt(i);
                                    if (_sentItem == null) _batchKey = null;
                                  }),
                          icon: const Icon(Symbols.close_rounded, color: Colors.white),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
            const SizedBox(height: 10),
            Text('Inquadra l\'etichetta: lotto e scadenza devono essere leggibili. '
                'Più foto = stesso prodotto (es. coperchio col lotto).',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 16),
            // E' la didascalia di Telegram: diventa il nome della scheda (Qwen
            // legge lotto, scadenza e allergeni, ma il nome lo scrive la cucina).
            const SectionLabel('Nome del prodotto'),
            const SizedBox(height: 6),
            TextField(
              controller: _caption,
              enabled: !_sending,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'es. Acciughe 2/10',
                helperText: 'Come la didascalia su Telegram. Puoi aggiungere "lotto ABC123".',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sending ? null : () => _take(ImageSource.gallery),
                  icon: const Icon(Symbols.photo_library_rounded),
                  label: const Text('Galleria'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending || _photos.isEmpty ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Symbols.send_rounded),
                  label: Text(_sending ? 'Invio…' : 'Invia'),
                ),
              ),
            ]),
            if (_sending) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_progress, textAlign: TextAlign.center)),
          ],
        ),
      );
}

class _BigCameraButton extends StatelessWidget {
  const _BigCameraButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: C.navy,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: const SizedBox(
            height: 260,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Symbols.photo_camera_rounded, color: Colors.white, size: 56),
              SizedBox(height: 12),
              Text('Scatta la foto', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
