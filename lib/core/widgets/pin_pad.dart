import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

class PinPad extends StatefulWidget {
  final int pinLength;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onPinComplete;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onBiometricPressed;
  final bool showBiometricButton;
  final int? lockoutSecondsRemaining;
  final int? lockoutRemainingSeconds;
  final String? errorMessage;

  const PinPad({
    super.key,
    this.pinLength = 6,
    this.onCompleted,
    this.onPinComplete,
    this.onChanged,
    this.onBiometricPressed,
    this.showBiometricButton = false,
    this.lockoutSecondsRemaining,
    this.lockoutRemainingSeconds,
    this.errorMessage,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _enteredPin = '';
  int _countdown = 0;
  Timer? _timer;

  int? get _effectiveLockout =>
      widget.lockoutRemainingSeconds ?? widget.lockoutSecondsRemaining;

  @override
  void initState() {
    super.initState();
    if (_effectiveLockout != null && _effectiveLockout! > 0) {
      _startCountdown(_effectiveLockout!);
    }
  }

  @override
  void didUpdateWidget(covariant PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldEffective =
        oldWidget.lockoutRemainingSeconds ?? oldWidget.lockoutSecondsRemaining;
    if (_effectiveLockout != oldEffective &&
        _effectiveLockout != null &&
        _effectiveLockout! > 0) {
      _startCountdown(_effectiveLockout!);
    }
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() {
      _countdown = seconds;
      _enteredPin = '';
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
      } else {
        setState(() => _countdown--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleDigit(String digit) {
    if (_countdown > 0) return;
    if (_enteredPin.length >= widget.pinLength) return;

    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin += digit;
    });

    widget.onChanged?.call(_enteredPin);

    if (_enteredPin.length == widget.pinLength) {
      (widget.onCompleted ?? widget.onPinComplete)?.call(_enteredPin);
    }
  }

  void _handleBackspace() {
    if (_countdown > 0 || _enteredPin.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
    widget.onChanged?.call(_enteredPin);
  }

  void clear() {
    setState(() {
      _enteredPin = '';
    });
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Lockout banner or PIN dots
        if (_countdown > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.statusDanger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.statusDanger.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, color: AppColors.statusDanger, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Locked out: try again in $_countdown seconds',
                  style: const TextStyle(
                    color: AppColors.statusDanger,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ] else ...[
          // Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.pinLength, (index) {
              final isFilled = index < _enteredPin.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFilled
                      ? AppColors.primaryTeal
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  border: Border.all(
                    color: isFilled ? AppColors.primaryTeal : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              );
            }),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.statusDanger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.statusDanger.withOpacity(0.3)),
              ),
              child: Text(
                widget.errorMessage!,
                style: const TextStyle(
                  color: AppColors.statusDanger,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
        ],

        // 3x4 Keypad Grid
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            children: [
              _buildRow(['1', '2', '3']),
              const SizedBox(height: 16),
              _buildRow(['4', '5', '6']),
              const SizedBox(height: 16),
              _buildRow(['7', '8', '9']),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Biometric or empty
                  if (widget.showBiometricButton && widget.onBiometricPressed != null)
                    _buildActionButton(
                      icon: Icons.fingerprint,
                      onTap: widget.onBiometricPressed!,
                      color: AppColors.primaryTeal,
                    )
                  else
                    const SizedBox(width: 72, height: 72),
                  _buildDigitButton('0'),
                  _buildActionButton(
                    icon: Icons.backspace_outlined,
                    onTap: _handleBackspace,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildDigitButton(d)).toList(),
    );
  }

  Widget _buildDigitButton(String digit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = _countdown == 0;

    return InkWell(
      onTap: isEnabled ? () => _handleDigit(digit) : null,
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Text(
          digit,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: _countdown == 0 ? onTap : null,
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
