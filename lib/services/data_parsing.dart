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

  bool get isValid => hh <= 23 && mm <= 59 && ss <= 59;
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

  // Getters to unpack raw bytes (according to main.c memory alignment and packed struct)
  int get hh => rawData[0];
  int get mm => rawData[1];
  int get ss => rawData[2];
  
  int get sss {
    try {
      return ByteData.view(rawData.buffer, rawData.offsetInBytes, rawData.length).getUint16(3, Endian.big);
    } catch (e) {
      return 0;
    }
  }

  int get db {
    try {
      final double val = ByteData.view(rawData.buffer, rawData.offsetInBytes, rawData.length).getFloat32(5, Endian.little);
      if (val.isNaN || val.isInfinite) {
        return 0;
      }
      return val.round().clamp(0, 150);
    } catch (e) {
      return 0;
    }
  }

  int get peak => 0; // Ignored for now as per request

  bool get isValid {
    if (hh > 23 || mm > 59 || ss > 59) return false;
    try {
      final double val = ByteData.view(rawData.buffer, rawData.offsetInBytes, rawData.length).getFloat32(5, Endian.little);
      if (val.isNaN || val.isInfinite || val < 0.0 || val > 150.0) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

class DataParser {
  static bool _isZeroSample(List<int> bytes) {
    for (int b in bytes) {
      if (b != 0) return false;
    }
    return true;
  }

  static Future<void> processFullDump(DumpType type, List<int> accumulatedData) async {
    if (type == DumpType.spectrometer) {
      List<SpectrometerSample> samples = [];
      const int bytesPerSample = 14;
      const int samplesPerPage = 292;
      const int pageSize = 4096;

      for (int pageStart = 0; pageStart < accumulatedData.length; pageStart += pageSize) {
        int currentPageSize = accumulatedData.length - pageStart;
        int numSamples = (currentPageSize < pageSize)
            ? (currentPageSize ~/ bytesPerSample)
            : samplesPerPage;
        if (numSamples > samplesPerPage) numSamples = samplesPerPage;

        for (int s = 0; s < numSamples; s++) {
          int offset = pageStart + s * bytesPerSample;
          if (offset + bytesPerSample <= accumulatedData.length) {
            var sampleBytes = accumulatedData.sublist(offset, offset + bytesPerSample);
            if (!_isZeroSample(sampleBytes)) {
              final sample = SpectrometerSample.fromBytes(sampleBytes);
              if (sample.isValid) {
                samples.add(sample);
              }
            }
          }
        }
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
      const int bytesPerSample = 9;
      const int samplesPerPage = 455;
      const int pageSize = 4096;

      for (int pageStart = 0; pageStart < accumulatedData.length; pageStart += pageSize) {
        int currentPageSize = accumulatedData.length - pageStart;
        int numSamples = (currentPageSize < pageSize)
            ? (currentPageSize ~/ bytesPerSample)
            : samplesPerPage;
        if (numSamples > samplesPerPage) numSamples = samplesPerPage;

        for (int s = 0; s < numSamples; s++) {
          int offset = pageStart + s * bytesPerSample;
          if (offset + bytesPerSample <= accumulatedData.length) {
            var sampleBytes = accumulatedData.sublist(offset, offset + bytesPerSample);
            if (!_isZeroSample(sampleBytes)) {
              final sample = MicrophoneSample.fromBytes(sampleBytes);
              if (sample.isValid) {
                samples.add(sample);
              }
            }
          }
        }
      }

      developer.log("Parsed ${samples.length} Microphone samples", name: 'DataParser');
      // Salva sul file CSV del microfono
      await StorageService().saveMicrophoneSamples(samples);
      developer.log("Saved microphone samples to CSV", name: 'DataParser');
    }
  }
}
