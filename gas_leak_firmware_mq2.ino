// SafeAir — прошивка для D1 mini (ESP8266)
// Датчики: MQ-2 (аналоговый A0 через делитель 10k/10k), DHT11
// Исполнители: баззер-модуль (I/O на D6), красный и зелёный светодиоды
// Связь: HTTPS POST в Cloudflare Worker (heartbeat и события leak_start / leak_end)

#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include <DHT.h>
#include <time.h>

// Пароли и секреты лежат в secrets.h (его нет в репозитории).
// Скопируй secrets.h.example в secrets.h и впиши свои значения.
#include "secrets.h"

// ====== WiFi ======
const char* ssid = WIFI_SSID;
const char* password = WIFI_PASSWORD;

// ====== Устройство ======
// deviceId должен совпадать с ID документа devices/{deviceId} в Firestore.
// deviceSecret — секрет платы; Worker сверяет его SHA-256 с полем secretHash.
const char* deviceId = DEVICE_ID;
const char* deviceSecret = DEVICE_SECRET;

// ====== URL Cloudflare Worker ======
const char* heartbeatUrl = WORKER_URL "/heartbeat";
const char* gasEventUrl  = WORKER_URL "/gasEvent";

// ====== Пины ======
#define MQ2_PIN     A0   // аналоговый выход MQ-2 (через делитель 10k/10k)
#define DHT_PIN     14   // D5
#define BUZZER_PIN  12   // D6
#define RED_LED_PIN 5    // D1
#define GREEN_LED_PIN 4  // D2

// ====== Настройка баззера ======
// Если баззер-модуль пищит сразу при включении и замолкает при тревоге —
// поставь BUZZER_ACTIVE_LOW = true.
// Если пищать он не хочет, а только щёлкает — это пассивный баззер:
// поставь BUZZER_PASSIVE = true.
// Проверено тестом: баззер пассивный, лучше всего звучит на 2500 Гц.
const bool BUZZER_PASSIVE = true;
const bool BUZZER_ACTIVE_LOW = false;
const int BUZZER_FREQ_HZ = 2500;

// ====== РЕЖИМ СИМУЛЯЦИИ (для проверки связи без нужных датчиков) ======
// SIMULATE_TEMP = true — DHT11 не читается, температура и влажность
//   придумываются: температура плавно растёт 22.0 -> 32.0 каждые 5 сек
//   и сбрасывается, влажность меняется 40..59.
// SIMULATE_GAS = true — MQ-2 не читается, раз в 90 секунд "газ"
//   подскакивает на 20 секунд (срабатывает тревога и уходят события).
// Сейчас: газ настоящий, температура придуманная.
const bool SIMULATE_TEMP = true;
const bool SIMULATE_GAS = false;

// ====== Настройка датчика газа ======
// Прогрев MQ-2 после включения питания. Для демонстрации 60 сек,
// для точной работы лучше 180000 (3 минуты). В симуляции газа — 15 сек.
const unsigned long WARMUP_MS = SIMULATE_GAS ? 15000UL : 60000UL;
// Последние CAL_WINDOW_MS прогрева идёт калибровка по чистому воздуху.
const unsigned long CAL_WINDOW_MS = 10000UL;
// Порог тревоги: значение A0 выше базового на ALARM_DELTA (шкала 0..1023).
// Тревога снимается, когда значение опустится ниже базового + CLEAR_DELTA.
// Подбирай по строке [debug] в мониторе порта.
const int ALARM_DELTA = 100;
const int CLEAR_DELTA = 50;

const unsigned long DEBOUNCE_MS = 300;
const unsigned long gasDuration = 5000UL; // как часто проверять, не ушёл ли газ

// ====== DHT11 ======
DHT dht(DHT_PIN, DHT11);
const unsigned long DHT_INTERVAL = 5000UL;
unsigned long lastDhtRead = 0;
float lastTemp = NAN;
float lastHum = NAN;

// ====== Состояние ======
bool calibrated = false;
long calSum = 0;
int calCount = 0;
int baseline = 0;
int lastGasRaw = 0;

bool stableGas = false;     // газ подтверждён дебаунсом
bool lastRawGas = false;
unsigned long lastChangeTime = 0;

bool gasActive = false;
unsigned long gasStartTime = 0;
unsigned long alarmFirstMillis = 0;

// ====== Общий TLS-клиент ======
WiFiClientSecure secureClient;

// ====== Heartbeat и лог ======
unsigned long lastHeartbeat = 0;
const unsigned long HEARTBEAT_INTERVAL = 10000UL; // раз в 10 сек
unsigned long lastLog = 0;

// ====== Баззер ======
void buzzerOn() {
  if (BUZZER_PASSIVE) {
    tone(BUZZER_PIN, BUZZER_FREQ_HZ);
  } else {
    digitalWrite(BUZZER_PIN, BUZZER_ACTIVE_LOW ? LOW : HIGH);
  }
}

void buzzerOff() {
  if (BUZZER_PASSIVE) {
    noTone(BUZZER_PIN);
    digitalWrite(BUZZER_PIN, BUZZER_ACTIVE_LOW ? HIGH : LOW);
  } else {
    digitalWrite(BUZZER_PIN, BUZZER_ACTIVE_LOW ? HIGH : LOW);
  }
}

// ====== Симулированные значения (режим SIMULATE) ======
int simGas() {
  unsigned long phase = (millis() / 1000UL) % 90UL;
  if (phase >= 60 && phase < 80) {
    return 650; // "утечка" на 20 секунд
  }
  return 200 + (int)random(-8, 9); // чистый воздух с небольшим шумом
}

float simTemp() {
  return 22.0f + ((millis() / 5000UL) % 100UL) * 0.1f; // 22.0 ... 31.9
}

float simHum() {
  return 40.0f + (float)((millis() / 5000UL) % 20UL); // 40 ... 59
}

// ====== Чтение MQ-2 (среднее из 10 замеров) ======
int readGas() {
  if (SIMULATE_GAS) {
    return simGas();
  }
  long sum = 0;
  for (int i = 0; i < 10; i++) {
    sum += analogRead(MQ2_PIN);
    delay(2);
  }
  return (int)(sum / 10);
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n=== SafeAir (MQ-2 + DHT11) ===");
  Serial.print("Reset reason: ");
  Serial.println(ESP.getResetReason());

  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  buzzerOff();
  digitalWrite(GREEN_LED_PIN, LOW);
  digitalWrite(RED_LED_PIN, LOW);

  dht.begin();

  // Самотест: оба светодиода и короткий писк
  digitalWrite(GREEN_LED_PIN, HIGH);
  digitalWrite(RED_LED_PIN, HIGH);
  buzzerOn();
  delay(300);
  buzzerOff();
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(GREEN_LED_PIN, LOW);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi подключен. IP: " + WiFi.localIP().toString());

  // NTP — нужен для проверки сроков TLS-сертификата (UTC+5)
  configTime(5 * 3600, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Синхронизация времени");
  time_t now = time(nullptr);
  while (now < 100000) {
    delay(500);
    Serial.print(".");
    now = time(nullptr);
  }
  Serial.println("\nВремя синхронизировано");

  secureClient.setInsecure();
  secureClient.setBufferSizes(4096, 1024);

  Serial.print("Free heap после setup(): ");
  Serial.println(ESP.getFreeHeap());
  if (SIMULATE_TEMP) {
    Serial.println("*** Температура и влажность СИМУЛИРУЮТСЯ (DHT11 не читается) ***");
  }
  if (SIMULATE_GAS) {
    Serial.println("*** Газ СИМУЛИРУЕТСЯ (MQ-2 не читается) ***");
  }
  Serial.println("Прогрев MQ-2, тревога отключена до конца прогрева...");
}

void loop() {
  unsigned long now = millis();
  lastGasRaw = readGas();

  // ====== DHT11 раз в 5 сек ======
  if (now - lastDhtRead >= DHT_INTERVAL) {
    lastDhtRead = now;
    if (SIMULATE_TEMP) {
      lastTemp = simTemp();
      lastHum = simHum();
    } else {
      float t = dht.readTemperature();
      float h = dht.readHumidity();
      if (!isnan(t)) lastTemp = t;
      if (!isnan(h)) lastHum = h;
    }
  }

  // ====== Прогрев и калибровка ======
  if (!calibrated) {
    static unsigned long lastWarmBlink = 0;
    static bool warmLed = false;
    if (now - lastWarmBlink > 500) {
      warmLed = !warmLed;
      digitalWrite(GREEN_LED_PIN, warmLed);
      lastWarmBlink = now;
    }

    if (now >= WARMUP_MS - CAL_WINDOW_MS && now < WARMUP_MS) {
      calSum += lastGasRaw;
      calCount++;
    }

    if (now >= WARMUP_MS) {
      if (calCount == 0) {
        // Прогрев уже закончился, пока плата подключалась к WiFi
        for (int i = 0; i < 30; i++) {
          calSum += readGas();
          calCount++;
          delay(50);
        }
      }
      baseline = (int)(calSum / calCount);
      calibrated = true;
      digitalWrite(GREEN_LED_PIN, HIGH);
      Serial.print("Калибровка готова. Базовое значение A0 = ");
      Serial.println(baseline);
      Serial.print("Тревога при A0 > ");
      Serial.println(baseline + ALARM_DELTA);
    }
  }

  // ====== Детектор газа с гистерезисом и дебаунсом ======
  if (calibrated) {
    int threshold = stableGas ? (baseline + CLEAR_DELTA) : (baseline + ALARM_DELTA);
    bool rawGas = lastGasRaw > threshold;

    if (rawGas != lastRawGas) {
      lastChangeTime = now;
      lastRawGas = rawGas;
    }
    if (now - lastChangeTime > DEBOUNCE_MS) {
      stableGas = rawGas;
    }

    if (stableGas && !gasActive) {
      Serial.println("\nЗАПУСК ТРЕВОГИ!");
      startAlarm();
      sendGasEvent("leak_start", -1);
    }

    if (gasActive) {
      handleAlarm();
    }
  }

  // ====== Heartbeat ======
  if (now - lastHeartbeat > HEARTBEAT_INTERVAL) {
    lastHeartbeat = now;
    sendHeartbeat();
  }

  // ====== Отладочный лог раз в секунду ======
  if (now - lastLog > 1000) {
    lastLog = now;
    Serial.print("[debug] A0=");
    Serial.print(lastGasRaw);
    Serial.print(" base=");
    Serial.print(baseline);
    Serial.print(" alarm=");
    Serial.print(gasActive ? "YES" : "no");
    Serial.print(" temp=");
    Serial.print(lastTemp);
    Serial.print("C hum=");
    Serial.print(lastHum);
    Serial.print("% heap=");
    Serial.print(ESP.getFreeHeap());
    Serial.print(" wifi=");
    Serial.println(WiFi.status() == WL_CONNECTED ? "OK" : "DOWN");
  }

  delay(100);
}

void startAlarm() {
  buzzerOn();
  gasStartTime = millis();
  alarmFirstMillis = millis();
  gasActive = true;
  digitalWrite(GREEN_LED_PIN, LOW);
}

void handleAlarm() {
  static unsigned long lastBlink = 0;
  static bool redOn = false;

  if (millis() - lastBlink > 300) {
    redOn = !redOn;
    digitalWrite(RED_LED_PIN, redOn);
    lastBlink = millis();
  }

  // Раз в 5 секунд проверяем, не ушёл ли газ (по дебаунсированному состоянию)
  if (millis() - gasStartTime >= gasDuration) {
    if (stableGas) {
      gasStartTime = millis();
    } else {
      unsigned long durationSec = (millis() - alarmFirstMillis) / 1000;
      stopAlarm();
      sendGasEvent("leak_end", (long)durationSec);
    }
  }
}

void stopAlarm() {
  buzzerOff();
  gasActive = false;
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(GREEN_LED_PIN, HIGH);
}

// ====== Heartbeat в Cloudflare Worker ======
void sendHeartbeat() {
  if (WiFi.status() != WL_CONNECTED) return;

  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["secret"] = deviceSecret;
  doc["gas"] = lastGasRaw;
  if (!isnan(lastTemp)) doc["temp"] = lastTemp;
  if (!isnan(lastHum)) doc["hum"] = lastHum;

  String body;
  serializeJson(doc, body);

  String response;
  int httpCode = postJson(heartbeatUrl, body, response);

  Serial.print("[heartbeat] HTTP ");
  Serial.println(httpCode);
  if (httpCode != 200) {
    Serial.println("[heartbeat] ответ: " + response);
  }
}

// ====== Событие утечки в Cloudflare Worker ======
// durationSec = -1 означает "не указывать поле" (для leak_start)
void sendGasEvent(const char* type, long durationSec) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Нет WiFi, событие " + String(type) + " не отправлено");
    return;
  }

  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["secret"] = deviceSecret;
  doc["type"] = type;
  if (durationSec >= 0) {
    doc["durationSec"] = durationSec;
  }
  doc["gas"] = lastGasRaw;
  if (!isnan(lastTemp)) doc["temp"] = lastTemp;

  String body;
  serializeJson(doc, body);

  String response;
  int httpCode = postJson(gasEventUrl, body, response);

  Serial.print("[gasEvent:");
  Serial.print(type);
  Serial.print("] HTTP ");
  Serial.println(httpCode);
  if (httpCode != 200) {
    Serial.println("[gasEvent] ответ: " + response);
  }
}

// ====== HTTPS POST с JSON-телом ======
int postJson(const char* url, const String& jsonBody, String& responseOut) {
  HTTPClient http;

  if (!http.begin(secureClient, url)) {
    responseOut = "http.begin() failed";
    return -1;
  }

  http.addHeader("Content-Type", "application/json");
  http.setTimeout(10000);

  int httpCode = http.POST(jsonBody);
  if (httpCode > 0) {
    responseOut = http.getString();
  } else {
    responseOut = http.errorToString(httpCode);
  }

  http.end();
  return httpCode;
}
