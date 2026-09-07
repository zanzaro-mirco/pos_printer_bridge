import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';

/// Ciò che si legge tornando indietro da un flusso di byte.
class DecodedStream {
  /// Crea il risultato di una decodifica.
  const DecodedStream({
    required this.lines,
    required this.escapes,
    required this.codePageId,
  });

  /// Le righe di testo, decodificate con la tabella dichiarata dal flusso.
  final List<String> lines;

  /// Le sequenze di controllo incontrate, in ordine e in forma leggibile.
  final List<String> escapes;

  /// La tabella che il flusso stesso ha selezionato.
  final int codePageId;
}

/// Rilegge un flusso ESC/POS e ne ricava testo e comandi.
///
/// Esiste per una ragione sola: **verificare il codificatore senza
/// riscriverlo**. Un test che costruisce la sequenza attesa concatenando gli
/// stessi byte che produce il codice in prova non dimostra niente, perché
/// sbaglia insieme a lui. Questo invece percorre il flusso al contrario, con
/// un codice che non condivide una riga con quello che sta mettendo alla
/// prova, e ricostruisce ciò che la stampante stamperebbe.
///
/// Rifiuta le sequenze che non conosce: se il codificatore infilasse un byte
/// di troppo, qui diventerebbe un errore invece di passare inosservato.
DecodedStream decodeEscPos(Uint8List bytes) {
  final List<String> lines = <String>[];
  final List<String> escapes = <String>[];
  final List<int> current = <int>[];
  CodePage table = CodePage.cp437;
  int codePageId = 0;

  String flush() {
    final String text = String.fromCharCodes(current
        .map((int b) => b < 0x80 ? b : table.upperHalf.codeUnitAt(b - 0x80)));
    current.clear();
    return text;
  }

  int i = 0;
  while (i < bytes.length) {
    final int byte = bytes[i];
    if (byte == 0x0A) {
      lines.add(flush());
      i += 1;
    } else if (byte == 0x1B) {
      final int command = bytes[i + 1];
      switch (command) {
        case 0x40:
          escapes.add('init');
          i += 2;
        case 0x74:
          codePageId = bytes[i + 2];
          table =
              codePageId == CodePage.cp858.id ? CodePage.cp858 : CodePage.cp437;
          escapes.add('codepage $codePageId');
          i += 3;
        case 0x21:
          escapes.add('mode 0x${bytes[i + 2].toRadixString(16)}');
          i += 3;
        case 0x61:
          escapes.add('align ${bytes[i + 2]}');
          i += 3;
        case 0x64:
          escapes.add('feed ${bytes[i + 2]}');
          i += 3;
        case 0x70:
          escapes.add('drawer ${bytes[i + 2]}');
          i += 5;
        default:
          throw StateError('Sequenza ESC sconosciuta: 0x'
              '${command.toRadixString(16)} a $i');
      }
    } else if (byte == 0x1D) {
      if (bytes[i + 1] != 0x56) {
        throw StateError('Sequenza GS sconosciuta a $i');
      }
      escapes.add('cut ${bytes[i + 2]}');
      i += 3;
    } else {
      current.add(byte);
      i += 1;
    }
  }
  if (current.isNotEmpty) lines.add(flush());
  return DecodedStream(
    lines: lines,
    escapes: escapes,
    codePageId: codePageId,
  );
}
