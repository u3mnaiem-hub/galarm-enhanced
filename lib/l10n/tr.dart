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
  'HOURLY': 'ßá ÓÇÚÉ',
  'DAILY': 'íæãíÇğ',
  'WEEKLY': 'ÃÓÈæÚíÇğ',
  'MONTHLY': 'ÔåÑíÇğ',
  'YEARLY': 'ÓäæíÇğ',
  'NONE': 'ãÑÉ æÇÍÏÉ',
  'Repeat on alternate days': 'ÊßÑÇÑ íæã ÈÚÏ íæã',
  'Repeat every 3 days': 'ÊßÑÇÑ ßá 3 ÃíÇã',
  'Repeat every 2 weeks': 'ÊßÑÇÑ ßá ÃÓÈæÚíä',
  'Repeat every 3 months (quarterly)': 'ÊßÑÇÑ ßá 3 ÔåæÑ',
  'Repeat last day of every month': 'ÊßÑÇÑ ÂÎÑ íæã ãä ßá ÔåÑ',
  'Repeat on 2nd Saturday of every month': 'ÊßÑÇÑ ËÇäí ÓÈÊ ãä ßá ÔåÑ',
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
        'minutes': 'ÏŞíŞÉ',
        'hours': 'ÓÇÚÉ',
        'days': 'íæã',
        'weeks': 'ÃÓÈæÚ',
        'months': 'ÔåÑ',
        'years': 'ÓäÉ',
      };
      return 'ßá ${m.group(1)} ${units[m.group(2)] ?? m.group(2)}';
    }
    return label;
  }
}

extension TrUnitX on BuildContext {
  String trUnit(String unit) {
    if (!isAr) return unit;
    const units = {
      'minutes': 'ÏŞíŞÉ',
      'hours': 'ÓÇÚÉ',
      'days': 'íæã',
      'weeks': 'ÃÓÈæÚ',
      'months': 'ÔåÑ',
      'years': 'ÓäÉ',
    };
    return units[unit] ?? unit;
  }
}
