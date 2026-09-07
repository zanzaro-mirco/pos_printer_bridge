import 'package:receipt_engine/receipt_engine.dart';

import 'document.dart';
import 'paper.dart';
import 'text_style.dart';

/// Le righe di testa e di coda dello scontrino: chi emette il documento.
///
/// Stanno qui e non dentro `Receipt` perché non sono un fatto del calcolo: il
/// motore fiscale sa quanto si paga, non come si chiama il locale. Un
/// documento identico stampato da due punti vendita è lo stesso documento con
/// due intestazioni diverse.
class ShopHeader {
  /// Crea l'intestazione di un punto vendita.
  const ShopHeader({
    required this.name,
    this.addressLines = const <String>[],
    this.vatNumber,
    this.footer,
  });

  /// Ragione sociale o insegna, stampata grande in cima.
  final String name;

  /// Righe dell'indirizzo, stampate centrate sotto il nome.
  final List<String> addressLines;

  /// Partita IVA. Se assente, la riga non viene stampata.
  final String? vatNumber;

  /// Riga di commiato in fondo allo scontrino.
  final String? footer;
}

/// Impagina uno scontrino di `receipt_engine` su carta.
///
/// È l'unico file del pacchetto che conosce `receipt_engine`: sotto, comandi
/// e codificatore non sanno cosa sia uno scontrino e sanno impaginare
/// qualunque cosa. La dipendenza va in una direzione sola, e c'è un test che
/// lo verifica leggendo i sorgenti — perché una regola di architettura che
/// nessuno controlla dura fino al primo che ha fretta.
class ReceiptLayout {
  /// Crea un'impaginazione per un punto vendita e un formato di carta.
  const ReceiptLayout({
    required this.shop,
    this.paper = PaperFormat.mm80,
    this.openDrawerOnClose = false,
    this.cutAtEnd = true,
  });

  /// Sotto questa larghezza il riepilogo IVA non entra su una riga sola e
  /// passa a due righe per aliquota.
  static const int _narrowBelow = 40;

  static const MoneyFormatter _amount = ItalianMoneyFormatter(suffix: '');

  /// Chi emette il documento.
  final ShopHeader shop;

  /// Formato della carta.
  final PaperFormat paper;

  /// Se mandare l'impulso al cassetto in chiusura.
  final bool openDrawerOnClose;

  /// Se tagliare la carta in fondo.
  final bool cutAtEnd;

  /// Impagina uno scontrino di vendita.
  EscPosDocument render(Receipt receipt) {
    final EscPosDocumentBuilder sheet = EscPosDocumentBuilder(paper);
    _head(sheet);

    for (final ReceiptLine line in receipt.lines) {
      // Il totale stampato è quello di riga, **prima** che lo sconto di
      // documento venga ripartito: lo sconto compare come voce a sé, subito
      // sotto, ed è così che il cliente riesce a rifare il conto.
      // `netLineTotals` esiste per i resi, dove serve sapere quanto quella
      // riga ha davvero incassato, e usarlo qui farebbe stampare importi che
      // non tornano con il listino.
      sheet.columns(line.description, _amount.format(line.total));
      final String detail = _lineDetail(line);
      if (detail.isNotEmpty) sheet.line('  $detail');
    }

    sheet.separator();
    if (!receipt.documentDiscount.isZero) {
      sheet.columns(
          'Sconto sul documento', _amount.format(-receipt.documentDiscount));
    }
    sheet.columns('TOTALE €', _amount.format(receipt.total),
        style: EscPosTextStyle.emphasis);
    sheet.columns('Contanti', _amount.format(receipt.paid));
    sheet.columns('Resto', _amount.format(receipt.change));

    _vatSummary(sheet, receipt.vatSummary);
    _foot(sheet,
        id: receipt.id,
        issuedAt: receipt.issuedAt,
        lines: receipt.lines.length);
    return sheet.build();
  }

  /// Impagina un documento di reso.
  ///
  /// Gli importi restano negativi come li tiene `receipt_engine`, perché è
  /// così che scontrini e resi si sommano senza casi particolari. L'unica
  /// eccezione è la riga del rimborso, che è positiva: all'operatore serve
  /// sapere quanto tirare fuori dal cassetto, non con che segno lo registra
  /// la contabilità.
  EscPosDocument renderReturn(ReturnReceipt receipt) {
    final EscPosDocumentBuilder sheet = EscPosDocumentBuilder(paper);
    _head(sheet);
    sheet.line('DOCUMENTO DI RESO', style: EscPosTextStyle.emphasis);
    sheet.line('Riferito allo scontrino ${receipt.originalReceiptId}');
    sheet.separator();

    for (final ReturnLine line in receipt.lines) {
      sheet.columns(line.description, _amount.format(line.amount));
      sheet.line('  quantità resa: ${_quantity(line.quantity)}');
    }

    sheet.separator();
    sheet.columns('TOTALE €', _amount.format(receipt.total));
    sheet.columns('RIMBORSO €', _amount.format(receipt.refund),
        style: EscPosTextStyle.emphasis);

    _vatSummary(sheet, receipt.vatSummary);
    _foot(sheet,
        id: receipt.id, issuedAt: receipt.issuedAt, lines: receipt.lineCount);
    return sheet.build();
  }

  void _head(EscPosDocumentBuilder sheet) {
    sheet.line(shop.name, style: EscPosTextStyle.title);
    for (final String address in shop.addressLines) {
      sheet.line(address, style: EscPosTextStyle.centered);
    }
    final String? vat = shop.vatNumber;
    if (vat != null) {
      sheet.line('P.IVA $vat', style: EscPosTextStyle.centered);
    }
    sheet.separator();
  }

  void _foot(
    EscPosDocumentBuilder sheet, {
    required String id,
    required DateTime issuedAt,
    required int lines,
  }) {
    sheet.separator();
    sheet.columns('Documento', id);
    sheet.columns('Emesso il', _dateTime(issuedAt));
    // Il conto delle **voci**, non la somma delle quantità: sommare due
    // coperti, mezzo chilo di carne e una bottiglia darebbe un numero che non
    // significa niente, perché mette insieme pezzi e chilogrammi.
    sheet.columns('Voci', lines.toString());
    final String? footer = shop.footer;
    if (footer != null) {
      sheet.blank();
      sheet.line(footer, style: EscPosTextStyle.centered);
    }
    sheet.feed(3);
    if (openDrawerOnClose) sheet.openDrawer();
    if (cutAtEnd) sheet.cut();
  }

  /// Il riepilogo IVA, nella forma che la carta consente.
  ///
  /// Su 80 mm è una tabella incolonnata; su 58 mm le colonne non entrano e
  /// diventa due righe per aliquota. È il posto in cui il formato della carta
  /// smette di essere un numero e diventa una scelta di impaginazione.
  void _vatSummary(EscPosDocumentBuilder sheet, List<VatBreakdown> summary) {
    if (summary.isEmpty) return;
    sheet.separator();
    if (paper.columns >= _narrowBelow) {
      final List<int> widths = _summaryWidths(paper.columns);
      sheet.row(<String>['Aliq.', 'Imponibile', 'Imposta', 'Totale'], widths);
      for (final VatBreakdown vat in summary) {
        sheet.row(<String>[
          vat.rate.toString(),
          _amount.format(vat.taxable),
          _amount.format(vat.tax),
          _amount.format(vat.gross),
        ], widths);
      }
    } else {
      for (final VatBreakdown vat in summary) {
        sheet.columns('IVA ${vat.rate}', _amount.format(vat.gross));
        sheet.line('  imponibile ${_amount.format(vat.taxable)}'
            '  imposta ${_amount.format(vat.tax)}');
      }
    }
  }

  /// Le quattro colonne del riepilogo, sommate esattamente alla larghezza
  /// della carta: la prima prende l'avanzo della divisione.
  static List<int> _summaryWidths(int columns) {
    final int cell = columns ~/ 4;
    return <int>[columns - cell * 3, cell, cell, cell];
  }

  /// La riga di dettaglio sotto una voce: quantità per prezzo, e lo sconto se
  /// c'è. Vuota per una riga da un pezzo senza sconto, dove ripetere
  /// `1 x 2,00` accanto a `2,00` non aggiunge niente.
  static String _lineDetail(ReceiptLine line) {
    final List<String> parts = <String>[];
    if (line.quantity != 1) {
      parts.add(
          '${_quantity(line.quantity)} x ${_amount.format(line.unitPrice)}');
    }
    final Discount? discount = line.discount;
    if (discount != null) {
      final String label = discount.description.isEmpty
          ? discount.toString()
          : discount.description;
      parts.add('$label -${_amount.format(line.discountAmount)}');
    }
    return parts.join('  ');
  }

  /// Quantità senza decimali inutili: `2`, non `2.0`; `1,5` per la merce a
  /// peso, con la virgola come vuole l'italiano.
  static String _quantity(num quantity) {
    final String text = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toString();
    return text.replaceAll('.', ',');
  }

  /// Data e ora nel formato italiano. Scritto a mano invece che con `intl`:
  /// una dipendenza intera per due `padLeft` è un costo che questo pacchetto
  /// non ha ragione di far pagare a chi lo usa.
  static String _dateTime(DateTime moment) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(moment.day)}/${two(moment.month)}/${moment.year} '
        '${two(moment.hour)}:${two(moment.minute)}';
  }
}
