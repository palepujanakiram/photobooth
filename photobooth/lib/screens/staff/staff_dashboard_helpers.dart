/// Pure helpers for staff dashboard date labels and shift duration.
abstract final class StaffDashboardHelpers {
  static const defaultTimezone = 'Asia/Kolkata';

  /// Venue-local calendar day as `YYYY-MM-DD` (default Asia/Kolkata).
  static String todayLocalDate({String timeZone = defaultTimezone}) {
    // Flutter doesn't expose IANA TZ formatting without a package; mirror web
    // by using the device clock converted with a fixed IST offset when needed.
    // Production kiosks run in IST; use UTC+5:30 for the label.
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// True when [isoDate] is `YYYY-MM-DD`.
  static bool isValidIsoDate(String isoDate) {
    return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(isoDate.trim());
  }

  static String formatDayLabel(String isoDate) {
    final parts = isoDate.split('-');
    if (parts.length != 3) return isoDate;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return isoDate;
    final dt = DateTime(y, m, d);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[dt.weekday - 1]}, $d ${months[m - 1]} $y';
  }

  /// Elapsed `Xh Ym` since [start], clamped at zero.
  static String formatElapsed(DateTime start, {DateTime? now}) {
    final end = now ?? DateTime.now();
    var diff = end.difference(start);
    if (diff.isNegative) diff = Duration.zero;
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  static String formatInr(int amount) => '₹$amount';
}
