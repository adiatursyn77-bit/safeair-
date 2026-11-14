import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

import '../models/device.dart';
import '../models/leak_event.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Список плат текущего пользователя (он состоит в memberUids),
  /// обновляется в реальном времени.
  Stream<List<Device>> streamDevicesForUser(String uid) {
    return _firestore
        .collection('devices')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Device.fromFirestore(doc)).toList());
  }

  /// Одна плата в реальном времени (показания датчиков, статус, heartbeat).
  /// Если документ удалён — приходит null.
  Stream<Device?> streamDevice(String deviceId) {
    return _firestore
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .map((doc) => doc.exists ? Device.fromFirestore(doc) : null);
  }

  /// История событий одной платы, новые сверху.
  Stream<List<LeakEvent>> streamEvents(String deviceId) {
    return _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('events')
        .orderBy('startedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => LeakEvent.fromFirestore(doc)).toList());
  }

  /// SHA-256 хэш секрета — тем же способом, что и прошивка/Worker.
  String hashSecret(String secret) {
    return sha256.convert(utf8.encode(secret)).toString();
  }

  /// Привязка платы к текущему аккаунту — работает и для совершенно
  /// новой платы, и для уже существующей (тогда это "присоединение"
  /// ещё одного пользователя к ней, например члена семьи).
  ///
  /// Сначала пробуем update() — сработает, только если плата уже
  /// существует И присланный secretHash совпадает с уже сохранённым
  /// (это проверяет firestore.rules). Если плата не найдена вообще —
  /// update() вернёт not-found, и тогда создаём её с нуля.
  Future<void> addDevice({
    required String deviceId,
    required String secret,
    required String name,
    required String currentUid,
  }) async {
    final secretHash = hashSecret(secret);
    final docRef = _firestore.collection('devices').doc(deviceId);

    try {
      // Попытка присоединиться к уже существующей плате: не трогаем
      // name (у неё уже есть своё, заданное первым владельцем), только
      // подтверждаем секрет и добавляем себя в участники.
      await docRef.update({
        'secretHash': secretHash,
        'memberUids': FieldValue.arrayUnion([currentUid]),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        // Платы ещё не существует — создаём с нуля, текущий пользователь
        // становится первым (пока единственным) участником.
        await docRef.set({
          'memberUids': [currentUid],
          'name': name,
          'secretHash': secretHash,
          'status': 'ok',
        });
      } else {
        // permission-denied здесь чаще всего означает неверный secret
        // (не совпал с уже сохранённым secretHash существующей платы).
        rethrow;
      }
    }
  }

  Future<void> renameDevice(String deviceId, String newName) async {
    await _firestore.collection('devices').doc(deviceId).update({
      'name': newName,
    });
  }

  /// Покидает плату. Если пользователь — последний участник, документ
  /// удаляется полностью (разрешено правилом allow delete). Иначе —
  /// убирается только он сам из списка, остальным участникам плата
  /// остаётся видна.
  Future<void> leaveDevice(String deviceId, String currentUid,
      {required bool isLastMember}) async {
    final docRef = _firestore.collection('devices').doc(deviceId);
    if (isLastMember) {
      await docRef.delete();
    } else {
      await docRef.update({
        'memberUids': FieldValue.arrayRemove([currentUid]),
      });
    }
  }
}
