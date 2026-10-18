import 'dart:typed_data';

/// Un'immagine in bianco e nero, nella forma in cui una stampante termica la
/// vuole: una riga di punti per volta, otto punti per byte, il bit più
/// significativo a sinistra.
///
/// **Questo pacchetto non legge i PNG, e non è una dimenticanza.** Decodificare
/// un'immagine vuole una libreria di decodifica, e Dart puro senza dipendenze è
/// metà del valore di `esc_pos_builder`: chi ha già un decodificatore gli passa
/// i bit, chi non ce l'ha disegna il logo come testo con [RasterImage.fromRows]
/// e non installa niente. La conversione da una foto a un'immagine in bianco e
/// nero, con la sua soglia e il suo mezzotono, è un problema di grafica e non
/// di stampa.
class RasterImage {
  /// Crea un'immagine dai suoi byte.
  ///
  /// [bits] deve contenere esattamente [bytesPerRow] byte per ognuna delle
  /// [heightDots] righe. Il controllo non è pedanteria: una lunghezza
  /// sbagliata manda alla stampante un comando con un numero di byte diverso
  /// da quello dichiarato nella sua testata, e da quel punto in avanti il
  /// flusso è spazzatura — lo scontrino esce con righe di caratteri casuali
  /// e nessun errore da nessuna parte.
  RasterImage({
    required this.widthDots,
    required this.heightDots,
    required List<int> bits,
  }) : bits = Uint8List.fromList(bits) {
    if (widthDots <= 0 || heightDots <= 0) {
      throw ArgumentError('Un\'immagine di $widthDots×$heightDots punti non '
          'ha niente da stampare');
    }
    final int expected = bytesPerRow * heightDots;
    if (this.bits.length != expected) {
      throw ArgumentError.value(
          bits.length,
          'bits',
          '$widthDots punti stanno in $bytesPerRow byte per riga, e con '
              '$heightDots righe fanno $expected byte');
    }
  }

  /// Crea un'immagine disegnata come testo, una riga per riga.
  ///
  /// Ogni carattere è un punto: quelli uguali a [ink] si stampano, tutti gli
  /// altri sono carta bianca. Serve per i loghi semplici — una cornice, una
  /// scritta disegnata a mano, un simbolo — e per i test, dove un'immagine
  /// che si legge nel codice sorgente vale più di un vettore di byte.
  ///
  /// ```dart
  /// RasterImage.fromRows(<String>[
  ///   '########',
  ///   '#      #',
  ///   '#  ##  #',
  ///   '########',
  /// ]);
  /// ```
  factory RasterImage.fromRows(List<String> rows, {String ink = '#'}) {
    if (rows.isEmpty) {
      throw ArgumentError.value(rows, 'rows', 'Nessuna riga da disegnare');
    }
    if (ink.length != 1) {
      throw ArgumentError.value(ink, 'ink', 'Un carattere, non «$ink»');
    }
    final int width = rows.first.length;
    if (width == 0) {
      throw ArgumentError.value(rows, 'rows', 'La prima riga è vuota');
    }
    for (int y = 0; y < rows.length; y++) {
      if (rows[y].length != width) {
        throw ArgumentError.value(
            rows,
            'rows',
            'La riga $y è larga ${rows[y].length} caratteri invece di '
                '$width: un\'immagine non ha righe di lunghezza diversa');
      }
    }

    final int stride = strideFor(width);
    final Uint8List bits = Uint8List(stride * rows.length);
    final int inkCode = ink.codeUnitAt(0);
    for (int y = 0; y < rows.length; y++) {
      for (int x = 0; x < width; x++) {
        if (rows[y].codeUnitAt(x) == inkCode) {
          bits[y * stride + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return RasterImage(
      widthDots: width,
      heightDots: rows.length,
      bits: bits,
    );
  }

  /// Larghezza in punti.
  final int widthDots;

  /// Altezza in punti.
  final int heightDots;

  /// I byte dell'immagine, una riga dopo l'altra.
  final Uint8List bits;

  /// Byte occupati da una riga larga [widthDots] punti.
  ///
  /// È statica perché serve anche prima che un'immagine esista: chi la
  /// costruisce dai bit deve sapere quanto spazio prendere.
  static int strideFor(int widthDots) => (widthDots + 7) ~/ 8;

  /// Byte occupati da una riga di punti.
  ///
  /// È una divisione che arrotonda per eccesso, e il punto in cui si sbaglia
  /// di più: un'immagine larga 12 punti occupa 2 byte per riga, non 1 e mezzo,
  /// e i 4 bit che restano sono carta bianca. Sta scritta qui una volta, e la
  /// usano sia il codificatore sia chi costruisce l'immagine.
  int get bytesPerRow => strideFor(widthDots);

  /// Vero se il punto in [x], [y] si stampa.
  bool dotAt(int x, int y) {
    if (x < 0 || x >= widthDots || y < 0 || y >= heightDots) return false;
    return bits[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;
  }

  @override
  String toString() => 'RasterImage($widthDots×$heightDots punti)';
}
