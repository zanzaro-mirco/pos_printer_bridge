# esc_pos_builder

Da uno scontrino ai byte che una stampante termica sa stampare.

**Dart puro**: niente Flutter, nessuna piattaforma, nessuna porta aperta. Il pacchetto
costruisce il flusso ESC/POS e si ferma lì — mandarlo alla stampante è un problema di
trasporto, e lo risolve [`pos_printer_bridge`](../../README.md).

```
   receipt_engine           esc_pos_builder           pos_printer_bridge
   calcola lo scontrino ->  lo impagina in byte  ->   lo manda alla stampante
```

## Com'è fatto

Tre strati, ognuno provabile da solo, e la dipendenza va in una direzione sola.

| Strato | Cosa sa | Cosa non sa |
|---|---|---|
| `EscPosCommand` | che esistono righe, avanzamenti, tagli e cassetti | come si scrivono in byte |
| `EscPosDocumentBuilder` | quanto è larga la carta | cosa sia uno scontrino |
| `ReceiptLayout` | cosa sia uno scontrino | come si scrivono i byte |
| `EscPosEncoder` | le sequenze di escape e le tabelle dei caratteri | tutto il resto |

`ReceiptLayout` è l'unico file che conosce `receipt_engine`, e c'è un test che lo verifica
leggendo i sorgenti: una regola di architettura che nessuno controlla dura fino al primo
che ha fretta.

## Come si usa

```dart
final Receipt receipt = (ReceiptBuilder(id: '0128')
      ..addLine(
        description: 'Caffè',
        unitPrice: const Money(120),
        vatRate: VatRate.reduced,
        quantity: 2,
      ))
    .close(paid: const Money(500));

const ReceiptLayout layout = ReceiptLayout(
  shop: ShopHeader(name: 'Bar Centrale', vatNumber: '01234567890'),
  paper: PaperFormat.mm58,
);

final EscPosDocument document = layout.render(receipt);

// Da guardare, senza stampante:
print(const PaperPreview().render(document, PaperFormat.mm58));

// Da mandare alla stampante:
final Uint8List bytes = const EscPosEncoder().encode(document);
```

L'esempio completo si lancia senza niente collegato:

```bash
dart run example/esc_pos_builder_example.dart
```

## Lo scontrino, come esce

Questa non è un'illustrazione: è l'anteprima dello scontrino di prova su cui gira il
confronto byte per byte, prodotta dallo stesso codice e verificata da un test — se
l'impaginazione cambia e questo blocco no, la suite fallisce.

```
               Trattoria da Mirco
          Via Roma 12 - 31100 Treviso
                Tel. 0422 123456
               P.IVA 01234567890
------------------------------------------------
Coperto                                     4,00
  2 x 2,00
Spaghetti alle vongole                     24,00
  2 x 12,00
Bistecca di manzo al kg                    12,80
  0,4 x 32,00
Caffè espresso                              2,40
  2 x 1,20
Vino della casa                            14,40
  Sconto soci -1,60
Acqua minerale naturale in bottiglia da un  2,00
  litro e mezzo
  2 x 1,00
------------------------------------------------
Sconto sul documento                       -3,00
TOTALE €                                   56,60
Contanti                                   60,00
Resto                                       3,40
------------------------------------------------
Aliq.         Imponibile     Imposta      Totale
10%                39,02        3,90       42,92
22%                11,21        2,47       13,68
------------------------------------------------
Documento                                   0042
Emesso il                       07/09/2026 20:15
Voci                                           6

              Grazie e arrivederci



-----------------------------------------------✂
```

Lo stesso scontrino su carta da 58 mm non è quello di sopra rimpicciolito: il riepilogo
IVA passa da quattro colonne incolonnate a due righe per aliquota, perché in 32 caratteri
le colonne non entrano.

## Le tre cose che rompono uno scontrino

**Le lettere accentate.** Una stampante termica non parla UTF-8: riceve un byte per
carattere e lo cerca in una tabella che tiene in memoria. Mandarle `caffè` in UTF-8
significa mandarle due byte per la `è`, e lei ne stampa due — di solito `caffÃ¨`. Il
sintomo si vede solo su carta. Le tabelle `PC437` e `PC858` di questo pacchetto sono
generate dai codec corrispondenti, non trascritte a mano: un byte sbagliato in una
tabella di 128 è un difetto che nessuna rilettura trova.

**L'euro.** `PC437` non ce l'ha. È esattamente la ragione per cui esiste `PC858`, ed è il
motivo per cui una stampante lasciata sulla tabella predefinita stampa `56,60 ?` sotto il
totale. La tabella predefinita di questo pacchetto è `PC858`.

**La larghezza.** `EscPosDocumentBuilder` garantisce che nessuna riga superi la carta,
qualunque cosa gli si passi: le descrizioni lunghe vanno a capo rientrate, e il testo a
doppia larghezza conta doppio — perché sulla carta occupa il doppio delle colonne.

## Test

```bash
dart test
```

| Test | Cosa verifica |
|---|---|
| `un documento minimo, scritto a mano e confrontato tutto` | Ogni byte accanto alla specifica: è l'unico confronto scritto a mano, ed è minuscolo apposta |
| **`è identico al flusso registrato, byte per byte`** | Lo scontrino di prova non cambia per sbaglio |
| **`riletto all'indietro dà esattamente le righe del documento`** | Un decodificatore che non condivide una riga con il codificatore rilegge il flusso: è il controllo indipendente |
| `le lettere accentate sono un byte, non due` | La UTF-8 non arriva alla stampante |
| `il simbolo dell'euro è quello di PC858` | E con PC437 lo stesso documento stampa `?` |
| `due righe uguali costano un cambio di stile solo` | Lo stile si manda quando cambia, non a ogni riga |
| `nessuna riga supera mai la larghezza della carta` | La garanzia dell'impaginazione, su entrambi i formati |
| `su 58 mm il riepilogo IVA passa a due righe per aliquota` | Il formato della carta è una scelta di impaginazione, non un numero |
| `lo sconto di documento è una voce a sé, non un prezzo ritoccato` | Il cliente può rifare il conto |
| `conta le voci, non la somma delle quantità` | Sommare pezzi e chilogrammi darebbe un numero senza significato |
| `solo l'impaginazione conosce receipt_engine` | La direzione della dipendenza, verificata sui sorgenti |
| `niente Flutter, da nessuna parte` | La promessa del pacchetto, scritta dove può fallire |

Dopo una modifica **voluta** all'impaginazione, il riferimento in byte si riscrive con:

```bash
dart run tool/record_golden.dart
```

È un comando separato di proposito: se fosse la suite a riscriverlo, il confronto non
fallirebbe mai e sarebbe una rete di sicurezza finta.

## Cosa non fa

- **Non parla con nessuna stampante.** Nessun socket, nessuna porta seriale, nessun
  permesso da chiedere. È un pacchetto di sola trasformazione, ed è per questo che la
  suite gira in millisecondi.
- **Niente codici a barre né immagini.** `GS k` e la stampa raster sono il passo
  successivo; oggi il pacchetto fa testo, e lo fa per intero.
- **Niente font B.** Il font piccolo cambia il numero di colonne e raddoppierebbe i casi
  da impaginare senza risolvere un problema che esiste adesso.
- **Nessuna lettura dallo stato della stampante.** Carta finita e coperchio aperto
  arrivano indietro dal dispositivo, e leggerli richiede un canale bidirezionale: è un
  problema di trasporto, quindi di `pos_printer_bridge`.

## Licenza

MIT
