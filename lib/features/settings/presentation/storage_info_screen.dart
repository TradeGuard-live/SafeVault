import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/encrypted_file_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../authentication/presentation/auth_providers.dart';

class StorageInfoScreen extends ConsumerStatefulWidget {
  const StorageInfoScreen({super.key});

  @override
  ConsumerState<StorageInfoScreen> createState() => _StorageInfoScreenState();
}

class _StorageInfoScreenState extends ConsumerState<StorageInfoScreen> {
  StorageBreakdown? _breakdown;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    final storage = ref.read(storageServiceProvider);
    final breakdown = await storage.getStorageBreakdown();
    if (mounted) {
      setState(() {
        _breakdown = breakdown;
        _isLoading = false;
      });
    }
  }

  Future<void> _cleanTempCache() async {
    final storage = ref.read(storageServiceProvider);
    await storage.wipeEphemeralFiles();
    await _loadStorage();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ephemeral view cache cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Storage Information',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: colors.primaryAccent),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // Total Storage Banner
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: colors.heroGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primaryAccent.withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.pie_chart_outline_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _breakdown?.formattedTotal ?? '0 B',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Total Encrypted Storage Used',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Breakdown Items
                _buildCard([
                  _buildRowItem(
                    icon: Icons.description_outlined,
                    color: colors.primaryAccent,
                    title: 'Encrypted Documents',
                    subtitle:
                        '${_breakdown?.encryptedFilesCount ?? 0} files in private storage',
                    value: _breakdown?.formattedDocuments ?? '0 B',
                  ),
                  Divider(height: 1, color: colors.cardBorder),
                  _buildRowItem(
                    icon: Icons.photo_size_select_actual_outlined,
                    color: const Color(0xFF2563EB),
                    title: 'Encrypted Thumbnails',
                    subtitle: 'Secure cached page previews',
                    value: _breakdown?.formattedThumbnails ?? '0 B',
                  ),
                  Divider(height: 1, color: colors.cardBorder),
                  _buildRowItem(
                    icon: Icons.storage_rounded,
                    color: const Color(0xFF7C3AED),
                    title: 'SQLite Database',
                    subtitle: 'Encrypted metadata & activity logs',
                    value: _breakdown?.formattedDatabase ?? '0 B',
                  ),
                ]),
                const SizedBox(height: 20),

                // Storage Guarantee Info
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security_rounded,
                        color: colors.primaryAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'All vault data is stored exclusively in Android app-private storage (/data/data/com.vault.vault/). Android automatic cloud backups are strictly disabled.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Clean Temp Cache Button
                OutlinedButton.icon(
                  onPressed: _cleanTempCache,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Purge Ephemeral Decryption Cache'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primaryAccent,
                    side: BorderSide(
                      color: colors.primaryAccent.withOpacity(0.5),
                    ),
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    final colors = context.themeColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildRowItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String value,
  }) {
    final colors = context.themeColors;

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: colors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
      ),
      trailing: Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
