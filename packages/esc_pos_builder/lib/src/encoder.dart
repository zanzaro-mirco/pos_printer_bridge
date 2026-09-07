import 'dart:typed_data';

import 'code_page.dart';
import 'commands.dart';
import 'document.dart';
import 'text_style.dart';

/// Traduce un [EscPosDocument] nel flusso di byte da mandare alla stampante.
///
/// È l'unico punto del pacchetto che conosce le sequenze di escape, ed è
/// l'unico che dipende da come è fatta la stampante invece che da come è
/// fatto uno scontrino.
///
/// **Emette i cambi di stile solo quando lo stile cambia davvero.** Non è
/// un'ottimizzazione gratuita: su una seriale a 9600 baud tre byte per riga
/// sono decine di byte per scontrino, e su una stampante da banco che ne
/// emette centinaia all'ora la differenza si sente al tatto. Il costo è tenere
/// traccia di uno stato mentre si scorre il documento, ed è tutto qui.
class EscPosEncoder {
  /// Crea un codificatore. La tabella predefinita è [CodePage.cp858], quella
  /// che contiene l'euro.
  const EscPosEncoder({
    this.codePage = CodePage.cp858,
    this.replacement = 0x3F,
  });

  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  /// Tabella dei caratteri con cui codificare il testo.
  final CodePage codePage;

  /// Byte con cui sostituire i caratteri che la tabella non ha. Il valore
  /// predefinito è il punto interrogativo.
  final int replacement;

  /// Codifica [document].
  ///
  /// Il flusso comincia sempre con l'inizializzazione e la scelta della
  /// tabella: una stampante può essere stata lasciata in qualunque stato dal
  /// documento precedente, e dare per buono lo stato di accensione è il modo
  /// di ottenere uno scontrino in grassetto ogni tanto, senza capire perché.
  Uint8List encode(EscPosDocument document) {
    final BytesBuilder bytes = BytesBuilder();
    bytes.add(<int>[_esc, 0x40]);
    bytes.add(<int>[_esc, 0x74, codePage.id]);

    int mode = 0;
    EscPosAlign align = EscPosAlign.left;

    for (final EscPosCommand command in document.commands) {
      switch (command) {
        case PrintLine(:final String text, :final EscPosTextStyle style):
          if (style.printMode != mode) {
            mode = style.printMode;
            bytes.add(<int>[_esc, 0x21, mode]);
          }
          if (style.align != align) {
            align = style.align;
            bytes.add(<int>[_esc, 0x61, _alignByte(align)]);
          }
          bytes.add(codePage.encode(text, replacement: replacement));
          bytes.addByte(_lf);
        case FeedLines(:final int count):
          bytes.add(<int>[_esc, 0x64, count]);
        case CutPaper(:final bool partial):
          bytes.add(<int>[_gs, 0x56, partial ? 0x01 : 0x00]);
        case OpenDrawer(:final int pin):
          // ESC p m t1 t2: impulso di 25 ms, pausa di 250 ms. Sono i tempi
          // consigliati da Epson e quelli che i cassetti in commercio si
          // aspettano; troppo corto e la bobina non scatta.
          bytes.add(<int>[_esc, 0x70, pin == 2 ? 0x00 : 0x01, 0x19, 0xFA]);
      }
    }
    return bytes.toBytes();
  }

  /// Il byte `n` di `ESC a n`. Scritto per esteso e non come indice
  /// dell'enumerazione: legare un protocollo all'ordine di dichiarazione di
  /// un enum significa che riordinarlo cambia silenziosamente ciò che esce
  /// dalla porta.
  static int _alignByte(EscPosAlign align) => switch (align) {
        EscPosAlign.left => 0x00,
        EscPosAlign.center => 0x01,
        EscPosAlign.right => 0x02,
      };
}
