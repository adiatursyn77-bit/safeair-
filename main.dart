import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/devices_screen.dart';
import 'screens/login_screen.dart';
import 'services/fcm_service.dart';
import 'services/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await LocalNotificationService.init();

  // Подписка на обновление FCM-токена — один раз за жизнь процесса,
  // независимо от того, вошёл ли пользователь через экран входа или
  // восстановил сохранённую сессию.
  final fcmService = FcmService();
  fcmService.startListeningForTokenRefresh();

  // При каждом старте приложения и каждом входе пересохраняем актуальный
  // токен в users/{uid}.fcmTokens (безопасно вызывать многократно).
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      fcmService.registerTokenForCurrentUser();
    }
  });

  // По умолчанию, пока приложение открыто (foreground), Firebase
  // Messaging доставляет push прямо в код через onMessage, но НЕ
  // показывает системное уведомление сам — это стандартное поведение
  // Android. Чтобы получить эффект "как в мессенджерах" (баннер сверху
  // экрана даже при открытом приложении), показываем его вручную.
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    // Временная диагностика — уберём после того, как разберёмся,
    // почему баннер не появляется. Смотрите вывод "flutter run" в
    // терминале в момент утечки/устранения.
    debugPrint(
      '[push] onMessage сработал. '
      'title=${message.notification?.title} '
      'body=${message.notification?.body} '
      'data=${message.data}',
    );

    final title = message.notification?.title;
    final body = message.notification?.body;
    if (title != null && body != null) {
      LocalNotificationService.show(title: title, body: body).then((_) {
        debugPrint('[push] LocalNotificationService.show() завершился без ошибок');
      }).catchError((Object e, StackTrace st) {
        debugPrint('[push] ОШИБКА при показе уведомления: $e');
      });
    } else {
      debugPrint('[push] title или body пустые — уведомление НЕ показано');
    }
  });

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('ru'),
        Locale('kk'),
        Locale('en'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('ru'),
      startLocale: const Locale('ru'),
      child: const GasLeakApp(),
    ),
  );
}

// Синяя-голубая минималистичная палитра: один seed-цвет, из которого
// Material 3 сам выводит согласованную схему (поверхности, акценты,
// состояния) для светлой и тёмной темы.
const Color kBrandSeed = Color(0xFF0EA5E9); // sky blue

class GasLeakApp extends StatelessWidget {
  const GasLeakApp({super.key});

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: kBrandSeed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeAir',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

/// Показывает экран входа или список устройств в зависимости от того,
/// залогинен ли пользователь — переключается автоматически при
/// входе/выходе, без ручной навигации из экранов входа/регистрации.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const DevicesScreen();
        }

        return const LoginScreen();
      },
    );
  }
}
