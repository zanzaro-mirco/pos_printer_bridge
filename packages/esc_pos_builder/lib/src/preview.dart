import 'barcode.dart';
import 'commands.dart';
import 'document.dart';
import 'paper.dart';
import 'raster_image.dart';
import 'text_style.dart';

/// Rende un documento come testo, così com'è disposto sulla carta.
///
/// Serve a vedere uno scontrino senza avere una stampante — nei test, nel
/// README, in una revisione del codice. Un pacchetto che si può solo provare
/// collegando l'hardware è un pacchetto che nessuno prova.
///
/// **È un'approssimazione, e in tre punti dichiarati:**
///
/// 1. l'anteprima è monospaziata, quindi un carattere a doppia larghezza
///    occupa due colonne sulla carta e una qui. La *posizione* del testo resta
///    quella giusta, la lunghezza no;
/// 2. la barra di un codice è in scala solo per EAN13 ed EAN8, dove la
///    larghezza è una misura fissa. Per CODE39 e CODE128 dipende da come il
///    sistema codifica quei caratteri e dal modello di stampante, quindi la
///    barra qui è un segnaposto;
/// 3. un'immagine non si disegna: si mostra il **rettangolo di carta che
///    occupa**, con la sua misura scritta dentro. È l'informazione che serve
///    impaginando — quanta carta mangia il logo — e l'unica che un'anteprima
///    di testo può dare onestamente.
class PaperPreview {
  /// Crea un'anteprima. Con [showCommands] a falso restano solo le righe
  /// stampate, senza i segni per taglio e cassetto.
  const PaperPreview({this.showCommands = true});

  /// Punti di un carattere del font A: 12 in larghezza, 24 in altezza.
  /// Servono a convertire le misure in punti nelle colonne e nelle righe
  /// dell'anteprima.
  static const int _dotsPerColumn = 12;
  static const int _dotsPerRow = 24;

  /// Se mostrare anche i comandi che non stampano testo.
  final bool showCommands;

  /// Rende [document] come apparirebbe su carta [paper].
  String render(EscPosDocument document, PaperFormat paper) {
    final List<String> lines = <String>[];
    for (final EscPosCommand command in document.commands) {
      switch (command) {
        case PrintLine(:final String text, :final EscPosTextStyle style):
          lines.add(_place(text, paper, style));
        case FeedLines(:final int count):
          lines.addAll(List<String>.filled(count, ''));
        case CutPaper():
          if (showCommands) lines.add('${'-' * (paper.columns - 1)}✂');
        case OpenDrawer(:final int pin):
          if (showCommands) lines.add('[ cassetto, piedino $pin ]');
        case final PrintBarcode barcode:
          lines.addAll(_barcode(barcode, paper));
        case final PrintImage picture:
          lines.addAll(_image(picture.image, paper, picture.align));
      }
    }
    return lines.join('\n');
  }

  /// Le righe di un codice a barre: la barra, e le cifre leggibili se la
  /// stampante le stampa — sopra, sotto o in entrambi i posti, come è stato
  /// chiesto al comando.
  static List<String> _barcode(PrintBarcode barcode, PaperFormat paper) {
    final int? dots = barcode.widthDots;
    final int width =
        dots == null ? barcode.data.length + 4 : (dots / _dotsPerColumn).ceil();
    final String bar = '█' * (width > paper.columns ? paper.columns : width);
    final String text = barcode.data;
    return <String>[
      if (barcode.textPosition == BarcodeTextPosition.above ||
          barcode.textPosition == BarcodeTextPosition.both)
        _placeAligned(text, paper, barcode.align),
      _placeAligned(bar, paper, barcode.align),
      if (barcode.textPosition == BarcodeTextPosition.below ||
          barcode.textPosition == BarcodeTextPosition.both)
        _placeAligned(text, paper, barcode.align),
    ];
  }

  /// Il rettangolo di carta occupato da un'immagine, con la misura dentro.
  static List<String> _image(
    RasterImage image,
    PaperFormat paper,
    EscPosAlign align,
  ) {
    final int columns = (image.widthDots / _dotsPerColumn).ceil();
    final int width = columns > paper.columns ? paper.columns : columns;
    final int rows = (image.heightDots / _dotsPerRow).ceil();
    final String label = '${image.widthDots}×${image.heightDots} punti';

    final List<String> block = <String>[];
    for (int row = 0; row < rows; row++) {
      String line = '▒' * width;
      // L'etichetta va nella riga di mezzo, e solo se ci sta per intero: una
      // misura troncata a metà è peggio di una misura assente.
      if (row == rows ~/ 2 && label.length + 2 <= width) {
        final int start = (width - label.length) ~/ 2;
        line = line.substring(0, start) +
            label +
            line.substring(start + label.length);
      }
      block.add(_placeAligned(line, paper, align));
    }
    return block;
  }

  /// Posiziona [text] nella riga, tenendo conto dell'allineamento e del
  /// raddoppio di larghezza.
  static String _place(String text, PaperFormat paper, EscPosTextStyle style) {
    final int width = paper.columns ~/ style.widthMultiplier;
    final int free = width - text.length;
    if (free <= 0) return text;
    final int leading = switch (style.align) {
      EscPosAlign.left => 0,
      EscPosAlign.center => free ~/ 2,
      EscPosAlign.right => free,
    };
    return ' ' * (leading * style.widthMultiplier) + text;
  }

  /// Posiziona [text] senza passare da uno stile: è il caso di tutto ciò che
  /// non è testo, dove l'unica cosa che conta è da che parte sta.
  static String _placeAligned(
    String text,
    PaperFormat paper,
    EscPosAlign align,
  ) {
    final int free = paper.columns - text.length;
    if (free <= 0) return text;
    return switch (align) {
      EscPosAlign.left => text,
      EscPosAlign.center => ' ' * (free ~/ 2) + text,
      EscPosAlign.right => ' ' * free + text,
    };
  }
}
