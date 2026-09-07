import 'package:flutter_test/flutter_test.dart';
import 'package:pos_printer_bridge/pos_printer_bridge.dart';

/// I quattro byte di uno stato «tutto a posto»: solo i bit fissi accesi.
const List<int> pronta = <int>[0x10, 0x10, 0x10, 0x10];

void main() {
  group('PrinterStatus · leggere quattro byte', () {
    test('una stampante pronta non ha niente da segnalare', () {
      final PrinterStatus? status = PrinterStatus.tryDecode(pronta);

      expect(status, isNotNull);
      expect(status!.online, isTrue);
      expect(status.needsAttention, isFalse);
      expect(status.toString(), contains('pronta'));
    });

    test('carta finita: due bit, e vanno letti insieme', () {
      // La specifica accende entrambi i bit del sensore. Accontentarsi di uno
      // significa leggere uno stato intermedio come definitivo, e fermare la
      // cassa mentre la carta c'è ancora.
      final PrinterStatus finita =
          PrinterStatus.tryDecode(<int>[0x18, 0x70, 0x10, 0x7C])!;

      expect(finita.paperEnd, isTrue);
      expect(finita.online, isFalse);
      expect(finita.needsAttention, isTrue);

      final PrinterStatus unSoloBit =
          PrinterStatus.tryDecode(<int>[0x10, 0x10, 0x10, 0x30])!;
      expect(unSoloBit.paperEnd, isFalse);
    });

    test('carta in esaurimento è lo stato che permette di avvisare prima', () {
      final PrinterStatus status =
          PrinterStatus.tryDecode(<int>[0x10, 0x10, 0x10, 0x1C])!;

      expect(status.paperNearEnd, isTrue);
      expect(status.paperEnd, isFalse,
          reason: 'si può ancora stampare: è un avviso, non un blocco');
    });

    test('coperchio aperto mette la stampante fuori linea', () {
      final PrinterStatus status =
          PrinterStatus.tryDecode(<int>[0x18, 0x14, 0x10, 0x10])!;

      expect(status.coverOpen, isTrue);
      expect(status.online, isFalse);
      expect(status.toString(), contains('coperchio aperto'));
    });

    test('taglierina inceppata ed errore non recuperabile sono distinti', () {
      final PrinterStatus status =
          PrinterStatus.tryDecode(<int>[0x18, 0x50, 0x38, 0x10])!;

      expect(status.cutterError, isTrue);
      expect(status.unrecoverableError, isTrue);
      expect(status.error, isTrue);
    });

    test('il cassetto dice solo se il piedino è alto', () {
      // Non si chiama `drawerOpen` perché se alto voglia dire aperto o chiuso
      // dipende da come è cablato, e sul campo si trovano entrambi.
      expect(
          PrinterStatus.tryDecode(<int>[0x14, 0x10, 0x10, 0x10])!.drawerPinHigh,
          isTrue);
      expect(PrinterStatus.tryDecode(pronta)!.drawerPinHigh, isFalse);
    });
  });

  group('PrinterStatus · rifiutare ciò che non è uno stato', () {
    test('i bit fissi non tornano: non è uno stato', () {
      // È l'unica difesa contro il decodificare rumore in qualcosa che sembra
      // plausibile — e contro l'aver capito male la specifica.
      expect(PrinterStatus.tryDecode(<int>[0x00, 0x00, 0x00, 0x00]), isNull);
      expect(PrinterStatus.tryDecode(<int>[0xFF, 0xFF, 0xFF, 0xFF]), isNull);
      expect(PrinterStatus.tryDecode(<int>[0x10, 0x10, 0x10, 0x01]), isNull,
          reason: 'basta che uno dei quattro non torni');
    });

    test('meno di quattro byte non sono uno stato', () {
      expect(PrinterStatus.tryDecode(<int>[0x10, 0x10, 0x10]), isNull);
      expect(PrinterStatus.tryDecode(const <int>[]), isNull);
    });

    test('restituisce null invece di sollevare un errore', () {
      // Su un canale seriale un byte spaiato è normale quanto un pacchetto
      // perso in rete: chi legge deve riallinearsi, non fermarsi.
      expect(() => PrinterStatus.tryDecode(<int>[0xFF]), returnsNormally);
    });
  });

  group('PrinterStatusReader · i byte non arrivano a gruppi di quattro', () {
    test('uno stato spezzato fra due letture si ricompone', () {
      final PrinterStatusReader reader = PrinterStatusReader();

      expect(reader.add(<int>[0x10, 0x10]), isEmpty);
      expect(reader.pending, 2);
      expect(reader.add(<int>[0x10, 0x7C]), hasLength(1));
      expect(reader.pending, 0);
    });

    test('due stati in una lettura sola escono entrambi', () {
      final PrinterStatusReader reader = PrinterStatusReader();

      expect(reader.add(<int>[...pronta, ...pronta]), hasLength(2));
    });

    test('un byte spaiato in testa viene scartato, non lo stato che segue', () {
      // Buttare tutti e quattro i byte perderebbe uno stato valido che
      // comincia un byte più in là: si scarta uno solo e si riprova.
      final PrinterStatusReader reader = PrinterStatusReader();

      final List<PrinterStatus> found =
          reader.add(<int>[0x00, 0x10, 0x10, 0x10, 0x7C]);

      expect(found, hasLength(1));
      expect(found.single.paperEnd, isTrue);
    });

    test('reset dimentica i byte a metà', () {
      // I byte di una connessione non completano quelli di un'altra.
      final PrinterStatusReader reader = PrinterStatusReader()
        ..add(<int>[0x10, 0x10]);

      reader.reset();

      expect(reader.pending, 0);
      expect(reader.add(<int>[0x10, 0x10]), isEmpty);
    });
  });

  group('PrinterStatus · accendere gli stati', () {
    test('la sequenza è GS a 255', () {
      // Sta accanto al decodificatore perché è il comando che accende
      // esattamente ciò che quel codice legge.
      expect(PrinterStatus.enableAutomaticStatusBack, <int>[0x1D, 0x61, 0xFF]);
    });
  });
}
