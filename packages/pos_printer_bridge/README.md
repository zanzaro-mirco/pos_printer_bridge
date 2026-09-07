# pos_printer_bridge

Manda byte a una stampante termica, da Flutter. Due trasporti, un contratto solo.

| Trasporto | Dove vive | Come si mette alla prova |
|---|---|---|
| `TcpPrinterTransport` | Dart puro, `Socket` | contro un vero server in ascolto su `localhost` |
| `UsbPrinterTransport` | Kotlin, `UsbManager`, via platform channel | con i canali sostituiti nei test, e l'APK compilato in pipeline |

Il contratto conosce **solo byte**: non sa cosa trasporta, come un cavo seriale non sa
cosa sia uno scontrino. A comporre i byte pensa
[`esc_pos_builder`](../esc_pos_builder), che sta apposta in un altro pacchetto — un
servizio che genera scontrini per una stampante di rete non ha ragione di installare
Flutter.

## Come si usa

```dart
final PrinterTransport printer = TcpPrinterTransport(host: '192.168.1.50');
// oppure: UsbPrinterTransport()

await printer.open();
printer.status.listen((PrinterStatus s) => print(s));   // «carta finita», mentre succede
await printer.write(bytes);
await printer.close();
```

Passare da un trasporto all'altro non cambia una riga di chi stampa. L'applicazione di
esempio lo fa con un interruttore a schermo.

## Lo stato non è una risposta

Una stampante termica non risponde «ok» a *stampa*. Manda **quattro byte di stato quando
qualcosa cambia** — la carta finisce, il coperchio si apre, la lama si inceppa — e possono
arrivare mentre non le si sta chiedendo niente.

È per questo che dall'altra parte c'è un `Stream` e non un `Future`, ed è la differenza fra
un'applicazione che dice «carta finita» mentre succede e una che se ne accorge alla stampa
dopo, con un cliente davanti.

Gli stati vanno accesi, altrimenti la stampante resta muta:

```dart
await printer.write(Uint8List.fromList(PrinterStatus.enableAutomaticStatusBack));
```

I byte non arrivano a gruppi di quattro: arrivano come li consegna il sistema operativo.
`PrinterStatusReader` accumula, e quando i byte in testa non hanno la firma di uno stato ne
scarta **uno solo** e riprova — buttarli tutti e quattro perderebbe uno stato valido che
comincia un byte più in là.

## Cosa fa il codice Kotlin, e cosa non fa

**Sposta byte, e basta.** Trova il dispositivo, chiede il permesso, apre gli endpoint,
scrive e legge. Non decodifica uno stato, non compone un comando, non decide quando
riprovare: tutta l'interpretazione sta dalla parte Dart.

Non è eleganza, è dove si possono mettere le cose alla prova. Il codice nativo è la parte
che costa di più verificare — serve un dispositivo, un emulatore non basta, e un test JVM
su `UsbManager` finisce per verificare i finti che ci si è scritti. Quindi il nativo si
tiene sottile fino a essere quasi ovvio, e **tutto ciò che ha una logica dentro attraversa
il canale**. La decodifica degli stati è la stessa per i due trasporti: byte da un endpoint
o da un socket, sono gli stessi byte.

Le tre cose che su Android USB si sbagliano, e che qui sono scritte con il perché accanto:

- **`FLAG_MUTABLE` sul `PendingIntent`** del permesso. È il sistema a scrivere dentro
  l'intent quale dispositivo è stato autorizzato, e su un intent immutabile non può farlo:
  è l'errore che da Android 12 fa arrivare sempre «negato».
- **`RECEIVER_NOT_EXPORTED`** da Android 13, altrimenti il sistema chiude l'applicazione.
- **La scrittura è un ciclo.** `bulkTransfer` scrive fino alla dimensione del pacchetto e
  dice quanto ha scritto; uno scontrino è quasi sempre più lungo, quindi il ciclo non è
  prudenza, è la condizione normale.

E la stampante si cerca per **classe 7 dello standard USB**, non per un elenco di
identificativi di fornitore: un elenco va aggiornato a ogni modello nuovo, e sul campo il
modello nuovo arriva sempre di sabato.

## Gli errori sono di dominio

Fuori da questo pacchetto una `PlatformException` non esiste: c'è una gerarchia chiusa, e
la distinzione che serve a chi chiama non è quale errore sia ma se **valga la pena
riprovare**.

| Errore | Riprovare |
|---|---|
| `PrinterUnreachable` — non risponde | sì |
| `PrinterNotFound` — non c'è proprio | sì |
| `PrinterWriteFailed` — partita a metà | sì |
| `PrinterPermissionDenied` — l'utente ha detto no | **no** |
| `PrinterNotOpen` — errore di chi programma | **no** |

`PrinterPermissionDenied` non è transitorio di proposito: riprovare significherebbe
rimostrare la stessa finestra a chi l'ha appena chiusa, ed è il modo più rapido per farsi
disinstallare.

## Provarlo

```bash
flutter test
```

35 test, e nessuno ha bisogno di una stampante.

```bash
cd example
flutter run
```

L'esempio è la filiera intera: `receipt_engine` calcola lo scontrino, `esc_pos_builder` lo
impagina, questo pacchetto lo manda. Con il trasporto di rete funziona contro qualunque
cosa sia in ascolto sulla 9100 — anche un `nc -l 9100` sul computer accanto.

| Test | Cosa verifica |
|---|---|
| **`quello che si scrive è quello che la stampante riceve`** | Un vero socket contro un vero `ServerSocket`: l'unica cosa finta è chi sta all'altro capo |
| **`quattro byte mandati dalla stampante diventano uno stato`** | Nessuno li ha chiesti: è il punto |
| `uno stato spezzato in due pacchetti si ricompone` | Sul filo i byte arrivano come capita |
| `un byte spaiato in testa viene scartato, non lo stato che segue` | Il riallineamento scarta uno, non quattro |
| `i bit fissi non tornano: non è uno stato` | La difesa contro il decodificare rumore in qualcosa di plausibile |
| **`open, write e close arrivano dall'altra parte`** | La chiamata attraversa davvero il canale, con il nome giusto |
| `i byte passano come Uint8List, non come lista di interi` | Il canale li consegna come `ByteArray`, senza convertirli uno per uno |
| `fuori di qui non esistono PlatformException` | Chi stampa non sa che sotto c'è Kotlin |
| `un canale non registrato lo dice invece di lasciare un mistero` | `MissingPluginException` è l'errore più difficile da capire di un plugin |
| `l'anteprima mostra lo scontrino calcolato davvero` | I tre pacchetti si incastrano: se una firma cambia, non compila |

Il codice Kotlin non ha test suoi, e ne ha uno solo indiretto: **la pipeline compila
l'APK dell'esempio**, quindi un errore di compilazione nel nativo fa fallire la build. È
poco, ed è dichiarato — è anche la ragione per cui il nativo contiene così poco.

## Cosa non fa

- **Niente iOS.** La stampa via USB su iOS non è aperta alle applicazioni di terze parti:
  servirebbe l'MFi, che è un programma commerciale di Apple e non una libreria. Il
  trasporto di rete funzionerebbe, ma un plugin che dichiara iOS e ne supporta metà è
  peggio di uno che non lo dichiara.
- **Niente Bluetooth.** È il terzo trasporto naturale ed entra dallo stesso contratto:
  `PrinterTransport` non cambia di una riga.
- **Nessuna scoperta delle stampanti di rete.** L'indirizzo si digita. Cercarle con mDNS è
  lo stesso problema già risolto in `pos_sync`, e va portato qui quando serve, non prima.
- **Una stampante per volta.** Un locale con due stampanti — scontrini al banco, comande in
  cucina — vuole due canali aperti insieme, e il lato Kotlin oggi ne tiene uno.
- **Nessuna coda.** Se la stampante è occupata, `write` fallisce e la decisione torna a chi
  chiama. Una coda con ritentativi è il livello sopra, e in questo portfolio esiste già:
  è l'outbox di `pos_sync`.

## Licenza

MIT
