import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../domain/document_model.dart';

class EditDurationDialog extends StatefulWidget {
  final DocumentModel document;
  final Future<void> Function(bool isTemporary, DateTime? expiresAt) onSave;

  const EditDurationDialog({
    super.key,
    required this.document,
    required this.onSave,
  });

  static Future<void> show(
    BuildContext context, {
    required DocumentModel document,
    required Future<void> Function(bool isTemporary, DateTime? expiresAt) onSave,
  }) {
    return showDialog(
      context: context,
      builder: (_) => EditDurationDialog(
        document: document,
        onSave: onSave,
      ),
    );
  }

  @override
  State<EditDurationDialog> createState() => _EditDurationDialogState();
}

class _EditDurationDialogState extends State<EditDurationDialog> {
  late bool _isTemporary;
  int _durationDays = 7;
  bool _isCustomDuration = false;
  late TextEditingController _customDaysController;
  DateTime? _customExpiryDate;
  bool _isSaving = false;

  static const List<int> _presets = [1, 3, 7, 15, 30, 60, 90];

  @override
  void initState() {
    super.initState();
    _isTemporary = widget.document.isTemporary;
    if (_isTemporary && widget.document.expiresAt != null) {
      final diff = widget.document.expiresAt!.difference(DateTime.now()).inDays;
      _durationDays = diff > 0 ? diff : 1;
      _customDaysController = TextEditingController(text: _durationDays.toString());
      if (!_presets.contains(_durationDays)) {
        _isCustomDuration = true;
      }
    } else {
      _durationDays = 7;
      _customDaysController = TextEditingController(text: '7');
    }
  }

  @override
  void dispose() {
    _customDaysController.dispose();
    super.dispose();
  }

  DateTime get _calculatedExpiry {
    if (_customExpiryDate != null) return _customExpiryDate!;
    return DateTime.now().add(Duration(days: _durationDays));
  }

  Future<void> _pickCustomExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customExpiryDate ?? now.add(Duration(days: _durationDays)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() {
        _customExpiryDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
        _durationDays = _customExpiryDate!.difference(now).inDays;
        _customDaysController.text = _durationDays.toString();
        _isCustomDuration = true;
      });
    }
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      final DateTime? finalExpiry = _isTemporary ? _calculatedExpiry : null;
      await widget.onSave(_isTemporary, finalExpiry);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating duration: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: colors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Icon(
            _isTemporary ? Icons.hourglass_top_rounded : Icons.shield_outlined,
            color: _isTemporary ? colors.warning : colors.primaryAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Document Duration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose whether this document is retained permanently or scheduled for automatic deletion.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            // Mode selector (Permanent vs Temporary)
            Container(
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                      onTap: () => setState(() => _isTemporary = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_isTemporary ? colors.primaryAccent.withValues(alpha: 0.18) : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        ),
                        child: Center(
                          child: Text(
                            'Permanent',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: !_isTemporary ? FontWeight.bold : FontWeight.w500,
                              color: !_isTemporary ? colors.primaryAccent : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                      onTap: () => setState(() => _isTemporary = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _isTemporary ? colors.warning.withValues(alpha: 0.2) : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        ),
                        child: Center(
                          child: Text(
                            'Temporary',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _isTemporary ? FontWeight.bold : FontWeight.w500,
                              color: _isTemporary ? colors.warning : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isTemporary) ...[
              const SizedBox(height: 16),
              Text(
                'Select Duration:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ..._presets.map((d) {
                    final isSelected = !_isCustomDuration && _durationDays == d && _customExpiryDate == null;
                    return ChoiceChip(
                      label: Text(d == 1 ? '1 Day' : '$d Days'),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _isCustomDuration = false;
                            _durationDays = d;
                            _customExpiryDate = null;
                            _customDaysController.text = d.toString();
                          });
                        }
                      },
                      selectedColor: colors.warning.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? colors.warning : colors.textPrimary,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }),
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: _isCustomDuration || _customExpiryDate != null,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _isCustomDuration = true;
                        });
                      }
                    },
                    selectedColor: colors.warning.withValues(alpha: 0.22),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: (_isCustomDuration || _customExpiryDate != null) ? FontWeight.bold : FontWeight.w500,
                      color: (_isCustomDuration || _customExpiryDate != null) ? colors.warning : colors.textPrimary,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ],
              ),
              if (_isCustomDuration) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _customDaysController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Days',
                          hintText: 'e.g. 45',
                          prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val.trim());
                          if (parsed != null && parsed > 0) {
                            setState(() {
                              _durationDays = parsed;
                              _customExpiryDate = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickCustomExpiryDate,
                      icon: const Icon(Icons.calendar_month_rounded, size: 16),
                      label: const Text('Pick Date', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.warningContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: colors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expires: ${DateFormatter.formatDisplay(_calculatedExpiry)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'When this date arrives, SafeVault will move this document to Trash. You will receive notifications 3 days, 1 day, and on expiry.',
                            style: TextStyle(fontSize: 11, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.primaryAccent.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: colors.primaryAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Permanent documents remain in your vault indefinitely without any automatic deletion schedule.',
                        style: TextStyle(fontSize: 11, color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isTemporary ? colors.warning : colors.primaryAccent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }
}
