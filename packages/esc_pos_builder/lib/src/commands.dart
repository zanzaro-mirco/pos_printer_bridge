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
