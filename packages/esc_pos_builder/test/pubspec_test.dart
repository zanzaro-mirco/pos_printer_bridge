import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Il `pubspec.yaml` è l'unico file del pacchetto che non viene letto da
/// nessun test: lo legge `pub`, e lo legge pub.dev con le sue regole di
/// punteggio. Un errore qui non rompe una funzione — rompe tutto insieme, e lo
/// scopre la pipeline.
///
/// È successo: accorciando la descrizione per rientrare nei 180 caratteri che
/// pub.dev vuole, ci è finito dentro un **due punti**. In YAML, dentro un
/// valore non quotato, i due punti aprono una mappa: `dart pub get` non è più
/// partito, e i tre lavori della pipeline sono diventati rossi tutti e tre per
/// un carattere.
///
/// Quel caso preciso **questi test non lo prendono**, ed è giusto dirlo: un
/// pubspec che non si legge ferma `pub` prima che la suite parta, e la
/// falsificazione lo conferma — rimettendo i due punti, `dart test` non arriva
/// nemmeno a eseguire questo file. Quello che i test aggiungono è il resto di
/// ciò che nessuno rilegge: la lunghezza che pub.dev misura, e la versione che
/// deve corrispondere a quella in testa al CHANGELOG.
void main() {
  final YamlMap pubspec =
      loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;

  test('nome e descrizione ci sono, e sono due stringhe', () {
    expect(pubspec['name'], 'esc_pos_builder');
    expect(pubspec['description'], isA<String>());
  });

  test('la descrizione sta fra 60 e 180 caratteri, come vuole pub.dev', () {
    // È una delle voci del punteggio con cui il pacchetto viene giudicato da
    // chiunque lo apra. Fuori da quella finestra si perdono punti, e il
    // controllo in pipeline arriva dopo aver pubblicato.
    final String description = pubspec['description'] as String;

    expect(description.length, greaterThanOrEqualTo(60));
    expect(description.length, lessThanOrEqualTo(180),
        reason: 'sono ${description.length} caratteri');
  });

  test('la versione del pubspec è quella in testa al CHANGELOG', () {
    // Pubblicare una versione che il CHANGELOG non racconta è il modo di
    // ritrovarsi su pub.dev con delle note di rilascio di due versioni prima.
    final String version = pubspec['version'] as String;
    final String first = File('CHANGELOG.md')
        .readAsLinesSync()
        .firstWhere((String line) => line.startsWith('## '));

    expect(first, '## $version');
  });
}
