// SafeAir — тест баззера на D6 (GPIO12)
// Скетч по кругу пробует 4 способа включить баззер-модуль.
// Красный светодиод (D1) горит, пока идёт попытка со звуком,
// в мониторе порта (115200) пишется номер варианта.
// Запомни, в каком варианте баззер запищал.

#define BUZZER_PIN 12     // D6
#define RED_LED_PIN 5     // D1
#define GREEN_LED_PIN 4   // D2

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);
  pinMode(GREEN_LED_PIN, OUTPUT);
  digitalWrite(RED_LED_PIN, LOW);
  digitalWrite(GREEN_LED_PIN, HIGH);
  Serial.println("\n=== ТЕСТ БАЗЗЕРА (пин D6) ===");
  Serial.println("Каждый вариант: 2 сек звук, потом 2 сек тишина.\n");
}

void phase(int number, const char* title) {
  Serial.print("ВАРИАНТ ");
  Serial.print(number);
  Serial.print(": ");
  Serial.println(title);
  digitalWrite(RED_LED_PIN, HIGH);
}

void pause_() {
  digitalWrite(RED_LED_PIN, LOW);
  noTone(BUZZER_PIN);
  delay(2000);
}

void loop() {
  // 1) Активный баззер, включается ВЫСОКИМ уровнем (HIGH = звук)
  phase(1, "HIGH на I/O (активный, обычный)");
  digitalWrite(BUZZER_PIN, HIGH);
  delay(2000);
  digitalWrite(BUZZER_PIN, LOW);
  pause_();

  // 2) Активный баззер, включается НИЗКИМ уровнем (LOW = звук)
  phase(2, "LOW на I/O (активный, инверсный)");
  digitalWrite(BUZZER_PIN, LOW);
  delay(2000);
  digitalWrite(BUZZER_PIN, HIGH);
  pause_();

  // 3) Пассивный баззер: сигнал 1000 Гц
  phase(3, "tone 1000 Гц (пассивный)");
  tone(BUZZER_PIN, 1000);
  delay(2000);
  pause_();

  // 4) Пассивный баззер: сигнал 2500 Гц (резонанс большинства модулей)
  phase(4, "tone 2500 Гц (пассивный)");
  tone(BUZZER_PIN, 2500);
  delay(2000);
  pause_();

  Serial.println("--- круг завершён, повторяю ---\n");
  delay(1000);
}
