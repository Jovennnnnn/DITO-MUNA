import 'package:intl/intl.dart';

class HolidayTracker {
  static final List<String> _fixedHolidays = [
    "01-01", // New Year
    "04-09", // Araw ng Kagitingan
    "05-01", // Labor Day
    "06-12", // Independence Day
    "08-21", // Ninoy Aquino Day
    "11-01", // All Saints Day
    "11-02", // All Souls Day
    "11-30", // Bonifacio Day
    "12-08", // Immaculate Conception
    "12-25", // Christmas Day
    "12-30", // Rizal Day
    "12-31", // Last Day of Year
  ];

  // Specific to Balintawak/Local area fiestas
  static final List<String> _localFiestas = [
    "08-26", // Cry of Pugad Lawin / Balintawak
  ];

  static bool isHoliday(DateTime date) {
    String formattedDate = DateFormat('MM-dd').format(date);
    
    // Check fixed holidays
    if (_fixedHolidays.contains(formattedDate)) return true;
    
    // Check local fiestas
    if (_localFiestas.contains(formattedDate)) return true;

    // Check for weekends (often higher waste volume)
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return true;
    }

    return false;
  }

  static double getMultiplier(DateTime date) {
    if (isHoliday(date)) {
      return 1.2; // 20% increase
    }
    return 1.0;
  }
}
