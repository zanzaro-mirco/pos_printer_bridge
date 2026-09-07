import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:receipt_engine/receipt_engine.dart';

/// Lo scontrino su cui girano il confronto byte per byte e l'anteprima del
/// README.
///
/// Non è uno scontrino qualunque: contiene, di proposito, tutto ciò che
/// l'impaginazione deve saper reggere — **due aliquote**, uno sconto di riga,
/// uno **sconto di documento**, una quantità frazionaria (la merce a peso) e
/// una descrizione più lunga della carta, che è il caso in cui l'a capo
/// automatico o funziona o si vede subito.
///
/// L'istante di emissione è fissato: un documento che cambia a ogni
/// esecuzione non si può confrontare con niente.
Receipt referenceReceipt() => (ReceiptBuilder(
      id: '0042',
      issuedAt: DateTime(2026, 9, 7, 20, 15),
    )
          ..addLine(
            description: 'Coperto',
            unitPrice: const Money(200),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          ..addLine(
            description: 'Spaghetti alle vongole',
            unitPrice: const Money(1200),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          ..addLine(
            description: 'Bistecca di manzo al kg',
            unitPrice: const Money(3200),
            vatRate: VatRate.reduced,
            quantity: 0.4,
          )
          ..addLine(
            description: 'Caffè espresso',
            unitPrice: const Money(120),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          ..addLine(
            description: 'Vino della casa',
            unitPrice: const Money(1600),
            vatRate: VatRate.standard,
            discount: PercentageDiscount(10, description: 'Sconto soci'),
          )
          ..addLine(
            description:
                'Acqua minerale naturale in bottiglia da un litro e mezzo',
            unitPrice: const Money(100),
            vatRate: VatRate.reduced,
            quantity: 2,
          )
          ..applyDocumentDiscount(
            AmountDiscount(const Money(300), description: 'Sconto fedeltà'),
          ))
        .close(paid: const Money(6000));

/// Il reso di due righe dello scontrino di riferimento.
ReturnReceipt referenceReturn() => (ReturnBuilder(
      id: 'R-0007',
      original: referenceReceipt(),
      issuedAt: DateTime(2026, 9, 8, 11, 30),
    )
          ..addLine(1, quantity: 1)
          ..addLine(3))
        .close();

/// L'impaginazione usata dal README e dai confronti: un locale con nome,
/// indirizzo e partita IVA, su carta da 80 mm.
const ReceiptLayout referenceLayout = ReceiptLayout(
  shop: ShopHeader(
    name: 'Trattoria da Mirco',
    addressLines: <String>['Via Roma 12 - 31100 Treviso', 'Tel. 0422 123456'],
    vatNumber: '01234567890',
    footer: 'Grazie e arrivederci',
  ),
);
