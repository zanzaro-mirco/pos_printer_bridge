import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'printer_failure.dart';
import 'printer_status.dart';
import 'printer_transport.dart';

/// Il canale verso una stampante di rete, in Dart puro.
///
/// Nessun codice nativo, nessun permesso da chiedere, nessuna piattaforma: una
/// stampante Ethernet o Wi-Fi espone una porta e accetta byte grezzi. È il
/// trasporto che si può mettere alla prova **contro un vero server in ascolto
/// su `localhost`**, senza avere una stampante — ed è il motivo per cui esiste
/// prima dell'altro.
class TcpPrinterTransport implements PrinterTransport {
  /// Crea il canale verso [host].
  TcpPrinterTransport({
    required this.host,
    this.port = defaultPort,
    this.timeout = const Duration(seconds: 5),
  });

  /// La porta 9100, cioè RAW/JetDirect: non è uno standard scritto da
  /// nessuno, è quella su cui tutti si sono trovati d'accordo. Chi ne usa
  /// un'altra la passa.
  static const int defaultPort = 9100;

  /// Indirizzo della stampante.
  final String host;

  /// Porta su cui è in ascolto.
  final int port;

  /// Quanto attendere la connessione prima di dichiararla irraggiungibile.
  ///
  /// Serve un limite esplicito: senza, una stampante spenta in una rete che
  /// non risponde lascia l'applicazione ferma finché il sistema operativo non
  /// si stanca, e sono decine di secondi con la cassa bloccata.
  final Duration timeout;

  final StreamController<PrinterStatus> _status =
      StreamController<PrinterStatus>.broadcast();
  final PrinterStatusReader _reader = PrinterStatusReader();

  Socket? _socket;

  @override
  bool get isOpen => _socket != null;

  @override
  Stream<PrinterStatus> get status => _status.stream;

  @override
  Future<void> open() async {
    if (isOpen) return;
    try {
      final Socket socket = await Socket.connect(host, port, timeout: timeout);
      // Niente algoritmo di Nagle: uno scontrino è una scrittura sola e
      // aspettare di riempire un pacchetto aggiunge ritardo senza risparmiare
      // niente.
      socket.setOption(SocketOption.tcpNoDelay, true);
      _socket = socket;
      socket.listen(
        _onIncoming,
        onError: (Object _) => _drop(),
        onDone: _drop,
        cancelOnError: true,
      );
    } on SocketException catch (e) {
      throw PrinterUnreachable('$host:$port non risponde (${e.message})');
    }
  }

  @override
  Future<void> write(Uint8List bytes) async {
    final Socket? socket = _socket;
    if (socket == null) {
      throw const PrinterNotOpen('Chiamare open() prima di write()');
    }
    try {
      socket.add(bytes);
      await socket.flush();
    } on SocketException catch (e) {
      throw PrinterWriteFailed('Scrittura interrotta (${e.message})');
    }
  }

  @override
  Future<void> close() async {
    final Socket? socket = _socket;
    _socket = null;
    _reader.reset();
    if (socket == null) return;
    // `destroy` e non `close`: chiudere in modo ordinato aspetta che l'altro
    // capo chiuda a sua volta, e una stampante non lo fa mai.
    socket.destroy();
  }

  /// Tutto ciò che arriva **indietro** da una stampante è stato: non c'è altro
  /// che possa mandare.
  void _onIncoming(Uint8List bytes) {
    for (final PrinterStatus status in _reader.add(bytes)) {
      if (!_status.isClosed) _status.add(status);
    }
  }

  void _drop() {
    _socket = null;
    _reader.reset();
  }

  /// Chiude anche il flusso degli stati. Da chiamare quando il canale non
  /// servirà più: [close] lascia il flusso aperto perché riaprire lo stesso
  /// canale è normale.
  Future<void> dispose() async {
    await close();
    await _status.close();
  }
}
