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
  const PaperFormat({required this.name, required this.columns})
      : assert(columns > 0, 'La carta ha almeno una colonna');

  /// Carta da 80 mm: 48 colonne. È il formato da banco più diffuso.
  static const PaperFormat mm80 = PaperFormat(name: '80 mm', columns: 48);

  /// Carta da 58 mm: 32 colonne. È quella dei palmari e delle stampanti
  /// portatili, ed è il formato in cui l'impaginazione fa più fatica.
  static const PaperFormat mm58 = PaperFormat(name: '58 mm', columns: 32);

  /// Nome leggibile del formato.
  final String name;

  /// Caratteri stampabili su una riga con il font A.
  final int columns;

  @override
  String toString() => '$name ($columns colonne)';
}
