import 'package:flutter/services.dart';

/// What a field accepts, read from its keyboard type, so every field in the app only takes what it is for:
/// phone → digits, at most 10 (the +91 sits in front) · number → digits · decimal number → digits and one
/// "." with 2 places (kg, cm) · email → no spaces. Text fields get nothing extra.
List<TextInputFormatter> inputRules(TextInputType? k) {
  if (k == null) return const [];
  if (k.index == TextInputType.phone.index) return [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)];
  if (k.index == TextInputType.number.index) {
    return k.decimal == true
        ? [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,4}([.,]\d{0,2})?')), _CommaToDot()]
        : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)];
  }
  if (k.index == TextInputType.emailAddress.index) return [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(254)];
  return const [];
}

class _CommaToDot extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) => newValue.copyWith(text: newValue.text.replaceAll(',', '.'));
}

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$');

/// A real-looking email ("riya@example.com"); empty is allowed where the field is optional.
bool isEmail(String v) => _email.hasMatch(v.trim());

/// An Indian mobile number: 10 digits starting 6–9 (with or without +91 / spaces).
bool isMobile(String v) {
  var d = v.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  return RegExp(r'^[6-9]\d{9}$').hasMatch(d);
}
