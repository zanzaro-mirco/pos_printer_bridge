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
        'poi il testo.')
    ..writeln();

  // 5. Un cartellino: logo e codice a barre, che sono le due cose che una
  //    termica fa e che non sono testo. Il logo è disegnato qui sotto come
  //    testo, perché questo pacchetto non legge i PNG: chi ha già un
  //    decodificatore gli passa i bit, chi non ce l'ha disegna.
  final EscPosDocumentBuilder label = EscPosDocumentBuilder(PaperFormat.mm58)
    ..image(_mark)
    ..blank()
    ..line('CAFFE ARABICA 250 G', style: EscPosTextStyle.centered)
    ..blank()
    // Dodici cifre: la tredicesima la calcola la stampante. Con tredici
    // ci sarebbe anche la verifica, perché la stampante non la fa.
    ..barcode(PrintBarcode.ean13('800123456789'))
    ..blank()
    ..barcode(PrintBarcode.code128('LOTTO-2026-10', heightDots: 60))
    ..feed(2)
    ..cut();

  stdout
    ..writeln(const PaperPreview().render(label.build(), PaperFormat.mm58))
    ..writeln()
    ..writeln('Il cartellino sono '
        '${const EscPosEncoder().encode(label.build()).length} byte: '
        'il logo se ne prende la gran parte.');
}

/// Un marchio disegnato a mano: 96 punti per 48, dentro una cornice.
///
/// È fatto con `RasterImage.fromRows`, che prende un punto per carattere. Su
/// 58 mm di carta ci sono 384 punti, quindi questo ne occupa un quarto.
final RasterImage _mark = RasterImage.fromRows(<String>[
  for (int y = 0; y < 48; y++)
    <String>[
      for (int x = 0; x < 96; x++)
        // La cornice, e una diagonale che dice da che parte sta il disegno.
        y < 3 || y >= 45 || x < 3 || x >= 93 || (x ~/ 2 - y).abs() < 3
            ? '#'
            : ' ',
    ].join(),
]);

String _hex(Uint8List bytes) =>
    bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
