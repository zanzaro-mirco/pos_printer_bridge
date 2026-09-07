/// Il canale fra Dart e una stampante termica.
///
/// Due trasporti, un contratto solo:
///
/// - `TcpPrinterTransport` — Dart puro, verso una stampante di rete. Si mette
///   alla prova contro un server in ascolto su `localhost`, senza hardware.
/// - `UsbPrinterTransport` — attraverso il codice Kotlin, verso una stampante
///   collegata alla porta USB.
///
/// Il contratto conosce solo byte: **non sa cosa trasporta**. A comporre i
/// byte di uno scontrino pensa `esc_pos_builder`, che sta apposta in un altro
/// pacchetto — un backend che genera scontrini per una stampante di rete non
/// ha ragione di installare Flutter.
library;

export 'src/printer_failure.dart';
export 'src/printer_status.dart';
export 'src/printer_transport.dart';
export 'src/tcp_printer_transport.dart';
export 'src/usb_printer_transport.dart';
