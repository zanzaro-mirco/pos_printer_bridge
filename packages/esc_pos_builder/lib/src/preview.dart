import 'commands.dart';
import 'document.dart';
import 'paper.dart';
import 'text_style.dart';

/// Rende un documento come testo, così com'è disposto sulla carta.
///
/// Serve a vedere uno scontrino senza avere una stampante — nei test, nel
/// README, in una revisione del codice. Un pacchetto che si può solo provare
/// collegando l'hardware è un pacchetto che nessuno prova.
///
/// **È un'approssimazione, e in un punto solo:** l'anteprima è monospaziata,
/// quindi un carattere a doppia larghezza occupa due colonne sulla carta e
/// una qui. La *posizione* del testo resta quella giusta, la lunghezza no.
class PaperPreview {
  /// Crea un'anteprima. Con [showCommands] a falso restano solo le righe
  /// stampate, senza i segni per taglio e cassetto.
  const PaperPreview({this.showCommands = true});

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
      }
    }
    return lines.join('\n');
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
}
