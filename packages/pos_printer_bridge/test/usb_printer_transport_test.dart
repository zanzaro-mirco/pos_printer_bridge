import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_printer_bridge/pos_printer_bridge.dart';

/// Il confine con il codice nativo, messo alla prova senza un dispositivo
/// collegato.
///
/// Qui non si verifica Kotlin: si verifica che **la chiamata attraversi
/// davvero il canale** con il nome e gli argomenti giusti, e che ciò che torna
/// indietro — errori compresi — diventi un tipo di dominio prima di uscire dal
/// pacchetto. È esattamente il confine che, sbagliato, produce l'errore più
/// difficile da capire: un metodo che non esiste dall'altra parte e una
/// `MissingPluginException` senza spiegazioni.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methods =
      MethodChannel(UsbPrinterTransport.methodChannelName);
  const EventChannel events =
      EventChannel(UsbPrinterTransport.eventChannelName);

  final List<MethodCall> calls = <MethodCall>[];
  Object? Function(MethodCall call) handler = (MethodCall call) => null;

  setUp(() {
    calls.clear();
    handler = (MethodCall call) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(methods, null)
      ..setMockStreamHandler(events, null);
  });

  group('UsbPrinterTransport · le chiamate attraversano il canale', () {
    test('open, write e close arrivano dall\'altra parte', () async {
      final UsbPrinterTransport transport = UsbPrinterTransport();

      await transport.open();
      await transport.write(Uint8List.fromList(<int>[0x1B, 0x40]));
      await transport.close();

      expect(calls.map((MethodCall c) => c.method).toList(),
          <String>['open', 'write', 'close']);
    });

    test('i byte passano come Uint8List, non come lista di interi', () async {
      // Il canale consegna un `Uint8List` a Kotlin come `ByteArray` senza
      // convertirlo elemento per elemento. Su uno scontrino sono un migliaio
      // di elementi, e la differenza si vede.
      final UsbPrinterTransport transport = UsbPrinterTransport();
      await transport.open();

      await transport.write(Uint8List.fromList(<int>[0x41, 0x42]));

      final MethodCall write =
          calls.firstWhere((MethodCall c) => c.method == 'write');
      expect(write.arguments, isA<Uint8List>());
      expect(write.arguments, <int>[0x41, 0x42]);
    });

    test('scrivere senza aprire non tocca nemmeno il canale', () async {
      // È un errore di chi programma: farlo arrivare al nativo significa
      // scoprirlo con un messaggio di Kotlin invece che con il proprio.
      final UsbPrinterTransport transport = UsbPrinterTransport();

      await expectLater(
        transport.write(Uint8List.fromList(<int>[0x41])),
        throwsA(isA<PrinterNotOpen>()),
      );
      expect(calls, isEmpty);
    });

    test('chiudere un canale mai aperto non chiama niente', () async {
      await UsbPrinterTransport().close();

      expect(calls, isEmpty);
    });
  });

  group('UsbPrinterTransport · gli errori diventano di dominio', () {
    Future<void> expectFailure(String code, TypeMatcher<Object> matcher) async {
      handler = (MethodCall call) => throw PlatformException(code: code);
      await expectLater(UsbPrinterTransport().open(), throwsA(matcher));
    }

    test('nessuna stampante collegata', () async {
      await expectFailure('not_found', isA<PrinterNotFound>());
    });

    test('permesso negato dall\'utente', () async {
      await expectFailure('permission_denied', isA<PrinterPermissionDenied>());
    });

    test('scrittura interrotta', () async {
      await expectFailure('write_failed', isA<PrinterWriteFailed>());
    });

    test('un codice sconosciuto resta un guasto, e transitorio', () async {
      // Al massimo si riprova una volta di troppo: è la scelta prudente.
      handler = (MethodCall call) => throw PlatformException(code: 'boh');

      await expectLater(
        UsbPrinterTransport().open(),
        throwsA(isA<PrinterUnreachable>().having(
            (PrinterFailure f) => f.isTransient, 'transitorio', isTrue)),
      );
    });

    test('fuori di qui non esistono PlatformException', () async {
      // Chi stampa non deve sapere che sotto c'è un canale verso Kotlin.
      handler = (MethodCall call) => throw PlatformException(code: 'not_found');

      await expectLater(
        UsbPrinterTransport().open(),
        throwsA(isNot(isA<PlatformException>())),
      );
    });

    test('un canale non registrato lo dice invece di lasciare un mistero',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methods, null);

      await expectLater(
        UsbPrinterTransport().open(),
        throwsA(isA<PrinterNotFound>().having(
          (PrinterFailure f) => f.message,
          'messaggio',
          contains('piattaforma'),
        )),
      );
    });

    test('un open fallito non lascia il canale aperto', () async {
      handler = (MethodCall call) => throw PlatformException(code: 'not_found');
      final UsbPrinterTransport transport = UsbPrinterTransport();

      await expectLater(transport.open(), throwsA(isA<PrinterFailure>()));

      expect(transport.isOpen, isFalse);
    });
  });

  group('UsbPrinterTransport · gli stati arrivano dal canale degli eventi', () {
    test('quattro byte dal nativo diventano uno stato', () async {
      // Kotlin manda i byte grezzi; a decodificarli è lo stesso codice che
      // usa il trasporto TCP. Una decodifica sola, due trasporti.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
            sink.success(Uint8List.fromList(<int>[0x18, 0x14, 0x10, 0x10]));
          },
        ),
      );

      final PrinterStatus status = await UsbPrinterTransport()
          .status
          .first
          .timeout(const Duration(seconds: 5));

      expect(status.coverOpen, isTrue);
      expect(status.online, isFalse);
    });

    test('byte che non sono uno stato non producono niente', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        events,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink sink) {
            sink
              ..success(Uint8List.fromList(<int>[0xFF, 0xFF, 0xFF, 0xFF]))
              ..success(Uint8List.fromList(<int>[0x10, 0x10, 0x10, 0x10]));
          },
        ),
      );

      final PrinterStatus status = await UsbPrinterTransport()
          .status
          .first
          .timeout(const Duration(seconds: 5));

      expect(status.needsAttention, isFalse,
          reason: 'il primo gruppo è rumore e viene scartato');
    });
  });
}
