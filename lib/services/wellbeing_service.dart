// lib/services/wellbeing_service.dart

import 'dart:math' as math;

class WellbeingResult {
  final double isg;              // Daily Stress Index (0-100%)
  final double melatonin;        // Melatonin Level (0-100%)
  final double pTwa;             // Noise TWA Penalty (0.0-1.0)
  final double pImpulse;          // Acoustic Impulse Penalty (0.0-1.0)
  final double pBlh;             // Blue Light Hazard Penalty (0.0-1.0)
  final double pFlicker;         // Flicker Penalty (0.0-1.0)
  final double pCircadian;       // Circadian Penalty (0.0-1.0)
  final double pDay;             // Day-time under-stimulation Penalty (0.0-1.0)
  final double pNight;           // Night-time over-stimulation Penalty (0.0-1.0)
  final double avgDayCs;         // Average Day-time Circadian Stimulus (0.0-0.7)
  final double avgNightCs;       // Average Night-time Circadian Stimulus (0.0-0.7)
  final double twaValue;         // Calculated TWA in dBA
  final int impulseCount;        // Number of impulsive noise events detected
  final double avgFlickerIndex;  // Average calculated Flicker Index

  WellbeingResult({
    required this.isg,
    required this.melatonin,
    required this.pTwa,
    required this.pImpulse,
    required this.pBlh,
    required this.pFlicker,
    required this.pCircadian,
    required this.pDay,
    required this.pNight,
    required this.avgDayCs,
    required this.avgNightCs,
    required this.twaValue,
    required this.impulseCount,
    required this.avgFlickerIndex,
  });

  factory WellbeingResult.empty() {
    return WellbeingResult(
      isg: 0.0,
      melatonin: 0.0,
      pTwa: 0.0,
      pImpulse: 0.0,
      pBlh: 0.0,
      pFlicker: 0.0,
      pCircadian: 0.0,
      pDay: 0.0,
      pNight: 0.0,
      avgDayCs: 0.0,
      avgNightCs: 0.0,
      twaValue: 0.0,
      impulseCount: 0,
      avgFlickerIndex: 0.0,
    );
  }
}

class WellbeingService {
  static final WellbeingService _instance = WellbeingService._internal();
  factory WellbeingService() => _instance;
  WellbeingService._internal();

  /// Calculates all wellbeing indices based on spectrometer and microphone data.
  WellbeingResult calculate({
    required List<Map<String, dynamic>> spectrometerData,
    required List<Map<String, dynamic>> microphoneData,
    required bool isDemoMode,
  }) {
    if (spectrometerData.isEmpty && microphoneData.isEmpty) {
      return WellbeingResult.empty();
    }

    // --- 1. ACOUSTIC CALCULATIONS ---
    double pTwa = 0.0;
    double pImpulse = 0.0;
    double twaValue = 0.0;
    int impulseCount = 0;

    if (microphoneData.isNotEmpty) {
      // Sort microphone data by timestamp
      final sortedMic = List<Map<String, dynamic>>.from(microphoneData)
        ..sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));

      // Calculate OSHA Noise Dose D
      double doseSum = 0.0;
      final double impulseThreshold = isDemoMode ? 120.0 : 140.0;

      for (int i = 0; i < sortedMic.length; i++) {
        final current = sortedMic[i];
        final double db = (current['db'] as num).toDouble();
        final double peak = (current['peak'] as num).toDouble();

        // Count impulses
        if (peak >= impulseThreshold) {
          impulseCount++;
        }

        // Calculate time delta in hours (C_i)
        double deltaHours = 10.0 / 3600.0; // Default: 10 seconds
        if (i > 0) {
          final prevTime = sortedMic[i - 1]['timestamp'] as DateTime;
          final currTime = current['timestamp'] as DateTime;
          final diffMs = currTime.difference(prevTime).inMilliseconds;
          if (diffMs > 0) {
            deltaHours = diffMs / 3600000.0; // ms to hours
          }
        }

        // T_i = 8 / 2^((L - 90)/5)
        final double allowedHours = 8.0 / math.pow(2.0, (db - 90.0) / 5.0);
        doseSum += deltaHours / allowedHours;
      }

      // Dose D in %
      final double noiseDose = 100.0 * doseSum;

      // TWA = 10 * log10(D/100) + 85
      if (noiseDose > 0.0) {
        twaValue = 10.0 * (math.log(noiseDose / 100.0) / math.ln10) + 85.0;
      } else {
        twaValue = 0.0;
      }

      // Normalize TWA Penalty (P_TWA): 50 dBA -> 0.0, 85 dBA -> 1.0
      if (twaValue <= 50.0) {
        pTwa = 0.0;
      } else if (twaValue >= 85.0) {
        pTwa = 1.0;
      } else {
        pTwa = (twaValue - 50.0) / (85.0 - 50.0);
      }

      // Calculate Impulse Penalty
      pImpulse = math.min(1.0, 0.5 * impulseCount);
    }

    // --- 2. OPTICAL CALCULATIONS ---
    double pBlh = 0.0;
    double pFlicker = 0.0;
    double pCircadian = 0.0;
    double pDay = 0.0;
    double pNight = 0.0;
    double avgDayCs = 0.0;
    double avgNightCs = 0.0;
    double avgFlickerIndex = 0.0;
    double melatonin = 0.0;

    if (spectrometerData.isNotEmpty) {
      // Sort spectrometer data by timestamp
      final sortedSpec = List<Map<String, dynamic>>.from(spectrometerData)
        ..sort((a, b) => (a['timestamp'] as DateTime).compareTo(b['timestamp'] as DateTime));

      double blhSum = 0.0;
      double flickerIndexSum = 0.0;

      final List<double> dayCsList = [];
      final List<double> nightCsList = [];

      for (int i = 0; i < sortedSpec.length; i++) {
        final current = sortedSpec[i];
        final DateTime timestamp = current['timestamp'] as DateTime;
        final double clear = (current['clear'] as num).toDouble();
        final double deepBlue = (current['deepBlue'] as num).toDouble();
        final double luceArtificiale = (current['luceArtificiale'] as num).toDouble();

        // A. Blue Light Hazard (P_BLH)
        double deltaSeconds = 10.0; // Default: 10 seconds
        if (i > 0) {
          final prevTime = sortedSpec[i - 1]['timestamp'] as DateTime;
          final diffMs = timestamp.difference(prevTime).inMilliseconds;
          if (diffMs > 0) {
            deltaSeconds = diffMs / 1000.0;
          }
        }

        // LB = deepBlue * 1.5e-7 (calibration proxy to W / m^2 / sr)
        final double lb = deepBlue * 1.5e-7;
        if (lb > 0.0) {
          final double tMax = 100.0 / lb; // safe exposure duration in seconds
          blhSum += deltaSeconds / tMax;
        }

        // B. Flicker Index approximation
        // Proxy: FI = 0.12 * LuceArtificiale / Clear
        final double fi = clear > 0.0 ? (0.12 * luceArtificiale / clear) : 0.0;
        flickerIndexSum += fi;

        // C. Circadian Stimulus (CS) Calculation
        final double ev = clear;
        final double z = ev > 0.0 ? (deepBlue / ev) : 0.0;
        double cs = 0.0;

        if (ev > 0.0) {
          if (z > 0.195) {
            final double base = z * math.pow(ev, 0.509265);
            cs = 0.7 - (0.7 / (1.0 + 0.016781 * math.pow(base, 2.268904)));
          } else {
            final double base = z * ev;
            cs = 0.7 - (0.7 / (1.0 + 0.011376 * math.pow(base, 1.109998)));
          }
        }
        cs = cs.clamp(0.0, 0.7);

        // Group by temporal windows: Day (08:00 - 18:00), Night/Evening (18:00 - 08:00)
        final int hour = timestamp.hour;
        if (hour >= 8 && hour < 18) {
          dayCsList.add(cs);
        } else {
          nightCsList.add(cs);
        }
      }

      // Calculate BLH Penalty
      pBlh = blhSum.clamp(0.0, 1.0);

      // Calculate Flicker Penalty (P_Flicker)
      avgFlickerIndex = sortedSpec.isNotEmpty ? flickerIndexSum / sortedSpec.length : 0.0;
      if (avgFlickerIndex <= 0.01) {
        pFlicker = 0.0;
      } else if (avgFlickerIndex >= 0.1) {
        pFlicker = 1.0;
      } else {
        pFlicker = (avgFlickerIndex - 0.01) / (0.1 - 0.01);
      }
      pFlicker = pFlicker.clamp(0.0, 1.0);

      // Calculate Circadian Penalties
      avgDayCs = dayCsList.isNotEmpty ? (dayCsList.reduce((a, b) => a + b) / dayCsList.length) : 0.0;
      avgNightCs = nightCsList.isNotEmpty ? (nightCsList.reduce((a, b) => a + b) / nightCsList.length) : 0.0;

      // P_Day = max(0, (0.3 - CS_day) / 0.3)
      pDay = math.max(0.0, (0.3 - avgDayCs) / 0.3).clamp(0.0, 1.0);

      // P_Night = min(1.0, max(0, CS_night - 0.1) / (0.7 - 0.1))
      pNight = (math.max(0.0, avgNightCs - 0.1) / (0.7 - 0.1)).clamp(0.0, 1.0);

      pCircadian = ((pDay + pNight) / 2.0).clamp(0.0, 1.0);

      // Melatonin Availability Level
      melatonin = (1.0 - pNight) * 100.0;
    }

    // --- 3. FINAL DAILY STRESS INDEX (ISG) ---
    // ISG = (30 * pTwa) + (20 * pImpulse) + (15 * pBlh) + (10 * pFlicker) + (25 * pCircadian)
    final double isg = (30.0 * pTwa) +
                       (20.0 * pImpulse) +
                       (15.0 * pBlh) +
                       (10.0 * pFlicker) +
                       (25.0 * pCircadian);

    return WellbeingResult(
      isg: isg.clamp(0.0, 100.0),
      melatonin: melatonin.clamp(0.0, 100.0),
      pTwa: pTwa,
      pImpulse: pImpulse,
      pBlh: pBlh,
      pFlicker: pFlicker,
      pCircadian: pCircadian,
      pDay: pDay,
      pNight: pNight,
      avgDayCs: avgDayCs,
      avgNightCs: avgNightCs,
      twaValue: twaValue,
      impulseCount: impulseCount,
      avgFlickerIndex: avgFlickerIndex,
    );
  }
}
