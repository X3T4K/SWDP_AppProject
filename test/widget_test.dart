import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wearables_app/services/wellbeing_service.dart';

void main() {
  test('WellbeingService calculates empty inputs correctly', () {
    final service = WellbeingService();
    final result = service.calculate(
      spectrometerData: [],
      microphoneData: [],
      isDemoMode: false,
    );
    expect(result.isg, 0.0);
    expect(result.melatonin, 0.0);
  });

  test('WellbeingService calculates stress and melatonin correctly with mock data', () {
    final service = WellbeingService();
    final result = service.calculate(
      spectrometerData: [
        {
          'timestamp': DateTime(2026, 6, 19, 12, 0, 0),
          'luceArtificiale': 100,
          'blue': 50,
          'deepBlue': 30,
          'clear': 500,
        }
      ],
      microphoneData: [
        {
          'timestamp': DateTime(2026, 6, 19, 12, 0, 0),
          'db': 70.0,
          'peak': 0,
        }
      ],
      isDemoMode: false,
    );
    expect(result.isg, greaterThan(0.0));
  });
}
