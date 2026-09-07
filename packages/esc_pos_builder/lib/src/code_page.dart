/// Tabella dei caratteri della stampante.
///
/// È il punto in cui si rompono quasi tutti gli scontrini scritti in italiano.
/// Una stampante termica non parla UTF-8: ha in memoria una tabella di 256
/// caratteri e riceve **un byte per carattere**. Mandarle `caffè` codificato
/// in UTF-8 significa mandarle due byte per la `è`, e la stampante ne stampa
/// due — di solito `caffÃ¨`. Il sintomo si vede solo su carta, mai nei test di
/// chi ha scritto il codice pensando alle stringhe.
///
/// Le due tabelle qui sotto non sono trascritte a mano: sono generate dai
/// codec `cp437` e `cp858` e verificate carattere per carattere. Un byte
/// sbagliato in una tabella di 128 è un difetto che nessuna rilettura trova.
class CodePage {
  /// Crea una tabella. [upperHalf] contiene i 128 caratteri da 0x80 a 0xFF,
  /// in ordine.
  const CodePage({
    required this.name,
    required this.id,
    required this.upperHalf,
  }) : assert(upperHalf.length == 128, 'La metà alta ha 128 caratteri');

  /// PC437, la tabella storica del PC IBM e il valore predefinito di quasi
  /// tutte le stampanti appena accese.
  ///
  /// **Non contiene il simbolo dell'euro.** È esattamente la ragione per cui
  /// esiste [cp858], e il motivo per cui una stampante lasciata sulla tabella
  /// predefinita stampa `39,40 ?` sotto il totale.
  static const CodePage cp437 = CodePage(
    name: 'PC437',
    id: 0,
    upperHalf:
        'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ',
  );

  /// PC858: la stessa PC850 dell'Europa occidentale, con l'euro al posto
  /// della `ı` senza punto. È la tabella giusta per uno scontrino italiano.
  static const CodePage cp858 = CodePage(
    name: 'PC858',
    id: 19,
    upperHalf:
        'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜø£Ø×ƒáíóúñÑªº¿®¬½¼¡«»░▒▓│┤ÁÂÀ©╣║╗╝¢¥┐└┴┬├─┼ãÃ╚╔╩╦╠═╬¤ðÐÊËÈ€ÍÎÏ┘┌█▄¦Ì▀ÓßÔÒõÕµþÞÚÛÙýÝ¯´­±‗¾¶§÷¸°¨·¹³²■ ',
  );

  /// Nome della tabella, come lo chiama la specifica.
  final String name;

  /// Il byte `n` del comando `ESC t n` che la seleziona.
  final int id;

  /// I 128 caratteri da 0x80 a 0xFF, in ordine.
  final String upperHalf;

  /// Il byte con cui questa tabella rappresenta [char], oppure `null` se il
  /// carattere non c'è.
  ///
  /// Accetta una stringa di un solo carattere; con una più lunga guarda solo
  /// il primo.
  int? byteOf(String char) =>
      char.isEmpty ? null : _byteOfRune(char.runes.first);

  /// Vero se ogni carattere di [text] esiste in questa tabella.
  ///
  /// Serve a chi vuole accorgersene prima: [encode] non fallisce mai, perché
  /// una stampante che non stampa è peggio di una che stampa un punto
  /// interrogativo.
  bool canEncode(String text) =>
      text.runes.every((int rune) => _byteOfRune(rune) != null);

  /// Traduce [text] in byte, sostituendo con [replacement] ciò che non è
  /// rappresentabile.
  List<int> encode(String text, {int replacement = 0x3F}) => text.runes
      .map((int rune) => _byteOfRune(rune) ?? replacement)
      .toList(growable: false);

  int? _byteOfRune(int rune) {
    if (rune < 0x80) return rune;
    for (int i = 0; i < 128; i++) {
      if (upperHalf.codeUnitAt(i) == rune) return 0x80 + i;
    }
    return null;
  }

  @override
  String toString() => '$name (ESC t $id)';
}
