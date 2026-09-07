# pos_printer_bridge

Dalla stampante termica a Dart: il flusso ESC/POS costruito in Dart puro, e — nel
prossimo passo — il canale nativo che lo porta fino all'hardware.

[![CI](https://github.com/zanzaro-mirco/pos_printer_bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/zanzaro-mirco/pos_printer_bridge/actions/workflows/ci.yml)

## Perché questo progetto

Gli altri tre progetti di questo portfolio calcolano, sincronizzano e mostrano. Nessuno
dei tre **tocca l'hardware**, che è invece il mestiere che faccio da dodici anni:
registratori di cassa, palmari da campo, terminali di pagamento, stampanti fiscali su
seriale.

Questo lo tocca, e chiude la filiera:

```
   receipt_engine           esc_pos_builder           pos_printer_bridge
   calcola lo scontrino ->  lo impagina in byte  ->   lo manda alla stampante
        pubblicato              qui sotto                 il passo dopo
```

## Cosa c'è oggi

**[`packages/esc_pos_builder`](packages/esc_pos_builder)** — Dart puro, zero dipendenze
oltre a `receipt_engine`. Prende uno scontrino e produce il flusso di byte che una
stampante termica sa stampare: impaginazione a colonne che rispetta la larghezza della
carta, tabelle dei caratteri, taglio e cassetto portavalori. Compreso `PaperPreview`, che
rende lo stesso documento come testo — così lo scontrino si guarda **senza avere una
stampante**.

Il README del pacchetto ha l'anteprima di uno scontrino vero, ed è verificata da un test:
se l'impaginazione cambia e il blocco no, la suite fallisce.

## Cosa arriva dopo

**`packages/pos_printer_bridge`** — il plugin Flutter con il canale verso il nativo. Un
contratto `PrinterTransport` in Dart, con due implementazioni sotto: TCP in Dart puro per
le stampanti di rete, e USB in Kotlin attraverso un `MethodChannel`. Gli stati che
arrivano *indietro* dalla stampante — carta finita, coperchio aperto — su un
`EventChannel`, perché non sono risposte a una chiamata ma eventi asincroni.

La divisione in due pacchetti non è burocrazia: un plugin dipende da Flutter, e chi
dipende dal plugin se lo porta dietro. Calcolare un flusso di byte non ha ragione di
richiedere un framework di interfaccia, e così `esc_pos_builder` resta usabile da un
servizio o da uno strumento a riga di comando.

## Provarlo

Non serve niente di collegato:

```bash
cd packages/esc_pos_builder
dart pub get
dart run example/esc_pos_builder_example.dart
```

Stampa a schermo lo scontrino come uscirebbe dalla carta, e in coda i primi byte del
flusso con la loro traduzione.

```bash
dart test
```

Le scelte di progetto, e le semplificazioni consapevoli, sono in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Stato

- [x] Il flusso ESC/POS da uno scontrino, con impaginazione e tabelle dei caratteri
- [x] Anteprima su carta, per guardare uno scontrino senza stampante
- [x] Documento di reso, con gli importi a segno invertito
- [ ] Il plugin: `MethodChannel` verso Kotlin, `EventChannel` per gli stati
- [ ] Trasporto TCP per le stampanti di rete
- [ ] Trasporto USB su Android
- [ ] Codici a barre (`GS k`) e logo raster
- [ ] Pubblicazione su pub.dev

## Licenza

MIT
