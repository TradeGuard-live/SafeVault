import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../data/ocr_extractor.dart';
import '../data/offline_ocr_service.dart';

class OcrReviewScreen extends StatefulWidget {
  final String imagePath;
  final List<dynamic>? allPageBytes;

  const OcrReviewScreen({
    super.key,
    required this.imagePath,
    this.allPageBytes,
  });

  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  final OfflineOcrService _ocrService = OfflineOcrService();

  String _selectedLanguage = 'eng';
  bool _isProcessing = true;
  String _rawExtractedText = '';

  late TextEditingController _nameController;
  late TextEditingController _docNumberController;
  late TextEditingController _ownerController;
  late TextEditingController _authorityController;

  String _selectedCategory = 'personal_identity';
  DateTime? _issueDate;
  DateTime? _expiryDate;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _docNumberController = TextEditingController();
    _ownerController = TextEditingController();
    _authorityController = TextEditingController();

    _runOcrExtraction();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _docNumberController.dispose();
    _ownerController.dispose();
    _authorityController.dispose();
    super.dispose();
  }

  Future<void> _runOcrExtraction() async {
    setState(() => _isProcessing = true);

    final text = await _ocrService.recognizeText(
      imagePath: widget.imagePath,
      language: _selectedLanguage,
    );

    final result = _ocrService.parseMetadata(text);

    setState(() {
      _rawExtractedText = text;
      _nameController.text = result.suggestedName ?? '';
      _docNumberController.text = result.suggestedNumber ?? '';
      _ownerController.text = result.suggestedOwner ?? '';
      _authorityController.text = result.suggestedAuthority ?? '';
      _selectedCategory = result.suggestedCategoryId ?? 'personal_identity';
      _issueDate = result.suggestedIssueDate;
      _expiryDate = result.suggestedExpiryDate;
      _isProcessing = false;
    });
  }

  void _proceedToSave() {
    context.push(
      '/add-document',
      extra: {
        'initialFilePath': widget.imagePath,
        'mimeType': 'image/jpeg',
        'initialFileName': '${_nameController.text.trim()}.jpg',
        'ocrData': {
          'name': _nameController.text.trim(),
          'categoryId': _selectedCategory,
          'documentNumber': _docNumberController.text.trim(),
          'ownerName': _ownerController.text.trim(),
          'issuingAuthority': _authorityController.text.trim(),
          'issueDate': _issueDate,
          'expiryDate': _expiryDate,
        },
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('OCR Metadata Review', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          // Language selector
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedLanguage,
              dropdownColor: isDark ? AppColors.darkCardElevated : AppColors.lightCard,
              icon: const Icon(Icons.language_rounded, size: 20, color: AppColors.primaryTeal),
              items: const [
                DropdownMenuItem(value: 'eng', child: Text('English (eng)')),
                DropdownMenuItem(value: 'hin', child: Text('Hindi (hin)')),
                DropdownMenuItem(value: 'guj', child: Text('Gujarati (guj)')),
              ],
              onChanged: (lang) {
                if (lang != null && lang != _selectedLanguage) {
                  setState(() => _selectedLanguage = lang);
                  _runOcrExtraction();
                }
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primaryTeal),
                  const SizedBox(height: 20),
                  Text(
                    'Recognizing Text (Offline Tesseract)...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Language model: $_selectedLanguage.traineddata',
                    style: const TextStyle(fontSize: 12, color: AppColors.darkTextSecondary),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              children: [
                // Scan Thumbnail Preview
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Security & Privacy Disclaimer
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryTeal.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, color: AppColors.primaryTeal, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'On-Device Offline OCR: Models run 100% locally on your phone. Please verify extracted fields before saving to encrypted storage.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Extracted Document Name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Suggested Document Name',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 12),

                // Extracted Document Number
                TextFormField(
                  controller: _docNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Extracted Document Number',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
                const SizedBox(height: 12),

                // Extracted Owner Name
                TextFormField(
                  controller: _ownerController,
                  decoration: const InputDecoration(
                    labelText: 'Extracted Person / Owner Name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),

                // Extracted Authority
                TextFormField(
                  controller: _authorityController,
                  decoration: const InputDecoration(
                    labelText: 'Suggested Authority',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                  ),
                ),
                const SizedBox(height: 12),

                // Extracted Dates
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Detected Issue Date',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                        ),
                        child: Text(
                          _issueDate != null ? DateFormatter.formatDisplay(_issueDate) : 'Not detected',
                          style: TextStyle(
                            fontSize: 13,
                            color: _issueDate != null
                                ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                : AppColors.darkTextTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Detected Expiry Date',
                          prefixIcon: Icon(Icons.event_busy_outlined, size: 18),
                        ),
                        child: Text(
                          _expiryDate != null ? DateFormatter.formatDisplay(_expiryDate) : 'Not detected',
                          style: TextStyle(
                            fontSize: 13,
                            color: _expiryDate != null
                                ? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
                                : AppColors.darkTextTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Raw Extracted Text Expander
                ExpansionTile(
                  title: const Text('View Raw OCR Text Output', style: TextStyle(fontSize: 13.5)),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCardElevated,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        _rawExtractedText.isEmpty ? 'No text detected.' : _rawExtractedText,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Proceed Button
                ElevatedButton.icon(
                  onPressed: _proceedToSave,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Confirm & Create Document'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

