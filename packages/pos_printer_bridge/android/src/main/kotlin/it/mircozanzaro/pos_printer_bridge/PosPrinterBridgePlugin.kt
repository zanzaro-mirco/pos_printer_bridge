package it.mircozanzaro.pos_printer_bridge

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Il ponte verso una stampante USB.
 *
 * Questo file **sposta byte e basta**: trova il dispositivo, chiede il
 * permesso, apre gli endpoint, scrive e legge. Non decodifica uno stato, non
 * compone un comando ESC/POS, non decide quando riprovare.
 *
 * Non e' eleganza, e' dove si possono mettere le cose alla prova. Il codice
 * nativo e' la parte che costa di piu' verificare: serve un dispositivo, un
 * emulatore non basta, e un test JVM su `UsbManager` finirebbe per verificare
 * i finti che ci si e' scritti. Quindi il nativo si tiene sottile fino a
 * essere quasi ovvio, e tutto cio' che ha una logica dentro attraversa il
 * canale e viene provato in Dart.
 */
class PosPrinterBridgePlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

  private companion object {
    const val METHODS = "it.mircozanzaro.pos_printer_bridge/methods"
    const val STATUS = "it.mircozanzaro.pos_printer_bridge/status"
    const val PERMISSION_ACTION = "it.mircozanzaro.pos_printer_bridge.PERMISSION"

    /** Classe 7 dello standard USB: le stampanti si dichiarano cosi'. */
    const val USB_CLASS_PRINTER = UsbConstants.USB_CLASS_PRINTER

    /** Millisecondi concessi a una singola scrittura sull'endpoint. */
    const val WRITE_TIMEOUT_MS = 3_000

    /**
     * Attesa di una lettura. Corta di proposito: e' un'attesa che scade
     * continuamente, ed e' cosi' che il ciclo di lettura resta interrompibile
     * senza dover chiudere il dispositivo da sotto i piedi.
     */
    const val READ_TIMEOUT_MS = 250
  }

  private lateinit var context: Context
  private lateinit var methods: MethodChannel
  private lateinit var status: EventChannel
  private lateinit var usb: UsbManager

  private var connection: UsbDeviceConnection? = null
  private var claimed: UsbInterface? = null
  private var output: UsbEndpoint? = null
  private var input: UsbEndpoint? = null

  private var events: EventChannel.EventSink? = null
  private var reader: Thread? = null
  @Volatile private var reading = false

  private val main = Handler(Looper.getMainLooper())

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    methods = MethodChannel(binding.binaryMessenger, METHODS)
    methods.setMethodCallHandler(this)
    status = EventChannel(binding.binaryMessenger, STATUS)
    status.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    status.setStreamHandler(null)
    closeDevice()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "open" -> open(result)
      "write" -> write(call.arguments as? ByteArray, result)
      "close" -> {
        closeDevice()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun open(result: Result) {
    if (connection != null) {
      result.success(null)
      return
    }
    val device = findPrinter()
    if (device == null) {
      result.error("not_found", "Nessuna stampante USB collegata", null)
      return
    }
    if (usb.hasPermission(device)) {
      openDevice(device, result)
    } else {
      requestPermission(device, result)
    }
  }

  /**
   * La prima stampante collegata.
   *
   * Si cerca l'interfaccia di classe 7 invece di un elenco di identificativi
   * di fornitore: un elenco va aggiornato a ogni modello nuovo, e sul campo il
   * modello nuovo arriva sempre di sabato.
   */
  private fun findPrinter(): UsbDevice? = usb.deviceList.values.firstOrNull { device ->
    (0 until device.interfaceCount).any {
      device.getInterface(it).interfaceClass == USB_CLASS_PRINTER
    }
  }

  private fun requestPermission(device: UsbDevice, result: Result) {
    val receiver = object : BroadcastReceiver() {
      override fun onReceive(context: Context, intent: Intent) {
        context.unregisterReceiver(this)
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        if (granted) {
          openDevice(device, result)
        } else {
          result.error("permission_denied", "Permesso negato per il dispositivo USB", null)
        }
      }
    }
    val filter = IntentFilter(PERMISSION_ACTION)
    // Da Android 13 un ricevitore va dichiarato esplicitamente non esportato,
    // altrimenti il sistema chiude l'applicazione.
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("UnspecifiedRegisterReceiverFlag")
      context.registerReceiver(receiver, filter)
    }
    // FLAG_MUTABLE e non IMMUTABLE: e' il sistema a scrivere dentro l'intent
    // quale dispositivo e' stato autorizzato, e su un intent immutabile non
    // puo' farlo. E' l'errore che su Android 12 fa arrivare sempre "negato".
    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      PendingIntent.FLAG_MUTABLE
    } else {
      0
    }
    val intent = PendingIntent.getBroadcast(
      context,
      0,
      Intent(PERMISSION_ACTION).setPackage(context.packageName),
      flags,
    )
    usb.requestPermission(device, intent)
  }

  private fun openDevice(device: UsbDevice, result: Result) {
    val target = (0 until device.interfaceCount)
      .map { device.getInterface(it) }
      .firstOrNull { it.interfaceClass == USB_CLASS_PRINTER }
    if (target == null) {
      result.error("not_found", "Il dispositivo non espone un'interfaccia di stampa", null)
      return
    }
    val opened = usb.openDevice(device)
    if (opened == null) {
      result.error("not_found", "Il dispositivo non si e' aperto", null)
      return
    }
    if (!opened.claimInterface(target, true)) {
      opened.close()
      result.error("not_found", "Interfaccia gia' occupata da un altro programma", null)
      return
    }
    connection = opened
    claimed = target
    for (i in 0 until target.endpointCount) {
      val endpoint = target.getEndpoint(i)
      if (endpoint.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
      if (endpoint.direction == UsbConstants.USB_DIR_OUT) output = endpoint
      if (endpoint.direction == UsbConstants.USB_DIR_IN) input = endpoint
    }
    if (output == null) {
      closeDevice()
      result.error("not_found", "Nessun endpoint di scrittura", null)
      return
    }
    startReading()
    result.success(null)
  }

  private fun write(bytes: ByteArray?, result: Result) {
    val connection = this.connection
    val endpoint = output
    if (connection == null || endpoint == null) {
      result.error("not_open", "Canale non aperto", null)
      return
    }
    if (bytes == null) {
      result.error("write_failed", "Nessun byte da scrivere", null)
      return
    }
    // bulkTransfer scrive fino alla dimensione del pacchetto e restituisce
    // quanto ha scritto: uno scontrino e' quasi sempre piu' lungo, quindi il
    // ciclo non e' prudenza, e' la condizione normale.
    var sent = 0
    while (sent < bytes.size) {
      val chunk = minOf(endpoint.maxPacketSize, bytes.size - sent)
      val written = connection.bulkTransfer(
        endpoint,
        bytes.copyOfRange(sent, sent + chunk),
        chunk,
        WRITE_TIMEOUT_MS,
      )
      if (written < 0) {
        result.error("write_failed", "Scrittura interrotta dopo $sent byte su ${bytes.size}", null)
        return
      }
      sent += written
    }
    result.success(null)
  }

  /**
   * Legge l'endpoint di ingresso su un thread suo.
   *
   * `bulkTransfer` blocca, quindi non puo' stare sul thread principale. I byte
   * letti tornano a Dart cosi' come sono: cosa significhino lo decide chi sa
   * decodificarli, che sta dall'altra parte.
   */
  private fun startReading() {
    val endpoint = input ?: return
    reading = true
    reader = Thread {
      val buffer = ByteArray(endpoint.maxPacketSize)
      while (reading) {
        val connection = this.connection ?: break
        val read = connection.bulkTransfer(endpoint, buffer, buffer.size, READ_TIMEOUT_MS)
        if (read > 0) {
          val payload = buffer.copyOf(read)
          // L'invio a Flutter avviene sul thread principale: e' un requisito
          // dei canali, non una precauzione.
          main.post { events?.success(payload) }
        }
      }
    }.also { it.start() }
  }

  private fun closeDevice() {
    reading = false
    reader?.join(1_000)
    reader = null
    claimed?.let { connection?.releaseInterface(it) }
    connection?.close()
    connection = null
    claimed = null
    output = null
    input = null
  }

  override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
    events = sink
  }

  override fun onCancel(arguments: Any?) {
    events = null
  }
}
