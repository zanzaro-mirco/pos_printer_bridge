import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:receipt_engine/receipt_engine.dart';
import 'package:test/test.dart';

import 'helpers/reference_receipt.dart';

void main() {
  const PaperPreview preview = PaperPreview(showCommands: false);

  String onPaper(EscPosDocument document, PaperFormat paper) =>
      preview.render(document, paper);

  group('ReceiptLayout · quello che il cliente deve poter rifare a mano', () {
    late String paper;

    setUp(() {
      paper =
          onPaper(referenceLayout.render(referenceReceipt()), PaperFormat.mm80);
    });

    test('ogni voce compare con il proprio totale di riga', () {
      expect(paper, contains('Spaghetti alle vongole'));
      expect(paper, contains('24,00'));
    });

    test('la quantità e il prezzo unitario stanno sotto la voce', () {
      // Senza, un totale di riga da 24,00 non si può verificare.
      expect(paper, contains('2 x 12,00'));
    });

    test('una riga da un pezzo senza sconto non ripete il prezzo', () {
      // «1 x 2,40» accanto a «2,40» non aggiunge niente e allunga lo
      // scontrino di una riga per voce.
      final Receipt single = (ReceiptBuilder(id: '1')
            ..addLine(
              description: 'Caffè',
              unitPrice: const Money(120),
              vatRate: VatRate.reduced,
            ))
          .close(paid: const Money(120));

      expect(onPaper(referenceLayout.render(single), PaperFormat.mm80),
          isNot(contains('1 x')));
    });

    test('lo sconto di riga si legge con il suo motivo', () {
      expect(paper, contains('Sconto soci'));
      expect(paper, contains('-1,60'));
    });

    test('lo sconto di documento è una voce a sé, non un prezzo ritoccato', () {
      // I totali di riga restano quelli del listino: è così che il conto
      // torna sotto gli occhi di chi paga.
      expect(paper, contains('Sconto sul documento'));
      expect(paper, contains('-3,00'));
      expect(paper, contains('24,00'),
          reason: 'la riga da 24,00 non è stata scontata di nascosto');
    });

    test('totale, contanti e resto', () {
      expect(paper, contains('TOTALE'));
      expect(paper, contains('56,60'));
      expect(paper, contains('Resto'));
      expect(paper, contains('3,40'));
    });

    test('il riepilogo IVA ha una riga per aliquota', () {
      expect(paper, contains('10%'));
      expect(paper, contains('22%'));
    });

    test('conta le voci, non la somma delle quantità', () {
      // Sommare due coperti, quattro etti di carne e una bottiglia darebbe
      // 7,4: un numero che non significa niente.
      expect(paper, contains('Voci'));
      expect(paper, isNot(contains('7,4')));
    });
  });

  group('ReceiptLayout · la carta stretta non è la carta larga', () {
    late String wide;
    late String narrow;

    setUp(() {
      wide =
          onPaper(referenceLayout.render(referenceReceipt()), PaperFormat.mm80);
      narrow = onPaper(
        const ReceiptLayout(
          shop: ShopHeader(name: 'Trattoria da Mirco'),
          paper: PaperFormat.mm58,
        ).render(referenceReceipt()),
        PaperFormat.mm58,
      );
    });

    test('nessuna riga supera mai la larghezza della carta', () {
      // È la garanzia su cui si regge tutto il resto: sforare significa una
      // stampante che va a capo dove capita.
      for (final String line in wide.split('\n')) {
        expect(line.length, lessThanOrEqualTo(48), reason: line);
      }
      for (final String line in narrow.split('\n')) {
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }
    });

    test('su 58 mm il riepilogo IVA passa a due righe per aliquota', () {
      // Le quattro colonne non entrano in 32 caratteri, e incolonnarle a
      // forza le renderebbe illeggibili.
      expect(wide, contains('Imponibile'));
      expect(narrow, isNot(contains('Imponibile')));
      expect(narrow, contains('imponibile 39,02'));
    });

    test('gli stessi importi, su entrambe', () {
      expect(wide, contains('56,60'));
      expect(narrow, contains('56,60'));
    });
  });

  group('ReceiptLayout · il reso', () {
    late String paper;

    setUp(() {
      paper = onPaper(
          referenceLayout.renderReturn(referenceReturn()), PaperFormat.mm80);
    });

    test('dichiara di essere un reso e a quale scontrino si riferisce', () {
      // Un reso senza il riferimento all'originale non è un documento
      // collegato: è un altro scontrino con i numeri negativi.
      expect(paper, contains('DOCUMENTO DI RESO'));
      expect(paper, contains('Riferito allo scontrino 0042'));
    });

    test('gli importi restano negativi, il rimborso è positivo', () {
      // I documenti si sommano senza casi particolari; all'operatore serve
      // sapere quanto tirare fuori dal cassetto.
      expect(paper, contains('TOTALE'));
      expect(paper, contains('-'));
      expect(paper, contains('RIMBORSO'));
      final RegExp refund = RegExp(r'RIMBORSO[^\n]*\s(\d+,\d\d)');
      expect(refund.firstMatch(paper)?.group(1), isNotNull);
      expect(refund.firstMatch(paper)!.group(1)!.startsWith('-'), isFalse);
    });
  });

  group('ReceiptLayout · chi emette il documento', () {
    test('nome, indirizzo e partita IVA in testa', () {
      final String paper =
          onPaper(referenceLayout.render(referenceReceipt()), PaperFormat.mm80);

      expect(paper, contains('Trattoria da Mirco'));
      expect(paper, contains('Via Roma 12'));
      expect(paper, contains('P.IVA 01234567890'));
    });

    test('senza partita IVA la riga non compare vuota', () {
      final String paper = onPaper(
        const ReceiptLayout(shop: ShopHeader(name: 'Bar'))
            .render(referenceReceipt()),
        PaperFormat.mm80,
      );

      expect(paper, isNot(contains('P.IVA')));
    });

    test('il cassetto si apre solo se questa cassa lo ha', () {
      // Un impulso su una stampante senza cassetto non fa danni, ma
      // dichiararlo è meglio che mandarlo per abitudine.
      const ReceiptLayout withDrawer = ReceiptLayout(
        shop: ShopHeader(name: 'Bar'),
        openDrawerOnClose: true,
      );

      expect(
        withDrawer.render(referenceReceipt()).commands.whereType<OpenDrawer>(),
        hasLength(1),
      );
      expect(
        const ReceiptLayout(shop: ShopHeader(name: 'Bar'))
            .render(referenceReceipt())
            .commands
            .whereType<OpenDrawer>(),
        isEmpty,
      );
    });
  });
}
