import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Lightweight bilingual helpers (English / Arabic).
extension TrX on BuildContext {
  bool get isAr => Localizations.localeOf(this).languageCode == 'ar';

  /// Returns [ar] when the app locale is Arabic, otherwise [en].
  String tr(String en, String ar) => isAr ? ar : en;

  /// Locale-aware DateFormat.
  DateFormat df(String pattern) =>
      DateFormat(pattern, Localizations.localeOf(this).languageCode);
}

const _arLabels = <String, String>{
  'HOURLY': 'كل ساعة',
  'DAILY': 'يومياً',
  'WEEKLY': 'أسبوعياً',
  'MONTHLY': 'شهرياً',
  'YEARLY': 'سنوياً',
  'NONE': 'مرة واحدة',
  'Repeat on alternate days': 'تكرار يوم بعد يوم',
  'Repeat every 3 days': 'تكرار كل 3 أيام',
  'Repeat every 2 weeks': 'تكرار كل أسبوعين',
  'Repeat every 3 months (quarterly)': 'تكرار كل 3 أشهر',
  'Repeat last day of every month': 'تكرار آخر يوم من كل شهر',
  'Repeat on 2nd Saturday of every month': 'تكرار ثاني سبت من كل شهر',
};

extension TrLabelX on BuildContext {
  /// Translates a repeat-rule display label when the app is Arabic.
  String trLabel(String label) {
    if (!isAr) return label;
    final hit = _arLabels[label];
    if (hit != null) return hit;
    final m = RegExp(r'^Every (\d+) (\w+)$').firstMatch(label);
    if (m != null) {
      const units = {
        'minutes': 'دقيقة',
        'hours': 'ساعة',
        'days': 'يوم',
        'weeks': 'أسبوع',
        'months': 'شهر',
        'years': 'سنة',
      };
      return 'كل ${m.group(1)} ${units[m.group(2)] ?? m.group(2)}';
    }
    return label;
  }
}

extension TrUnitX on BuildContext {
  String trUnit(String unit) {
    if (!isAr) return unit;
    const units = {
      'minutes': 'دقيقة',
      'hours': 'ساعة',
      'days': 'يوم',
      'weeks': 'أسبوع',
      'months': 'شهر',
      'years': 'سنة',
    };
    return units[unit] ?? unit;
  }
}
