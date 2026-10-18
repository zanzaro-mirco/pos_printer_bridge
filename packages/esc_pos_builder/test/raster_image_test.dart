import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

import 'helpers/esc_pos_decoder.dart';

/// Il criterio di questa voce, per la parte del logo: **l'immagine che entra
/// nel flusso è la stessa che si rilegge dall'altra parte, anche quando la sua
/// larghezza non è un multiplo di otto.**
///
/// Otto punti stanno in un byte, e una larghezza che non è un multiplo di otto
/// lascia dei bit di avanzo: contarli male è il difetto classico della stampa
/// raster, e si vede come un'immagine che scivola in diagonale riga per riga.
/// Il conto sta in un posto solo, [RasterImage.bytesPerRow], e il
/// decodificatore dei test lo rifà per conto suo partendo dai numeri che il
/// comando dichiara.
///
/// Difesa falsificata: cambiando quel conto in `widthDots ~/ 8`, «un disegno
/// larga 12 punti torna identico» e «la lunghezza dichiarata e le misure
/// dicono la stessa cosa» diventano rossi.
void main() {
  Uint8List encode(List<EscPosCommand> commands) =>
      const EscPosEncoder().encode(EscPosDocument(commands));

  group('RasterImage · i bit', () {
    test('un disegno come testo diventa bit, e i bit di avanzo sono bianchi',
        () {
      // Quattro punti su dodici: il primo byte porta i quattro punti e i
      // quattro bianchi, il secondo è tutto avanzo.
      final RasterImage image = RasterImage.fromRows(<String>['####        ']);

      expect(image.widthDots, 12);
      expect(image.bytesPerRow, 2);
      expect(image.bits, <int>[0xF0, 0x00]);
    });

    test('dodici punti occupano due byte per riga, non uno e mezzo', () {
      expect(RasterImage.fromRows(<String>['#' * 12]).bytesPerRow, 2);
      expect(RasterImage.fromRows(<String>['#' * 16]).bytesPerRow, 2);
      expect(RasterImage.fromRows(<String>['#' * 17]).bytesPerRow, 3);
    });

    test('righe di lunghezza diversa non sono un\'immagine', () {
      expect(
        () => RasterImage.fromRows(<String>['###', '##']),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'messaggio',
            contains('La riga 1'))),
      );
    });

    test('un vettore di byte della lunghezza sbagliata non passa', () {
      // Una lunghezza sbagliata manderebbe alla stampante un comando con un
      // numero di byte diverso da quello dichiarato nella testata, e da quel
      // punto in avanti il flusso è spazzatura.
      expect(
        () => RasterImage(
          widthDots: 12,
          heightDots: 2,
          bits: <int>[0xFF, 0xFF, 0xFF],
        ),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'messaggio',
            contains('2 byte per riga'))),
      );
    });

    test('il punto si rilegge dove è stato messo', () {
      final RasterImage image = RasterImage.fromRows(<String>[
        '#  #',
        ' ## ',
      ]);

      expect(image.dotAt(0, 0), isTrue);
      expect(image.dotAt(1, 0), isFalse);
      expect(image.dotAt(3, 0), isTrue);
      expect(image.dotAt(1, 1), isTrue);
      expect(image.dotAt(4, 0), isFalse, reason: 'fuori dall\'immagine');
    });
  });

  group('La funzione grafica nel flusso', () {
    test('un\'immagine minima, scritta a mano e confrontata tutta', () {
      expect(
        encode(<EscPosCommand>[
          PrintImage(
            RasterImage.fromRows(<String>['########']),
            align: EscPosAlign.left,
          ),
        ]),
        <int>[
          0x1B, 0x40, //                   ESC @
          0x1B, 0x74, 0x13, //             ESC t 19
          0x1D, 0x28, 0x4C, 0x0B, 0x00, // GS ( L  p = 11
          0x30, 0x70, //                   m = 48, fn = 112
          0x30, //                         a: monocromatica
          0x01, 0x01, //                   bx, by: nessun ingrandimento
          0x31, //                         c: colore 1
          0x08, 0x00, //                   8 punti in larghezza
          0x01, 0x00, //                   1 punto in altezza
          0xFF, //                         gli otto punti
          0x1D, 0x28, 0x4C, 0x02, 0x00, 0x30, 0x32, // stampa il buffer
        ],
      );
    });

    test('un disegno largo 12 punti torna identico dall\'altra parte', () {
      // Il giro completo: disegno nel codice sorgente ➜ bit ➜ byte del
      // comando ➜ riletti ➜ disegno. Il decodificatore rifà il conto dei byte
      // per riga da solo, partendo dalle misure dichiarate nel comando.
      final List<String> drawing = <String>[
        '####    ####',
        '#  #    #  #',
        '#  ######  #',
        '#          #',
        '####    ####',
      ];

      final DecodedStream stream = decodeEscPos(encode(<EscPosCommand>[
        PrintImage(RasterImage.fromRows(drawing)),
      ]));

      expect(stream.images, hasLength(1));
      expect(stream.images.single.widthDots, 12);
      expect(stream.images.single.heightDots, 5);
      expect(stream.images.single.rows(), drawing);
    });

    test('la lunghezza dichiarata e le misure dicono la stessa cosa', () {
      // È il controllo che il decodificatore fa da sé: `p` conta i byte del
      // comando, le misure dicono quanti dovrebbero essere, e se i due numeri
      // non tornano la rilettura si ferma.
      expect(
        () => decodeEscPos(encode(<EscPosCommand>[
          PrintImage(RasterImage.fromRows(<String>['#' * 17, '#' * 17])),
        ])),
        returnsNormally,
      );
    });

    test(
        'un\'immagine grande passa da GS 8 L, con la lunghezza su quattro '
        'byte', () {
      // `GS ( L` dichiara la lunghezza in due byte e arriva a 65535: un logo
      // da 576 punti su 920 righe fa 66.240 byte, e non ci sta.
      final RasterImage tall = RasterImage(
        widthDots: 576,
        heightDots: 920,
        bits: Uint8List(72 * 920),
      );
      final Uint8List bytes =
          encode(<EscPosCommand>[PrintImage(tall, align: EscPosAlign.left)]);

      // 10 byte di testata più i dati.
      const int p = 10 + 72 * 920;
      expect(bytes.sublist(5, 12), <int>[
        0x1D, 0x38, 0x4C, //  GS 8 L
        p & 0xFF, p >> 8 & 0xFF, p >> 16 & 0xFF, p >> 24 & 0xFF,
      ]);
      expect(decodeEscPos(bytes).images.single.heightDots, 920);
    });

    test('l\'immagine si allinea, e lo fa con lo stesso comando del testo', () {
      final List<String> escapes = decodeEscPos(encode(<EscPosCommand>[
        PrintImage(RasterImage.fromRows(<String>['####'])),
        PrintLine('Bar Centrale'),
      ])).escapes;

      expect(escapes.where((String e) => e.startsWith('align')),
          <String>['align 1', 'align 0']);
    });
  });

  group('La carta è il limite', () {
    test('un\'immagine più larga della carta non si impagina', () {
      // La stampante non direbbe niente: stamperebbe quello che ci sta e
      // taglierebbe il resto.
      expect(
        () => EscPosDocumentBuilder(PaperFormat.mm58).image(RasterImage(
          widthDots: 576,
          heightDots: 8,
          bits: Uint8List(72 * 8),
        )),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.message.toString(),
            'messaggio',
            contains('senza dire niente'))),
      );
    });

    test('la carta si misura in punti e in colonne, e i due conti combaciano',
        () {
      // Un carattere del font A è largo 12 punti: è il rapporto su cui si
      // appoggiano sia l'impaginazione del testo sia l'anteprima di
      // un'immagine.
      expect(PaperFormat.mm80.dots, PaperFormat.mm80.columns * 12);
      expect(PaperFormat.mm58.dots, PaperFormat.mm58.columns * 12);
    });
  });

  group('L\'anteprima dell\'immagine', () {
    test('mostra il rettangolo di carta che occupa, con la misura dentro', () {
      // Non disegna il logo: dice quanta carta mangia, che è la cosa che
      // serve impaginando.
      final EscPosDocumentBuilder builder =
          EscPosDocumentBuilder(PaperFormat.mm80)
            ..image(RasterImage(
              widthDots: 240,
              heightDots: 72,
              bits: Uint8List(30 * 72),
            ));

      final List<String> lines = const PaperPreview()
          .render(builder.build(), PaperFormat.mm80)
          .split('\n');

      expect(lines, hasLength(3), reason: '72 punti sono tre righe da 24');
      expect(lines[1], contains('240×72 punti'));
      expect(lines[0].trim(), '▒' * 20);
      expect(lines[0].indexOf('▒'), 14, reason: 'centrato su 48 colonne');
    });
  });
}
