import 'package:intl/intl.dart';

/// Date, time, currency, and number formatters for CatchUP.
/// Dates use MM/DD/YYYY and 12-hour time format.
/// Currency uses PHP exclusively (e.g., PHP 1,250.00).
class AppFormatters {
  static final DateFormat _dateFormat = DateFormat('MM/dd/yyyy');
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('MM/dd/yyyy hh:mm a');
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: 'PHP ',
    decimalDigits: 2,
  );
  static final NumberFormat _numberFormat = NumberFormat('#,##0.##');

  static String formatDate(DateTime? date) {
    if (date == null) return '-';
    return _dateFormat.format(date);
  }

  static String formatMonthYear(DateTime? date) {
    if (date == null) return '-';
    return _monthYearFormat.format(date);
  }

  static String formatDateTime(DateTime? date) {
    if (date == null) return '-';
    return _dateTimeFormat.format(date);
  }

  static String formatCurrency(num? amount) {
    if (amount == null) return 'PHP 0.00';
    return _currencyFormat.format(amount);
  }

  static String formatNumber(num? value) {
    if (value == null) return '0';
    return _numberFormat.format(value);
  }
}

/// Form field validators including Philippine phone and email checks.
class AppValidators {
  static String? requiredField(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Validates Philippine mobile number format: 09XXXXXXXXX (11 digits).
  static String? phPhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required.';
    }
    final phoneRegex = RegExp(r'^09\d{9}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Use PH mobile format: 09XXXXXXXXX (11 digits).';
    }
    return null;
  }

  static String? positiveNumber(String? value, [String fieldName = 'Value']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return '$fieldName must be greater than 0.';
    }
    return null;
  }

  static String? nonNegativeNumber(String? value, [String fieldName = 'Value']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required.';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      return '$fieldName must be 0 or greater.';
    }
    return null;
  }
}
