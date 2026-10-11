import 'package:flutter_test/flutter_test.dart';
import 'package:powerguard_iot/models/channel_reading.dart';
import 'package:powerguard_iot/models/device.dart';

ChannelReading _reading({String status = 'ON'}) => ChannelReading(
      id: 'r1',
      deviceId: 'd1',
      channelNumber: 2,
      voltage: 211.8,
      current: 1.5,
      power: 300,
      energy: 0.608,
      frequency: 60,
      powerFactor: 0.9,
      breakerStatus: status,
      updatedAt: DateTime.utc(2026, 9, 21),
    );

void main() {
  group('ChannelReading.zeroed', () {
    test('zeroes every displayed meter value, energy included', () {
      final z = _reading().zeroed();
      expect(z.voltage, 0);
      expect(z.current, 0);
      expect(z.power, 0);
      expect(z.energy, 0);
      expect(z.frequency, 0);
      expect(z.powerFactor, 0);
    });

    test('keeps identity and breaker status', () {
      final z = _reading(status: 'OFF').zeroed();
      expect(z.channelNumber, 2);
      expect(z.isOff, isTrue);
    });
  });

  group('Device.isOnline', () {
    Device device(String status, DateTime? lastSeen) => Device(
          id: 'd1',
          deviceName: 'PowerGuard ESP32',
          status: status,
          lastSeen: lastSeen,
        );

    test('online with a recent heartbeat', () {
      final d = device('online', DateTime.now().subtract(const Duration(seconds: 10)));
      expect(d.isOnline, isTrue);
    });

    test('offline when the heartbeat is stale even if status says online', () {
      final d = device('online', DateTime.now().subtract(const Duration(seconds: 60)));
      expect(d.isOnline, isFalse);
    });

    test('offline when status is offline or last_seen is missing', () {
      expect(device('offline', DateTime.now()).isOnline, isFalse);
      expect(device('online', null).isOnline, isFalse);
    });
  });
}
