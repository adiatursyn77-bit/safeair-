import 'package:cloud_firestore/cloud_firestore.dart';

/// Порог, после которого плата считается offline, если не было heartbeat.
/// Плата шлёт heartbeat раз в 10 сек (см. прошивку), поэтому 35 сек —
/// запас на пропуск двух-трёх вызовов.
const Duration kOfflineThreshold = Duration(seconds: 35);

enum DeviceDisplayStatus { alarm, ok, offline }

class Device {
  final String id;
  final String name;
  final List<String> memberUids;
  final String status; // "ok" | "alarm" — как прислал бэкенд
  final DateTime? lastSeenAt;
  final double? lastGas;  // сырое значение MQ-2 (0..1023)
  final double? lastTemp; // температура, °C
  final double? lastHum;  // влажность, %

  Device({
    required this.id,
    required this.name,
    required this.memberUids,
    required this.status,
    required this.lastSeenAt,
    this.lastGas,
    this.lastTemp,
    this.lastHum,
  });

  factory Device.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final lastSeenTimestamp = data['lastSeenAt'] as Timestamp?;
    final rawMembers = data['memberUids'] as List<dynamic>?;

    return Device(
      id: doc.id,
      name: (data['name'] as String?) ?? doc.id,
      memberUids: rawMembers?.map((e) => e.toString()).toList() ?? [],
      status: (data['status'] as String?) ?? 'ok',
      lastSeenAt: lastSeenTimestamp?.toDate(),
      lastGas: (data['lastGas'] as num?)?.toDouble(),
      lastTemp: (data['lastTemp'] as num?)?.toDouble(),
      lastHum: (data['lastHum'] as num?)?.toDouble(),
    );
  }

  /// Объединяет "сырой" status с платы и возраст lastSeenAt в один
  /// понятный для UI статус. Offline имеет приоритет над alarm/ok,
  /// потому что если плата давно не выходила на связь, текущий status
  /// мог устареть и не отражать реальность.
  DeviceDisplayStatus get displayStatus {
    final isStale = lastSeenAt == null ||
        DateTime.now().difference(lastSeenAt!) > kOfflineThreshold;

    if (isStale) return DeviceDisplayStatus.offline;
    if (status == 'alarm') return DeviceDisplayStatus.alarm;
    return DeviceDisplayStatus.ok;
  }
}
