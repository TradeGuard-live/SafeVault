import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/encryption_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../data/password_generator.dart';
import '../domain/password_entry_model.dart';

class AddEditPasswordScreen extends ConsumerStatefulWidget {
  final String? entryId;
  final String? initialPassword;

  const AddEditPasswordScreen({super.key, this.entryId, this.initialPassword});

  @override
  ConsumerState<AddEditPasswordScreen> createState() =>
      _AddEditPasswordScreenState();
}

class _AddEditPasswordScreenState extends ConsumerState<AddEditPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _selectedCategory = 'social';
  bool _isFavorite = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isEditing = false;
  DateTime? _createdAt;

  @override
  void initState() {
    super.initState();
    if (widget.initialPassword != null) {
      _passwordCtrl.text = widget.initialPassword!;
    }
    if (widget.entryId != null) {
      _isEditing = true;
      _loadExistingEntry();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingEntry() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final repo = ref.read(passwordRepositoryProvider);
    final entry = await repo.getEntryById(widget.entryId!, session.masterKey!);
    if (entry != null && mounted) {
      setState(() {
        _titleCtrl.text = entry.title;
        _urlCtrl.text = entry.websiteUrl ?? '';
        _usernameCtrl.text = entry.decryptedUsername ?? '';
        _emailCtrl.text = entry.decryptedEmail ?? '';
        _passwordCtrl.text = entry.decryptedPassword ?? '';
        _notesCtrl.text = entry.decryptedNotes ?? '';
        _selectedCategory = entry.categoryId;
        _isFavorite = entry.isFavorite;
        _createdAt = entry.createdAt;
      });
    }
  }

  void _generateRandomPassword() {
    final generated = PasswordGenerator.generate(
      const PasswordGeneratorConfig(
        length: 16,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
      ),
    );
    setState(() {
      _passwordCtrl.text = generated;
      _obscurePassword = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generated 16-character strong password.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) return;

    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      ErrorDialog.show(
        context,
        title: 'Vault Locked',
        message: 'Please unlock vault.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(passwordRepositoryProvider);
      final encService = EncryptionService();
      final id = widget.entryId ?? const Uuid().v4();

      final entry = await PasswordEntryModel.createEncrypted(
        id: id,
        title: _titleCtrl.text.trim(),
        websiteUrl: _urlCtrl.text.trim().isNotEmpty
            ? _urlCtrl.text.trim()
            : null,
        username: _usernameCtrl.text.trim().isNotEmpty
            ? _usernameCtrl.text.trim()
            : null,
        email: _emailCtrl.text.trim().isNotEmpty
            ? _emailCtrl.text.trim()
            : null,
        password: _passwordCtrl.text,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
        categoryId: _selectedCategory,
        isFavorite: _isFavorite,
        masterKey: session.masterKey!,
        encryptionService: encService,
      );

      final finalEntry = _isEditing && _createdAt != null
          ? entry.copyWith(createdAt: _createdAt, updatedAt: DateTime.now())
          : entry;

      if (_isEditing) {
        await repo.updateEntry(finalEntry);
      } else {
        await repo.insertEntry(finalEntry);
      }

      ref.invalidate(allPasswordsProvider);
      ref.invalidate(favoritePasswordsProvider);
      ref.invalidate(passwordSecurityAuditProvider);

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorDialog.show(context, title: 'Save Failed', message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final categoriesAsync = ref.watch(passwordCategoriesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Password' : 'Add Password'),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _isFavorite ? Colors.amber : null,
            ),
            tooltip: 'Favorite',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          TextButton(
            onPressed: _isLoading ? null : _saveEntry,
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          children: [
            // Title
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Account / Title *',
                hintText: 'e.g. Google, GitHub, Netflix',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 16),

            // Website URL
            TextFormField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Website URL (Optional)',
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.link_rounded),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),

            // Category Dropdown
            categoriesAsync.when(
              data: (cats) {
                return DropdownButtonFormField<String>(
                  value: cats.any((c) => c.id == _selectedCategory)
                      ? _selectedCategory
                      : cats.first.id,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  items: cats.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 6,
                            backgroundColor: Color(c.colorValue),
                          ),
                          const SizedBox(width: 8),
                          Text(c.name),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Username
            TextFormField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username (Optional)',
                hintText: 'e.g. johndoe',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // Email
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email Address (Optional)',
                hintText: 'e.g. john@example.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Password with Generator shortcut
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password *',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      tooltip: 'Toggle Visibility',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.auto_awesome_rounded,
                        color: colors.primaryAccent,
                      ),
                      tooltip: 'Generate Strong Password',
                      onPressed: _generateRandomPassword,
                    ),
                  ],
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Password is required' : null,
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Secure Notes (Encrypted)',
                hintText: 'Add recovery codes, security questions, or notes...',
                prefixIcon: Icon(Icons.note_alt_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveEntry,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      _isEditing ? 'Save Changes' : 'Save Password',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
