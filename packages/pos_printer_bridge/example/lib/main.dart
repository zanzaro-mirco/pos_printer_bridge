import 'dart:async';
import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:flutter/material.dart';
import 'package:pos_printer_bridge/pos_printer_bridge.dart';
import 'package:receipt_engine/receipt_engine.dart';

/// La filiera intera, in un'applicazione sola.
///
/// `receipt_engine` calcola lo scontrino, `esc_pos_builder` lo impagina in
/// byte, `pos_printer_bridge` lo manda alla stampante. I tre pacchetti si
/// incontrano **qui** e non fra loro: è il motivo per cui il costruttore di
/// byte non dipende da Flutter e il trasporto non sa cosa sia uno scontrino.
void main() => runApp(const PrinterDemoApp());

/// L'applicazione di prova.
class PrinterDemoApp extends StatelessWidget {
  /// Crea l'applicazione.
  const PrinterDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'pos_printer_bridge',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
        home: const PrinterDemoPage(),
      );
}

/// Come si raggiunge la stampante.
enum TransportKind {
  /// Via rete, sulla porta 9100.
  network('Rete'),

  /// Collegata alla porta USB.
  usb('USB');

  const TransportKind(this.label);

  /// Nome mostrato all'operatore.
  final String label;
}

/// La schermata: si sceglie il trasporto, si guarda l'anteprima, si stampa.
class PrinterDemoPage extends StatefulWidget {
  /// Crea la schermata.
  const PrinterDemoPage({super.key});

  @override
  State<PrinterDemoPage> createState() => _PrinterDemoPageState();
}

class _PrinterDemoPageState extends State<PrinterDemoPage> {
  static const ReceiptLayout _layout = ReceiptLayout(
    shop: ShopHeader(
      name: 'Bar Centrale',
      addressLines: <String>['Piazza dei Signori 1 - Treviso'],
      vatNumber: '01234567890',
      footer: 'Arrivederci e grazie',
    ),
    paper: PaperFormat.mm58,
  );

  final TextEditingController _host =
      TextEditingController(text: '192.168.1.50');

  TransportKind _kind = TransportKind.network;
  StreamSubscription<PrinterStatus>? _watching;
  PrinterStatus? _status;
  String? _message;
  bool _busy = false;

  late final EscPosDocument _document = _layout.render(_demoReceipt());

  @override
  void dispose() {
    unawaited(_watching?.cancel());
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Stampa di prova')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SegmentedButton<TransportKind>(
              segments: TransportKind.values
                  .map((TransportKind k) => ButtonSegment<TransportKind>(
                        value: k,
                        label: Text(k.label),
                      ))
                  .toList(),
              selected: <TransportKind>{_kind},
              onSelectionChanged: (Set<TransportKind> chosen) =>
                  setState(() => _kind = chosen.single),
            ),
            if (_kind == TransportKind.network) ...<Widget>[
              const SizedBox(height: 12),
              TextField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'Indirizzo della stampante',
                  helperText: 'La porta è la 9100, quella di tutte',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _print,
              icon: const Icon(Icons.print),
              label: const Text('Stampa lo scontrino'),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 12),
              _Notice(text: _message!),
            ],
            if (_status != null) ...<Widget>[
              const SizedBox(height: 12),
              _Notice(text: 'Stato: ${_status!}'),
            ],
            const SizedBox(height: 24),
            Text('Anteprima', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // L'anteprima arriva dallo stesso documento che si stampa: quello
            // che si vede a schermo e quello che esce dalla carta non possono
            // divergere.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                const PaperPreview().render(_document, PaperFormat.mm58),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      );

  Future<void> _print() async {
    setState(() {
      _busy = true;
      _message = null;
      _status = null;
    });

    final PrinterTransport transport = switch (_kind) {
      TransportKind.network => TcpPrinterTransport(host: _host.text.trim()),
      TransportKind.usb => UsbPrinterTransport(),
    };

    try {
      await transport.open();
      // Gli stati vanno accesi: senza, la stampante non manda niente e il
      // flusso resta muto anche quando la carta finisce.
      await _watching?.cancel();
      _watching = transport.status.listen(
        (PrinterStatus status) => setState(() => _status = status),
      );
      await transport.write(
        Uint8List.fromList(PrinterStatus.enableAutomaticStatusBack),
      );

      await transport.write(const EscPosEncoder().encode(_document));
      _say('Scontrino mandato: '
          '${const EscPosEncoder().encode(_document).length} byte.');
    } on PrinterFailure catch (e) {
      // Un errore di stampa non è una schermata rossa: è una riga che dice
      // cosa fare. E se riprovare ha senso, lo dice.
      _say(e.isTransient
          ? '${e.message}. Riprovare può avere senso.'
          : '${e.message}. Riprovare non serve.');
    } finally {
      await transport.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (mounted) setState(() => _message = message);
  }
}

/// Uno scontrino da bar, calcolato per davvero.
Receipt _demoReceipt() => (ReceiptBuilder(id: '0128')
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
      ))
    .close(paid: const Money(1000));

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text),
      );
}
