import 'package:flutter_test/flutter_test.dart';
import 'package:pos_printer_bridge_example/main.dart';

/// La filiera intera, in un test solo.
///
/// Non c'è nessuna stampante e non ce n'è bisogno: quello che si verifica è
/// che i tre pacchetti si incastrino davvero — `receipt_engine` calcola,
/// `esc_pos_builder` impagina, e ciò che ne esce arriva a schermo. Se una
/// delle tre firme cambiasse, questo test non compilerebbe nemmeno.
void main() {
  testWidgets('l\'anteprima mostra lo scontrino calcolato davvero',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PrinterDemoApp());

    expect(find.textContaining('Bar Centrale'), findsWidgets);
    expect(find.textContaining('TOTALE'), findsOneWidget);
    // 2,40 di caffè + 1,50 di cornetto + 3,15 di spremuta scontata.
    expect(find.textContaining('7,05'), findsOneWidget);
  });

  testWidgets('l\'indirizzo si chiede solo al trasporto di rete',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PrinterDemoApp());

    expect(find.text('Indirizzo della stampante'), findsOneWidget);

    await tester.tap(find.text('USB'));
    await tester.pumpAndSettle();

    expect(find.text('Indirizzo della stampante'), findsNothing,
        reason: 'una stampante USB non ha un indirizzo da digitare');
  });
}
