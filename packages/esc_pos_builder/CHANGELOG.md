# Changelog

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
