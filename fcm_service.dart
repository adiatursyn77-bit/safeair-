import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static bool _refreshListenerStarted = false;

  /// Подписывается на обновление FCM-токена ОДИН раз за всё время жизни
  /// приложения — вызывается в main() при старте, независимо от того,
  /// залогинен пользователь в этот момент или нет. Раньше эта подписка
  /// создавалась только внутри registerTokenForCurrentUser(), которая
  /// вызывается лишь при явном входе (signIn/signUp) — а при обычном
  /// открытии уже вошедшим пользователем (через сохранённую сессию
  /// Firebase Auth) этот код не выполнялся вовсе, и после перезапуска
  /// процесса приложением Android'ом слушателя обновления токена не
  /// оставалось ни одного — новый токен, если Firebase его ротировал,
  /// негде было сохранить.
  void startListeningForTokenRefresh() {
    if (_refreshListenerStarted) return;
    _refreshListenerStarted = true;

    _messaging.onTokenRefresh.listen((newToken) {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        _saveToken(currentUser.uid, newToken);
      }
    });
  }

  /// Запрашивает разрешение на push (нужно на iOS и Android 13+) и
  /// сохраняет ТЕКУЩИЙ FCM-токен в users/{uid}.fcmTokens. Безопасно
  /// вызывать многократно (в том числе при каждом старте приложения
  /// для уже залогиненного пользователя) — просто пересохраняет тот же
  /// самый актуальный токен, что и так уже действителен.
  Future<void> registerTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _messaging.requestPermission();

    final token = await _messaging.getToken();
    if (token == null) return;

    await _saveToken(user.uid, token);
  }

  Future<void> _saveToken(String uid, String token) async {
    await _firestore.collection('users').doc(uid).set(
      {
        'fcmTokens': FieldValue.arrayUnion([token]),
      },
      SetOptions(merge: true),
    );
  }

  /// Убирает текущий токен этого устройства из списка — вызывается
  /// перед выходом из аккаунта, чтобы не слать push туда, где уже
  /// разлогинились.
  Future<void> unregisterTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await _messaging.getToken();
    if (token == null) return;

    await _firestore.collection('users').doc(user.uid).set(
      {
        'fcmTokens': FieldValue.arrayRemove([token]),
      },
      SetOptions(merge: true),
    );
  }
}
