import 'dart:typed_data';

import 'barcode.dart';
import 'code_page.dart';
import 'commands.dart';
import 'document.dart';
import 'raster_image.dart';
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

    // Le quattro impostazioni di un codice a barre partono da «non si sa».
    //
    // È la differenza con lo stile del testo, dove `ESC @` lascia la stampante
    // in uno stato noto e la prima riga normale non costa niente. Qui il
    // riferimento ESC/POS dice che il valore predefinito di `GS h` e `GS w`
    // **dipende dal modello**: dare per buono un valore significa un codice
    // alto due centimetri su una stampante e due millimetri su quella del
    // negozio accanto. Il primo codice del documento dichiara tutto, e dal
    // secondo in poi valgono le stesse regole del testo.
    int? barcodeHeight;
    int? barcodeModule;
    BarcodeTextPosition? barcodeText;
    BarcodeTextFont? barcodeFont;

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
        case final PrintBarcode barcode:
          if (barcode.align != align) {
            align = barcode.align;
            bytes.add(<int>[_esc, 0x61, _alignByte(align)]);
          }
          if (barcodeText != barcode.textPosition) {
            barcodeText = barcode.textPosition;
            // GS H n: dove vanno le cifre leggibili.
            bytes.add(<int>[_gs, 0x48, barcodeText.value]);
          }
          if (barcodeFont != barcode.textFont) {
            barcodeFont = barcode.textFont;
            // GS f n: con quale font.
            bytes.add(<int>[_gs, 0x66, barcodeFont.value]);
          }
          if (barcodeHeight != barcode.heightDots) {
            barcodeHeight = barcode.heightDots;
            // GS h n: altezza della barra in punti.
            bytes.add(<int>[_gs, 0x68, barcodeHeight]);
          }
          if (barcodeModule != barcode.moduleWidth) {
            barcodeModule = barcode.moduleWidth;
            // GS w n: larghezza del modulo, il tratto più stretto.
            bytes.add(<int>[_gs, 0x77, barcodeModule]);
          }
          // GS k m n d1...dn, la funzione B: la lunghezza va davanti ai dati.
          // L'altra funzione di `GS k` chiude con uno zero invece di
          // dichiarare la lunghezza, e non va usata qui: un CODE128 può
          // contenere un byte zero, e il codice finirebbe tagliato nel punto
          // in cui capita.
          bytes.add(<int>[
            _gs,
            0x6B,
            barcode.symbology.selector,
            barcode.payload.length,
          ]);
          bytes.add(barcode.payload);
        case final PrintImage picture:
          if (picture.align != align) {
            align = picture.align;
            bytes.add(<int>[_esc, 0x61, _alignByte(align)]);
          }
          _addImage(bytes, picture.image);
      }
    }
    return bytes.toBytes();
  }

  /// Mette l'immagine nel buffer della stampante e la stampa.
  ///
  /// Sono due comandi, non uno: `GS ( L` con la funzione 112 trasferisce i
  /// punti, la funzione 50 li stampa. Sembra un giro inutile e non lo è —
  /// l'immagine può arrivare in più pezzi, e il foglio esce quando è
  /// completa.
  ///
  /// La scelta di fondo è un'altra: **non si usa `GS v 0`**, il comando con
  /// cui tutti stampano un logo. Il riferimento di Epson lo marca come
  /// obsoleto e scrive che i modelli futuri non lo supporteranno. La funzione
  /// grafica è quella consigliata, e questo è un pacchetto che dovrà
  /// funzionare anche fra qualche anno. Il prezzo è dichiarato in
  /// `ARCHITECTURE.md`: le stampanti che accettano solo il comando obsoleto —
  /// qualche modello economico non Epson — con questo pacchetto non stampano
  /// il logo.
  static void _addImage(BytesBuilder bytes, RasterImage image) {
    // La testata della funzione 112 sono dieci byte: m, fn, a, bx, by, c e le
    // due misure. `p` li conta insieme ai dati, ed è il numero da cui la
    // stampante capisce dove finisce l'immagine e ricomincia lo scontrino.
    final int p = 10 + image.bits.length;
    if (p <= 0xFFFF) {
      bytes.add(<int>[_gs, 0x28, 0x4C, p & 0xFF, p >> 8]);
    } else {
      // `GS ( L` dichiara la lunghezza in due byte, e un logo grande non ci
      // sta: 576 punti su mille righe fanno 72 mila byte. `GS 8 L` è lo
      // stesso comando con la lunghezza in quattro byte.
      bytes.add(<int>[
        _gs,
        0x38,
        0x4C,
        p & 0xFF,
        p >> 8 & 0xFF,
        p >> 16 & 0xFF,
        p >> 24 & 0xFF,
      ]);
    }
    bytes.add(<int>[
      0x30, // m: sempre 48.
      0x70, // fn 112: immagina in formato raster nel buffer.
      0x30, // a: monocromatica. Il mezzotono è un problema di grafica.
      0x01, // bx: nessun ingrandimento in larghezza.
      0x01, // by: nessun ingrandimento in altezza.
      0x31, // c: colore 1, il nero delle termiche a un colore.
      image.widthDots & 0xFF,
      image.widthDots >> 8,
      image.heightDots & 0xFF,
      image.heightDots >> 8,
    ]);
    bytes.add(image.bits);
    // GS ( L con la funzione 50: stampa quello che c'è nel buffer.
    bytes.add(<int>[_gs, 0x28, 0x4C, 0x02, 0x00, 0x30, 0x32]);
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
