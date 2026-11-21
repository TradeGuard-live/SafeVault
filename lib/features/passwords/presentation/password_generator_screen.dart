import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/clipboard_security_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../data/password_generator.dart';

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});

  @override
  State<PasswordGeneratorScreen> createState() =>
      _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> {
  int _length = 16;
  bool _includeUpper = true;
  bool _includeLower = true;
  bool _includeNumbers = true;
  bool _includeSymbols = true;
  String _generatedPassword = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    final pwd = PasswordGenerator.generate(
      PasswordGeneratorConfig(
        length: _length,
        includeUppercase: _includeUpper,
        includeLowercase: _includeLower,
        includeNumbers: _includeNumbers,
        includeSymbols: _includeSymbols,
      ),
    );
    setState(() => _generatedPassword = pwd);
  }

  String _getStrengthLabel() {
    if (_length >= 20 &&
        _includeUpper &&
        _includeLower &&
        _includeNumbers &&
        _includeSymbols) {
      return 'Very Strong';
    } else if (_length >= 14) {
      return 'Strong';
    } else {
      return 'Moderate';
    }
  }

  Color _getStrengthColor(AppThemeColors colors) {
    if (_length >= 20 &&
        _includeUpper &&
        _includeLower &&
        _includeNumbers &&
        _includeSymbols) {
      return colors.success;
    } else if (_length >= 14) {
      return colors.primaryAccent;
    } else {
      return colors.warning;
    }
  }

  Future<void> _copyPassword() async {
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _generatedPassword,
      label: 'Generated Password',
    );
  }

  void _saveToVault() {
    context.push(
      '/add-password',
      extra: {'initialPassword': _generatedPassword},
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final strengthColor = _getStrengthColor(colors);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Password Generator')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Generated Password Display Box
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: strengthColor.withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                SelectableText(
                  _generatedPassword,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: strengthColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_getStrengthLabel()} • $_length Characters',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: strengthColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _regenerate,
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Regenerate',
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: _copyPassword,
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy with 30s auto-clear',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Length Slider
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Password Length',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '$_length',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryAccent,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _length.toDouble(),
                  min: 12,
                  max: 64,
                  divisions: 52,
                  activeColor: colors.primaryAccent,
                  onChanged: (val) {
                    setState(() => _length = val.round());
                    _regenerate();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Options Toggles
          Container(
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Uppercase Letters (A-Z)',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _includeUpper,
                  activeColor: colors.primaryAccent,
                  onChanged: (v) {
                    setState(() => _includeUpper = v);
                    _regenerate();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Lowercase Letters (a-z)',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _includeLower,
                  activeColor: colors.primaryAccent,
                  onChanged: (v) {
                    setState(() => _includeLower = v);
                    _regenerate();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Numbers (0-9)',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _includeNumbers,
                  activeColor: colors.primaryAccent,
                  onChanged: (v) {
                    setState(() => _includeNumbers = v);
                    _regenerate();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text(
                    'Symbols (!@#\$%^&*)',
                    style: TextStyle(fontSize: 14),
                  ),
                  value: _includeSymbols,
                  activeColor: colors.primaryAccent,
                  onChanged: (v) {
                    setState(() => _includeSymbols = v);
                    _regenerate();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          ElevatedButton.icon(
            onPressed: _saveToVault,
            icon: const Icon(Icons.save_rounded, size: 20),
            label: const Text(
              'Save Directly to Vault',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _copyPassword,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy to Clipboard (30s auto-clear)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
