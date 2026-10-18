/// Formato della carta su cui si stampa.
///
/// La larghezza non è un dettaglio estetico: è il vincolo che decide se un
/// riepilogo IVA sta su una riga o su due, ed è la prima cosa che cambia
/// passando da un modello di stampante all'altro. Tenerla come parametro
/// invece che come costante è ciò che permette allo stesso codice di
/// impaginare su entrambe.
///
/// Le colonne valgono per il font A, quello predefinito. Il font B ne
/// permette di più ed è più piccolo; questo pacchetto non lo usa, e la
/// ragione è scritta in `ARCHITECTURE.md`.
class PaperFormat {
  /// Crea un formato di carta con la sua larghezza in colonne.
  ///
  /// [dots] si può omettere: un carattere del font A è largo 12 punti, quindi
  /// una carta da 48 colonne ne stampa 576. Va passato solo per una stampante
  /// che non rispetti questo rapporto.
  const PaperFormat({required this.name, required this.columns, int? dots})
      : assert(columns > 0, 'La carta ha almeno una colonna'),
        dots = dots ?? columns * _dotsPerColumn;

  /// Carta da 80 mm: 48 colonne, 576 punti. È il formato da banco più
  /// diffuso.
  static const PaperFormat mm80 = PaperFormat(name: '80 mm', columns: 48);

  /// Carta da 58 mm: 32 colonne, 384 punti. È quella dei palmari e delle
  /// stampanti portatili, ed è il formato in cui l'impaginazione fa più
  /// fatica.
  static const PaperFormat mm58 = PaperFormat(name: '58 mm', columns: 32);

  /// Punti occupati in larghezza da un carattere del font A.
  static const int _dotsPerColumn = 12;

  /// Nome leggibile del formato.
  final String name;

  /// Caratteri stampabili su una riga con il font A.
  final int columns;

  /// Punti stampabili su una riga.
  ///
  /// Serve a chi stampa qualcosa che non è testo: un'immagine si misura in
  /// punti, e una più larga della carta viene tagliata dalla stampante senza
  /// dire niente. È l'unica misura con cui si può rifiutare prima.
  final int dots;

  @override
  String toString() => '$name ($columns colonne, $dots punti)';
}
