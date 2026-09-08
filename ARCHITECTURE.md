# Architettura e scelte di progetto

Il progetto è un **monorepo**, e lo è dal primo giorno per una ragione precisa: il pezzo
che sta in piedi da solo — trasformare uno scontrino in byte — non deve dipendere da
Flutter solo perché un giorno gli starà accanto un plugin che ne ha bisogno.

```
packages/
  esc_pos_builder/     Dart puro: dallo scontrino ai byte
  pos_printer_bridge/  il plugin: dai byte alla stampante
```

## Perché due pacchetti e non uno

Un plugin Flutter dipende da Flutter, e chiunque dipenda dal plugin se lo porta dietro.
Il calcolo di un flusso ESC/POS non ha ragione di farlo: gira in un test, in un servizio,
in uno strumento a riga di comando. Tenerli separati costa un `pubspec.yaml` in più e
restituisce un pacchetto che un backend può usare per generare uno scontrino da mandare a
una stampante di rete, senza installare un framework di interfaccia.

C'è un test che lo verifica invece di scriverlo e basta: `layering_test.dart` legge i
sorgenti di `lib/` e fallisce se qualcuno importa `package:flutter/` — o se un file che
non sia l'impaginazione importa `receipt_engine`.

## Tre strati, e la direzione della dipendenza

```
ReceiptLayout      sa cosa sia uno scontrino, non sa cosa sia un byte
      |
      v
EscPosDocument     righe, avanzamenti, tagli: cosa fare, non come si scrive
      |
      v
EscPosEncoder      sa le sequenze di escape, non sa cosa sia uno scontrino
```

Il documento **non è una stringa con dentro le sequenze di escape**. È una lista di
comandi tipizzati, e questa è la scelta da cui discende tutto il resto: un documento fatto
di comandi si può leggere, mettere alla prova, contare e — soprattutto — rendere in
anteprima. Un blocco di byte si può solo mandare a una stampante e guardare cosa esce.

La gerarchia dei comandi è `sealed`: il codificatore la percorre con uno `switch`
esaustivo, e aggiungere un comando domani fa fallire la compilazione nel punto esatto in
cui va gestito, invece di cadere in un ramo `default` che non stampa niente.

## Lo stato di una stampante, e perché lo stile sta sulla riga

ESC/POS è un protocollo **con stato**: `ESC ! 8` accende il grassetto e ci resta finché
qualcuno non lo spegne. Il difetto classico di questi tracciati è una riga in grassetto
che ne lascia dieci in grassetto sotto di sé, e nessuno se ne accorge finché non lo vede
su carta.

Qui lo stile è un attributo della **riga**, non un comando a sé: dichiararlo riga per
riga rende impossibile dimenticare di riportarlo indietro. A ricostruire lo stato è il
codificatore, che tiene traccia di ciò che ha già mandato ed emette un cambio **solo
quando lo stile cambia davvero**.

Non è un'ottimizzazione gratuita. Su una seriale a 9600 baud tre byte per riga sono
decine di byte per scontrino, e su una stampante da banco che ne emette centinaia all'ora
la differenza si sente al tatto. Il costo è tenere uno stato mentre si scorre il
documento, ed è tutto lì.

E il flusso comincia **sempre** con `ESC @`: la stampante può essere stata lasciata in
qualunque stato dal documento precedente, magari da un altro programma. Dare per buono lo
stato di accensione è il modo di ottenere uno scontrino in grassetto ogni tanto, senza
capire perché.

## Le tabelle dei caratteri, generate e non trascritte

È il punto in cui si rompono quasi tutti gli scontrini scritti in italiano. Una stampante
termica non parla UTF-8: riceve **un byte per carattere** e lo cerca in una tabella che
tiene in memoria. Mandarle `caffè` in UTF-8 significa mandarle due byte per la `è`, e lei
ne stampa due.

Le due tabelle — `PC437` e `PC858` — sono **generate dai codec corrispondenti** e
incollate come costanti, non trascritte a mano guardando una specifica. Un byte sbagliato
in una tabella di 128 è un difetto che nessuna rilettura trova e che si manifesta su un
carattere solo, magari mesi dopo.

Due dei loro caratteri sono **invisibili nel sorgente**: lo spazio unificatore a `0xFF` e
il trattino condizionale a `0xF0`. Un editor distratto o un formattatore possono
mangiarseli senza che niente lo segnali, e la tabella diventerebbe lunga 127 caratteri con
tutto ciò che segue spostato di uno. Per questo c'è un test che fissa proprio quelle
posizioni: sono le uniche righe di codice del progetto che non si possono controllare
guardandole.

**`PC858` è la tabella predefinita, e la ragione è una sola: l'euro.** `PC437` non ce
l'ha — `PC858` esiste appunto perché mette il simbolo dell'euro al posto di un carattere
che a nessuno serviva. Una stampante lasciata sulla tabella predefinita di fabbrica
stampa `56,60 ?` sotto il totale, ed è un difetto che si vede solo su carta.

Ciò che una tabella non contiene diventa un punto interrogativo, **non un errore**: una
stampante che non stampa è peggio di una che stampa `?`, perché lo scontrino va
consegnato comunque. Chi vuole accorgersene prima ha `canEncode`.

## La larghezza della carta è un parametro, non una costante

`PaperFormat` porta con sé le colonne, e tutta l'aritmetica sta in
`EscPosDocumentBuilder`. La garanzia che offre è una sola frase: **nessuna riga prodotta
supera la larghezza della carta**, qualunque cosa gli si passi.

Ne discendono tre comportamenti che sembrano dettagli e non lo sono:

- **Le descrizioni lunghe vanno a capo rientrate**, e l'importo resta sulla prima riga
  dove chi legge lo cerca.
- **Una parola più lunga della riga viene spezzata.** La stampante andrebbe comunque a
  capo per conto suo, e nel punto sbagliato: meglio decidere qui dove.
- **Il testo a doppia larghezza conta doppio.** Occupa due colonne per carattere, quindi
  le colonne utilizzabili si chiedono allo stile e non alla carta. È la ragione per cui
  l'intestazione è a doppia *altezza* e non a doppia larghezza: su 58 mm resterebbero
  sedici colonne, e un'insegna come «Ristorante Al Vecchio Mulino» finirebbe su tre righe.

Un importo più largo della carta è invece un **errore di chi chiama**, non un caso da
impaginare: troncarlo in silenzio produrrebbe uno scontrino con un totale falso.

E la carta stretta non è la carta larga rimpicciolita: sotto le 40 colonne il riepilogo
IVA smette di essere una tabella e diventa due righe per aliquota. È il punto in cui il
formato della carta smette di essere un numero e diventa una scelta di impaginazione.

## Cosa sa il motore fiscale e cosa sa la carta

`receipt_engine` sa quanto si paga. Non sa come si chiama il locale, e non deve saperlo:
lo stesso documento stampato da due punti vendita è lo stesso documento con due
intestazioni diverse. Per questo `ShopHeader` sta qui e non lì.

Due decisioni di impaginazione che vengono dal dominio e non dall'estetica:

- **I totali di riga stampati sono quelli del listino**, prima che lo sconto di documento
  venga ripartito; lo sconto compare come voce a sé. `receipt_engine` espone anche
  `netLineTotals`, cioè quanto ogni riga ha davvero incassato, ma quello serve ai resi:
  stamparlo qui produrrebbe importi che non tornano con il prezzo esposto, e il cliente
  non riuscirebbe più a rifare il conto.
- **In fondo si conta il numero di voci, non la somma delle quantità.** Sommare due
  coperti, quattro etti di carne e una bottiglia darebbe `7,4`: un numero che non
  significa niente, perché mette insieme pezzi e chilogrammi.

Sul documento di reso gli importi **restano negativi**, come li tiene `receipt_engine`:
è così che scontrini e resi si sommano senza casi particolari. L'unica eccezione è la riga
del rimborso, che è positiva — all'operatore serve sapere quanto tirare fuori dal
cassetto, non con che segno lo registra la contabilità.

## Come si mette alla prova qualcosa che finisce in byte

Il criterio di questa voce era «un test che confronta il flusso di byte con un atteso,
byte per byte». Preso alla lettera ha una trappola: **un'attesa costruita concatenando gli
stessi byte che produce il codice in prova non dimostra niente**, perché sbaglia insieme a
lui. E su un documento intero, scritta a mano, sarebbe illeggibile.

Tre controlli, che rispondono a domande diverse:

1. **Un documento minimo, scritto a mano.** Due comandi, sedici byte, ognuno con accanto
   la riga della specifica che lo giustifica. È l'unico posto dove il flusso si può
   leggere byte per byte, ed è minuscolo apposta.
2. **Il riferimento registrato**, `test/golden/scontrino_80mm.hex`. Dice che lo scontrino
   di prova non cambia per sbaglio. Si riscrive con `dart run tool/record_golden.dart`,
   che è un comando **separato dalla suite**: se fosse la suite a riscriverlo, il confronto
   non fallirebbe mai e sarebbe una rete di sicurezza finta.
3. **La rilettura all'indietro.** Un decodificatore nei test percorre il flusso al
   contrario e ricostruisce le righe; non condivide una riga di codice con il
   codificatore. Rifiuta le sequenze che non conosce, quindi arrivare in fondo è già
   un'asserzione: se il codificatore infilasse un byte di troppo, qui diventerebbe un
   errore invece di passare inosservato.

Lo scontrino di riferimento non è uno scontrino qualunque: contiene di proposito due
aliquote, uno sconto di riga, uno sconto di documento, una quantità frazionaria, una
descrizione più lunga della carta, una lettera accentata e il simbolo dell'euro. Ognuna di
quelle cose è un modo diverso di rompersi.

**Le prove sono state falsificate**, non solo scritte:

| Modifica | Cosa deve diventare rosso | Esito |
|---|---|---|
| Mandare il cambio di stile a ogni riga | i tre test sullo stile, e il riferimento | 4 rossi |
| Codificare il testo in UTF-8 invece che con la tabella | accenti, euro, tabella dichiarata | 6 rossi |

## Dove ho consapevolmente semplificato

- **Niente codici a barre né immagini.** `GS k` per i codici a barre e la stampa raster
  per i loghi sono i due pezzi che mancano perché il pacchetto copra uno scontrino
  commerciale completo. Sono aggiunte, non modifiche: entrano come nuovi comandi nella
  gerarchia chiusa, e il compilatore indicherà da solo dove gestirli.
- **Niente font B.** Il font piccolo cambia il numero di colonne, quindi raddoppierebbe i
  casi da impaginare e i formati da provare. Vale quando esiste una carta su cui il font A
  non basta.
- **Nessuna lettura dallo stato della stampante.** Carta finita, coperchio aperto e
  cassetto rimasto aperto arrivano *indietro* dal dispositivo, e leggerli richiede un
  canale bidirezionale: è un problema di trasporto, e quindi del plugin.
- **L'anteprima è monospaziata**, quindi un carattere a doppia larghezza occupa due
  colonne sulla carta e una nell'anteprima: la posizione del testo è giusta, la lunghezza
  no. Renderla fedele significherebbe scrivere un rasterizzatore per guardare uno
  scontrino di prova.
- **Nessuna gestione della numerazione progressiva.** L'identificativo del documento
  arriva da fuori, come in `receipt_engine`: è materia di normativa e di registratore di
  cassa, non di chi impagina.
- **Una tabella dei caratteri per documento.** ESC/POS permette di cambiarla in mezzo al
  flusso, e servirebbe per stampare cirillico e greco sullo stesso scontrino. Non è un
  problema che esiste in un locale italiano.

---

# Il plugin: dai byte alla stampante

## Il contratto conosce solo byte

`PrinterTransport` sa aprire, scrivere byte, chiudere, e ha un flusso di stati. **Non sa
cosa trasporta**, come un cavo seriale non sa cosa sia uno scontrino.

È da questa povertà che discende la cosa utile: due implementazioni molto diverse — un
socket in Dart puro e un canale verso Kotlin — sono intercambiabili, e chi stampa non
cambia una riga passando dall'una all'altra. Nell'applicazione di esempio è letteralmente
un interruttore a schermo.

È anche la ragione per cui il plugin **non dipende da `esc_pos_builder`**. Sarebbe stato
comodo offrire un `stampa(EscPosDocument)`, e sarebbe stato sbagliato: un trasporto che
conosce il formato di ciò che trasporta non può più trasportare altro, e in cambio non si
guadagna niente che l'applicazione non possa fare in due righe. I tre pacchetti si
incontrano nell'esempio, non fra loro.

## Il nativo sposta byte, e basta

Il codice Kotlin trova il dispositivo, chiede il permesso, apre gli endpoint, scrive e
legge. **Non decodifica uno stato, non compone un comando, non decide quando riprovare.**

Non è eleganza, è dove si possono mettere le cose alla prova. Il nativo è la parte che
costa di più verificare: serve un dispositivo, un emulatore non basta — non ha una porta
USB host — e un test JVM su `UsbManager` finisce per verificare i finti che ci si è
scritti. Quindi il nativo si tiene sottile fino a essere quasi ovvio, e tutto ciò che ha
una logica dentro attraversa il canale e viene provato in Dart.

La prova che ne discende: **la decodifica degli stati è una sola per i due trasporti.** I
byte arrivano da un endpoint USB o da un socket, ma sono gli stessi byte, e li legge lo
stesso codice — che ha i suoi test e non ha bisogno di hardware.

## Lo stato non è una risposta

Una stampante termica non risponde «ok» a *stampa*. Manda quattro byte quando qualcosa
cambia — la carta finisce, il coperchio si apre, la lama si inceppa — e possono arrivare
mentre non le si sta chiedendo niente.

Per questo dall'altra parte c'è un `Stream` e non un `Future`, e per questo sul canale
nativo c'è un `EventChannel` accanto al `MethodChannel`: sono due direzioni diverse, non
due modi di fare la stessa cosa. È la differenza fra un'applicazione che dice «carta
finita» mentre succede e una che se ne accorge alla stampa dopo, con un cliente davanti.

**La decodifica verifica i bit fissi.** La specifica Epson dell'Automatic Status Back dà a
ognuno dei quattro byte la stessa firma: i due bit più bassi a zero, il quarto a uno, il
più alto a zero. Controllarla è l'unica difesa contro il decodificare rumore in qualcosa
che *sembra* uno stato plausibile — e, va detto, anche contro l'aver capito male la
specifica: i costruttori non sono tutti uguali su tutto, e prima di fidarsi su un modello
specifico vale la pena confrontare con il suo manuale.

E il riallineamento scarta **un byte solo**, non quattro: buttare l'intero gruppo
perderebbe uno stato valido che comincia un byte più in là.

Un nome di campo racconta la stessa prudenza: il bit del cassetto si chiama
`drawerPinHigh` e non `drawerOpen`, perché se alto voglia dire aperto o chiuso dipende da
**come è cablato il cassetto**, e sul campo si trovano entrambi. Un nome che promette più
di quello che il bit dice fa scrivere a qualcuno un controllo sbagliato.

## Le tre cose che su Android USB si sbagliano

Sono scritte nel codice con il perché accanto, perché nessuna delle tre dà un errore
comprensibile quando è sbagliata.

1. **`FLAG_MUTABLE` sul `PendingIntent` del permesso.** È il sistema a scrivere dentro
   l'intent quale dispositivo è stato autorizzato, e su un intent immutabile non può
   farlo. Da Android 12 il risultato è che arriva sempre «negato», senza spiegazioni.
2. **`RECEIVER_NOT_EXPORTED` da Android 13.** Senza, il sistema chiude l'applicazione.
3. **La scrittura è un ciclo.** `bulkTransfer` scrive fino alla dimensione del pacchetto e
   restituisce quanto ha scritto: uno scontrino è quasi sempre più lungo, quindi il ciclo
   non è prudenza, è la condizione normale.

E la stampante si cerca per **classe 7 dello standard USB**, non per un elenco di
identificativi di fornitore: un elenco va aggiornato a ogni modello nuovo, e sul campo il
modello nuovo arriva sempre di sabato.

## Perché niente struttura federata

`flutter create` genera un plugin con `plugin_platform_interface`, una classe astratta e
un'implementazione a canale. Quella divisione serve quando **più pacchetti, scritti da
persone diverse, implementano lo stesso contratto per piattaforme diverse**: è nata perché
chi mantiene `url_launcher` non debba anche mantenere la versione Windows.

Qui la piattaforma è una, il contratto è `PrinterTransport` in Dart, e le due
implementazioni stanno accanto a tutte le altre. Aggiungerla adesso vorrebbe dire tre
classi in più per ottenere quello che un'interfaccia già fa — e il giorno in cui servisse
davvero, il contratto è già al posto giusto.

## Come si mette alla prova un plugin senza il dispositivo

Tre livelli, e nessuno dei tre ha bisogno di una stampante:

1. **Il trasporto di rete contro un vero `ServerSocket`.** Non è un doppio: è un socket
   vero che parla con un socket vero, e ciò che si verifica è il codice che andrà in
   produzione. L'unica cosa finta è chi sta all'altro capo del cavo — e può anche
   rispondere con quattro byte di stato, che è come si mette alla prova il flusso.
2. **Il confine con il nativo, con i canali sostituiti.** Non verifica Kotlin: verifica che
   la chiamata attraversi davvero il canale con il nome e gli argomenti giusti, e che ciò
   che torna indietro — errori compresi — diventi un tipo di dominio prima di uscire dal
   pacchetto. È il confine che, sbagliato, produce l'errore più difficile da capire di un
   plugin: un metodo che non esiste dall'altra parte e una `MissingPluginException` senza
   spiegazioni.
3. **La compilazione dell'APK dell'esempio, in pipeline.** È l'unica verifica che tocchi il
   Kotlin, e verifica una cosa sola: che compili. È poco, ed è dichiarato — ed è anche la
   ragione per cui nel nativo c'è così poco.

**Le prove sono state falsificate:**

| Modifica | Cosa deve diventare rosso | Esito |
|---|---|---|
| Accettare qualunque byte come stato | rifiuto del rumore, riallineamento, filtro sul canale eventi | 3 rossi |
| Lasciare uscire la `PlatformException` | tutta la traduzione degli errori | 6 rossi |

## La prova contro una stampante che non ho scritto io

Tutti i test di questo repository, tranne questi, girano contro un socket che ho scritto
io — e un server scritto da chi scrive anche il client va d'accordo con lui per
costruzione. `example/test/real_printer_test.dart` punta invece a un indirizzo vero:

```bash
flutter test test/real_printer_test.dart \
  --dart-define=PRINTER_HOST=192.168.1.100 \
  --dart-define=PRINTER_PORT=9200
```

Senza quel parametro i test **si saltano invece di fallire**. Una suite che diventa rossa
perché *non* hai una stampante collegata è una suite che si impara a ignorare, e allora
tanto vale non averla.

Cosa ha dimostrato, contro un emulatore ESC/POS in rete: il canale si apre in decine di
millisecondi, uno scontrino intero da 1012 byte parte per intero, due scontrini di fila
viaggiano sulla stessa connessione senza riaprirla, e una porta vicina a quella giusta
diventa un `PrinterUnreachable` invece di un errore generico. L'impaginazione arriva
identica all'anteprima: colonne allineate, l'a capo rientrato sulla descrizione lunga.

### E ha trovato una cosa che nessun test poteva trovare

**Le lettere accentate e l'euro uscivano sbagliati.** «Sarà l'emulatore» è la spiegazione
comoda, ed è anche quella che non si può consegnare a nessuno. È una domanda con una
risposta esatta, perché i byte che mandiamo sono deterministici.

La stampa di prova che l'ha determinata ha quattro righe. Le prime tre hanno **gli stessi
identici byte di testo** — quelli di PC858 — e cambia solo la tabella dichiarata prima di
ognuna; la quarta ha gli stessi caratteri in UTF-8:

| Esito | Cosa avrebbe significato |
|---|---|
| giusta solo la terza | l'emulatore rispetta `ESC t`, e la nostra tabella è quella giusta |
| le prime tre uguali fra loro | ignora `ESC t` e legge sempre con una tabella sua |
| **giusta solo la quarta** | **ignora `ESC t` e decodifica in UTF-8** |

È uscita giusta la quarta. L'emulatore fa quello che fa quasi ogni programma scritto in un
linguaggio moderno, e che **nessuna stampante termica fa**: assume UTF-8. Il pacchetto
manda `0x8A` per la `è` e `0xD5` per l'euro, che è ciò che la specifica prescrive e ciò che
un dispositivo vero si aspetta.

Quindi il difetto non è nostro, e adeguarsi sarebbe il difetto: mandare UTF-8 a una
stampante vera fa uscire `caffÃ¨`, ed è precisamente la ragione per cui le tabelle esistono.

Resta però un fatto utile da dichiarare invece che da nascondere: **questa prova ha
verificato il trasporto, non la codifica del testo.** Per quella l'emulatore non è un
giudice, e serve carta.

## Dove ho consapevolmente semplificato, nel plugin

- **Niente iOS.** La stampa via USB non è aperta alle applicazioni di terze parti:
  servirebbe l'MFi, che è un programma commerciale di Apple e non una libreria. Il
  trasporto di rete funzionerebbe, ma un plugin che dichiara iOS e ne supporta metà è
  peggio di uno che non lo dichiara.
- **Niente Bluetooth**, che è il terzo trasporto naturale. Entra dallo stesso contratto:
  `PrinterTransport` non cambia di una riga, ed è il senso di averlo.
- **Nessuna scoperta delle stampanti di rete.** L'indirizzo si digita. Cercarle con mDNS è
  lo stesso problema già risolto in `pos_sync`, e va portato qui quando serve.
- **Una stampante per volta.** Un locale con due stampanti — scontrini al banco, comande in
  cucina — vuole due canali aperti insieme, e il lato Kotlin oggi ne tiene uno.
- **Nessuna coda con ritentativi.** Se la stampante è occupata, `write` fallisce e la
  decisione torna a chi chiama. La coda è il livello sopra, e in questo portfolio esiste
  già: è l'outbox di `pos_sync`.
- **Nessun test JVM sul Kotlin.** Verificherebbe i finti che ci si è scritti. La scelta è
  stata togliere logica dal nativo invece che aggiungerci prove.
- **Niente testo in UTF-8.** Alcune stampanti recenti lo accettano, e ogni emulatore lo
  assume. Il pacchetto parla solo tabelle di caratteri, perché è ciò che funziona su tutto
  il parco installato: una stampante da dieci anni non sa cosa sia UTF-8, e chi compra un
  registratore di cassa non lo cambia perché è uscito un formato nuovo. Aggiungerlo è una
  riga nell'`EscPosEncoder` il giorno in cui esiste un dispositivo che lo richiede.
