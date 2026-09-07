import 'commands.dart';
import 'paper.dart';
import 'text_style.dart';

/// Uno scontrino pronto da stampare, espresso come lista di comandi.
///
/// Non è ancora un flusso di byte: è la forma in cui si può leggere, mettere
/// alla prova e vedere in anteprima. I byte li fa `EscPosEncoder`, e sono un
/// dettaglio di trasporto.
class EscPosDocument {
  /// Crea un documento dalla lista dei suoi comandi.
  EscPosDocument(List<EscPosCommand> commands)
      : commands = List<EscPosCommand>.unmodifiable(commands);

  /// I comandi, in ordine. Non modificabile.
  final List<EscPosCommand> commands;

  @override
  String toString() => 'EscPosDocument(${commands.length} comandi)';
}

/// Costruisce un [EscPosDocument] rispettando la larghezza della carta.
///
/// Tutta l'aritmetica delle colonne sta qui, in un posto solo. È ciò che
/// permette all'impaginazione di uno scontrino di leggersi come uno
/// scontrino — `columns('TOTALE EUR', '39,40')` — invece che come un calcolo
/// di riempimenti.
///
/// La garanzia che offre: **nessuna riga prodotta supera la larghezza della
/// carta**, qualunque cosa le si passi. Le descrizioni lunghe vanno a capo,
/// e il testo a doppia larghezza conta doppio.
class EscPosDocumentBuilder {
  /// Crea un costruttore per il formato di carta dato.
  EscPosDocumentBuilder(this.paper);

  /// Formato su cui si sta impaginando.
  final PaperFormat paper;

  final List<EscPosCommand> _commands = <EscPosCommand>[];

  /// Colonne utilizzabili con [style]: la metà, se il testo è a doppia
  /// larghezza.
  int columnsFor(EscPosTextStyle style) =>
      paper.columns ~/ style.widthMultiplier;

  /// Aggiunge [text], andando a capo se non ci sta.
  void line(String text, {EscPosTextStyle style = EscPosTextStyle.normal}) {
    for (final String piece in _wrap(text, columnsFor(style))) {
      _commands.add(PrintLine(piece, style: style));
    }
  }

  /// Aggiunge una riga vuota.
  void blank() => _commands.add(PrintLine(''));

  /// Aggiunge una riga con [left] a sinistra e [right] a destra, allineato al
  /// bordo della carta: la forma di ogni riga di uno scontrino.
  ///
  /// Se [left] non ci sta, continua sulle righe successive rientrato di due
  /// spazi. Se [right] da solo non ci sta, è un errore di chi chiama: un
  /// importo più largo della carta non si impagina, si sbaglia.
  void columns(
    String left,
    String right, {
    EscPosTextStyle style = EscPosTextStyle.normal,
  }) {
    final int width = columnsFor(style);
    if (right.length + 1 > width) {
      throw ArgumentError.value(
          right, 'right', 'Non ci sta in $width colonne insieme a uno spazio');
    }
    final int leftWidth = width - right.length - 1;
    final List<String> pieces = _wrap(left, leftWidth);
    final String first = pieces.first;
    _commands.add(PrintLine(
      first.padRight(width - right.length) + right,
      style: style,
    ));
    if (pieces.length == 1) return;
    final String remainder = pieces.skip(1).join(' ');
    for (final String piece in _wrap(remainder, width - 2)) {
      _commands.add(PrintLine('  $piece', style: style));
    }
  }

  /// Aggiunge una riga di celle, larghe [widths] colonne ciascuna.
  ///
  /// La prima cella è allineata a sinistra, le altre a destra: è la forma di
  /// una tabella di importi. Le celle troppo larghe vengono troncate — in una
  /// tabella andare a capo distruggerebbe l'incolonnamento, che è l'unica
  /// ragione per cui la tabella esiste.
  void row(
    List<String> cells,
    List<int> widths, {
    EscPosTextStyle style = EscPosTextStyle.normal,
  }) {
    if (cells.length != widths.length) {
      throw ArgumentError('Una larghezza per ogni cella');
    }
    final int total = widths.fold<int>(0, (int a, int b) => a + b);
    if (total > columnsFor(style)) {
      throw ArgumentError.value(widths, 'widths',
          'Somma $total, ma la carta ne ha ${columnsFor(style)}');
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < cells.length; i++) {
      final String cell = cells[i].length > widths[i]
          ? cells[i].substring(0, widths[i])
          : cells[i];
      buffer.write(i == 0 ? cell.padRight(widths[i]) : cell.padLeft(widths[i]));
    }
    _commands.add(PrintLine(buffer.toString().trimRight(), style: style));
  }

  /// Aggiunge una riga di separazione larga quanto la carta.
  void separator([String character = '-']) =>
      _commands.add(PrintLine(character * paper.columns));

  /// Fa avanzare la carta di [count] righe.
  void feed(int count) => _commands.add(FeedLines(count));

  /// Taglia la carta.
  void cut({bool partial = true}) => _commands.add(CutPaper(partial: partial));

  /// Manda l'impulso al cassetto portavalori.
  void openDrawer({int pin = 2}) => _commands.add(OpenDrawer(pin: pin));

  /// Chiude la costruzione e restituisce il documento.
  EscPosDocument build() => EscPosDocument(_commands);

  /// Manda [text] a capo ogni [width] colonne, spezzando fra le parole.
  ///
  /// Una parola più lunga della riga viene tagliata: è preferibile a una riga
  /// che sfora, perché la stampante andrebbe comunque a capo per conto suo e
  /// nel punto sbagliato.
  static List<String> _wrap(String text, int width) {
    if (width <= 0) return <String>[text];
    if (text.length <= width) return <String>[text];
    final List<String> lines = <String>[];
    final StringBuffer current = StringBuffer();
    for (String word in text.split(' ')) {
      while (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current.toString());
          current.clear();
        }
        lines.add(word.substring(0, width));
        word = word.substring(width);
      }
      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= width) {
        current.write(' $word');
      } else {
        lines.add(current.toString());
        current
          ..clear()
          ..write(word);
      }
    }
    if (current.isNotEmpty) lines.add(current.toString());
    return lines.isEmpty ? <String>[''] : lines;
  }
}
