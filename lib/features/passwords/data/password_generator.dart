import 'dart:math';

class PasswordGeneratorConfig {
  final int length;
  final bool includeUppercase;
  final bool includeLowercase;
  final bool includeNumbers;
  final bool includeSymbols;

  const PasswordGeneratorConfig({
    this.length = 16,
    this.includeUppercase = true,
    this.includeLowercase = true,
    this.includeNumbers = true,
    this.includeSymbols = true,
  });

  PasswordGeneratorConfig copyWith({
    int? length,
    bool? includeUppercase,
    bool? includeLowercase,
    bool? includeNumbers,
    bool? includeSymbols,
  }) {
    return PasswordGeneratorConfig(
      length: length ?? this.length,
      includeUppercase: includeUppercase ?? this.includeUppercase,
      includeLowercase: includeLowercase ?? this.includeLowercase,
      includeNumbers: includeNumbers ?? this.includeNumbers,
      includeSymbols: includeSymbols ?? this.includeSymbols,
    );
  }
}

/// Cryptographically secure random password generator.
/// Uses Random.secure() and Fisher-Yates shuffle to ensure unbiased entropy.
class PasswordGenerator {
  static const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
  static const String numberChars = '0123456789';
  static const String symbolChars = '!@#\$%^&*()-_=+[]{}|;:,.<>?';

  static String generate(PasswordGeneratorConfig config) {
    if (config.length < 12 || config.length > 64) {
      throw ArgumentError('Password length must be between 12 and 64 characters.');
    }

    final random = Random.secure();
    final List<String> pools = [];
    final List<String> guaranteedChars = [];

    if (config.includeUppercase) {
      pools.add(uppercaseChars);
      guaranteedChars.add(uppercaseChars[random.nextInt(uppercaseChars.length)]);
    }
    if (config.includeLowercase) {
      pools.add(lowercaseChars);
      guaranteedChars.add(lowercaseChars[random.nextInt(lowercaseChars.length)]);
    }
    if (config.includeNumbers) {
      pools.add(numberChars);
      guaranteedChars.add(numberChars[random.nextInt(numberChars.length)]);
    }
    if (config.includeSymbols) {
      pools.add(symbolChars);
      guaranteedChars.add(symbolChars[random.nextInt(symbolChars.length)]);
    }

    if (pools.isEmpty) {
      // Fallback to lowercase + uppercase if all disabled
      pools.add(lowercaseChars);
      pools.add(uppercaseChars);
      guaranteedChars.add(lowercaseChars[random.nextInt(lowercaseChars.length)]);
      guaranteedChars.add(uppercaseChars[random.nextInt(uppercaseChars.length)]);
    }

    final combinedPool = pools.join();
    final List<String> result = List.from(guaranteedChars);

    final remaining = config.length - result.length;
    for (int i = 0; i < remaining; i++) {
      result.add(combinedPool[random.nextInt(combinedPool.length)]);
    }

    // Cryptographic Fisher-Yates shuffle
    for (int i = result.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = result[i];
      result[i] = result[j];
      result[j] = temp;
    }

    return result.join();
  }
}

