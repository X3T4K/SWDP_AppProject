import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:smart_wearables_app/services/data_parsing.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Future<File> _getFile(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$fileName');
  }

  // Controlla l'ultimo orario di aggiornamento del file
  Future<DateTime?> getLastUpdateTime(String fileName) async {
    final file = await _getFile(fileName);
    if (await file.exists()) {
      return await file.lastModified();
    }
    return null;
  }

  // Salvataggio Spettrometro (Evita duplicati)
  Future<void> saveSpectrometerSamples(List<SpectrometerSample> newSamples) async {
    final file = await _getFile('spectrometer_data.csv');
    Map<String, String> dataMap = {};

    // 1. Leggi i dati esistenti se il file esiste
    if (await file.exists()) {
      List<String> lines = await file.readAsLines();
      if (lines.isNotEmpty) {
        // Salta l'intestazione
        for (int i = 1; i < lines.length; i++) {
          if (lines[i].trim().isEmpty) continue;
          List<String> parts = lines[i].split(',');
          if (parts.isNotEmpty) {
            String timestamp = parts[0];
            dataMap[timestamp] = lines[i];
          }
        }
      }
    }

    // 2. Aggiungi i nuovi campioni con timestamp odierno + ore:minuti:secondi del campione
    final now = DateTime.now();
    for (var s in newSamples) {
      final dt = DateTime(now.year, now.month, now.day, s.hh, s.mm, s.ss);
      final timestamp = dt.millisecondsSinceEpoch.toString();
      final row = "$timestamp,${s.luceArtificiale},${s.blue},${s.deepBlue},${s.clear}";
      dataMap[timestamp] = row;
    }

    // 3. Riscrivi il file ordinato per timestamp
    var sortedKeys = dataMap.keys.toList()..sort();
    final buffer = StringBuffer();
    buffer.writeln("Timestamp,LuceArtificiale,Blue,DeepBlue,Clear");
    for (var key in sortedKeys) {
      buffer.writeln(dataMap[key]);
    }
    await file.writeAsString(buffer.toString());
  }

  // Salvataggio Microfono (Evita duplicati)
  Future<void> saveMicrophoneSamples(List<MicrophoneSample> newSamples) async {
    final file = await _getFile('microphone_data.csv');
    Map<String, String> dataMap = {};

    // 1. Leggi i dati esistenti se il file esiste
    if (await file.exists()) {
      List<String> lines = await file.readAsLines();
      if (lines.isNotEmpty) {
        // Salta l'intestazione
        for (int i = 1; i < lines.length; i++) {
          if (lines[i].trim().isEmpty) continue;
          List<String> parts = lines[i].split(',');
          if (parts.isNotEmpty) {
            String timestamp = parts[0];
            dataMap[timestamp] = lines[i];
          }
        }
      }
    }

    // 2. Aggiungi i nuovi campioni
    final now = DateTime.now();
    for (var s in newSamples) {
      final dt = DateTime(now.year, now.month, now.day, s.hh, s.mm, s.ss);
      final timestamp = dt.millisecondsSinceEpoch.toString();
      final row = "$timestamp,${s.db},${s.peak}";
      dataMap[timestamp] = row;
    }

    // 3. Riscrivi il file ordinato per timestamp
    var sortedKeys = dataMap.keys.toList()..sort();
    final buffer = StringBuffer();
    buffer.writeln("Timestamp,DB,Peak");
    for (var key in sortedKeys) {
      buffer.writeln(dataMap[key]);
    }
    await file.writeAsString(buffer.toString());
  }

  // Recupera i dati dello spettrometro per i grafici
  Future<List<Map<String, dynamic>>> getSpectrometerData() async {
    final file = await _getFile('spectrometer_data.csv');
    if (!await file.exists()) return [];

    List<String> lines = await file.readAsLines();
    List<Map<String, dynamic>> result = [];
    if (lines.length <= 1) return [];

    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      List<String> parts = lines[i].split(',');
      if (parts.length < 5) continue;
      result.add({
        'timestamp': DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0])),
        'luceArtificiale': int.parse(parts[1]),
        'blue': int.parse(parts[2]),
        'deepBlue': int.parse(parts[3]),
        'clear': int.parse(parts[4]),
      });
    }
    return result;
  }

  // Recupera i dati del microfono per i grafici
  Future<List<Map<String, dynamic>>> getMicrophoneData() async {
    final file = await _getFile('microphone_data.csv');
    if (!await file.exists()) return [];

    List<String> lines = await file.readAsLines();
    List<Map<String, dynamic>> result = [];
    if (lines.length <= 1) return [];

    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      List<String> parts = lines[i].split(',');
      if (parts.length < 3) continue;
      result.add({
        'timestamp': DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0])),
        'db': int.parse(parts[1]),
        'peak': int.parse(parts[2]),
      });
    }
    return result;
  }

  // Cancella tutti i dati salvati
  Future<void> clearAllData() async {
    final f1 = await _getFile('spectrometer_data.csv');
    final f2 = await _getFile('microphone_data.csv');
    if (await f1.exists()) await f1.delete();
    if (await f2.exists()) await f2.delete();
  }
}
