/// Локализованное форматирование относительного времени и длительностей.
///
/// Три языка ведут себя по-разному:
/// - Русский: полное склонение (1 минута / 2 минуты / 5 минут).
/// - Казахский: числительное НЕ меняет форму существительного вообще
///   (5 минут = "5 минут", 10 минут = "10 минут" — то же слово).
/// - Английский: простое one/other (1 minute / 5 minutes).
///
/// Поэтому это не отдаётся на откуп общему плюрализатору easy_localization,
/// а считается явно здесь — так проще гарантировать правильность для
/// всех трёх разных грамматик сразу.
library duration_format;

String _pluralRu(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && !(mod100 >= 12 && mod100 <= 14)) return few;
  return many;
}

String _unitWord(String languageCode, int count, String unitType) {
  switch (unitType) {
    case 'seconds':
      switch (languageCode) {
        case 'kk':
          return 'секунд';
        case 'en':
          return count == 1 ? 'second' : 'seconds';
        default:
          return _pluralRu(count, 'секунду', 'секунды', 'секунд');
      }
    case 'minutes':
      switch (languageCode) {
        case 'kk':
          return 'минут';
        case 'en':
          return count == 1 ? 'minute' : 'minutes';
        default:
          return _pluralRu(count, 'минуту', 'минуты', 'минут');
      }
    case 'hours':
      switch (languageCode) {
        case 'kk':
          return 'сағат';
        case 'en':
          return count == 1 ? 'hour' : 'hours';
        default:
          return _pluralRu(count, 'час', 'часа', 'часов');
      }
    case 'days':
    default:
      switch (languageCode) {
        case 'kk':
          return 'күн';
        case 'en':
          return count == 1 ? 'day' : 'days';
        default:
          return _pluralRu(count, 'день', 'дня', 'дней');
      }
  }
}

/// Строит короткую строку "5 минут" / "5 минут" (kk) / "5 minutes" — без
/// слов "назад"/"ago", для использования там, где нужна только сама
/// длительность (например, "устранено за X").
String formatShortDuration(String languageCode, int totalSeconds) {
  if (totalSeconds < 60) {
    return '$totalSeconds ${_unitWord(languageCode, totalSeconds, 'seconds')}';
  }
  final minutes = totalSeconds ~/ 60;
  final restSeconds = totalSeconds % 60;
  final minutesPart =
      '$minutes ${_unitWord(languageCode, minutes, 'minutes')}';
  if (restSeconds == 0) return minutesPart;
  return '$minutesPart $restSeconds ${_unitWord(languageCode, restSeconds, 'seconds')}';
}

/// Возвращает (число, слово-единицу) для относительного времени
/// ("была на связи {число} {единица} назад") — сам шаблон с "назад"/"ago"
/// берётся из JSON-переводов через .tr(), а эта функция только считает
/// число и подбирает корректное слово единицы измерения.
class RelativeTimeParts {
  final int value;
  final String unit;
  RelativeTimeParts(this.value, this.unit);
}

RelativeTimeParts relativeTimeParts(
  String languageCode,
  Duration diff,
  String magnitude, // 'seconds' | 'minutes' | 'hours' | 'days'
) {
  switch (magnitude) {
    case 'seconds':
      final s = diff.inSeconds;
      return RelativeTimeParts(s, _unitWord(languageCode, s, 'seconds'));
    case 'minutes':
      final m = diff.inMinutes;
      return RelativeTimeParts(m, _unitWord(languageCode, m, 'minutes'));
    case 'hours':
      final h = diff.inHours;
      return RelativeTimeParts(h, _unitWord(languageCode, h, 'hours'));
    case 'days':
    default:
      final d = diff.inDays;
      return RelativeTimeParts(d, _unitWord(languageCode, d, 'days'));
  }
}
