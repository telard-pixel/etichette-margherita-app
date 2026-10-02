import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../ui.dart';
import 'reading.dart';

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
  final List<File> _photos = [];
  bool _sending = false;
  String _progress = '';
  static const _maxPhotos = 5;

  @override
  void initState() {
    super.initState();
    _recover();
  }

  /// Se Android ha chiuso l'app mentre la fotocamera era aperta, la foto
  /// scattata si recupera qui invece di andare persa.
  Future<void> _recover() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (!lost.isEmpty && lost.files != null && mounted) {
        setState(() => _photos.addAll(lost.files!.map((f) => File(f.path))));
      }
    } catch (_) {}
  }

  Future<void> _take(ImageSource source) async {
    try {
      // 2400 px bastano a leggere lotti minuscoli e pesano un quinto dell'originale.
      if (source == ImageSource.gallery) {
        final files = await _picker.pickMultiImage(maxWidth: 2400, maxHeight: 2400, imageQuality: 88, limit: _maxPhotos);
        setState(() => _photos.addAll(files.take(_maxPhotos - _photos.length).map((f) => File(f.path))));
      } else {
        final file = await _picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 88);
        if (file != null) setState(() => _photos.add(File(file.path)));
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
    setState(() {
      _sending = true;
      _progress = 'Invio foto ${_sentCount + 1} di ${_photos.length}…';
    });
    _batchKey ??= _newKey();
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
      setState(() {
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
      setState(() => _sending = false);
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
                            Icon(Icons.add_a_photo_outlined),
                            SizedBox(height: 6),
                            Text('Altra foto\nstesso prodotto', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                          ]),
                        ),
                      );
                    }
                    return Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_photos[i], width: 190, height: 260, fit: BoxFit.cover, cacheWidth: 400),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: IconButton.filled(
                          tooltip: 'Togli questa foto',
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          onPressed: _sending || i < _sentCount ? null : () => setState(() => _photos.removeAt(i)),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ]);
                  },
                ),
              ),
            const SizedBox(height: 10),
            const Text('Inquadra l\'etichetta: lotto e scadenza devono essere leggibili. '
                'Più foto = stesso prodotto (es. coperchio col lotto).',
                style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _caption,
              enabled: !_sending,
              maxLength: 200,
              decoration: const InputDecoration(hintText: 'Nota (facoltativa), es. "frigo 2"'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sending ? null : () => _take(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galleria'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _sending || _photos.isEmpty ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Icon(Icons.send),
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
              Icon(Icons.photo_camera, color: Colors.white, size: 56),
              SizedBox(height: 12),
              Text('Scatta la foto', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}
