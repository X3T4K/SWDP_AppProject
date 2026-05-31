import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:smart_wearables_app/connection/stream.dart';
import 'package:smart_wearables_app/connection/messages.dart';
import 'package:smart_wearables_app/services/data_parsing.dart';

class MyBleManager {
  // Singleton pattern
  static final MyBleManager _instance = MyBleManager._internal();
  factory MyBleManager() => _instance;
  MyBleManager._internal();

  // --- BLE Service and Characteristic UUIDs ---
  static final Uuid serviceUuid = Uuid.parse("49535343-FE7D-4AE5-8FA9-9FAFD205E455");
  static final Uuid characteristicUuid = Uuid.parse("49535343-1E4D-4BD9-BA61-23C647249616"); // RX
  static final Uuid characteristicUuidTX = Uuid.parse("49535343-8841-43F4-A8D4-ECBE34729BB3"); // TX

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  // Stream Subscriptions
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription? _rxSubscription;
  StreamSubscription? _txSubscription;

  // Connection State Notifiers (Observable by UI)
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isConnectingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isReconnectingNotifier = ValueNotifier<bool>(false);

  // Connection State Variables
  String? _connectedDeviceId;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isReconnecting = false;

  // Retry / Recovery Parameters
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 3;

  MyStream? _stream;
  MyStream? get stream => _stream;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isReconnecting => _isReconnecting;
  String? get connectedDeviceId => _connectedDeviceId;

  static const int startByte = 0x7B; // '{'
  static const int endByte = 0x7D;   // '}'

  static const int typeData = 0x44; // 'D'
  static const int typeEop  = 0x45; // 'E'
  static const int typeEod  = 0x46; // 'F' - End Of Dump

  // Gestione Partizioni
  int _partitionOffset = 0;
  int? _receivedPageCrc;

  static const int headerSize = 4;
  static const int crcSize = 2;
  static const int footerSize = 1;

  static const int maxPayloadSize = 512;
  static const int maxBufferSize = 16384;

  bool _waitingPage = false;

  // Buffering and Parsing
  final List<int> _rxBuffer = [];
  
  // Page Dumping State
  DumpType _currentDumpType = DumpType.none;
  final List<int> _accumulatedDumpData = [];
  int _currentPage = 0;
  final List<int> _pageData = [];
  static const int pageSize = 4096;
  Timer? _pageTimeoutTimer;

  final StreamController<DumpType> _dumpCompletedController = StreamController<DumpType>.broadcast();
  Stream<DumpType> get onDumpCompleted => _dumpCompletedController.stream;

  // Connette a un dispositivo specifico
  Future<void> connect(String deviceId) async {
    if (_isConnected) {
      developer.log("Già connesso al dispositivo $_connectedDeviceId", name: 'BLE_DEBUG');
      return;
    }

    _isConnecting = true;
    _connectedDeviceId = deviceId;
    _updateNotifiers();
    developer.log("Avvio connessione al dispositivo: $deviceId", name: 'BLE_DEBUG');

    try {
      // Negoziazione MTU consigliata per elevate prestazioni e stabilità del dump
      developer.log("Negoziazione MTU a 512 byte...", name: 'BLE_DEBUG');
      final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 512);
      developer.log("MTU Negoziata con successo: $mtu", name: 'BLE_DEBUG');
    } catch (e) {
      developer.log("Avviso: Errore negoziazione MTU (proseguo comunque): $e", name: 'BLE_DEBUG');
    }

    _connectionSubscription?.cancel();
    _connectionSubscription = _ble.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 8),
    ).listen((event) {
      _handleConnectionStateUpdate(event);
    }, onError: (Object error) {
      developer.log("Errore critico durante la connessione: $error", name: 'BLE_DEBUG');
      _handleDisconnection(deviceId);
    });
  }

  // Forza la disconnessione completa e pulisce le risorse
  Future<void> disconnect() async {
    developer.log("Forzatura disconnessione manuale...", name: 'BLE_DEBUG');
    _connectedDeviceId = null;
    _isReconnecting = false;
    _reconnectAttempts = 0;
    _isConnected = false;
    _isConnecting = false;
    
    _teardownDataStreams();
    _pageTimeoutTimer?.cancel();
    _waitingPage = false;
    
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _updateNotifiers();
    developer.log("Disconnesso e risorse liberate completamente.", name: 'BLE_DEBUG');
  }

  // Gestione interna degli stati di connessione BLE
  void _handleConnectionStateUpdate(ConnectionStateUpdate event) {
    final state = event.connectionState;
    final id = event.deviceId;
    developer.log("Aggiornamento Stato Connessione BLE per $id: $state", name: 'BLE_DEBUG');

    switch (state) {
      case DeviceConnectionState.connecting:
        _isConnected = false;
        _isConnecting = true;
        _updateNotifiers();
        break;

      case DeviceConnectionState.connected:
        developer.log("Stato: Connesso fisicamente a $id. Attendo 2 secondi prima di abbonarmi alle caratteristiche per permettere allo stack BLE del sistema operativo di completare la scoperta dei servizi ed evitare errori di scrittura GATT...", name: 'BLE_DEBUG');
        _isConnected = true;
        _isConnecting = false;
        _isReconnecting = false;
        _reconnectAttempts = 0; // Azzera i tentativi di riconnessione a link layer attivo
        _updateNotifiers();
        
        // Ritardo di sicurezza di 2 secondi consigliato per evitare errori "Cannot write client characteristic config descriptor (code 3)"
        Future.delayed(const Duration(seconds: 2), () {
          if (_isConnected && _connectedDeviceId == id) {
            _setupDataStreams(id);
          } else {
            developer.log("Rilevata disconnessione o cambio dispositivo durante l'attesa del setup dei canali dati.", name: 'BLE_DEBUG');
          }
        });
        break;

      case DeviceConnectionState.disconnected:
        developer.log("Stato: Disconnesso da $id", name: 'BLE_DEBUG');
        _handleDisconnection(id);
        break;
      
      case DeviceConnectionState.disconnecting:
        developer.log("Stato: Disconnessione in corso da $id", name: 'BLE_DEBUG');
        break;
    }
  }

  // Configura i canali RX e TX
  void _setupDataStreams(String deviceId) {
    _teardownDataStreams();

    _stream = MyStream();
    developer.log("Inizializzazione canali dati RX e TX...", name: 'BLE_DEBUG');

    // 1. Setup RECEIVE (RX)
    final rxCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    developer.log("Sottoscrizione alla caratteristica RX per ricevere dati...", name: 'BLE_DEBUG');
    _rxSubscription = _ble.subscribeToCharacteristic(rxCharacteristic).listen(
      (packet) {
        processRawData(packet);
      },
      onError: (dynamic error) {
        developer.log("Errore nello stream RX: $error", name: 'BLE_DEBUG');
      },
    );

    // 2. Setup TRANSMIT (TX)
    final txCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuidTX,
      deviceId: deviceId,
    );

    developer.log("Sottoscrizione allo stream TX per inviare dati...", name: 'BLE_DEBUG');
    _txSubscription = _stream!.controllerSend.stream.listen(
      (event) async {
        try {
          await _ble.writeCharacteristicWithoutResponse(txCharacteristic, value: event);
        } catch (e) {
          developer.log("Errore durante l'invio TX: $e", name: 'BLE_DEBUG');
        }
      },
      onError: (dynamic error) {
        developer.log("Errore nello stream di invio TX: $error", name: 'BLE_DEBUG');
      },
    );
  }

  // Libera le risorse dei flussi dati (Teardown parziale consigliato per evitare leaks)
  void _teardownDataStreams() {
    developer.log("Teardown parziale: chiusura ed eliminazione stream dati RX/TX...", name: 'BLE_DEBUG');
    _rxSubscription?.cancel();
    _rxSubscription = null;
    _txSubscription?.cancel();
    _txSubscription = null;
    _stream = null;
  }

  // Gestione disconnessione accidentale con meccanismo di Auto-Recovery (Backoff e Retry)
  void _handleDisconnection(String deviceId) async {
    _isConnected = false;
    _isConnecting = false;
    _teardownDataStreams();
    _pageTimeoutTimer?.cancel();
    _waitingPage = false;
    _updateNotifiers();

    if (_connectedDeviceId == null) {
      // È una disconnessione manuale, non tentare il ripristino
      return;
    }

    if (_isReconnecting) return; // Riconnessione già in esecuzione

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _isReconnecting = true;
      _updateNotifiers();
      developer.log("Connessione persa accidentalmente! Avvio Auto-Recovery...", name: 'BLE_DEBUG');
      developer.log("Tentativo di riconnessione $_reconnectAttempts di $_maxReconnectAttempts in corso...", name: 'BLE_DEBUG');

      // Pausa di Backoff di 2 secondi per far stabilizzare lo stack BLE di Android e del modulo RN4871
      developer.log("Pausa di Backoff: attesa di 2 secondi...", name: 'BLE_DEBUG');
      await Future.delayed(const Duration(seconds: 2));

      _isReconnecting = false;
      _updateNotifiers();

      if (_connectedDeviceId != null) {
        developer.log("Riprovo la connessione a $deviceId...", name: 'BLE_DEBUG');
        connect(_connectedDeviceId!);
      }
    } else {
      developer.log("Tentativi di riconnessione esauriti. Disconnessione definitiva.", name: 'BLE_DEBUG');
      _connectedDeviceId = null;
      _isReconnecting = false;
      _reconnectAttempts = 0;
      _connectionSubscription?.cancel();
      _connectionSubscription = null;
      _updateNotifiers();
    }
  }

  // Aggiorna i notifiers per informare la UI
  void _updateNotifiers() {
    isConnectedNotifier.value = _isConnected;
    isConnectingNotifier.value = _isConnecting;
    isReconnectingNotifier.value = _isReconnecting;
  }

  // Metodo per la compatibilità con il codice esistente
  void init(MyStream stream) {
    developer.log("Metodo init chiamato esternamente (ereditato). Flussi gestiti internamente.", name: 'BLE_DEBUG');
  }

  /// Entry point for raw bytes from BLE
  void processRawData(List<int> data) {
    _rxBuffer.addAll(data);
    _extractPackets();
  }

  void _extractPackets() {
    while (true) {
      // Prevent infinite growth
      if (_rxBuffer.length > maxBufferSize) {
        developer.log("RX buffer overflow. Clearing buffer.", name: 'BleManager');
        _rxBuffer.clear();
        return;
      }

      // Search start byte
      int startIndex = _rxBuffer.indexOf(startByte);
      if (startIndex == -1) {
        _rxBuffer.clear();
        return;
      }
      // Remove garbage before packet
      if (startIndex > 0) {
        _rxBuffer.removeRange(0, startIndex);
      }
      // Need at least minimal header
      if (_rxBuffer.length < headerSize) {
        return;
      }

      int type = _rxBuffer[1];
      int payloadLength =
      (_rxBuffer[2] << 8) |
      (_rxBuffer[3]);

      // Sanity check
      if (payloadLength > maxPayloadSize) {
        developer.log(
            "Invalid payload length: $payloadLength. Resync.",
            name: 'BleManager');

        _rxBuffer.removeAt(0);
        continue;
      }

      int packetLength =
          headerSize +
              payloadLength +
              crcSize +
              footerSize;

      // Wait full packet
      if (_rxBuffer.length < packetLength) {
        return;
      }

      // Check end byte
      if (_rxBuffer[packetLength - 1] != endByte) {
        developer.log(
            "Invalid end byte. Resync.",
            name: 'BleManager');

        _rxBuffer.removeAt(0);
        continue;
      }

      // Extract packet
      List<int> packet =
      _rxBuffer.sublist(0, packetLength);

      _rxBuffer.removeRange(0, packetLength);

      _handlePacket(packet);
    }
  }

  void _handlePacket(List<int> packet) {
    int type = packet[1];
    int payloadLength =
    (packet[2] << 8) |
    packet[3];

    List<int> payload =
    packet.sublist(4, 4 + payloadLength);

    int receivedCrc = ((packet[4 + payloadLength] << 8) | packet[5 + payloadLength]) & 0xFFFF;
    int computedCrc = _crc16(payload) & 0xFFFF;

    if (receivedCrc != computedCrc) {
      developer.log("CRC16 ERROR. Received: $receivedCrc, Computed: $computedCrc", name: 'BleManager');
      return;
    }

    switch (type) {
      case typeData:
        if (_pageData.length + payload.length > pageSize) {
          developer.log("Page overflow. Restarting page.", name: 'BleManager');
          _waitingPage = false; // Reset dello stato per permettere il retry
          _requestPage(_partitionOffset + _currentPage);
          return;
        }
        _pageData.addAll(payload);
        developer.log("Chunk OK: ${payload.length} bytes (${_pageData.length}/$pageSize)", name: 'BleManager');
        break;

      case typeEop:
        if (payload.length != 4) {
          developer.log("Invalid EOP payload", name: 'BleManager');
          return;
        }
        // Masking per consistenza 32-bit unsigned
        _receivedPageCrc = ((payload[0] << 24) |
                           (payload[1] << 16) |
                           (payload[2] << 8)  |
                            payload[3]) & 0xFFFFFFFF;

        developer.log("EOP received. Page CRC: ${_receivedPageCrc!.toRadixString(16)}", name: 'BleManager');
        _verifyAndProcessPage();
        break;

      case typeEod:
        developer.log("EOD Ricevuto. Scaricamento completato per questa partizione!", name: 'BleManager');
        _waitingPage = false;
        _pageTimeoutTimer?.cancel();
        
        final completedType = _currentDumpType;
        DataParser.processFullDump(completedType, _accumulatedDumpData).then((_) {
          _dumpCompletedController.add(completedType);
        });
        _currentDumpType = DumpType.none;
        break;

      default:
        developer.log(
            "Unknown packet type: $type",
            name: 'BleManager');
        break;
    }
  }

  int _crc16(List<int> data) {
    int crc = 0xFFFF;
    for (final b in data) {
      crc ^= (b << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  void startDump() {
    _currentPage = 0;
    _requestPage(_partitionOffset + _currentPage);
  }

  void startSpectrometerDump() {
    _currentDumpType = DumpType.spectrometer;
    _accumulatedDumpData.clear();
    _partitionOffset = 0; // Parte dal blocco logico 0
    _currentPage = 0;     // Indice relativo alla partizione
    _requestPage(_partitionOffset + _currentPage);
  }

  void startMicrophoneDump() {
    _currentDumpType = DumpType.microphone;
    _accumulatedDumpData.clear();
    _partitionOffset = 65536; // 1024 blocchi * 64 pagine
    _currentPage = 0;         // Indice relativo alla partizione
    _requestPage(_partitionOffset + _currentPage);
  }

  void _requestPage(int absolutePageNumber) {
    if (_waitingPage) return;

    _waitingPage = true;
    _pageData.clear();
    _receivedPageCrc = null;
    _pageTimeoutTimer?.cancel();

    developer.log("Requesting Absolute Page $absolutePageNumber", name: 'BleManager');

    // Manda la richiesta della pagina (ora a 24-bit come corretto in precedenza)
    sendMessage(PageRequestMessage(absolutePageNumber));

    _pageTimeoutTimer = Timer(const Duration(seconds: 5), () {
      developer.log("Timeout Absolute Page $absolutePageNumber", name: 'BleManager');
      _waitingPage = false;
      _requestPage(absolutePageNumber); // Retry
    });
  }

  void _verifyAndProcessPage() {
    _waitingPage = false;
    _pageTimeoutTimer?.cancel();

    if (_pageData.length != pageSize) {
      developer.log(
          "Page size mismatch "
              "(${_pageData.length}/$pageSize). "
              "Retransmitting...",
          name: 'BleManager');

      _requestPage(_partitionOffset + _currentPage);
      return;
    }

    if (_receivedPageCrc == null) {
      developer.log(
          "Missing page CRC.",
          name: 'BleManager');

      _requestPage(_partitionOffset + _currentPage);
      return;
    }

    int computedCrc = _crc32(_pageData) & 0xFFFFFFFF;

    if (computedCrc != (_receivedPageCrc ?? 0)) {
      developer.log(
          "PAGE CRC ERROR. Page $_currentPage. Computed: ${computedCrc.toRadixString(16)} Received: ${_receivedPageCrc?.toRadixString(16)}",
          name: 'BleManager');
      _requestPage(_partitionOffset + _currentPage);
      return;
    }

    developer.log("Page ${_partitionOffset + _currentPage} verified successfully!", name: 'BleManager');

    // Salvataggio in memoria dei dati della pagina
    _accumulatedDumpData.addAll(_pageData);

    _currentPage++;
    _requestPage(_partitionOffset + _currentPage);
  }

  void sendMessage(BleMessage message) {
    if (_stream != null) {
      _stream!.sendData(message.toBytes());
    }
  }
}
