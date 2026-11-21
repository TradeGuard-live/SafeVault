import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/encryption_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/payment_card_model.dart';
import 'widgets/payment_card_widget.dart';

/// Formatter that groups card digits into chunks of 4.
class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AddEditCardScreen extends ConsumerStatefulWidget {
  final String? cardId;

  const AddEditCardScreen({super.key, this.cardId});

  @override
  ConsumerState<AddEditCardScreen> createState() => _AddEditCardScreenState();
}

class _AddEditCardScreenState extends ConsumerState<AddEditCardScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nicknameCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _cardNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  CardType _cardType = CardType.credit;
  CardNetwork _network = CardNetwork.visa;

  // Start Date / Valid From (Optional)
  bool _hasStartDate = false;
  int _startMonth = DateTime.now().month;
  int _startYear = DateTime.now().year - 1;

  // Expiry Date / Valid Thru (Required)
  int _expiryMonth = DateTime.now().month;
  int _expiryYear = DateTime.now().year + 3;

  int _cardColor = 0;
  bool _isFavorite = false;
  bool _isLoading = false;
  bool _isEditing = false;
  DateTime? _createdAt;

  @override
  void initState() {
    super.initState();
    if (widget.cardId != null) {
      _isEditing = true;
      _loadExistingCard();
    }
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _holderCtrl.dispose();
    _bankNameCtrl.dispose();
    _cardNumberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExistingCard() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final repo = ref.read(cardRepositoryProvider);
    final card = await repo.getCardById(widget.cardId!, session.masterKey!);
    if (card != null && mounted) {
      setState(() {
        _nicknameCtrl.text = card.cardNickname;
        _holderCtrl.text = card.decryptedCardholderName ?? '';
        _bankNameCtrl.text = card.bankName;
        _cardNumberCtrl.text = card.decryptedCardNumber != null
            ? card.formattedFullCardNumber
            : card.lastFourDigits;
        _cardType = card.cardType;
        _network = card.network;
        _hasStartDate = card.startMonth != null && card.startYear != null;
        if (_hasStartDate) {
          _startMonth = card.startMonth!;
          _startYear = card.startYear!;
        }
        _expiryMonth = card.expiryMonth;
        _expiryYear = card.expiryYear;
        _cardColor = card.cardColor;
        _notesCtrl.text = card.decryptedNotes ?? '';
        _isFavorite = card.isFavorite;
        _createdAt = card.createdAt;
      });
    }
  }

  PaymentCardModel _buildPreviewCard() {
    final cleanDigits = _cardNumberCtrl.text.replaceAll(RegExp(r'\D'), '');
    final last4 = cleanDigits.length >= 4
        ? cleanDigits.substring(cleanDigits.length - 4)
        : cleanDigits.padLeft(4, '0');

    return PaymentCardModel(
      id: widget.cardId ?? 'preview',
      cardNickname: _nicknameCtrl.text.trim().isNotEmpty
          ? _nicknameCtrl.text.trim()
          : 'Card Nickname',
      bankName: _bankNameCtrl.text.trim().isNotEmpty
          ? _bankNameCtrl.text.trim()
          : 'Bank Name',
      cardType: _cardType,
      network: _network,
      lastFourDigits: last4.isNotEmpty ? last4 : '1234',
      startMonth: _hasStartDate ? _startMonth : null,
      startYear: _hasStartDate ? _startYear : null,
      expiryMonth: _expiryMonth,
      expiryYear: _expiryYear,
      cardColor: _cardColor,
      isFavorite: _isFavorite,
      decryptedCardholderName: _holderCtrl.text.trim().isNotEmpty
          ? _holderCtrl.text.trim()
          : 'Cardholder Name',
      decryptedCardNumber: cleanDigits.isNotEmpty ? cleanDigits : null,
      createdAt: _createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;

    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      ErrorDialog.show(
        context,
        title: 'Vault Locked',
        message: 'Please unlock the vault before saving card details.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(cardRepositoryProvider);
      final encService = EncryptionService();
      final id = widget.cardId ?? const Uuid().v4();

      final rawCardNumber = _cardNumberCtrl.text.trim().replaceAll(
        RegExp(r'\D'),
        '',
      );
      final last4 = rawCardNumber.length >= 4
          ? rawCardNumber.substring(rawCardNumber.length - 4)
          : rawCardNumber.padLeft(4, '0');

      final card = await PaymentCardModel.createEncrypted(
        id: id,
        cardNickname: _nicknameCtrl.text.trim(),
        cardholderName: _holderCtrl.text.trim().isNotEmpty
            ? _holderCtrl.text.trim()
            : null,
        fullCardNumber: rawCardNumber.isNotEmpty ? rawCardNumber : null,
        lastFourDigits: last4,
        bankName: _bankNameCtrl.text.trim(),
        cardType: _cardType,
        network: _network,
        startMonth: _hasStartDate ? _startMonth : null,
        startYear: _hasStartDate ? _startYear : null,
        expiryMonth: _expiryMonth,
        expiryYear: _expiryYear,
        cardColor: _cardColor,
        notes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
        isFavorite: _isFavorite,
        masterKey: session.masterKey!,
        encryptionService: encService,
      );

      final finalCard = _isEditing && _createdAt != null
          ? card.copyWith(createdAt: _createdAt, updatedAt: DateTime.now())
          : card;

      if (_isEditing) {
        await repo.updateCard(finalCard);
      } else {
        await repo.createCard(finalCard);
      }

      ref.invalidate(allPaymentCardsProvider);
      ref.invalidate(favoritePaymentCardsProvider);
      ref.invalidate(expiringPaymentCardsProvider);

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
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Payment Card' : 'Add Payment Card',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: _isFavorite ? Colors.amber : colors.textSecondary,
            ),
            tooltip: 'Favorite',
            onPressed: () => setState(() => _isFavorite = !_isFavorite),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          children: [
            // Live Card Preview
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _nicknameCtrl,
                  _holderCtrl,
                  _bankNameCtrl,
                  _cardNumberCtrl,
                ]),
                builder: (context, _) => PaymentCardWidget(
                  card: _buildPreviewCard(),
                  isInteractive: false,
                  showFullWidth: true,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Card Color Theme Palette Picker
            Text(
              'Card Color Theme',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: CardVisualPreset.presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final preset = CardVisualPreset.presets[index];
                  final isSelected = _cardColor == preset.id;
                  return InkWell(
                    onTap: () => setState(() => _cardColor = preset.id),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: preset.gradientColors
                              .map((c) => Color(c))
                              .toList(),
                        ),
                        border: Border.all(
                          color: isSelected
                              ? colors.primaryAccent
                              : colors.cardBorder,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),

            // Card Type Selection: Credit or Debit
            Text(
              'Card Type',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<CardType>(
              segments: const [
                ButtonSegment(
                  value: CardType.credit,
                  label: Text('Credit Card'),
                  icon: Icon(Icons.credit_card_rounded),
                ),
                ButtonSegment(
                  value: CardType.debit,
                  label: Text('Debit Card'),
                  icon: Icon(Icons.payment_rounded),
                ),
              ],
              selected: {_cardType},
              onSelectionChanged: (newSelection) {
                setState(() => _cardType = newSelection.first);
              },
            ),
            const SizedBox(height: 20),

            // Bank Name Field
            TextFormField(
              controller: _bankNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Bank Name *',
                hintText: 'e.g. HDFC Bank, SBI, ICICI Bank',
                prefixIcon: const Icon(Icons.account_balance_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Bank name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Card Nickname Field
            TextFormField(
              controller: _nicknameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Card Nickname *',
                hintText: 'e.g. Primary Rewards, Travel Card',
                prefixIcon: const Icon(Icons.label_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Card nickname is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Cardholder Name (Encrypted with AES-256-GCM)
            TextFormField(
              controller: _holderCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Cardholder Name',
                hintText: 'As printed on the card',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Card Network Dropdown
            DropdownButtonFormField<CardNetwork>(
              value: _network,
              decoration: InputDecoration(
                labelText: 'Card Network *',
                prefixIcon: const Icon(Icons.credit_card_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: CardNetwork.values.map((net) {
                return DropdownMenuItem(
                  value: net,
                  child: Text(net.displayName),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _network = val);
              },
            ),
            const SizedBox(height: 16),

            // Card Number Field (Full 15-19 digits, or last 4)
            TextFormField(
              controller: _cardNumberCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
                LengthLimitingTextInputFormatter(23), // 19 digits + 4 spaces
                CardNumberInputFormatter(),
              ],
              decoration: InputDecoration(
                labelText: 'Card Number *',
                hintText: 'e.g. 4532 1234 5678 9012',
                helperText: 'Encrypted at rest with AES-256-GCM. Masked by default; requires 2FA to reveal.',
                prefixIcon: const Icon(Icons.credit_card_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Card number is required';
                }
                final digitsOnly = v.trim().replaceAll(RegExp(r'\D'), '');
                if (digitsOnly.length < 4 || digitsOnly.length > 19) {
                  return 'Enter a valid card number (13-19 digits or last 4 digits)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Start Date Toggle & Selectors (Valid From)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            color: colors.primaryAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Specify Start Date (Valid From)',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _hasStartDate,
                        activeColor: colors.primaryAccent,
                        onChanged: (val) => setState(() => _hasStartDate = val),
                      ),
                    ],
                  ),
                  if (_hasStartDate) ...[
                    const Divider(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _startMonth,
                            decoration: InputDecoration(
                              labelText: 'Start Month',
                              prefixIcon: const Icon(
                                Icons.calendar_month_outlined,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: List.generate(12, (i) => i + 1).map((m) {
                              return DropdownMenuItem(
                                value: m,
                                child: Text(m.toString().padLeft(2, '0')),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _startMonth = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _startYear,
                            decoration: InputDecoration(
                              labelText: 'Start Year',
                              prefixIcon: const Icon(Icons.event_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: List.generate(15, (i) => currentYear - 8 + i)
                                .map((y) {
                                  return DropdownMenuItem(
                                    value: y,
                                    child: Text(y.toString()),
                                  );
                                })
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _startYear = val);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Expiry Month & Year Row (Valid Thru)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _expiryMonth,
                    decoration: InputDecoration(
                      labelText: 'Expiry Month *',
                      prefixIcon: const Icon(Icons.calendar_month_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: List.generate(12, (i) => i + 1).map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m.toString().padLeft(2, '0')),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _expiryMonth = val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _expiryYear,
                    decoration: InputDecoration(
                      labelText: 'Expiry Year *',
                      prefixIcon: const Icon(Icons.event_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: List.generate(25, (i) => currentYear - 2 + i).map((
                      y,
                    ) {
                      return DropdownMenuItem(
                        value: y,
                        child: Text(y.toString()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _expiryYear = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes (Encrypted at rest)
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Private Notes (Encrypted)',
                hintText: 'e.g. International transactions enabled, reward points balance',
                prefixIcon: const Icon(Icons.notes_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Security Notice Container
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.primaryAccent.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: colors.primaryAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'SafeVault never asks for or stores CVV, ATM PINs, UPI PINs, or OTPs. Card numbers and cardholder notes are authenticated and encrypted at rest with AES-256-GCM.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Action Buttons: Save & Cancel
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveCard,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primaryAccent,
                      foregroundColor: colors.onPrimaryAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isEditing ? 'Save Changes' : 'Save Card',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
