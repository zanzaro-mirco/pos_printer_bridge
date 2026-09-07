import 'dart:async';

import 'package:flutter/services.dart';

import 'printer_failure.dart';
import 'printer_status.dart';
import 'printer_transport.dart';

/// Il canale verso una stampante collegata via USB, attraverso il codice
/// nativo.
///
/// ## Cosa fa il codice Kotlin, e cosa non fa
///
/// **Sposta byte, e basta.** Trova il dispositivo, chiede il permesso, apre
/// gli endpoint, scrive e legge. Non decodifica uno stato, non compone un
/// comando, non decide quando riprovare: tutta l'interpretazione sta da questa
/// parte del canale.
///
/// Non è eleganza, è dove si possono mettere le cose alla prova. Il codice
/// nativo è la parte che costa di più verificare — serve un dispositivo, un
/// emulatore non basta, e un test JVM su `UsbManager` finisce per mettere alla
/// prova i finti che si è scritto. Quindi il nativo si tiene sottile fino a
/// essere quasi ovvio, e tutto ciò che ha una logica dentro attraversa il
/// canale e viene provato in Dart.
///
/// La decodifica degli stati è **la stessa** che usa il trasporto TCP: i byte
/// arrivano da un endpoint invece che da un socket, ma sono gli stessi byte.
class UsbPrinterTransport implements PrinterTransport {
  /// Crea il canale. I due canali si sostituiscono nei test, ed è così che il
  /// confine con il nativo si mette alla prova senza un dispositivo collegato.
  UsbPrinterTransport({
    MethodChannel? methods,
    EventChannel? events,
  })  : _methods = methods ?? const MethodChannel(methodChannelName),
        _events = events ?? const EventChannel(eventChannelName);

  /// Il canale delle operazioni: apri, scrivi, chiudi.
  static const String methodChannelName =
      'it.mircozanzaro.pos_printer_bridge/methods';

  /// Il canale degli stati, che vanno in una direzione sola e non sono
  /// risposte a niente.
  static const String eventChannelName =
      'it.mircozanzaro.pos_printer_bridge/status';

  final MethodChannel _methods;
  final EventChannel _events;
  final PrinterStatusReader _reader = PrinterStatusReader();

  Stream<PrinterStatus>? _status;
  bool _open = false;

  @override
  bool get isOpen => _open;

  @override
  Stream<PrinterStatus> get status =>
      _status ??= _events.receiveBroadcastStream().expand(_decode);

  @override
  Future<void> open() async {
    await _guard(() async {
      await _methods.invokeMethod<void>('open');
      _open = true;
    });
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (!_open) {
      throw const PrinterNotOpen('Chiamare open() prima di write()');
    }
    // I byte passano come `Uint8List` e non come lista di interi: il canale li
    // consegna a Kotlin come `ByteArray` senza convertirli uno per uno. Su uno
    // scontrino sono un migliaio di elementi, e la differenza si vede.
    await _guard(() => _methods.invokeMethod<void>('write', bytes));
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    _reader.reset();
    await _guard(() => _methods.invokeMethod<void>('close'));
  }

  Iterable<PrinterStatus> _decode(Object? event) {
    if (event is! List<int>) return const <PrinterStatus>[];
    return _reader.add(event);
  }

  /// Traduce gli errori della piattaforma nella gerarchia di dominio.
  ///
  /// È l'unico punto in cui una `PlatformException` esiste: fuori di qui
  /// circolano solo `PrinterFailure`, e chi stampa non deve sapere che sotto
  /// c'è un canale verso Kotlin. È la stessa scelta di `ErrorMapper` in
  /// field-reports e della gerarchia sealed in pos_sync.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      final String message = e.message ?? e.code;
      throw switch (e.code) {
        'not_found' => PrinterNotFound(message),
        'permission_denied' => PrinterPermissionDenied(message),
        'not_open' => PrinterNotOpen(message),
        'write_failed' => PrinterWriteFailed(message),
        // Un codice che non conosciamo è comunque un guasto del canale, e
        // trattarlo come transitorio è la scelta prudente: al massimo si
        // riprova una volta di troppo.
        _ => PrinterUnreachable('${e.code}: $message'),
      };
    } on MissingPluginException {
      throw const PrinterNotFound(
          'Il canale nativo non è registrato: questa piattaforma non è '
          'supportata');
    }
  }
}
