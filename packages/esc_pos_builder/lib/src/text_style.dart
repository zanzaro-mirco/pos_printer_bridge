/// Allineamento del testo sulla riga.
enum EscPosAlign {
  /// Allineato a sinistra: è lo stato in cui la stampante si accende.
  left,

  /// Centrato.
  center,

  /// Allineato a destra.
  right,
}

/// Aspetto di una riga di testo.
///
/// Lo stile è un attributo della riga e non un comando a sé, anche se sulla
/// stampante è il contrario: ESC/POS è un protocollo con stato, e lo stile
/// impostato vale finché qualcuno non lo cambia. Dichiararlo riga per riga
/// rende impossibile dimenticare di riportarlo indietro — il difetto classico
/// di questi tracciati, dove una riga in grassetto ne lascia dieci in
/// grassetto sotto di sé. A ricostruire lo stato è il codificatore, che sa
/// anche non ripetere ciò che è già impostato.
class EscPosTextStyle {
  /// Crea uno stile. Ogni attributo assente vale come sulla carta appena
  /// inizializzata: testo normale, allineato a sinistra.
  const EscPosTextStyle({
    this.align = EscPosAlign.left,
    this.bold = false,
    this.doubleHeight = false,
    this.doubleWidth = false,
    this.underline = false,
  });

  /// Testo normale, a sinistra.
  static const EscPosTextStyle normal = EscPosTextStyle();

  /// Testo normale, centrato.
  static const EscPosTextStyle centered =
      EscPosTextStyle(align: EscPosAlign.center);

  /// Intestazione: centrata, in grassetto e alta il doppio.
  ///
  /// Alta e non larga, di proposito. Il doppio della larghezza dimezza le
  /// colonne, e su 58 mm ne restano sedici: un'insegna come «Ristorante Al
  /// Vecchio Mulino» finirebbe su tre righe. L'altezza doppia si vede
  /// altrettanto e non costa niente in impaginazione.
  static const EscPosTextStyle title = EscPosTextStyle(
    align: EscPosAlign.center,
    bold: true,
    doubleHeight: true,
  );

  /// Riga da far notare — il totale — senza raddoppiare la larghezza.
  static const EscPosTextStyle emphasis =
      EscPosTextStyle(bold: true, doubleHeight: true);

  /// Allineamento della riga.
  final EscPosAlign align;

  /// Testo marcato.
  final bool bold;

  /// Caratteri alti il doppio. Non consuma colonne in più.
  final bool doubleHeight;

  /// Caratteri larghi il doppio: **dimezza le colonne disponibili**, ed è la
  /// ragione per cui la larghezza utile si chiede allo stile e non alla carta.
  final bool doubleWidth;

  /// Testo sottolineato.
  final bool underline;

  /// Il byte `n` del comando `ESC ! n`, che imposta i quattro attributi in
  /// una volta sola.
  ///
  /// I bit sono quelli della specifica Epson: 0x08 marcato, 0x10 doppia
  /// altezza, 0x20 doppia larghezza, 0x80 sottolineato.
  int get printMode {
    int mode = 0;
    if (bold) mode |= 0x08;
    if (doubleHeight) mode |= 0x10;
    if (doubleWidth) mode |= 0x20;
    if (underline) mode |= 0x80;
    return mode;
  }

  /// Quante colonne occupa un carattere con questo stile: 2 a doppia
  /// larghezza, 1 altrimenti.
  int get widthMultiplier => doubleWidth ? 2 : 1;

  @override
  bool operator ==(Object other) =>
      other is EscPosTextStyle &&
      other.align == align &&
      other.printMode == printMode;

  @override
  int get hashCode => Object.hash(align, printMode);

  @override
  String toString() => 'EscPosTextStyle($align, mode 0x'
      '${printMode.toRadixString(16).padLeft(2, '0')})';
}
