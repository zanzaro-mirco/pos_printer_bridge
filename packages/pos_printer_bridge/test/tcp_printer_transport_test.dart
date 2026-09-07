import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_printer_bridge/pos_printer_bridge.dart';

/// Una stampante finta in ascolto su `localhost`.
///
/// Non è un doppio: è un vero `ServerSocket`, e il trasporto ci parla con un
/// vero socket. Ciò che questi test mettono alla prova è quindi il codice che
/// andrà in produzione, non una sua imitazione — l'unica cosa finta è chi sta
/// dall'altro capo del cavo.
class FakePrinter {
  FakePrinter._(this._server);

  static Future<FakePrinter> listen() async =>
      FakePrinter._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));

  final ServerSocket _server;
  final List<int> received = <int>[];
  final Completer<void> _connected = Completer<void>();
  Socket? _client;

  int get port => _server.port;

  Future<void> get connected => _connected.future;

  void start() {
    _server.listen((Socket client) {
      _client = client;
      if (!_connected.isCompleted) _connected.complete();
      client.listen(received.addAll);
    });
  }

  /// Manda indietro dei byte, come fa una stampante quando cambia qualcosa.
  void send(List<int> bytes) => _client?.add(bytes);

  Future<void> close() async {
    await _client?.close();
    await _server.close();
  }
}

void main() {
  late FakePrinter printer;

  setUp(() async {
    printer = await FakePrinter.listen();
    printer.start();
  });

  tearDown(() async => printer.close());

  group('TcpPrinterTransport · i byte arrivano davvero', () {
    test('quello che si scrive è quello che la stampante riceve', () async {
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);

      await transport.open();
      await transport.write(Uint8List.fromList(<int>[0x1B, 0x40, 0x41]));
      await printer.connected;
      await _settle();

      expect(printer.received, <int>[0x1B, 0x40, 0x41]);
      await transport.dispose();
    });

    test('open e close si riflettono su isOpen', () async {
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);

      expect(transport.isOpen, isFalse);
      await transport.open();
      expect(transport.isOpen, isTrue);
      await transport.close();
      expect(transport.isOpen, isFalse);

      await transport.dispose();
    });

    test('chiudere due volte non è un errore', () async {
      // Chiudere è l'unica operazione che si finisce sempre per fare due
      // volte, di solito da un `finally` e da un `dispose`.
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);

      await transport.open();
      await transport.close();

      expect(transport.close, returnsNormally);
      await transport.dispose();
    });
  });

  group('TcpPrinterTransport · quando non funziona', () {
    test('una porta senza nessuno in ascolto è irraggiungibile', () async {
      final ServerSocket closed =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final int freePort = closed.port;
      await closed.close();

      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: freePort);

      await expectLater(
        transport.open(),
        throwsA(isA<PrinterUnreachable>()),
      );
    });

    test('un guasto di rete è transitorio: riprovare ha senso', () async {
      // È la distinzione che serve a chi chiama, e l'unica che la gerarchia
      // degli errori deve rendere ovvia.
      const PrinterFailure unreachable = PrinterUnreachable('spenta');
      const PrinterFailure denied = PrinterPermissionDenied('negato');

      expect(unreachable.isTransient, isTrue);
      expect(denied.isTransient, isFalse,
          reason: 'riprovare vuol dire rimostrare la stessa finestra a chi '
              "l'ha appena chiusa");
    });

    test('scrivere senza aprire è un errore di chi programma', () async {
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);

      await expectLater(
        transport.write(Uint8List.fromList(<int>[0x41])),
        throwsA(isA<PrinterNotOpen>()),
      );
    });
  });

  group('TcpPrinterTransport · lo stato torna indietro da solo', () {
    test('quattro byte mandati dalla stampante diventano uno stato', () async {
      // Nessuno li ha chiesti: è il punto. La carta finisce quando finisce.
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);
      await transport.open();
      final Future<PrinterStatus> first = transport.status.first;
      await printer.connected;

      printer.send(<int>[0x18, 0x70, 0x10, 0x7C]);

      final PrinterStatus status = await first.timeout(
        const Duration(seconds: 5),
      );
      expect(status.paperEnd, isTrue);
      expect(status.online, isFalse);

      await transport.dispose();
    });

    test('uno stato spezzato in due pacchetti si ricompone', () async {
      // Sul filo i byte arrivano come li consegna il sistema operativo, non a
      // gruppi di quattro.
      final TcpPrinterTransport transport =
          TcpPrinterTransport(host: '127.0.0.1', port: printer.port);
      await transport.open();
      final Future<PrinterStatus> first = transport.status.first;
      await printer.connected;

      printer.send(<int>[0x10, 0x10]);
      await _settle();
      printer.send(<int>[0x10, 0x1C]);

      final PrinterStatus status = await first.timeout(
        const Duration(seconds: 5),
      );
      expect(status.paperNearEnd, isTrue);

      await transport.dispose();
    });
  });
}

/// Lascia girare il ciclo degli eventi: i socket lavorano fuori dal test.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));
