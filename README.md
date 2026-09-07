# pos_printer_bridge

Dalla stampante termica a Dart: il flusso ESC/POS costruito in Dart puro, e il canale
nativo che lo porta fino all'hardware.

[![CI](https://github.com/zanzaro-mirco/pos_printer_bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/zanzaro-mirco/pos_printer_bridge/actions/workflows/ci.yml)

## Perché questo progetto

Gli altri tre progetti di questo portfolio calcolano, sincronizzano e mostrano. Nessuno dei
tre **tocca l'hardware**, che è invece il mestiere che faccio da dodici anni: registratori
di cassa, palmari da campo, terminali di pagamento, stampanti fiscali su seriale.

Questo lo tocca, e chiude la filiera:

```
   receipt_engine           esc_pos_builder           pos_printer_bridge
   calcola lo scontrino ->  lo impagina in byte  ->   lo manda alla stampante
        pubblicato               qui sotto                  qui sotto
```

## I due pacchetti

**[`packages/esc_pos_builder`](packages/esc_pos_builder)** — Dart puro, senza Flutter.
Prende uno scontrino e produce i byte che una stampante termica sa stampare:
impaginazione a colonne che rispetta la larghezza della carta, tabelle dei caratteri,
taglio e cassetto portavalori. Compreso `PaperPreview`, che rende lo stesso documento come
testo — così lo scontrino si guarda **senza avere una stampante**.

**[`packages/pos_printer_bridge`](packages/pos_printer_bridge)** — il plugin Flutter. Un
contratto `PrinterTransport` che conosce **solo byte**, con due implementazioni sotto: TCP
in Dart puro per le stampanti di rete, e USB in Kotlin attraverso un `MethodChannel`. Gli
stati che arrivano *indietro* dalla stampante — carta finita, coperchio aperto — su un
`EventChannel`, perché non sono risposte a una chiamata ma eventi asincroni.

La divisione in due pacchetti non è burocrazia: un plugin dipende da Flutter, e chi dipende
dal plugin se lo porta dietro. Calcolare un flusso di byte non ha ragione di richiedere un
framework di interfaccia, e così `esc_pos_builder` resta usabile da un servizio o da uno
strumento a riga di comando.

E il plugin, a sua volta, **non dipende dal costruttore di byte**: un trasporto che conosce
il formato di ciò che trasporta non può più trasportare altro. I tre pacchetti si
incontrano nell'applicazione di esempio, non fra loro.

## Provarlo

Senza niente di collegato:

```bash
cd packages/esc_pos_builder
dart pub get
dart run example/esc_pos_builder_example.dart
```

Stampa a schermo lo scontrino come uscirebbe dalla carta, e in coda i primi byte del flusso
con la loro traduzione.

L'applicazione di esempio del plugin è la filiera intera, con un interruttore fra rete e
USB:

```bash
cd packages/pos_printer_bridge/example
flutter run
```

Con il trasporto di rete funziona contro qualunque cosa sia in ascolto sulla porta 9100 —
anche un `nc -l 9100` sul computer accanto, che stampa a schermo i byte che arrivano.

## Test

94 test, e **nessuno ha bisogno di una stampante**.

| Dove | Cosa | Come |
|---|---|---|
| `esc_pos_builder` | 57 | confronto byte per byte, e un decodificatore che rilegge il flusso all'indietro |
| `pos_printer_bridge` | 35 | un vero socket contro un vero `ServerSocket`, e il confine con Kotlin con i canali sostituiti |
| esempio del plugin | 2 | i tre pacchetti si incastrano davvero |

Il codice Kotlin ha una verifica sola: **la pipeline compila l'APK dell'esempio**. È poco,
ed è dichiarato — ed è anche la ragione per cui nel nativo c'è così poco: sposta byte, e
tutta l'interpretazione sta in Dart, dove si può mettere alla prova.

Le scelte di progetto, e le semplificazioni consapevoli, sono in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Stato

- [x] Il flusso ESC/POS da uno scontrino, con impaginazione e tabelle dei caratteri
- [x] Anteprima su carta, per guardare uno scontrino senza stampante
- [x] Documento di reso, con gli importi a segno invertito
- [x] Il contratto `PrinterTransport`, con gli errori come gerarchia chiusa
- [x] Trasporto TCP per le stampanti di rete
- [x] Trasporto USB su Android: `MethodChannel` e `EventChannel` verso Kotlin
- [x] Stati della stampante decodificati, uguali per i due trasporti
- [ ] La prova su una stampante vera
- [ ] Codici a barre (`GS k`) e logo raster
- [ ] Trasporto Bluetooth, dallo stesso contratto
- [ ] Pubblicazione su pub.dev

## Licenza

MIT
