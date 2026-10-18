# Changelog

## 0.2.0

Codici a barre e immagini: le due cose che una stampante termica fa e che non sono
testo.

- `PrintBarcode` con quattro sistemi — EAN13, EAN8, CODE39, CODE128 — e il dato
  controllato nel costruttore contro le regole di ognuno. La cifra di controllo di un
  EAN, quando arriva già scritta, viene verificata: il riferimento ESC/POS dice che la
  stampante non lo fa.
- `PrintImage` e `RasterImage`, con `RasterImage.fromRows` per disegnare un logo come
  testo. Il pacchetto non decodifica immagini: resta Dart puro senza dipendenze.
- Il logo passa dalla funzione grafica `GS ( L` / `GS 8 L`, non da `GS v 0`, che il
  riferimento di Epson marca come obsoleto. Un'immagine grande passa da sola alla forma
  con la lunghezza su quattro byte.
- `PaperFormat.dots`: la larghezza della carta in punti, con cui
  `EscPosDocumentBuilder` rifiuta un'immagine o un EAN più larghi della carta, invece di
  lasciarli tagliare dalla stampante senza un errore.
- `PaperPreview` mostra la barra in scala per EAN13 ed EAN8, e di un'immagine il
  rettangolo di carta che occupa.

## 0.1.0

Prima versione.

- `EscPosCommand`, gerarchia chiusa: righe di testo, avanzamento, taglio, cassetto.
- `EscPosDocumentBuilder` con l'aritmetica delle colonne in un posto solo, e la garanzia
  che nessuna riga superi la larghezza della carta.
- `EscPosEncoder`: il flusso di byte, con i cambi di stile mandati solo quando lo stile
  cambia davvero.
- `CodePage` con `PC437` e `PC858`, generate dai codec corrispondenti. `PC858` è la
  predefinita perché è l'unica delle due che ha il simbolo dell'euro.
- `ReceiptLayout`: da uno `Receipt` o da un `ReturnReceipt` di `receipt_engine` alla
  carta, su 80 o 58 mm.
- `PaperPreview`: lo scontrino come testo, per guardarlo senza avere una stampante.
