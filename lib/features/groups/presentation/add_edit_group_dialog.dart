import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/document_group_model.dart';

class AddEditGroupDialog extends ConsumerStatefulWidget {
  final DocumentGroupModel? editGroup;

  const AddEditGroupDialog({super.key, this.editGroup});

  static Future<DocumentGroupModel?> show(
    BuildContext context, {
    DocumentGroupModel? editGroup,
  }) {
    return showModalBottomSheet<DocumentGroupModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEditGroupDialog(editGroup: editGroup),
    );
  }

  @override
  ConsumerState<AddEditGroupDialog> createState() => _AddEditGroupDialogState();
}

class _AddEditGroupDialogState extends ConsumerState<AddEditGroupDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late String _selectedIcon;
  late int _selectedColor;
  bool _isSaving = false;

  static const List<Map<String, dynamic>> _availableIcons = [
    {'name': 'folder_rounded', 'icon': Icons.folder_rounded, 'label': 'General'},
    {'name': 'person_rounded', 'icon': Icons.person_rounded, 'label': 'Personal'},
    {'name': 'directions_car_rounded', 'icon': Icons.directions_car_rounded, 'label': 'Vehicle'},
    {'name': 'school_rounded', 'icon': Icons.school_rounded, 'label': 'Education'},
    {'name': 'local_hospital_rounded', 'icon': Icons.local_hospital_rounded, 'label': 'Medical'},
    {'name': 'account_balance_rounded', 'icon': Icons.account_balance_rounded, 'label': 'Banking'},
    {'name': 'home_rounded', 'icon': Icons.home_rounded, 'label': 'Property'},
    {'name': 'shield_rounded', 'icon': Icons.shield_rounded, 'label': 'Insurance'},
    {'name': 'family_restroom_rounded', 'icon': Icons.family_restroom_rounded, 'label': 'Family'},
    {'name': 'work_rounded', 'icon': Icons.work_rounded, 'label': 'Work'},
    {'name': 'flight_rounded', 'icon': Icons.flight_rounded, 'label': 'Travel'},
    {'name': 'receipt_long_rounded', 'icon': Icons.receipt_long_rounded, 'label': 'Tax & Bills'},
    {'name': 'business_center_rounded', 'icon': Icons.business_center_rounded, 'label': 'Business'},
    {'name': 'card_membership_rounded', 'icon': Icons.card_membership_rounded, 'label': 'Certificates'},
    {'name': 'badge_rounded', 'icon': Icons.badge_rounded, 'label': 'Identity'},
  ];

  static const List<int> _availableColors = [
    0xFF3B82F6, // Blue
    0xFF10B981, // Emerald
    0xFFF59E0B, // Amber
    0xFFEF4444, // Red
    0xFF8B5CF6, // Purple
    0xFFEC4899, // Pink
    0xFF06B6D4, // Cyan
    0xFFF97316, // Orange
    0xFF14B8A6, // Teal
    0xFF6366F1, // Indigo
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.editGroup?.name ?? '');
    _descController = TextEditingController(text: widget.editGroup?.description ?? '');
    _selectedIcon = widget.editGroup?.icon ?? 'folder_rounded';
    _selectedColor = widget.editGroup?.colorValue ?? _availableColors.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  IconData _getIconData(String name) {
    for (final item in _availableIcons) {
      if (item['name'] == name) return item['icon'] as IconData;
    }
    return Icons.folder_rounded;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final repo = ref.read(documentGroupRepositoryProvider);
      DocumentGroupModel result;
      if (widget.editGroup != null) {
        result = await repo.updateGroup(
          id: widget.editGroup!.id,
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          icon: _selectedIcon,
          colorValue: _selectedColor,
        );
      } else {
        result = await repo.createGroup(
          name: _nameController.text.trim(),
          description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
          icon: _selectedIcon,
          colorValue: _selectedColor,
        );
      }

      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final isEditing = widget.editGroup != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colors.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(_selectedColor).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconData(_selectedIcon),
                        color: Color(_selectedColor),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit Document Group' : 'Create Document Group',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Group Name *',
                    hintText: 'e.g. Vehicle Documents, Medical, Travel',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a group name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Brief note about documents organized here',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                Text(
                  'Group Icon',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableIcons.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final item = _availableIcons[i];
                      final isSelected = item['name'] == _selectedIcon;
                      return InkWell(
                        onTap: () => setState(() => _selectedIcon = item['name'] as String),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(_selectedColor).withOpacity(0.2)
                                : colors.cardBackground,
                            border: Border.all(
                              color: isSelected
                                  ? Color(_selectedColor)
                                  : colors.cardBorder,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            item['icon'] as IconData,
                            size: 22,
                            color: isSelected ? Color(_selectedColor) : colors.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Group Color',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableColors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final colorVal = _availableColors[i];
                      final isSelected = colorVal == _selectedColor;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = colorVal),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Color(colorVal),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Color(colorVal).withOpacity(0.5),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      isEditing ? 'Save Changes' : 'Create Group',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Color(_selectedColor),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
