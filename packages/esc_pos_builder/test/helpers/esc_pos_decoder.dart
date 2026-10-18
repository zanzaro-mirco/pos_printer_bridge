import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';

/// Un codice a barre riletto dal flusso.
class DecodedBarcode {
  /// Crea il risultato della rilettura.
  const DecodedBarcode({required this.selector, required this.payload});

  /// Il valore di `m`: dice quale sistema di codifica è.
  final int selector;

  /// I byte dei dati, come sono arrivati.
  final List<int> payload;

  /// I dati come testo, per confrontarli con quello che si è scritto.
  String get text => String.fromCharCodes(payload);
}

/// Un'immagine riletta dal flusso.
class DecodedImage {
  /// Crea il risultato della rilettura.
  const DecodedImage({
    required this.widthDots,
    required this.heightDots,
    required this.bits,
  });

  /// Larghezza in punti, come dichiarata dal comando.
  final int widthDots;

  /// Altezza in punti, come dichiarata dal comando.
  final int heightDots;

  /// I byte dell'immagine.
  final List<int> bits;

  /// Ridisegna l'immagine come righe di testo.
  ///
  /// Serve a chiudere il giro: un logo scritto come disegno nel codice
  /// sorgente, codificato in byte e riletto qui, deve tornare identico. Se i
  /// byte per riga fossero contati male, qui tornerebbe sfalsato in diagonale,
  /// che è esattamente come si vede il difetto sulla carta.
  List<String> rows({String ink = '#', String blank = ' '}) {
    final int stride = (widthDots + 7) ~/ 8;
    return List<String>.generate(heightDots, (int y) {
      final StringBuffer row = StringBuffer();
      for (int x = 0; x < widthDots; x++) {
        final bool on = bits[y * stride + (x >> 3)] & (0x80 >> (x & 7)) != 0;
        row.write(on ? ink : blank);
      }
      return row.toString();
    });
  }
}

/// Ciò che si legge tornando indietro da un flusso di byte.
class DecodedStream {
  /// Crea il risultato di una decodifica.
  const DecodedStream({
    required this.lines,
    required this.escapes,
    required this.codePageId,
    this.barcodes = const <DecodedBarcode>[],
    this.images = const <DecodedImage>[],
  });

  /// I codici a barre incontrati, in ordine.
  final List<DecodedBarcode> barcodes;

  /// Le immagini incontrate, in ordine.
  final List<DecodedImage> images;

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
  final List<DecodedBarcode> barcodes = <DecodedBarcode>[];
  final List<DecodedImage> images = <DecodedImage>[];
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
      switch (bytes[i + 1]) {
        case 0x56:
          escapes.add('cut ${bytes[i + 2]}');
          i += 3;
        case 0x48:
          escapes.add('hri ${bytes[i + 2]}');
          i += 3;
        case 0x66:
          escapes.add('hri font ${bytes[i + 2]}');
          i += 3;
        case 0x68:
          escapes.add('barcode height ${bytes[i + 2]}');
          i += 3;
        case 0x77:
          escapes.add('barcode module ${bytes[i + 2]}');
          i += 3;
        case 0x6B:
          // GS k m n d1...dn: la lunghezza è dichiarata, quindi si può
          // saltare esattamente i byte dei dati. Se il codificatore ne
          // scrivesse uno in più o in meno, il byte successivo cadrebbe in
          // mezzo ai dati e la decodifica finirebbe su una sequenza
          // sconosciuta.
          final int length = bytes[i + 3];
          barcodes.add(DecodedBarcode(
            selector: bytes[i + 2],
            payload: bytes.sublist(i + 4, i + 4 + length),
          ));
          escapes.add('barcode ${bytes[i + 2]} ($length byte)');
          i += 4 + length;
        case 0x28:
        case 0x38:
          i = _readGraphics(bytes, i, escapes, images);
        default:
          throw StateError('Sequenza GS sconosciuta: 0x'
              '${bytes[i + 1].toRadixString(16)} a $i');
      }
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
    barcodes: barcodes,
    images: images,
  );
}

/// Rilegge la funzione grafica: `GS ( L` oppure `GS 8 L`.
///
/// Le due forme sono lo stesso comando con la lunghezza dichiarata in due
/// byte o in quattro. Qui la lunghezza **si usa per controllare**, non solo
/// per saltare: il comando dichiara quanti byte lo compongono e dichiara
/// anche le misure dell'immagine, e le due cose devono dire la stessa cosa.
/// Un'immagine larga 12 punti occupa 2 byte per riga, e se il codificatore ne
/// mandasse 1 o 3 i due numeri non tornerebbero. È il controllo che un
/// confronto con una sequenza attesa non farebbe: direbbe soltanto che i byte
/// sono diversi da quelli di ieri.
int _readGraphics(
  Uint8List bytes,
  int start,
  List<String> escapes,
  List<DecodedImage> images,
) {
  final bool long = bytes[start + 1] == 0x38;
  if (bytes[start + 2] != 0x4C) {
    throw StateError('Funzione grafica senza «L» a $start');
  }
  final int p = long
      ? bytes[start + 3] |
          bytes[start + 4] << 8 |
          bytes[start + 5] << 16 |
          bytes[start + 6] << 24
      : bytes[start + 3] | bytes[start + 4] << 8;
  final int head = start + (long ? 7 : 3 + 2);

  if (bytes[head] != 0x30) {
    throw StateError('La funzione grafica vuole m = 48, non '
        '${bytes[head]} a $head');
  }
  final int function = bytes[head + 1];

  if (function == 0x32) {
    if (p != 2) {
      throw StateError('La funzione 50 non ha parametri: p dichiara $p');
    }
    escapes.add('print graphics');
    return head + 2;
  }
  if (function != 0x70) {
    throw StateError('Funzione grafica sconosciuta: $function a ${head + 1}');
  }

  final int widthDots = bytes[head + 6] | bytes[head + 7] << 8;
  final int heightDots = bytes[head + 8] | bytes[head + 9] << 8;
  final int declared = p - 10;
  final int expected = ((widthDots + 7) ~/ 8) * heightDots;
  if (declared != expected) {
    throw StateError('L\'immagine dichiara $widthDots×$heightDots punti, che '
        'sono $expected byte, ma la lunghezza del comando ne conta $declared');
  }
  images.add(DecodedImage(
    widthDots: widthDots,
    heightDots: heightDots,
    bits: bytes.sublist(head + 10, head + 10 + declared),
  ));
  escapes.add('graphics $widthDots×$heightDots');
  return head + 10 + declared;
}
