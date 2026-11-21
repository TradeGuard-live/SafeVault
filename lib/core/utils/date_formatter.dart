import 'package:intl/intl.dart';

class DateFormatter {
  static final DateFormat _displayFormat = DateFormat('dd MMM yyyy');
  static final DateFormat _displayTimeFormat = DateFormat(
    'dd MMM yyyy, hh:mm a',
  );
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');

  static String formatDisplay(DateTime? date) {
    if (date == null) return 'N/A';
    return _displayFormat.format(date);
  }

  static String formatDate(DateTime? date) => formatDisplay(date);

  static String formatDateTimeDisplay(DateTime? dateTime) {
    if (dateTime == null) return 'N/A';
    return _displayTimeFormat.format(dateTime);
  }

  static String toIso(DateTime date) {
    return _isoFormat.format(date);
  }

  static DateTime? parseIso(String? isoString) {
    if (isoString == null || isoString.isEmpty) return null;
    try {
      return DateTime.parse(isoString);
    } catch (_) {
      return null;
    }
  }

  /// Calculates days remaining until a given date.
  /// Negative if already expired.
  static int daysRemaining(DateTime expiryDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return target.difference(today).inDays;
  }
}
