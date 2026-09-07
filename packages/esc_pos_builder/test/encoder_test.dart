import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

import 'helpers/esc_pos_decoder.dart';

void main() {
  Uint8List encode(List<EscPosCommand> commands,
          {CodePage page = CodePage.cp858}) =>
      EscPosEncoder(codePage: page).encode(EscPosDocument(commands));

  group('EscPosEncoder · il flusso, byte per byte', () {
    test('un documento minimo, scritto a mano e confrontato tutto', () {
      // È il solo confronto del pacchetto scritto byte per byte a mano, ed è
      // volutamente minuscolo: su un documento intero un'attesa compilata a
      // mano sarebbe illeggibile, e compilata dal codice in prova sarebbe
      // inutile. Qui invece ogni byte si può guardare accanto alla specifica.
      expect(
        encode(<EscPosCommand>[
          PrintLine('Ciao', style: EscPosTextStyle.centered),
          const CutPaper(),
        ]),
        <int>[
          0x1B, 0x40, //             ESC @   inizializza la stampante
          0x1B, 0x74, 0x13, //       ESC t 19   tabella PC858
          0x1B, 0x61, 0x01, //       ESC a 1    centrato
          0x43, 0x69, 0x61, 0x6F, // "Ciao"
          0x0A, //                   a capo
          0x1D, 0x56, 0x01, //       GS V 1     taglio parziale
        ],
      );
    });

    test('inizializza sempre, anche per un documento vuoto', () {
      // La stampante può essere stata lasciata in qualunque stato dal
      // documento precedente. Dare per buono lo stato di accensione è il modo
      // di ottenere uno scontrino in grassetto ogni tanto, senza capire
      // perché.
      expect(encode(<EscPosCommand>[]), <int>[0x1B, 0x40, 0x1B, 0x74, 0x13]);
    });

    test('la tabella dei caratteri viene dichiarata prima di ogni testo', () {
      final Uint8List bytes = encode(<EscPosCommand>[PrintLine('è')]);
      final int declaration = _indexOf(bytes, <int>[0x1B, 0x74]);
      final int accent = bytes.indexOf(0x8A);

      expect(declaration, isNonNegative);
      expect(accent, greaterThan(declaration),
          reason: 'dichiarare la tabella dopo aver stampato non serve');
    });
  });

  group('EscPosEncoder · lo stile si manda solo quando cambia', () {
    test('due righe uguali costano un cambio di stile solo', () {
      // Su una seriale a 9600 baud tre byte per riga sono decine di byte per
      // scontrino, e su una stampante da banco si sentono al tatto.
      final Uint8List bytes = encode(<EscPosCommand>[
        PrintLine('a', style: EscPosTextStyle.emphasis),
        PrintLine('b', style: EscPosTextStyle.emphasis),
        PrintLine('c', style: EscPosTextStyle.emphasis),
      ]);

      expect(_countOf(bytes, <int>[0x1B, 0x21]), 1);
    });

    test('tornare allo stile normale è un cambio come un altro', () {
      final Uint8List bytes = encode(<EscPosCommand>[
        PrintLine('titolo', style: EscPosTextStyle.emphasis),
        PrintLine('testo'),
      ]);

      expect(_countOf(bytes, <int>[0x1B, 0x21]), 2,
          reason: 'senza il ritorno, tutto il resto resterebbe in grassetto');
      expect(decodeEscPos(bytes).escapes, contains('mode 0x0'));
    });

    test('la prima riga normale non manda niente: è già lo stato iniziale', () {
      expect(
          _countOf(encode(<EscPosCommand>[PrintLine('a')]), <int>[0x1B, 0x21]),
          0);
      expect(
          _countOf(encode(<EscPosCommand>[PrintLine('a')]), <int>[0x1B, 0x61]),
          0);
    });

    test('gli attributi stanno tutti in un byte solo', () {
      expect(
          const EscPosTextStyle(
                  bold: true, doubleHeight: true, doubleWidth: true)
              .printMode,
          0x38);
      expect(const EscPosTextStyle(underline: true).printMode, 0x80);
      expect(EscPosTextStyle.normal.printMode, 0x00);
    });
  });

  group('EscPosEncoder · i comandi che non stampano', () {
    test('il taglio parziale e quello completo sono due byte diversi', () {
      expect(encode(<EscPosCommand>[const CutPaper()]).sublist(5),
          <int>[0x1D, 0x56, 0x01]);
      expect(encode(<EscPosCommand>[const CutPaper(partial: false)]).sublist(5),
          <int>[0x1D, 0x56, 0x00]);
    });

    test('il cassetto sceglie il piedino, e i tempi sono quelli consigliati',
        () {
      // Un impulso troppo corto non fa scattare la bobina, e il cassetto
      // resta chiuso senza che nessun errore lo dica.
      expect(encode(<EscPosCommand>[const OpenDrawer()]).sublist(5),
          <int>[0x1B, 0x70, 0x00, 0x19, 0xFA]);
      expect(encode(<EscPosCommand>[const OpenDrawer(pin: 5)]).sublist(5),
          <int>[0x1B, 0x70, 0x01, 0x19, 0xFA]);
    });

    test('l\'avanzamento porta con sé il numero di righe', () {
      expect(encode(<EscPosCommand>[const FeedLines(3)]).sublist(5),
          <int>[0x1B, 0x64, 0x03]);
    });
  });

  group('EscPosEncoder · la tabella si sceglie', () {
    test('con PC437 l\'euro diventa un punto interrogativo', () {
      // Lo stesso documento, due tabelle, due scontrini diversi: è il motivo
      // per cui la tabella predefinita è PC858.
      expect(encode(<EscPosCommand>[PrintLine('€')], page: CodePage.cp437),
          containsAllInOrder(<int>[0x1B, 0x74, 0x00, 0x3F]));
      expect(encode(<EscPosCommand>[PrintLine('€')]),
          containsAllInOrder(<int>[0x1B, 0x74, 0x13, 0xD5]));
    });
  });
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (int i = 0; i + needle.length <= haystack.length; i++) {
    bool found = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  return -1;
}

int _countOf(List<int> haystack, List<int> needle) {
  int count = 0;
  for (int i = 0; i + needle.length <= haystack.length; i++) {
    bool found = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) count++;
  }
  return count;
}
