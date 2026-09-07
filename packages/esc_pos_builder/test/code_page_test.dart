import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

void main() {
  group('CodePage · un carattere, un byte', () {
    test('l\'ASCII passa intatto', () {
      expect(CodePage.cp858.encode('EUR 12,00'),
          <int>[0x45, 0x55, 0x52, 0x20, 0x31, 0x32, 0x2C, 0x30, 0x30]);
    });

    test('una lettera accentata diventa un byte solo, non due', () {
      // È il difetto che si vede solo su carta: in UTF-8 la «è» sono due
      // byte, e la stampante ne stampa due.
      expect(CodePage.cp858.encode('è'), <int>[0x8A]);
      expect('è'.codeUnits.length, 1, reason: 'un carattere in Dart');
      expect(CodePage.cp858.encode('caffè').length, 5);
    });

    test('le vocali accentate italiane ci sono tutte', () {
      expect(CodePage.cp858.canEncode('àèéìòù ÀÈÉÌÒÙ'), isTrue);
    });
  });

  group('CodePage · perché due tabelle e non una', () {
    test('PC858 ha l\'euro, PC437 no', () {
      // È l\'unica differenza che conta per uno scontrino italiano, ed è la
      // ragione per cui PC858 esiste: prende il posto di un carattere che a
      // nessuno serviva.
      expect(CodePage.cp858.byteOf('€'), 0xD5);
      expect(CodePage.cp437.byteOf('€'), isNull);
    });

    test('ciò che non c\'è diventa un punto interrogativo, non un errore', () {
      // Una stampante che non stampa è peggio di una che stampa «?»: lo
      // scontrino va consegnato comunque.
      expect(CodePage.cp437.encode('12,00 €').last, 0x3F);
      expect(CodePage.cp437.canEncode('€'), isFalse,
          reason: 'chi vuole accorgersene prima ha come');
    });

    test('la tabella dichiara il numero con cui la stampante la seleziona', () {
      expect(CodePage.cp437.id, 0);
      expect(CodePage.cp858.id, 19);
    });
  });

  group('CodePage · le tabelle sono quelle giuste', () {
    // Le tabelle sono generate dai codec cp437 e cp858 e incollate come
    // costanti. Due dei loro caratteri sono **invisibili nel sorgente** — lo
    // spazio unificatore e il trattino condizionale — e un editor distratto
    // può mangiarseli senza che niente lo segnali. Questi controlli esistono
    // per quello: fissano le posizioni che non si possono guardare.
    test('le posizioni invisibili sono al loro posto', () {
      expect(CodePage.cp858.upperHalf.codeUnitAt(0xFF - 0x80), 0x00A0,
          reason: 'spazio unificatore a 0xFF');
      expect(CodePage.cp858.upperHalf.codeUnitAt(0xF0 - 0x80), 0x00AD,
          reason: 'trattino condizionale a 0xF0');
      expect(CodePage.cp437.upperHalf.codeUnitAt(0xFF - 0x80), 0x00A0);
    });

    test('ogni tabella copre i 128 byte alti', () {
      for (final CodePage page in <CodePage>[CodePage.cp437, CodePage.cp858]) {
        expect(page.upperHalf.length, 128, reason: page.name);
        expect(page.upperHalf.runes.toSet().length, 128,
            reason: '${page.name}: nessun carattere ripetuto, '
                'altrimenti un byte non sarebbe raggiungibile');
      }
    });

    test('qualche posizione nota, presa dalla specifica', () {
      expect(CodePage.cp858.byteOf('Ç'), 0x80);
      expect(CodePage.cp858.byteOf('ü'), 0x81);
      expect(CodePage.cp858.byteOf('°'), 0xF8);
      expect(CodePage.cp858.byteOf('£'), 0x9C);
    });
  });
}
