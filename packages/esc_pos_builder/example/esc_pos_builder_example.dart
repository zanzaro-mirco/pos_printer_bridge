import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:receipt_engine/receipt_engine.dart';

/// Uno scontrino da bar, dal calcolo ai byte.
///
/// Si lancia con `dart run example/esc_pos_builder_example.dart` e non serve
/// niente: nessuna stampante, nessuna porta aperta. Stampa a schermo lo
/// scontrino come uscirebbe dalla carta, e in coda i primi byte del flusso.
void main() {
  // 1. Il conto lo fa `receipt_engine`: aliquote, sconti e scorporo dell'IVA
  //    non sono affari di chi stampa.
  final Receipt receipt = (ReceiptBuilder(id: '0128')
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

  // 2. L'impaginazione decide come sta sulla carta, e la carta è un
  //    parametro: la stessa riga di codice produce 80 o 58 mm.
  const ReceiptLayout layout = ReceiptLayout(
    shop: ShopHeader(
      name: 'Bar Centrale',
      addressLines: <String>['Piazza dei Signori 1 - Treviso'],
      vatNumber: '01234567890',
      footer: 'Arrivederci e grazie',
    ),
    paper: PaperFormat.mm58,
  );
  final EscPosDocument document = layout.render(receipt);

  // 3. L'anteprima: lo scontrino senza avere una stampante.
  stdout
    ..writeln(const PaperPreview().render(document, PaperFormat.mm58))
    ..writeln();

  // 4. I byte, che è quello che si manda alla stampante. Da qui in poi è un
  //    problema di trasporto — seriale, USB o socket — e non di questo
  //    pacchetto.
  final Uint8List bytes = const EscPosEncoder().encode(document);
  stdout
    ..writeln('${bytes.length} byte da mandare alla stampante.')
    ..writeln('I primi sedici: ${_hex(bytes.sublist(0, 16))}')
    ..writeln('Cioè: ESC @ (inizializza), ESC t 19 (tabella PC858), '
        'poi il testo.');
}

String _hex(Uint8List bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
