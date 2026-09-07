import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_builder/esc_pos_builder.dart';

import '../test/helpers/reference_receipt.dart';

/// Riscrive il riferimento in byte dello scontrino di prova e stampa le
/// anteprime.
///
/// Va lanciato **a mano**, dopo una modifica voluta all'impaginazione:
///
/// ```
/// dart run tool/record_golden.dart
/// ```
///
/// È volutamente un comando separato dai test. Se fosse la suite a
/// riscriverlo, il confronto non fallirebbe mai e sarebbe una rete di
/// sicurezza finta — peggio di nessuna rete, perché ci si conta sopra.
void main() {
  final Uint8List bytes =
      const EscPosEncoder().encode(referenceLayout.render(referenceReceipt()));
  File('test/golden/scontrino_80mm.hex').writeAsStringSync(_asHex(bytes));
  stdout.writeln('Scritti ${bytes.length} byte in '
      'test/golden/scontrino_80mm.hex');

  const PaperPreview preview = PaperPreview();
  stdout
    ..writeln()
    ..writeln('--- 80 mm ---')
    ..writeln(preview.render(
        referenceLayout.render(referenceReceipt()), PaperFormat.mm80))
    ..writeln()
    ..writeln('--- 58 mm ---')
    ..writeln(preview.render(
      const ReceiptLayout(
        shop: ShopHeader(
          name: 'Trattoria da Mirco',
          addressLines: <String>['Via Roma 12 - 31100 Treviso'],
          vatNumber: '01234567890',
          footer: 'Grazie e arrivederci',
        ),
        paper: PaperFormat.mm58,
      ).render(referenceReceipt()),
      PaperFormat.mm58,
    ))
    ..writeln()
    ..writeln('--- reso, 80 mm ---')
    ..writeln(preview.render(
        referenceLayout.renderReturn(referenceReturn()), PaperFormat.mm80));
}

/// Il flusso in esadecimale, sedici byte per riga: un formato che si legge e
/// che in un `git diff` mostra dove è cambiato.
String _asHex(Uint8List bytes) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < bytes.length; i += 16) {
    final int end = i + 16 < bytes.length ? i + 16 : bytes.length;
    out.writeln(bytes
        .sublist(i, end)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' '));
  }
  return out.toString();
}
