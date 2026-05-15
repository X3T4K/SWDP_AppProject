import 'dart:developer' as developer;
import 'package:smart_wearables_app/connection/stream.dart';
import 'package:smart_wearables_app/connection/messages.dart';
import 'package:smart_wearables_app/connection/message_type.dart';
import 'package:smart_wearables_app/services/notification_service.dart';

class MyBleManager {
  // Singleton pattern
  static final MyBleManager _instance = MyBleManager._internal();
  factory MyBleManager() => _instance;
  MyBleManager._internal();

  MyStream? _stream;

  /// Inizializza il manager con lo stream utilizzato per la comunicazione
  void init(MyStream stream) {
    _stream = stream;
  }

  /// Funzione per intercettare ed elaborare i dati in arrivo
  void handleData(List<int> data) {
    // --- LOGICA DI ELABORAZIONE ---
    // Qui puoi inserire i tuoi algoritmi, filtri o logiche di controllo
    // prima che i dati arrivino alla UI.

    developer.log("Pacchetto ricevuto: $data", name: 'MyBleManager');

    // Verifichiamo se il pacchetto deve scatenare una notifica
    _checkForNotificationTriggers(data);

    // Invia i dati allo stream per aggiornare la UI
    _stream?.setNum(data);
  }

  /// Analizza il tipo di messaggio e scatena notifiche predefinite
  void _checkForNotificationTriggers(List<int> data) {
    if (data.length < 2) return;

    final int typeByte = data[1];

    // Esempi di trigger basati sui tipi definiti in MsgType
    if (typeByte == MsgType.battery.description) {
      NotificationService().showNotification(
        id: 1,
        title: "Stato Batteria",
        body: "Il dispositivo wearable ha inviato un aggiornamento della batteria.",
      );
    }
  }

  /// Invia un oggetto BleMessage al dispositivo
  void sendMessage(BleMessage message) {
    if (_stream != null) {
      final bytes = message.toBytes();
      developer.log(bytes.toString(), name: 'MyBleManager');
      _stream!.sendData(bytes);
      developer.log("Messaggio inviato (${message.runtimeType}): $bytes", name: 'MyBleManager');
    } else {
      developer.log("Attenzione: MyBleManager non inizializzato!", name: 'MyBleManager');
    }
  }

  /// Manteniamo sendData per compatibilità o per invii grezzi rapidi
  void sendData(List<int> data) {
    _stream?.sendData(data);
  }
}
