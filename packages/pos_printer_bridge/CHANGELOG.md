# Changelog

## 0.1.0

Prima versione.

- `PrinterTransport`: aprire, scrivere byte, chiudere, e un flusso di stati.
- `TcpPrinterTransport`: Dart puro verso una stampante di rete, porta 9100.
- `UsbPrinterTransport`: `MethodChannel` per le operazioni ed `EventChannel` per gli
  stati, verso il codice Kotlin.
- `PrinterStatus`: decodifica dei quattro byte dell’Automatic Status Back, con la
  verifica dei bit fissi. `PrinterStatusReader` accumula e riallinea i byte che arrivano
  a pezzi.
- `PrinterFailure`: gerarchia chiusa, con la distinzione fra ciò che vale la pena
  riprovare e ciò che no. Fuori dal pacchetto una `PlatformException` non circola.
- Solo Android. iOS non è dichiarato perché la stampa via USB non gli è aperta.
