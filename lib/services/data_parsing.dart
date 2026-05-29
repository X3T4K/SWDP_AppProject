import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:smart_wearables_app/services/storage_service.dart';

enum DumpType { none, spectrometer, microphone }

/// Campione dello spettrometro (14 byte)
class SpectrometerSample {
  final Uint8List rawData;

  SpectrometerSample(this.rawData);

  factory SpectrometerSample.fromBytes(List<int> bytes) {
    if (bytes.length != 14) {
      throw ArgumentError("SpectrometerSample requires exactly 14 bytes");
    }
    return SpectrometerSample(Uint8List.fromList(bytes));
  }

  // Getters to unpack raw bytes (Little Endian, as written by STM32 Cortex-M)
  int get hh => ByteData.view(rawData.buffer).getUint16(0, Endian.little);
  int get mm => ByteData.view(rawData.buffer).getUint16(2, Endian.little);
  int get ss => ByteData.view(rawData.buffer).getUint16(4, Endian.little);
  int get luceArtificiale => ByteData.view(rawData.buffer).getUint16(6, Endian.little);
  int get blue => ByteData.view(rawData.buffer).getUint16(8, Endian.little);
  int get deepBlue => ByteData.view(rawData.buffer).getUint16(10, Endian.little);
  int get clear => ByteData.view(rawData.buffer).getUint16(12, Endian.little);
}

/// Campione del microfono (9 byte)
class MicrophoneSample {
  final Uint8List rawData;

  MicrophoneSample(this.rawData);

  factory MicrophoneSample.fromBytes(List<int> bytes) {
    if (bytes.length != 9) {
      throw ArgumentError("MicrophoneSample requires exactly 9 bytes");
    }
    return MicrophoneSample(Uint8List.fromList(bytes));
  }

  // Getters to unpack raw bytes (Little Endian)
  int get hh => ByteData.view(rawData.buffer).getUint16(0, Endian.little);
  int get mm => ByteData.view(rawData.buffer).getUint16(2, Endian.little);
  int get ss => ByteData.view(rawData.buffer).getUint16(4, Endian.little);
  int get db => ByteData.view(rawData.buffer).getUint16(6, Endian.little);
  int get peak => rawData[8];
}

class DataParser {
  static Future<void> processFullDump(DumpType type, List<int> accumulatedData) async {
    if (type == DumpType.spectrometer) {
      List<SpectrometerSample> samples = [];
      for (int i = 0; i <= accumulatedData.length - 14; i += 14) {
        samples.add(SpectrometerSample.fromBytes(accumulatedData.sublist(i, i + 14)));
      }
      developer.log("Parsed ${samples.length} Spectrometer samples", name: 'DataParser');
      for (var i = 0; i < samples.length; i++) {
        var s = samples[i];
        developer.log("  [$i] Ora: ${s.hh.toString().padLeft(2, '0')}:${s.mm.toString().padLeft(2, '0')}:${s.ss.toString().padLeft(2, '0')} | Luce Artif: ${s.luceArtificiale} | Blue: ${s.blue} | DeepBlue: ${s.deepBlue} | Clear: ${s.clear}", name: 'DataParser');
      }
      // Salva sul file CSV dello spettrometro
      await StorageService().saveSpectrometerSamples(samples);
      developer.log("Saved spectrometer samples to CSV", name: 'DataParser');
      
    } else if (type == DumpType.microphone) {
      List<MicrophoneSample> samples = [];
      for (int i = 0; i <= accumulatedData.length - 9; i += 9) {
        samples.add(MicrophoneSample.fromBytes(accumulatedData.sublist(i, i + 9)));
      }
      developer.log("Parsed ${samples.length} Microphone samples", name: 'DataParser');
      // Salva sul file CSV del microfono
      await StorageService().saveMicrophoneSamples(samples);
      developer.log("Saved microphone samples to CSV", name: 'DataParser');
    }
  }
}
