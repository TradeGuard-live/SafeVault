import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/security/encryption_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/bank_account_model.dart';

class AddEditBankAccountScreen extends ConsumerStatefulWidget {
  final String? accountId;

  const AddEditBankAccountScreen({super.key, this.accountId});

  @override
  ConsumerState<AddEditBankAccountScreen> createState() => _AddEditBankAccountScreenState();
}

class _AddEditBankAccountScreenState extends ConsumerState<AddEditBankAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bankNameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _accountType = 'savings';
  bool _isFavorite = false;
  bool _isLoading = false;
  bool _isEditing = false;
  DateTime? _createdAt;

  @override
  void initState() {
    super.initState();
    if (widget.accountId != null) {
      _isEditing = true;
      _loadExistingAccount();
    }
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _nicknameCtrl.dispose();
    _holderCtrl.dispose();
    _accountNumberCtrl.dispose();
    _ifscCtrl.dispose();
    _branchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingAccount() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final repo = ref.read(bankVaultRepositoryProvider);
    final account = await repo.getAccountById(widget.accountId!, session.masterKey!);
    if (account != null && mounted) {
      setState(() {
        _bankNameCtrl.text = account.bankName;
        _nicknameCtrl.text = account.nickname ?? '';
        _holderCtrl.text = account.decryptedAccountHolder ?? '';
        _accountNumberCtrl.text = account.decryptedAccountNumber ?? '';
        _ifscCtrl.text = account.decryptedIFSC ?? '';
        _branchCtrl.text = account.decryptedBranch ?? '';
        _accountType = account.accountType;
        _notesCtrl.text = account.decryptedNotes ?? '';
        _isFavorite = account.isFavorite;
        _createdAt = account.createdAt;
      });
    }
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) return;

    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      ErrorDialog.show(context, title: 'Vault Locked', message: 'Please unlock vault.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(bankVaultRepositoryProvider);
      final encService = EncryptionService();
      final id = widget.accountId ?? const Uuid().v4();

      final account = await BankAccountModel.createEncrypted(
        id: id,
        bankName: _bankNameCtrl.text.trim(),
        nickname: _nicknameCtrl.text.trim().isNotEmpty ? _nicknameCtrl.text.trim() : null,
        accountHolder: _holderCtrl.text.trim().isNotEmpty ? _holderCtrl.text.trim() : null,
        accountNumber: _accountNumberCtrl.text.trim(),
        ifsc: _ifscCtrl.text.trim().isNotEmpty ? _ifscCtrl.text.trim().toUpperCase() : null,
        branch: _branchCtrl.text.trim().isNotEmpty ? _branchCtrl.text.trim() : null,
        accountType: _accountType,
        notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
        isFavorite: _isFavorite,
        masterKey: session.masterKey!,
        encryptionService: encService,
      );

      final finalAccount = _isEditing && _createdAt != null
          ? account.copyWith(createdAt: _createdAt, updatedAt: DateTime.now())
          : account;

      if (_isEditing) {
        await repo.updateAccount(finalAccount);
      } else {
        await repo.insertAccount(finalAccount);
      }

      ref.invalidate(allBankAccountsProvider);
      ref.invalidate(favoriteBankAccountsProvider);

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

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Bank Account' : 'Add Bank Account'),
        actions: [
          IconButton(
            icon: Icon(_isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: _isFavorite ? Colors.amber : null),
            tooltip: 'Favorite',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
          TextButton(
            onPressed: _isLoading ? null : _saveAccount,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          children: [
            // Strict Privacy Warning Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.warning.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gpp_bad_outlined, color: colors.warning, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'DO NOT enter ATM PINs, CVVs, UPI PINs, OTPs, or Netbanking passwords. Vault does not support or permit storing transaction credentials.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.warning,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Bank Name
            TextFormField(
              controller: _bankNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Bank Name *',
                hintText: 'e.g. State Bank of India, HDFC Bank, Chase',
                prefixIcon: Icon(Icons.account_balance_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Bank Name is required' : null,
            ),
            const SizedBox(height: 16),

            // Nickname
            TextFormField(
              controller: _nicknameCtrl,
              decoration: const InputDecoration(
                labelText: 'Account Nickname (Optional)',
                hintText: 'e.g. Primary Salary Account, Tax Reserve',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // Account Type Dropdown
            DropdownButtonFormField<String>(
              value: _accountType,
              decoration: const InputDecoration(
                labelText: 'Account Type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'savings', child: Text('Savings Account')),
                DropdownMenuItem(value: 'current', child: Text('Current / Business Account')),
                DropdownMenuItem(value: 'salary', child: Text('Salary Account')),
                DropdownMenuItem(value: 'other', child: Text('Other Account')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _accountType = val);
              },
            ),
            const SizedBox(height: 16),

            // Account Holder Name
            TextFormField(
              controller: _holderCtrl,
              decoration: const InputDecoration(
                labelText: 'Account Holder Name',
                hintText: 'Name as registered with the bank',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),

            // Account Number
            TextFormField(
              controller: _accountNumberCtrl,
              decoration: const InputDecoration(
                labelText: 'Account Number *',
                hintText: 'e.g. 10023456789',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              keyboardType: TextInputType.number,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Account number is required' : null,
            ),
            const SizedBox(height: 16),

            // IFSC / Swift / Routing Code
            TextFormField(
              controller: _ifscCtrl,
              decoration: const InputDecoration(
                labelText: 'IFSC / Routing / SWIFT Code',
                hintText: 'e.g. SBIN0001234',
                prefixIcon: Icon(Icons.code_rounded),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),

            // Branch Name
            TextFormField(
              controller: _branchCtrl,
              decoration: const InputDecoration(
                labelText: 'Branch Name',
                hintText: 'e.g. Downtown Central Branch',
                prefixIcon: Icon(Icons.location_city_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Secure Notes (AES-256-GCM Encrypted)',
                hintText: 'Customer ID, RM contact info, or branch details...',
                prefixIcon: Icon(Icons.note_alt_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // Save Button
            ElevatedButton(
              onPressed: _isLoading ? null : _saveAccount,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(_isEditing ? 'Save Changes' : 'Save Account',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

