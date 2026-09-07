# Architettura e scelte di progetto

Il progetto è un **monorepo**, e lo è dal primo giorno per una ragione precisa: il pezzo
che sta in piedi da solo — trasformare uno scontrino in byte — non deve dipendere da
Flutter solo perché un giorno gli starà accanto un plugin che ne ha bisogno.

```
packages/
  esc_pos_builder/     Dart puro: dallo scontrino ai byte
  pos_printer_bridge/  (non ancora scritto) il plugin: dai byte alla stampante
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
