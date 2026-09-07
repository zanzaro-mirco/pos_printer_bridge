import 'dart:io';

import 'package:esc_pos_builder/esc_pos_builder.dart';
import 'package:test/test.dart';

import 'helpers/reference_receipt.dart';

/// Il README mostra uno scontrino impaginato. Un'immagine del genere invecchia
/// il giorno in cui l'impaginazione cambia, e diventa una bugia scritta in
/// prima pagina: chi legge crede di vedere cosa fa il pacchetto, e vede cosa
/// faceva.
///
/// Questo la tiene onesta.
void main() {
  test('l\'anteprima nel README è quella che il pacchetto produce davvero', () {
    final String readme = File('README.md').readAsStringSync();
    final String preview = const PaperPreview().render(
      referenceLayout.render(referenceReceipt()),
      PaperFormat.mm80,
    );

    expect(readme.replaceAll('\r\n', '\n'), contains(preview),
        reason: 'Rigenera il blocco con: dart run tool/record_golden.dart');
  });
}
