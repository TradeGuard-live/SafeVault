class MaskedTextFormatter {
  /// Masks sensitive strings by default, displaying only the last 4 characters.
  /// Example: '123456789012' -> '•••• •••• 9012'
  static String maskDocumentNumber(String? input) {
    if (input == null || input.trim().isEmpty) return 'Not Provided';
    final clean = input.replaceAll(' ', '');
    if (clean.length <= 4) {
      return '•••• $clean';
    }

    final visibleSuffix = clean.substring(clean.length - 4);
    final maskedLength = clean.length - 4;

    // Group in chunks of 4 for readability
    final buffer = StringBuffer();
    for (int i = 0; i < maskedLength; i++) {
      buffer.write('•');
      if ((i + 1) % 4 == 0 && i < maskedLength - 1) {
        buffer.write(' ');
      }
    }
    buffer.write(' ');
    buffer.write(visibleSuffix);
    return buffer.toString();
  }

  /// General masking for notes or sensitive fields
  static String maskGeneral(String? input, {int visibleChars = 3}) {
    if (input == null || input.trim().isEmpty) return 'Not Provided';
    if (input.length <= visibleChars) return '••••';
    final suffix = input.substring(input.length - visibleChars);
    return '••••••••$suffix';
  }
}
