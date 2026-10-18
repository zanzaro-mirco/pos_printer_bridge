/// Sistema di codifica di un codice a barre.
///
/// Sono quattro, e non i quindici che ESC/POS elenca. Ognuno porta con sé le
/// regole su cosa può contenere, e un sistema dichiarato senza le sue regole
/// è peggio di un sistema assente: accetterebbe dati che la stampante
/// trasforma in barre che nessun lettore legge, e il difetto si scopre alla
/// cassa. Gli altri si aggiungono quando servono, uno per volta con le sue
/// regole; la gerarchia chiusa dei comandi fa il resto.
enum BarcodeSymbology {
  /// EAN13, il codice dei prodotti sul mercato europeo.
  ean13(selector: 67, label: 'EAN13', moduleCount: 95),

  /// EAN8, la versione corta per le confezioni piccole.
  ean8(selector: 68, label: 'EAN8', moduleCount: 67),

  /// CODE39: lettere maiuscole e cifre, nato per i codici interni.
  code39(selector: 69, label: 'CODE39'),

  /// CODE128: tutto l'ASCII, denso. È quello dei codici di spedizione.
  code128(selector: 73, label: 'CODE128');

  const BarcodeSymbology({
    required this.selector,
    required this.label,
    this.moduleCount,
  });

  /// Il valore di `m` nella funzione B di `GS k`.
  final int selector;

  /// Nome del sistema, per i messaggi di errore e per l'anteprima.
  final String label;

  /// Quanti moduli larga esce la barra, quando è una misura fissa.
  ///
  /// EAN13 sono 95 moduli e EAN8 sono 67, qualunque cifra ci sia dentro:
  /// barre di guardia e separatore centrale compresi. Moltiplicati per la
  /// larghezza del modulo danno i punti occupati, ed è così che
  /// `EscPosDocumentBuilder` può rifiutare un codice più largo della carta
  /// prima di stamparlo.
  ///
  /// Per CODE39 e CODE128 è `null`: la larghezza dipende da quanti caratteri
  /// ci sono e, nel CODE39, dal rapporto fra barra stretta e barra larga, che
  /// è una scelta del modello di stampante. Preferisco non saperlo che
  /// stimarlo: una stima sbagliata rifiuterebbe codici buoni.
  final int? moduleCount;
}

/// Dove vanno le cifre leggibili che accompagnano la barra.
///
/// ESC/POS le chiama HRI, «Human Readable Interpretation»: sono il numero
/// stampato sotto il codice, quello che si legge a voce quando il lettore non
/// legge.
enum BarcodeTextPosition {
  /// Nessuna cifra: solo la barra.
  none(0),

  /// Sopra la barra.
  above(1),

  /// Sotto la barra. È dove la cerca chi guarda uno scontrino.
  below(2),

  /// Sopra e sotto.
  both(3);

  const BarcodeTextPosition(this.value);

  /// Il valore di `n` in `GS H`.
  final int value;

  /// Vero se le cifre vengono stampate da qualche parte.
  bool get printed => this != BarcodeTextPosition.none;
}

/// Font delle cifre leggibili sotto la barra.
enum BarcodeTextFont {
  /// Font A, quello predefinito del testo.
  a(0),

  /// Font B, più piccolo.
  b(1);

  const BarcodeTextFont(this.value);

  /// Il valore di `n` in `GS f`.
  final int value;
}

/// Insieme di caratteri con cui comincia un CODE128.
///
/// CODE128 non ha un alfabeto solo: ne ha tre, e il flusso deve dire quale
/// usare prima del primo carattere. Non è un dettaglio che si possa
/// nascondere, perché cambia cosa il codice può contenere e quanto diventa
/// lungo.
enum Code128Set {
  /// Caratteri di controllo e maiuscole.
  a(0x41),

  /// Tutto l'ASCII stampabile: maiuscole, minuscole, cifre, simboli.
  b(0x42),

  /// Solo cifre, a coppie: due cifre per carattere, quindi un codice
  /// numerico lungo occupa metà spazio.
  c(0x43);

  const Code128Set(this.selector);

  /// Il byte che segue `{` per selezionare l'insieme.
  final int selector;
}

/// La cifra di controllo di un codice EAN, calcolata dalle cifre di dati.
///
/// Serve perché **la stampante non la verifica**: il riferimento ESC/POS dice
/// che quando i dati arrivano completi della loro ultima cifra, quella cifra
/// viene stampata così com'è, senza controlli. Una cifra sbagliata diventa
/// quindi una barra stampata benissimo che nessun lettore accetta, e il
/// difetto si vede solo alla cassa, con il cliente davanti.
///
/// I pesi sono 3 e 1 alternati partendo dall'ultima cifra di dati e andando
/// verso sinistra: la stessa regola per EAN13 e per EAN8, che hanno un numero
/// diverso di cifre.
int eanCheckDigit(String dataDigits) {
  int sum = 0;
  for (int i = 0; i < dataDigits.length; i++) {
    final int digit = dataDigits.codeUnitAt(dataDigits.length - 1 - i) - 0x30;
    sum += (i.isEven ? 3 : 1) * digit;
  }
  return (10 - sum % 10) % 10;
}

/// I byte di un EAN13, controllati.
///
/// Dodici cifre lasciano calcolare la cifra di controllo alla stampante;
/// tredici devono essere già giuste.
List<int> ean13Payload(String digits) => _eanPayload(
      digits,
      label: 'EAN13',
      dataLength: 12,
    );

/// I byte di un EAN8, controllati. Sette cifre o otto, come per EAN13.
List<int> ean8Payload(String digits) => _eanPayload(
      digits,
      label: 'EAN8',
      dataLength: 7,
    );

List<int> _eanPayload(
  String digits, {
  required String label,
  required int dataLength,
}) {
  if (digits.length != dataLength && digits.length != dataLength + 1) {
    throw ArgumentError.value(
        digits,
        'data',
        '$label vuole $dataLength cifre, o ${dataLength + 1} con quella di '
            'controllo: ne ha ${digits.length}');
  }
  for (int i = 0; i < digits.length; i++) {
    final int code = digits.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) {
      throw ArgumentError.value(
          digits, 'data', '$label accetta solo cifre: «${digits[i]}» non lo è');
    }
  }
  if (digits.length == dataLength + 1) {
    final int expected = eanCheckDigit(digits.substring(0, dataLength));
    final int given = digits.codeUnitAt(dataLength) - 0x30;
    if (given != expected) {
      throw ArgumentError.value(
          digits,
          'data',
          'La cifra di controllo di $label è $expected, non $given. La '
              'stampante non la verifica: stamperebbe un codice illeggibile '
              'dai lettori');
    }
  }
  return digits.codeUnits;
}

/// I caratteri che CODE39 sa rappresentare.
const String _code39Alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. \$/+%*';

/// I byte di un CODE39, controllati.
List<int> code39Payload(String data) {
  if (data.isEmpty) {
    throw ArgumentError.value(data, 'data', 'CODE39 vuole almeno un carattere');
  }
  if (data.length > 255) {
    throw ArgumentError.value(
        data, 'data', 'CODE39 arriva a 255 caratteri: ne ha ${data.length}');
  }
  for (int i = 0; i < data.length; i++) {
    if (!_code39Alphabet.contains(data[i])) {
      throw ArgumentError.value(
          data,
          'data',
          'CODE39 non ha il carattere «${data[i]}». Il suo alfabeto è cifre, '
              'maiuscole e - . spazio \$ / + % *');
    }
  }
  return data.codeUnits;
}

/// I byte di un CODE128, controllati, con il selettore dell'insieme davanti.
///
/// Due cose che chi chiama non deve ricordarsi, e che sono il modo classico
/// di sbagliare questo codice:
///
/// 1. **il selettore dell'insieme** va messo davanti ai dati, come due byte
///    `{` e `A`/`B`/`C`, e senza di lui la stampante non stampa niente;
/// 2. **una graffa dentro i dati va raddoppiata**, perché `{` è il carattere
///    con cui si introducono i caratteri speciali. Scriverla una volta sola
///    significa stampare qualcosa di diverso da quello che si legge nel
///    codice sorgente.
List<int> code128Payload(String data, Code128Set set) {
  if (data.isEmpty) {
    throw ArgumentError.value(
        data, 'data', 'CODE128 vuole almeno un carattere');
  }
  for (int i = 0; i < data.length; i++) {
    final int code = data.codeUnitAt(i);
    if (code > 0x7F) {
      throw ArgumentError.value(
          data,
          'data',
          'CODE128 arriva a 127 come codice di carattere: «${data[i]}» vale '
              '$code. Una tabella dei caratteri non c\'entra: qui i byte sono '
              'il codice, non una lettera');
    }
  }
  if (set == Code128Set.c) {
    if (data.length.isOdd) {
      throw ArgumentError.value(
          data,
          'data',
          'L\'insieme C codifica due cifre per carattere, quindi ne vuole un '
              'numero pari: ne ha ${data.length}');
    }
    for (int i = 0; i < data.length; i++) {
      final int code = data.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) {
        throw ArgumentError.value(data, 'data',
            'L\'insieme C accetta solo cifre: «${data[i]}» non lo è');
      }
    }
  }
  final List<int> payload = <int>[0x7B, set.selector];
  for (int i = 0; i < data.length; i++) {
    final int code = data.codeUnitAt(i);
    if (code == 0x7B) payload.add(0x7B);
    payload.add(code);
  }
  if (payload.length > 255) {
    throw ArgumentError.value(
        data,
        'data',
        'CODE128 arriva a 255 byte, selettore e graffe raddoppiate comprese: '
            'questo ne fa ${payload.length}');
  }
  return payload;
}
