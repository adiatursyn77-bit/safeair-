import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Показывает системное всплывающее уведомление (heads-up banner) даже
/// когда приложение открыто — так же, как это делают мессенджеры вроде
/// WhatsApp/Telegram. По умолчанию Firebase Messaging доставляет пуш в
/// код приложения, пока оно открыто, но НЕ показывает его сам — эта
/// служба берёт показ на себя через flutter_local_notifications.
class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    // ID канала изменён с "gas_leak_alerts" на "gas_leak_alerts_v2" —
    // Android запоминает важность канала НАВСЕГДА при первом создании
    // и не даёт коду изменить её позже. Если старый канал случайно
    // создался с низкой важностью в одной из ранних сборок — новый ID
    // заставляет Android создать канал заново, уже с правильным
    // Importance.max с самого начала.
    'gas_leak_alerts_v2',
    'Оповещения SafeAir',
    description: 'Уведомления об утечках газа и статусе плат',
    importance: Importance.max,
  );

  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    // В версиях библиотеки 20.0.0+ initialize() и show() перешли на
    // именованные параметры вместо позиционных.
    await _plugin.initialize(settings: initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(_channel);

    // Явно запрашиваем разрешение на уведомления и здесь тоже (не
    // полагаясь только на firebase_messaging.requestPermission()) —
    // на некоторых устройствах/версиях Android 13+ этого требует именно
    // сама эта библиотека, отдельно от FCM.
    final granted = await androidPlugin?.requestNotificationsPermission();
    // ignore: avoid_print
    print('[push] Разрешение на уведомления предоставлено: $granted');
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channel.id,
      _channel.name,
      channelDescription: _channel.description,
      importance: Importance.max,
      priority: Priority.high,
    );

    final details = NotificationDetails(android: androidDetails);

    // ID уведомления делаем на основе текущего времени, чтобы разные
    // события не перезаписывали друг друга в шторке — каждое новое
    // уведомление появляется отдельной строкой.
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
