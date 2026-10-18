import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

import 'helpers/esc_pos_decoder.dart';

/// Il criterio di questa voce, per la parte dei codici a barre: **i byte sono
/// quelli della specifica, e un dato che la stampante stamperebbe illeggibile
/// non arriva alla stampante.**
///
/// La seconda metà è quella che conta. Un codice a barre non dà errore da
/// nessuna parte: esce dalla carta come barre perfette, e nessun lettore le
/// accetta. Il riferimento ESC/POS dice che la cifra di controllo, quando
/// arriva, **non viene verificata**; quindi se non la verifica questo
/// pacchetto non la verifica nessuno.
///
/// Due difese falsificate, eseguite togliendo il codice e guardando la suite:
///
/// 1. senza il controllo della cifra di controllo, «la cifra sbagliata non
///    parte» diventa rosso;
/// 2. senza il raddoppio della graffa nel CODE128, «una graffa nei dati
///    arriva raddoppiata» diventa rosso.
void main() {
  Uint8List encode(List<EscPosCommand> commands) =>
      const EscPosEncoder().encode(EscPosDocument(commands));

  group('Il dato si controlla nel costruttore', () {
    test('EAN13 accetta dodici cifre, e lascia il conto alla stampante', () {
      expect(PrintBarcode.ean13('800123456789').payload.length, 12);
    });

    test('EAN13 accetta tredici cifre se la tredicesima è giusta', () {
      // 800123456789 ➜ cifra di controllo 7.
      expect(PrintBarcode.ean13('8001234567897').payload.length, 13);
    });

    test(
        'la cifra di controllo sbagliata non parte, e il messaggio dice '
        'quale sarebbe', () {
      // È la difesa che conta: la stampante stamperebbe questo codice senza
      // una parola, e il difetto si scoprirebbe al primo lettore che non
      // suona.
      expect(
        () => PrintBarcode.ean13('8001234567890'),
        throwsA(isA<ArgumentError>()
            .having((ArgumentError e) => e.message.toString(), 'messaggio',
                contains('è 7, non 0'))
            .having((ArgumentError e) => e.message.toString(), 'motivo',
                contains('non la verifica'))),
      );
    });

    test('EAN13 rifiuta un numero di cifre che non esiste', () {
      expect(() => PrintBarcode.ean13('80012345678'), throwsArgumentError);
      expect(() => PrintBarcode.ean13('80012345678901'), throwsArgumentError);
    });

    test('EAN13 rifiuta tutto ciò che non è una cifra', () {
      expect(() => PrintBarcode.ean13('80012345678X'), throwsArgumentError);
    });

    test('EAN8 vuole sette cifre, o otto con la sua', () {
      expect(PrintBarcode.ean8('9638507').payload.length, 7);
      expect(PrintBarcode.ean8('96385074').payload.length, 8);
      expect(() => PrintBarcode.ean8('96385070'), throwsArgumentError);
    });

    test('CODE39 ha un alfabeto, e le minuscole non ci sono', () {
      expect(PrintBarcode.code39('RICAMBIO-12/A').payload.length, 13);
      expect(
        () => PrintBarcode.code39('ricambio'),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'messaggio',
            contains('non ha il carattere'))),
      );
    });

    test('CODE128 porta davanti il selettore dell\'insieme', () {
      // Senza i due byte iniziali la stampante non stampa niente, e sono
      // l'errore classico di questo codice: il pacchetto li mette sempre.
      expect(PrintBarcode.code128('AB').payload, <int>[0x7B, 0x42, 0x41, 0x42]);
      expect(PrintBarcode.code128('12', set: Code128Set.c).payload,
          <int>[0x7B, 0x43, 0x31, 0x32]);
    });

    test('una graffa nei dati arriva raddoppiata', () {
      // `{` introduce i caratteri speciali: scritta una volta sola
      // significherebbe stampare qualcosa di diverso da quello che si legge
      // nel codice sorgente.
      expect(PrintBarcode.code128('a{b').payload,
          <int>[0x7B, 0x42, 0x61, 0x7B, 0x7B, 0x62]);
    });

    test('l\'insieme C codifica due cifre per carattere, e lo pretende', () {
      expect(() => PrintBarcode.code128('123', set: Code128Set.c),
          throwsArgumentError);
      expect(() => PrintBarcode.code128('1A', set: Code128Set.c),
          throwsArgumentError);
    });

    test('le misure stanno in un byte', () {
      expect(() => PrintBarcode.ean13('800123456789', heightDots: 0),
          throwsArgumentError);
      expect(() => PrintBarcode.ean13('800123456789', heightDots: 256),
          throwsArgumentError);
      expect(() => PrintBarcode.ean13('800123456789', moduleWidth: 0),
          throwsArgumentError);
    });
  });

  group('Il codice a barre nel flusso, byte per byte', () {
    test('un EAN13 da solo, scritto a mano e confrontato tutto', () {
      expect(
        encode(<EscPosCommand>[PrintBarcode.ean13('800123456789')]),
        <int>[
          0x1B, 0x40, //                ESC @    inizializza
          0x1B, 0x74, 0x13, //          ESC t 19 tabella PC858
          0x1B, 0x61, 0x01, //          ESC a 1  centrato
          0x1D, 0x48, 0x02, //          GS H 2   cifre sotto la barra
          0x1D, 0x66, 0x00, //          GS f 0   font A
          0x1D, 0x68, 0xA2, //          GS h 162 altezza in punti
          0x1D, 0x77, 0x03, //          GS w 3   larghezza del modulo
          0x1D, 0x6B, 0x43, 0x0C, //    GS k 67 12  EAN13, dodici byte
          0x38, 0x30, 0x30, 0x31, 0x32, 0x33, // "800123"
          0x34, 0x35, 0x36, 0x37, 0x38, 0x39, // "456789"
        ],
      );
    });

    test(
        'il primo codice dichiara tutte e quattro le impostazioni, anche '
        'quelle predefinite', () {
      // Qui il pacchetto si comporta all'opposto di come fa con lo stile del
      // testo, e per un motivo preciso: `ESC @` lascia il testo in uno stato
      // noto, ma il riferimento ESC/POS dice che il valore di accensione di
      // `GS h` e `GS w` dipende dal modello. Darlo per buono significa un
      // codice alto due centimetri su una stampante e due millimetri su
      // quella del negozio accanto.
      final List<String> escapes = decodeEscPos(
          encode(<EscPosCommand>[PrintBarcode.ean13('800123456789')])).escapes;

      expect(escapes, containsAllInOrder(<String>['hri 2', 'hri font 0']));
      expect(escapes, contains('barcode height 162'));
      expect(escapes, contains('barcode module 3'));
    });

    test('due codici uguali costano un giro di impostazioni solo', () {
      final List<String> escapes = decodeEscPos(encode(<EscPosCommand>[
        PrintBarcode.ean13('800123456789'),
        PrintBarcode.ean13('800123456790'),
      ])).escapes;

      expect(escapes.where((String e) => e == 'barcode height 162').length, 1);
      expect(escapes.where((String e) => e == 'barcode module 3').length, 1);
      expect(escapes.where((String e) => e.startsWith('barcode 67')).length, 2);
    });

    test('un\'altezza diversa manda solo l\'altezza', () {
      final List<String> escapes = decodeEscPos(encode(<EscPosCommand>[
        PrintBarcode.ean13('800123456789'),
        PrintBarcode.ean13('800123456789', heightDots: 80),
      ])).escapes;

      expect(escapes.where((String e) => e.startsWith('barcode height')),
          <String>['barcode height 162', 'barcode height 80']);
      expect(escapes.where((String e) => e == 'barcode module 3').length, 1);
    });

    test('riletto all\'indietro, il dato è quello che si è scritto', () {
      // Il decodificatore non condivide una riga con il codificatore: se la
      // lunghezza dichiarata nel comando fosse sbagliata di un byte, qui la
      // decodifica finirebbe su una sequenza sconosciuta invece che su questi
      // dati.
      final DecodedStream stream = decodeEscPos(encode(<EscPosCommand>[
        PrintBarcode.ean13('8001234567897'),
        PrintBarcode.code128('RIF{12', set: Code128Set.b),
      ]));

      expect(
          stream.barcodes.map((DecodedBarcode b) => b.selector), <int>[67, 73]);
      expect(stream.barcodes.first.text, '8001234567897');
      expect(stream.barcodes.last.text, '{BRIF{{12');
    });

    test('l\'allineamento del codice è un cambio di stato come un altro', () {
      final List<String> escapes = decodeEscPos(encode(<EscPosCommand>[
        PrintLine('scontrino'),
        PrintBarcode.ean13('800123456789'),
        PrintLine('grazie'),
      ])).escapes;

      // Centrato per il codice, e poi indietro a sinistra per il testo: senza
      // il ritorno, «grazie» resterebbe centrato.
      expect(escapes.where((String e) => e.startsWith('align')),
          <String>['align 1', 'align 0']);
    });
  });

  group('La carta è il limite, dove si può calcolarlo', () {
    test('un EAN13 troppo largo per la carta non si impagina', () {
      // 95 moduli da 6 punti sono 570 punti: ci stanno su 80 mm, non su 58.
      final EscPosDocumentBuilder narrow =
          EscPosDocumentBuilder(PaperFormat.mm58);

      expect(
        () =>
            narrow.barcode(PrintBarcode.ean13('800123456789', moduleWidth: 6)),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'suggerimento',
            contains('moduli da 4 punti ci starebbe'))),
      );
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm80)
            .barcode(PrintBarcode.ean13('800123456789', moduleWidth: 6)),
        returnsNormally,
      );
    });

    test('per CODE39 e CODE128 la larghezza non è calcolata, ed è dichiarato',
        () {
      // La loro larghezza dipende da quanti caratteri ci sono e, nel CODE39,
      // dal rapporto fra tratto stretto e tratto largo, che è una scelta del
      // modello. Una stima sbagliata rifiuterebbe codici buoni.
      expect(BarcodeSymbology.code39.moduleCount, isNull);
      expect(BarcodeSymbology.code128.moduleCount, isNull);
      expect(PrintBarcode.code39('RICAMBIO').widthDots, isNull);
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm58).barcode(
            PrintBarcode.code39('RICAMBIO-1234567890', moduleWidth: 6)),
        returnsNormally,
      );
    });
  });

  group('L\'anteprima del codice', () {
    test('la barra è in scala, e le cifre stanno dove le stampa', () {
      final EscPosDocumentBuilder builder =
          EscPosDocumentBuilder(PaperFormat.mm80)
            ..barcode(PrintBarcode.ean13('8001234567897'));

      // 95 moduli da 3 punti sono 285 punti: 24 colonne da 12 punti.
      expect(
        const PaperPreview().render(builder.build(), PaperFormat.mm80),
        '${' ' * 12}${'█' * 24}\n'
        '${' ' * 17}8001234567897',
      );
    });

    test('senza cifre leggibili resta la barra sola', () {
      final EscPosDocumentBuilder builder =
          EscPosDocumentBuilder(PaperFormat.mm80)
            ..barcode(PrintBarcode.ean13(
              '8001234567897',
              textPosition: BarcodeTextPosition.none,
            ));

      expect(
        const PaperPreview().render(builder.build(), PaperFormat.mm80).trim(),
        '█' * 24,
      );
    });
  });
}
