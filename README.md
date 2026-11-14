# SafeAir

Детектор утечки газа и дыма на ESP8266 с push-уведомлениями на Android.

```
ESP8266 (D1 mini)  ──HTTPS──►  Cloudflare Worker  ──►  Firebase Firestore  ──►  Flutter-приложение
 MQ-2, DHT11, баззер            heartbeat / gasEvent       devices, events           история, статус, push (FCM)
```

## Состав репозитория

| Папка | Что внутри |
|---|---|
| `firmware/gas_leak_firmware_mq2` | Прошивка D1 mini: MQ-2 (A0), DHT11, баззер, 2 светодиода |
| `firmware/buzzer_test` | Тест баззера (4 способа управления) |
| `worker/` | Cloudflare Worker: принимает данные платы, пишет в Firestore, шлёт push через FCM |
| `firebase/` | Правила Firestore (`firestore.rules`) |
| `app/` | Исходники Flutter-приложения (Android) |
| `docs/` | Схема базы данных и документация |
| `index.html` | Демо-панель (симулятор) для GitHub Pages |

## Схема подключения (D1 mini)

| Деталь | Пин |
|---|---|
| MQ-2 AO | A0 через делитель 10 кОм / 10 кОм |
| MQ-2 VCC / GND | 5V / GND |
| DHT11 data | D5 (GPIO14), питание 3V3 |
| Баззер (пассивный) I/O | D6 (GPIO12), питание 3V3 |
| Красный светодиод | D1 через резистор |
| Зелёный светодиод | D2 через резистор |

## Запуск

### 1. Firebase
1. Создай проект Firebase, включи Firestore и Authentication (Email/Password).
2. Выложи правила:
   ```
   cd firebase
   firebase deploy --only firestore:rules --project <PROJECT_ID>
   ```

### 2. Cloudflare Worker
1. В `worker/wrangler.toml` впиши свой `FIREBASE_PROJECT_ID`.
2. Создай сервисный аккаунт GCP (роли Cloud Datastore User и Firebase Cloud Messaging API Admin) и задай секреты:
   ```
   cd worker
   wrangler secret put GCP_SERVICE_ACCOUNT_EMAIL
   wrangler secret put GCP_SERVICE_ACCOUNT_PRIVATE_KEY
   wrangler deploy
   ```

### 3. Прошивка
1. Установи в Arduino IDE пакет плат **esp8266** и библиотеки **DHT sensor library** (Adafruit), **Adafruit Unified Sensor**, **ArduinoJson 6.x**.
2. В папке `firmware/gas_leak_firmware_mq2` скопируй `secrets.h.example` в `secrets.h` и впиши Wi-Fi, `DEVICE_ID`, `DEVICE_SECRET`, адрес Worker.
3. В `.ino` настрой флаги `SIMULATE_TEMP` / `SIMULATE_GAS`, `BUZZER_PASSIVE`, `ALARM_DELTA`.
4. Плата: LOLIN(WEMOS) D1 R2 & mini, скорость монитора порта 115200.

### 4. Приложение
```
flutter create --project-name gas_leak_app --platforms android app_tmp
```
Скопируй содержимое `app/` (`lib`, `assets`, `pubspec.yaml`, `android/app/src/main/AndroidManifest.xml`) поверх созданного проекта, затем:
```
flutterfire configure --project=<PROJECT_ID> --platforms=android
flutter pub get
flutter run
```
В `android/app/build.gradle.kts` нужны `minSdk = 23`, `isCoreLibraryDesugaringEnabled = true` и зависимость `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`.

## Протокол платы

`POST /heartbeat` — раз в 10 секунд:
```json
{ "deviceId": "...", "secret": "...", "gas": 65, "temp": 23.4, "hum": 48 }
```

`POST /gasEvent` — начало и конец тревоги:
```json
{ "deviceId": "...", "secret": "...", "type": "leak_start" }
{ "deviceId": "...", "secret": "...", "type": "leak_end", "durationSec": 42 }
```

Worker сверяет SHA-256 секрета с полем `secretHash` в документе `devices/{deviceId}`.

## Ограничения

- MQ-2 реагирует на горючие газы и дым, но не различает их и не видит открытое пламя.
- DHT11 надёжно измеряет только 0–50 °C.

## Демо-панель (GitHub Pages)

Живая ссылка: **https://ЗАМЕНИТЕ_ЛОГИН.github.io/ЗАМЕНИТЕ_РЕПО/** (вставить после включения Pages).

Страница `index.html` показывает карточки устройств со статусами «норма / тревога / нет связи», температуру, влажность и журнал событий (начало, конец, длительность). Кнопки «Симулировать газ», «Отбой» и «Отключить связь» позволяют проверить логику без железа. Данные имитируются в браузере и помечены как тестовые.

Демо не заменяет штатную пожарную сигнализацию и не вызывает экстренные службы.

## Что реализовано сейчас и что в планах

| Возможность | Статус |
|---|---|
| Приём данных платы: heartbeat каждые 10 с, события начала и конца тревоги | есть |
| Статус устройства: норма / тревога / нет связи (порог 30 с) | есть |
| Журнал событий: начало, конец, длительность | есть |
| Push-уведомления в Android-приложение всем участникам устройства | есть |
| Несколько пользователей на одно устройство, защита ключа (SHA-256) | есть |
| Температура и влажность (DHT11) передаются на сервер | есть |
| Различение «газ / пожар» по росту температуры | в планах |
| Объекты и зоны, ответственный за тревогу, плановые проверки датчиков | в планах |
