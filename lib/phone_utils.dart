String maskedPhoneNumber(String phoneNumber) {
  final trimmed = phoneNumber.trim();
  if (trimmed.length <= 4) {
    return trimmed;
  }

  return '${trimmed.substring(0, trimmed.length - 4)}XXXX';
}
