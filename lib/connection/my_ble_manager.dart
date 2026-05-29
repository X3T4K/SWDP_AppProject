import 'dart:async';
import 'dart:developer' as developer;
import 'package:smart_wearables_app/connection/stream.dart';
import 'package:smart_wearables_app/connection/messages.dart';
import 'package:smart_wearables_app/services/data_parsing.dart';

class MyBleManager {
  // Singleton pattern
  static final MyBleManager _instance = MyBleManager._internal();
  factory MyBleManager() => _instance;
  MyBleManager._internal();

  MyStream? _stream;
  MyStream? get stream => _stream;

  bool get isConnected => _stream != null;

  void clearConnection() {
    _stream = null;
  }

  final StreamController<DumpType> _dumpCompletedController = StreamController<DumpType>.broadcast();
  Stream<DumpType> get onDumpCompleted => _dumpCompletedController.stream;

  static const int startByte = 0x7B; // '{'
  static const int endByte = 0x7D;   // '}'

  static const int typeData = 0x44; // 'D'
  static const int typeEop  = 0x45; // 'E'
  static const int typeEod  = 0x46; // 'F' - End Of Dump
  // Gestione Partizioni
  int _partitionOffset = 0;
  int? _receivedPageCrc;

  static const int headerSize = 4;
// { TYPE LEN_H LEN_L

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

  void init(MyStream stream) {
    _stream = stream;    // Ascolta lo stream dei dati in arrivo e processali
    _stream!.controller.stream.listen((data) {
      processRawData(data as List<int>);
    });
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

  // Modifica _requestPage per usare l'indirizzo assoluto
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
