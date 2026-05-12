import 'dart:typed_data';
import 'package:smart_wearables_app/connection/message_type.dart';

/// Interfaccia base per tutti i messaggi BLE (sia in entrata che in uscita)
abstract class BleMessage {
  List<int> toBytes();
}

/// --- MESSAGGI IN USCITA (COMANDI) ---

abstract class StructuredMessage implements BleMessage {
  static const int startByte = 123; // '{'
  static const int endByte = 125;   // '}'

  int get command;
  List<int> get payload => [];

  @override
  List<int> toBytes() {
    return [startByte, command, ...payload, endByte];
  }
}

class AckMessage extends StructuredMessage {
  @override
  int get command => 6; // ACK standard
}

class StartSensorMessage extends StructuredMessage {
  final MsgType type;
  StartSensorMessage(this.type);
  @override
  int get command => type.description;
}

/// Rappresenta i dati ricevuti da un sensore (IMU/ECG/ecc.)
class SensorData {
  final String type;
  final double x, y, z;

  SensorData({required this.type, required this.x, required this.y, required this.z});

  /// Factory che incapsula la logica di parsing e conversione fisica (g)
  factory SensorData.fromBytes(List<int> packet) {
    // packet[0] = '{', packet[1] = Tipo, packet[2..7] = Dati, packet[8] = '}'
    final String type = String.fromCharCode(packet[1]);
    final byteData = Uint8List.fromList(packet.sublist(2)).buffer.asByteData();
    
    // La logica di sensibilità ora è "nascosta" qui dentro
    const double sensitivity = 2.0 / 32767.0;

    return SensorData(
      type: type,
      x: byteData.getInt16(0, Endian.little) * sensitivity,
      y: byteData.getInt16(2, Endian.little) * sensitivity,
      z: byteData.getInt16(4, Endian.little) * sensitivity,
    );
  }
}
