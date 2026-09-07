/// Perché una stampa non è arrivata alla carta.
///
/// Gerarchia chiusa, come in `pos_sync`: chi la percorre con uno `switch` non
/// può dimenticare un caso, e aggiungerne uno domani fa fallire la
/// compilazione nel punto in cui va gestito.
///
/// La distinzione che conta per chi chiama non è quale errore sia, ma se
/// **valga la pena riprovare**: una stampante staccata torna, un permesso
/// negato no. Per questo [isTransient] sta sulla classe base.
sealed class PrinterFailure implements Exception {
  /// Costruttore delle sottoclassi.
  const PrinterFailure(this.message);

  /// Descrizione tecnica, per un registro o un messaggio di errore.
  final String message;

  /// Vero se riprovare ha senso.
  bool get isTransient;

  @override
  String toString() => '$runtimeType: $message';
}

/// La stampante non risponde: cavo staccato, spenta, indirizzo sbagliato.
final class PrinterUnreachable extends PrinterFailure {
  /// Crea l'errore.
  const PrinterUnreachable(super.message);

  @override
  bool get isTransient => true;
}

/// Nessuna stampante collegata alla porta USB.
///
/// Diverso da [PrinterUnreachable]: lì c'è un indirizzo che non risponde, qui
/// non c'è proprio un dispositivo. Chi lo mostra a un operatore dice due cose
/// diverse — «controlla la rete» contro «collega la stampante».
final class PrinterNotFound extends PrinterFailure {
  /// Crea l'errore.
  const PrinterNotFound(super.message);

  @override
  bool get isTransient => true;
}

/// L'utente ha negato il permesso di accedere al dispositivo USB.
///
/// **Non è transitorio.** Riprovare significherebbe rimostrare la stessa
/// finestra a chi l'ha appena chiusa, ed è il modo più rapido per far
/// disinstallare un'applicazione.
final class PrinterPermissionDenied extends PrinterFailure {
  /// Crea l'errore.
  const PrinterPermissionDenied(super.message);

  @override
  bool get isTransient => false;
}

/// I byte sono partiti ma non sono arrivati tutti.
final class PrinterWriteFailed extends PrinterFailure {
  /// Crea l'errore.
  const PrinterWriteFailed(super.message);

  @override
  bool get isTransient => true;
}

/// Si è provato a scrivere su un canale non aperto.
///
/// È un errore di chi programma, non della stampante: per questo non è
/// transitorio e riprovare non serve a niente.
final class PrinterNotOpen extends PrinterFailure {
  /// Crea l'errore.
  const PrinterNotOpen(super.message);

  @override
  bool get isTransient => false;
}
