import 'dart:typed_data';

import 'printer_status.dart';

/// Un canale verso una stampante.
///
/// Il contratto è volutamente povero: aprire, scrivere byte, chiudere, e un
/// flusso di stati che arrivano quando arrivano. **Non sa cosa siano i byte
/// che trasporta**, e non deve — è la stessa ragione per cui un cavo seriale
/// non sa cosa sia uno scontrino.
///
/// È da questa povertà che discende la cosa utile: due implementazioni molto
/// diverse — un socket in Dart puro e un canale verso Kotlin — sono
/// intercambiabili, e chi stampa non cambia una riga passando dall'una
/// all'altra.
abstract interface class PrinterTransport {
  /// Apre il canale. Fallisce se la stampante non c'è o non è raggiungibile.
  Future<void> open();

  /// Manda [bytes] alla stampante.
  Future<void> write(Uint8List bytes);

  /// Chiude il canale. Chiamarla su un canale già chiuso non è un errore:
  /// chiudere è l'unica operazione che si finisce sempre per fare due volte,
  /// di solito da un `finally` e da un `dispose`.
  Future<void> close();

  /// Gli stati che la stampante manda di sua iniziativa.
  ///
  /// Un flusso e non un `Future`: la carta finisce quando finisce, non quando
  /// glielo si chiede.
  Stream<PrinterStatus> get status;

  /// Vero fra [open] e [close].
  bool get isOpen;
}
