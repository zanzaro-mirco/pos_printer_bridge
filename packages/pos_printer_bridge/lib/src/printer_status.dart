import 'dart:typed_data';

/// Cosa sta succedendo alla stampante, letto dai byte che manda indietro.
///
/// **Questi non sono risposte a una chiamata.** Una stampante termica non
/// risponde «ok» a `stampa`: manda quattro byte di stato quando qualcosa
/// cambia — la carta finisce, il coperchio si apre, la lama si inceppa — e
/// possono arrivare mentre non le si sta chiedendo niente. È il motivo per
/// cui dall'altra parte del canale c'è un flusso e non un `Future`, ed è la
/// differenza fra un'applicazione che dice «carta finita» mentre succede e una
/// che se ne accorge alla stampa dopo.
///
/// ## Da dove viene la decodifica
///
/// Dalla specifica Epson dell'**Automatic Status Back**: quattro byte, ognuno
/// con la stessa firma nei bit fissi — i due più bassi a zero, il quarto a
/// uno, il più alto a zero. I costruttori non sono tutti uguali su tutto:
/// prima di fidarsene su un modello specifico vale la pena confrontare con il
/// suo manuale. I bit fissi servono proprio a questo: se non tornano, questi
/// quattro byte **non sono uno stato** e vengono rifiutati invece di essere
/// interpretati in qualcosa che sembra plausibile.
class PrinterStatus {
  /// Crea uno stato. Normalmente lo costruisce [tryDecode].
  const PrinterStatus({
    required this.online,
    required this.coverOpen,
    required this.paperEnd,
    required this.paperNearEnd,
    required this.feedButtonPressed,
    required this.drawerPinHigh,
    required this.error,
    required this.cutterError,
    required this.unrecoverableError,
  });

  /// Quanti byte occupa uno stato.
  static const int length = 4;

  /// La sequenza che accende l'invio automatico dello stato: `GS a 255`.
  ///
  /// Sta qui, in mezzo a codice che di ESC/POS non sa altro, per una ragione
  /// sola: è il comando che accende esattamente ciò che questo file decodifica.
  /// Tenerli separati vorrebbe dire poter accendere gli stati senza saperli
  /// leggere, o il contrario.
  static const List<int> enableAutomaticStatusBack = <int>[0x1D, 0x61, 0xFF];

  /// La stampante è pronta a stampare.
  final bool online;

  /// Coperchio aperto. Da solo mette la stampante fuori linea.
  final bool coverOpen;

  /// Carta finita: la stampa si è fermata.
  final bool paperEnd;

  /// Carta quasi finita. È l'unico stato che permette di avvisare **prima**
  /// che uno scontrino resti a metà.
  final bool paperNearEnd;

  /// Qualcuno sta tenendo premuto il pulsante di avanzamento.
  final bool feedButtonPressed;

  /// Il piedino 3 del connettore del cassetto è alto.
  ///
  /// Non si chiama `drawerOpen` di proposito: se alto voglia dire aperto o
  /// chiuso dipende da **come è cablato il cassetto**, e sul campo si trovano
  /// entrambi. Dare un nome che promette più di quello che il bit dice è il
  /// modo di far scrivere a qualcuno un controllo sbagliato.
  final bool drawerPinHigh;

  /// C'è un errore in corso.
  final bool error;

  /// La taglierina si è inceppata.
  final bool cutterError;

  /// Errore non recuperabile: serve spegnere e riaccendere.
  final bool unrecoverableError;

  /// Vero se c'è qualcosa da dire a chi sta alla cassa.
  bool get needsAttention =>
      !online || coverOpen || paperEnd || error || unrecoverableError;

  /// Decodifica quattro byte di stato, oppure restituisce `null` se non lo
  /// sono.
  ///
  /// Restituisce `null` invece di sollevare un errore perché su un canale
  /// seriale un byte spaiato è normale quanto un pacchetto perso in rete: chi
  /// legge deve poter riallineare, non fermarsi.
  static PrinterStatus? tryDecode(List<int> bytes) {
    if (bytes.length < length) return null;
    for (int i = 0; i < length; i++) {
      if (!isStatusByte(bytes[i])) return null;
    }
    final int info = bytes[0];
    final int offline = bytes[1];
    final int failure = bytes[2];
    final int paper = bytes[3];
    return PrinterStatus(
      online: info & 0x08 == 0,
      drawerPinHigh: info & 0x04 != 0,
      coverOpen: offline & 0x04 != 0,
      feedButtonPressed: offline & 0x08 != 0,
      error: offline & 0x40 != 0,
      cutterError: failure & 0x08 != 0,
      unrecoverableError: failure & 0x20 != 0,
      // Due bit per ogni sensore, e vanno letti insieme: la specifica li mette
      // a uno entrambi. Accontentarsi di uno solo significa leggere uno stato
      // intermedio come definitivo.
      paperNearEnd: paper & 0x0C == 0x0C,
      paperEnd: paper & 0x60 == 0x60,
    );
  }

  /// Vero se [byte] ha la firma dei bit fissi di uno stato.
  ///
  /// I bit 0 e 1 a zero, il bit 4 a uno, il bit 7 a zero. È un filtro debole —
  /// un byte su otto la passa per caso — ma è quanto la specifica garantisce,
  /// ed è abbastanza per riallinearsi dopo un byte perso.
  static bool isStatusByte(int byte) => byte & 0x93 == 0x10;

  @override
  String toString() {
    if (!needsAttention) return 'PrinterStatus(pronta)';
    final List<String> problems = <String>[
      if (!online) 'fuori linea',
      if (coverOpen) 'coperchio aperto',
      if (paperEnd) 'carta finita',
      if (paperNearEnd) 'carta in esaurimento',
      if (cutterError) 'taglierina inceppata',
      if (unrecoverableError) 'errore non recuperabile',
      if (error) 'errore',
    ];
    return 'PrinterStatus(${problems.join(', ')})';
  }
}

/// Ricava gli stati da un flusso di byte che arrivano a pezzi.
///
/// I byte non arrivano a gruppi di quattro: arrivano come li consegna il
/// sistema operativo, e uno stato può essere spezzato fra due letture o
/// seguito subito dal successivo. Questo accumula e riallinea.
///
/// Il riallineamento è la parte che conta. Se i quattro byte in testa non
/// hanno la firma di uno stato, ne butta **uno solo** e riprova: buttarli
/// tutti e quattro perderebbe uno stato valido che comincia un byte più in là.
class PrinterStatusReader {
  final List<int> _buffer = <int>[];

  /// Aggiunge byte appena arrivati e restituisce gli stati completi che ne
  /// escono, in ordine.
  List<PrinterStatus> add(List<int> incoming) {
    _buffer.addAll(incoming);
    final List<PrinterStatus> found = <PrinterStatus>[];
    while (_buffer.length >= PrinterStatus.length) {
      final PrinterStatus? status =
          PrinterStatus.tryDecode(_buffer.sublist(0, PrinterStatus.length));
      if (status == null) {
        _buffer.removeAt(0);
      } else {
        found.add(status);
        _buffer.removeRange(0, PrinterStatus.length);
      }
    }
    return found;
  }

  /// Quanti byte sono in attesa di completare uno stato.
  int get pending => _buffer.length;

  /// Dimentica ciò che è stato accumulato. Da chiamare quando il canale si
  /// chiude: i byte di una connessione non completano quelli di un'altra.
  void reset() => _buffer.clear();
}

/// I byte così come li ha mandati la stampante, per chi vuole guardarli.
typedef RawStatus = Uint8List;
