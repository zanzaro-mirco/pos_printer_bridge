import 'dart:io';

import 'package:test/test.dart';

/// Una regola di architettura che nessuno controlla dura fino al primo che ha
/// fretta.
///
/// Il README dichiara che il pacchetto sa impaginare qualunque cosa e che
/// solo l'ultimo strato conosce `receipt_engine`. Questa è la stessa frase
/// scritta dove può fallire.
void main() {
  test('solo l\'impaginazione conosce receipt_engine', () {
    final List<String> offenders = <String>[];
    for (final File file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))) {
      final bool imports =
          file.readAsStringSync().contains("package:receipt_engine/");
      final bool allowed = file.path.endsWith('receipt_layout.dart');
      if (imports && !allowed) offenders.add(file.path);
    }

    expect(offenders, isEmpty,
        reason: 'Comandi, codificatore e anteprima non devono sapere cosa sia '
            'uno scontrino: senza questa direzione, il pacchetto smette di '
            'poter stampare qualcosa che non sia uno scontrino.');
  });

  test('niente Flutter, da nessuna parte', () {
    // È l'altra metà della promessa: questo pacchetto gira in un test, in un
    // servizio, in uno strumento a riga di comando. Aggiungere un import di
    // Flutter lo renderebbe utilizzabile solo dentro un'app.
    final List<String> offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .where((File f) => f.readAsStringSync().contains('package:flutter/'))
        .map((File f) => f.path)
        .toList();

    expect(offenders, isEmpty);
  });
}
