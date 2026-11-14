import 'package:cloud_firestore/cloud_firestore.dart';

class LeakEvent {
  final String id;
  final String type; // "leak_start" | "leak_end"
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationSec;

  LeakEvent({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.durationSec,
  });

  bool get isActive => endedAt == null;

  factory LeakEvent.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final startedAtTimestamp = data['startedAt'] as Timestamp?;
    final endedAtTimestamp = data['endedAt'] as Timestamp?;

    return LeakEvent(
      id: doc.id,
      type: (data['type'] as String?) ?? 'leak_start',
      startedAt: startedAtTimestamp?.toDate() ?? DateTime.now(),
      endedAt: endedAtTimestamp?.toDate(),
      durationSec: data['durationSec'] as int?,
    );
  }
}
