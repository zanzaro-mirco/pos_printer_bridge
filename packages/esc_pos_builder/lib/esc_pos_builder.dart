/// Da uno scontrino ai byte che una stampante termica sa stampare.
///
/// Dart puro: nessuna dipendenza da Flutter, nessuna piattaforma, nessun
/// accesso a porte o socket. Il pacchetto costruisce il flusso ESC/POS e si
/// ferma lì — mandarlo alla stampante è un problema di trasporto, e lo
/// risolve `pos_printer_bridge`.
///
/// Tre livelli, ognuno provabile da solo:
///
/// 1. **Comandi** — cosa deve fare la stampante, non come si scrive.
/// 2. **Impaginazione** — da uno `Receipt` di `receipt_engine` ai comandi,
///    rispettando la larghezza della carta.
/// 3. **Codifica** — dai comandi ai byte, tabella dei caratteri compresa.
///
/// In mezzo c'è `PaperPreview`, che rende gli stessi comandi come testo: è
/// così che si guarda uno scontrino senza avere una stampante.
library;

export 'src/code_page.dart';
export 'src/commands.dart';
export 'src/document.dart';
export 'src/encoder.dart';
export 'src/paper.dart';
export 'src/preview.dart';
export 'src/receipt_layout.dart';
export 'src/text_style.dart';
