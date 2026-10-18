import 'barcode.dart';
import 'raster_image.dart';
import 'text_style.dart';

/// Una cosa che la stampante deve fare.
///
/// Gerarchia chiusa: il codificatore la percorre con uno `switch` esaustivo,
/// e aggiungere un comando domani fa fallire la compilazione nel punto esatto
/// in cui va gestito, invece di lasciarlo cadere in un ramo `default`.
///
/// Il documento è fatto di questi, non di stringhe con dentro le sequenze di
/// escape. È la differenza fra qualcosa che si può leggere, verificare e
/// impaginare in anteprima, e un blocco di byte che si può solo mandare a una
/// stampante e guardare cosa esce.
sealed class EscPosCommand {
  /// Costruttore delle sottoclassi.
  const EscPosCommand();
}

/// Una riga di testo, con il suo a capo.
///
/// Il testo di una riga non contiene mai un a capo: metterlo dentro
/// aggirerebbe l'unico posto che conosce la larghezza della carta, e la riga
/// finirebbe troncata dalla stampante senza che nessuno se ne accorga prima
/// della prova su carta.
final class PrintLine extends EscPosCommand {
  /// Crea una riga di testo. Rifiuta un a capo dentro [text].
  PrintLine(this.text, {this.style = EscPosTextStyle.normal}) {
    if (text.contains('\n') || text.contains('\r')) {
      throw ArgumentError.value(text, 'text',
          'Una riga per volta: l\'a capo lo mette il codificatore');
    }
  }

  /// Testo da stampare, senza a capo.
  final String text;

  /// Aspetto della riga.
  final EscPosTextStyle style;

  @override
  String toString() => 'PrintLine("$text", $style)';
}

/// Avanzamento della carta di [count] righe vuote.
///
/// Serve prima del taglio: la lama sta qualche millimetro sopra la testina, e
/// senza avanzamento il taglio cadrebbe in mezzo all'ultima riga stampata.
final class FeedLines extends EscPosCommand {
  /// Crea un avanzamento di [count] righe.
  const FeedLines(this.count)
      : assert(count > 0, 'Avanzare di zero righe non è un comando');

  /// Numero di righe da far scorrere.
  final int count;

  @override
  String toString() => 'FeedLines($count)';
}

/// Taglio della carta.
final class CutPaper extends EscPosCommand {
  /// Crea un taglio. Parziale per impostazione predefinita: lascia un punto
  /// di carta attaccato, così lo scontrino non cade a terra prima che il
  /// cliente lo prenda.
  const CutPaper({this.partial = true});

  /// Vero per il taglio parziale, falso per quello completo.
  final bool partial;

  @override
  String toString() => 'CutPaper(${partial ? 'parziale' : 'completo'})';
}

/// Impulso sul connettore del cassetto portavalori.
///
/// Il cassetto non è collegato al computer: è collegato alla stampante, e si
/// apre con un impulso elettrico su uno dei due piedini del connettore RJ11.
/// È il motivo per cui "apri il cassetto" è un comando di stampa e non
/// sembra averci niente a che fare.
final class OpenDrawer extends EscPosCommand {
  /// Crea l'impulso. [pin] è 2 o 5 a seconda di come è cablato il cassetto:
  /// entrambi esistono sul campo, e sbagliarlo significa un cassetto che non
  /// si apre senza nessun errore da nessuna parte.
  const OpenDrawer({this.pin = 2})
      : assert(pin == 2 || pin == 5, 'Il connettore ha solo i piedini 2 e 5');

  /// Piedino su cui mandare l'impulso: 2 o 5.
  final int pin;

  @override
  String toString() => 'OpenDrawer(pin $pin)';
}

/// Un codice a barre.
///
/// Il dato arriva come lo scrive una persona — tredici cifre, un codice
/// interno — e viene controllato qui, nel costruttore, contro le regole del
/// sistema scelto. Non più tardi: un codice a barre sbagliato non dà errore
/// da nessuna parte. Esce dalla stampante come barre perfette che nessun
/// lettore accetta, e lo scopre il cassiere.
///
/// Delle altezze e delle larghezze **non c'è un valore di accensione su cui
/// contare**: il riferimento ESC/POS dice che il valore predefinito di `GS h`
/// e `GS w` dipende dal modello. Per questo ogni comando porta le sue misure,
/// e il codificatore le dichiara alla stampante prima del primo codice.
final class PrintBarcode extends EscPosCommand {
  /// EAN13: dodici cifre, oppure tredici con la cifra di controllo già
  /// calcolata e giusta.
  PrintBarcode.ean13(
    this.data, {
    this.heightDots = _defaultHeight,
    this.moduleWidth = _defaultModuleWidth,
    this.textPosition = BarcodeTextPosition.below,
    this.textFont = BarcodeTextFont.a,
    this.align = EscPosAlign.center,
  })  : symbology = BarcodeSymbology.ean13,
        payload = ean13Payload(data) {
    _checkMeasures();
  }

  /// EAN8: sette cifre, oppure otto con la cifra di controllo.
  PrintBarcode.ean8(
    this.data, {
    this.heightDots = _defaultHeight,
    this.moduleWidth = _defaultModuleWidth,
    this.textPosition = BarcodeTextPosition.below,
    this.textFont = BarcodeTextFont.a,
    this.align = EscPosAlign.center,
  })  : symbology = BarcodeSymbology.ean8,
        payload = ean8Payload(data) {
    _checkMeasures();
  }

  /// CODE39: cifre, maiuscole e pochi simboli. È il codice dei cartellini
  /// interni, quelli che un'azienda si stampa da sé.
  PrintBarcode.code39(
    this.data, {
    this.heightDots = _defaultHeight,
    this.moduleWidth = _defaultModuleWidth,
    this.textPosition = BarcodeTextPosition.below,
    this.textFont = BarcodeTextFont.a,
    this.align = EscPosAlign.center,
  })  : symbology = BarcodeSymbology.code39,
        payload = code39Payload(data) {
    _checkMeasures();
  }

  /// CODE128, con l'insieme di caratteri da usare.
  ///
  /// L'insieme va scelto, non indovinato: cambia cosa il codice può contenere
  /// e quanto viene lungo. [Code128Set.b] è l'ASCII stampabile e va bene per
  /// quasi tutto; [Code128Set.c] dimezza la lunghezza di un codice fatto di
  /// sole cifre.
  PrintBarcode.code128(
    this.data, {
    Code128Set set = Code128Set.b,
    this.heightDots = _defaultHeight,
    this.moduleWidth = _defaultModuleWidth,
    this.textPosition = BarcodeTextPosition.below,
    this.textFont = BarcodeTextFont.a,
    this.align = EscPosAlign.center,
  })  : symbology = BarcodeSymbology.code128,
        payload = code128Payload(data, set) {
    _checkMeasures();
  }

  /// 162 punti: circa 20 mm sulle testine da 8 punti per millimetro, che sono
  /// la quasi totalità delle termiche da banco. Non è il valore di accensione
  /// della stampante — quello dipende dal modello — è una scelta di questo
  /// pacchetto, dichiarata e sovrascrivibile.
  static const int _defaultHeight = 162;

  /// 3 punti per modulo. Un EAN13 sono 95 moduli: 285 punti, metà della
  /// larghezza di una carta da 80 mm.
  static const int _defaultModuleWidth = 3;

  /// Il sistema di codifica.
  final BarcodeSymbology symbology;

  /// Il dato come lo si legge: le cifre, o il codice interno.
  final String data;

  /// I byte che vanno nel comando, controllati e completi di ciò che il
  /// sistema richiede — per CODE128, il selettore dell'insieme e le graffe
  /// raddoppiate.
  final List<int> payload;

  /// Altezza della barra in punti.
  final int heightDots;

  /// Larghezza di un modulo in punti: è il tratto più stretto del codice, e
  /// moltiplica la larghezza di tutto il resto.
  final int moduleWidth;

  /// Dove stampare le cifre leggibili.
  final BarcodeTextPosition textPosition;

  /// Con quale font stamparle.
  final BarcodeTextFont textFont;

  /// Allineamento del codice sulla carta.
  final EscPosAlign align;

  /// Punti occupati in larghezza, quando il sistema ha una misura fissa.
  ///
  /// `null` per CODE39 e CODE128, e il motivo sta in
  /// [BarcodeSymbology.moduleCount].
  int? get widthDots {
    final int? modules = symbology.moduleCount;
    return modules == null ? null : modules * moduleWidth;
  }

  void _checkMeasures() {
    if (heightDots < 1 || heightDots > 255) {
      throw ArgumentError.value(heightDots, 'heightDots',
          'L\'altezza sta in un byte: da 1 a 255 punti');
    }
    if (moduleWidth < 1 || moduleWidth > 255) {
      throw ArgumentError.value(moduleWidth, 'moduleWidth',
          'La larghezza del modulo sta in un byte: da 1 a 255 punti');
    }
  }

  @override
  String toString() => 'PrintBarcode(${symbology.label} "$data", '
      '$heightDots×$moduleWidth punti, $align)';
}

/// Un'immagine in bianco e nero, stampata dove sta nel documento.
///
/// Sulla carta è il logo in testa allo scontrino, ed è l'unica cosa che una
/// stampante termica fa che non sia testo.
final class PrintImage extends EscPosCommand {
  /// Crea il comando per [image].
  const PrintImage(this.image, {this.align = EscPosAlign.center});

  /// L'immagine da stampare.
  final RasterImage image;

  /// Allineamento sulla carta. Centrato per impostazione predefinita: un logo
  /// a sinistra su uno scontrino si nota, e non in bene.
  final EscPosAlign align;

  @override
  String toString() => 'PrintImage($image, $align)';
}
