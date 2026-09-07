import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

import 'helpers/esc_pos_decoder.dart';
import 'helpers/reference_receipt.dart';

/// Il criterio di questa voce: **lo scontrino di riferimento, byte per byte**.
///
/// Tre controlli che rispondono a domande diverse, e nessuno dei tre da solo
/// basterebbe:
///
/// 1. il confronto con il riferimento registrato dice che il flusso **non è
///    cambiato per sbaglio**;
/// 2. la rilettura all'indietro dice che è **leggibile e completo**, con un
///    codice che non condivide una riga con il codificatore;
/// 3. le asserzioni mirate dicono che i punti che contano — inizializzazione,
///    tabella, accenti, taglio — sono **giusti**, non solo stabili.
void main() {
  final Uint8List bytes =
      const EscPosEncoder().encode(referenceLayout.render(referenceReceipt()));

  group('Lo scontrino di riferimento', () {
    test('è identico al flusso registrato, byte per byte', () {
      // Dopo una modifica voluta all'impaginazione:
      //   dart run tool/record_golden.dart
      // È un comando a parte di proposito: se fosse la suite a riscriverlo,
      // il confronto non fallirebbe mai.
      final List<int> expected =
          _readHex(File('test/golden/scontrino_80mm.hex'));

      expect(bytes.length, expected.length,
          reason: 'il flusso è lungo ${bytes.length} byte invece di '
              '${expected.length}');
      for (int i = 0; i < expected.length; i++) {
        if (bytes[i] != expected[i]) {
          fail('Primo byte diverso a $i: '
              '0x${bytes[i].toRadixString(16)} invece di '
              '0x${expected[i].toRadixString(16)}\n'
              'Intorno: ${_around(bytes, i)}');
        }
      }
    });

    test('riletto all\'indietro dà esattamente le righe del documento', () {
      // È il controllo indipendente: il decodificatore non condivide una riga
      // con il codificatore, e se il flusso avesse un byte di troppo o una
      // lettera persa per strada lo direbbe qui.
      final List<String> written = referenceLayout
          .render(referenceReceipt())
          .commands
          .whereType<PrintLine>()
          .map((PrintLine line) => line.text)
          .toList();

      expect(decodeEscPos(bytes).lines, written);
    });

    test('comincia inizializzando e dichiarando la tabella', () {
      expect(bytes.sublist(0, 5), <int>[0x1B, 0x40, 0x1B, 0x74, 0x13]);
      expect(decodeEscPos(bytes).codePageId, CodePage.cp858.id);
    });

    test('le lettere accentate sono un byte, non due', () {
      // «Caffè espresso» è nello scontrino apposta. In UTF-8 sarebbero
      // 0xC3 0xA8 e la stampante scriverebbe «CaffÃ¨».
      expect(bytes, contains(0x8A));
      expect(_containsPair(bytes, 0xC3, 0xA8), isFalse,
          reason: 'la «è» in UTF-8 non deve arrivare alla stampante');
      expect(decodeEscPos(bytes).lines.any((String l) => l.contains('Caffè')),
          isTrue);
    });

    test('il simbolo dell\'euro è quello di PC858', () {
      expect(bytes, contains(0xD5));
      expect(
          decodeEscPos(bytes).lines.any((String l) => l.contains('€')), isTrue);
    });

    test('finisce facendo avanzare la carta e poi tagliando', () {
      // La lama sta qualche millimetro sopra la testina: senza avanzamento
      // il taglio cadrebbe in mezzo all'ultima riga.
      final List<String> escapes = decodeEscPos(bytes).escapes;
      expect(escapes.last, 'cut 1');
      expect(escapes[escapes.length - 2], startsWith('feed'));
    });

    test('nessun byte fuori dalle sequenze conosciute', () {
      // Il decodificatore solleva un errore su ciò che non riconosce:
      // arrivare in fondo è già l'asserzione.
      expect(() => decodeEscPos(bytes), returnsNormally);
    });
  });
}

List<int> _readHex(File file) => file
    .readAsStringSync()
    .split(RegExp(r'\s+'))
    .where((String token) => token.isNotEmpty)
    .map((String token) => int.parse(token, radix: 16))
    .toList();

String _around(Uint8List bytes, int index) {
  final int from = index - 8 < 0 ? 0 : index - 8;
  final int to = index + 8 > bytes.length ? bytes.length : index + 8;
  return bytes
      .sublist(from, to)
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
}

bool _containsPair(Uint8List bytes, int first, int second) {
  for (int i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == first && bytes[i + 1] == second) return true;
  }
  return false;
}
