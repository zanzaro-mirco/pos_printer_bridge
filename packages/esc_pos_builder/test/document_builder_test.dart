import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

void main() {
  List<String> textOf(EscPosDocument document) => document.commands
      .whereType<PrintLine>()
      .map((PrintLine line) => line.text)
      .toList();

  group('EscPosDocumentBuilder · le colonne', () {
    test('l\'importo finisce al bordo destro della carta', () {
      final EscPosDocumentBuilder sheet =
          EscPosDocumentBuilder(PaperFormat.mm58)..columns('Coperto', '2,00');

      expect(textOf(sheet.build()).single, 'Coperto                     2,00');
      expect(textOf(sheet.build()).single.length, 32);
    });

    test(
        'una descrizione lunga va a capo rientrata, e l\'importo resta in cima',
        () {
      final EscPosDocumentBuilder sheet = EscPosDocumentBuilder(
          PaperFormat.mm58)
        ..columns('Acqua minerale naturale in bottiglia da un litro', '2,00');

      final List<String> lines = textOf(sheet.build());
      expect(lines.first, endsWith('2,00'));
      expect(lines.length, greaterThan(1));
      expect(lines[1], startsWith('  '));
      expect(lines.every((String l) => l.length <= 32), isTrue);
    });

    test('una parola più lunga della carta viene spezzata invece che sforare',
        () {
      // La stampante andrebbe comunque a capo per conto suo, e nel punto
      // sbagliato: meglio decidere qui dove.
      final EscPosDocumentBuilder sheet =
          EscPosDocumentBuilder(PaperFormat.mm58)
            ..line('Supercalifragilistichespiralidoso' * 2);

      expect(textOf(sheet.build()).every((String l) => l.length <= 32), isTrue);
    });

    test('un importo più largo della carta è un errore di chi chiama', () {
      // Non si impagina: si sbaglia. Silenziosamente troncarlo produrrebbe
      // uno scontrino con un totale falso.
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm58).columns('x', '1' * 40),
        throwsArgumentError,
      );
    });
  });

  group('EscPosDocumentBuilder · la doppia larghezza conta doppio', () {
    test('un testo largo il doppio ha metà colonne a disposizione', () {
      const EscPosTextStyle wide = EscPosTextStyle(doubleWidth: true);
      final EscPosDocumentBuilder sheet =
          EscPosDocumentBuilder(PaperFormat.mm80)
            ..columns('TOTALE', '56,60', style: wide);

      // 24 caratteri, non 48: sulla carta ne occupano comunque 48.
      expect(textOf(sheet.build()).single.length, 24);
    });

    test('senza tenerne conto la riga sforerebbe', () {
      expect(
        EscPosDocumentBuilder(PaperFormat.mm80)
            .columnsFor(const EscPosTextStyle(doubleWidth: true)),
        24,
      );
      expect(
        EscPosDocumentBuilder(PaperFormat.mm80)
            .columnsFor(EscPosTextStyle.emphasis),
        48,
        reason: 'la doppia altezza non toglie colonne',
      );
    });
  });

  group('EscPosDocumentBuilder · la tabella', () {
    test('la prima cella a sinistra, le altre a destra', () {
      final EscPosDocumentBuilder sheet =
          EscPosDocumentBuilder(PaperFormat.mm80)
            ..row(<String>['10%', '39,02', '3,90'], <int>[16, 16, 16]);

      expect(textOf(sheet.build()).single,
          '10%                        39,02            3,90');
    });

    test('una cella troppo larga viene troncata, non mandata a capo', () {
      // In una tabella l\'a capo distruggerebbe l\'incolonnamento, che è
      // l\'unica ragione per cui la tabella esiste.
      final EscPosDocumentBuilder sheet =
          EscPosDocumentBuilder(PaperFormat.mm58)
            ..row(<String>['Aliquota ordinaria', '1,00'], <int>[8, 8]);

      expect(textOf(sheet.build()).single, 'Aliquota    1,00');
    });

    test('celle e larghezze devono corrispondersi', () {
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm80)
            .row(<String>['a'], <int>[4, 4]),
        throwsArgumentError,
      );
    });

    test('una tabella più larga della carta è un errore', () {
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm58)
            .row(<String>['a', 'b'], <int>[20, 20]),
        throwsArgumentError,
      );
    });
  });

  group('PrintLine · una riga è una riga', () {
    test('un a capo dentro il testo è rifiutato', () {
      // Aggirerebbe l\'unico posto che conosce la larghezza della carta.
      expect(() => PrintLine('primo\nsecondo'), throwsArgumentError);
      expect(() => PrintLine('primo\rsecondo'), throwsArgumentError);
    });
  });
}
