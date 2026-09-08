import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_printer_bridge/pos_printer_bridge.dart';
import 'package:receipt_engine/receipt_engine.dart';

/// La prova contro una stampante che esiste davvero.
///
/// È l'unica cosa che nessun altro test di questo repository può dare: tutti
/// gli altri girano contro un socket che ho scritto io, e un socket scritto da
/// chi scrive anche il client va d'accordo con lui per costruzione.
///
/// Non gira per conto suo. Serve dirgli dove guardare:
///
/// ```bash
/// flutter test test/real_printer_test.dart \
///   --dart-define=PRINTER_HOST=192.168.1.100 \
///   --dart-define=PRINTER_PORT=9200
/// ```
///
/// Senza, i test si saltano invece di fallire: una suite che diventa rossa
/// perché **non** hai una stampante collegata è una suite che si impara a
/// ignorare.
void main() {
  const String host = String.fromEnvironment('PRINTER_HOST');
  const int port = int.fromEnvironment('PRINTER_PORT', defaultValue: 9100);
  final bool configured = host.isNotEmpty;
  // `skip` va lasciato nullo quando il test deve girare: una stringa vuota e'
  // comunque una stringa, e il test verrebbe saltato con un motivo vuoto.
  final String? motivo = configured
      ? null
      : 'Serve --dart-define=PRINTER_HOST=<indirizzo> per girare';

  group('Contro una stampante vera', () {
    test('si apre, e in fretta', () async {
      final TcpPrinterTransport printer =
          TcpPrinterTransport(host: host, port: port);

      final Stopwatch t = Stopwatch()..start();
      await printer.open();
      t.stop();

      expect(printer.isOpen, isTrue);
      // Una stampante di rete su una LAN risponde in decine di millisecondi.
      // Se ci mette secondi, c'è di mezzo una risoluzione di nome che non
      // dovrebbe esserci, e vale la pena saperlo.
      expect(t.elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'aperta in ${t.elapsedMilliseconds} ms');

      await printer.dispose();
    }, skip: motivo);

    test('lo scontrino intero parte senza errori', () async {
      final Uint8List bytes = const EscPosEncoder().encode(_layout.render(
        _receipt(),
      ));
      final TcpPrinterTransport printer =
          TcpPrinterTransport(host: host, port: port);

      await printer.open();
      await printer.write(bytes);

      // Un migliaio di byte non entra in un pacchetto solo: se la scrittura
      // tornasse dopo il primo, questo passerebbe lo stesso. È il `flush`
      // dentro `write` a renderlo significativo.
      expect(bytes.length, greaterThan(500),
          reason: 'se fosse corto non proverebbe niente sulla frammentazione');

      await printer.dispose();
    }, skip: motivo);

    test('due scontrini di fila sulla stessa connessione', () async {
      // Al banco si stampa uno scontrino dietro l'altro: riaprire il socket a
      // ogni scontrino costerebbe una stretta di mano ogni volta.
      final Uint8List bytes =
          const EscPosEncoder().encode(_layout.render(_receipt()));
      final TcpPrinterTransport printer =
          TcpPrinterTransport(host: host, port: port);

      await printer.open();
      await printer.write(bytes);
      await printer.write(bytes);

      expect(printer.isOpen, isTrue);
      await printer.dispose();
    }, skip: motivo);

    test('chiusa e riaperta, stampa ancora', () async {
      final TcpPrinterTransport printer =
          TcpPrinterTransport(host: host, port: port);

      await printer.open();
      await printer.close();
      expect(printer.isOpen, isFalse);

      await printer.open();
      await printer
          .write(const EscPosEncoder().encode(_layout.render(_receipt())));

      expect(printer.isOpen, isTrue);
      await printer.dispose();
    }, skip: motivo);

    test('un indirizzo giusto sulla porta sbagliata è irraggiungibile',
        () async {
      // La stessa macchina, una porta dove non c'è niente: distingue «la rete
      // non arriva» da «il servizio non c'è», che per chi configura sono due
      // problemi diversi.
      final TcpPrinterTransport printer = TcpPrinterTransport(
        host: host,
        port: port + 1,
        timeout: const Duration(seconds: 3),
      );

      await expectLater(printer.open(), throwsA(isA<PrinterUnreachable>()));
    }, skip: motivo);

    test('se manda indietro qualcosa, lo si legge', () async {
      // Non tutte le stampanti mandano lo stato, e molte lo fanno solo se
      // glielo si accende. Questo test **riferisce** invece di pretendere: un
      // silenzio non è un difetto del client.
      final TcpPrinterTransport printer =
          TcpPrinterTransport(host: host, port: port);
      await printer.open();

      final Future<PrinterStatus?> first = printer.status.first
          .timeout(const Duration(seconds: 3), onTimeout: () => throw 0)
          .then<PrinterStatus?>((PrinterStatus s) => s)
          .catchError((Object _) => null);

      await printer
          .write(Uint8List.fromList(PrinterStatus.enableAutomaticStatusBack));
      final PrinterStatus? status = await first;

      printOnConsole(status == null
          ? 'La stampante non ha mandato stati: normale su molti modelli, e '
              'su quasi tutti gli emulatori.'
          : 'Stato ricevuto: $status');

      await printer.dispose();
    }, skip: motivo);
  });
}

/// Scrive nel registro del test senza asserire niente: qui l'informazione vale
/// più di un verdetto.
void printOnConsole(String message) =>
    // ignore: avoid_print
    print('  >> $message');

const ReceiptLayout _layout = ReceiptLayout(
  shop: ShopHeader(
    name: 'Bar Centrale',
    addressLines: <String>['Piazza dei Signori 1 - Treviso'],
    vatNumber: '01234567890',
    footer: 'Arrivederci e grazie',
  ),
);

Receipt _receipt() => (ReceiptBuilder(id: '0128')
      ..addLine(
        description: 'Caffè',
        unitPrice: const Money(120),
        vatRate: VatRate.reduced,
        quantity: 2,
      )
      ..addLine(
        description: 'Cornetto integrale',
        unitPrice: const Money(150),
        vatRate: VatRate.reduced,
      )
      ..addLine(
        description: 'Spremuta d\'arancia',
        unitPrice: const Money(350),
        vatRate: VatRate.standard,
        discount: PercentageDiscount(10, description: 'Sconto colazione'),
      )
      ..addLine(
        description: 'Acqua minerale naturale in bottiglia da un litro e mezzo',
        unitPrice: const Money(100),
        vatRate: VatRate.reduced,
        quantity: 2,
      ))
    .close(paid: const Money(1000));
