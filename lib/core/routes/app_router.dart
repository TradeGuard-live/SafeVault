import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/authentication/presentation/auth_providers.dart';
import '../../features/authentication/presentation/biometric_auth_screen.dart';
import '../../features/authentication/presentation/pin_auth_screen.dart';
import '../../features/categories/presentation/category_management_screen.dart';
import '../../features/dashboard/presentation/home_dashboard_screen.dart';
import '../../features/dashboard/presentation/main_shell.dart';
import '../../features/documents/domain/document_model.dart';
import '../../features/documents/presentation/add_document_screen.dart';
import '../../features/documents/presentation/all_documents_screen.dart';
import '../../features/documents/presentation/category_documents_screen.dart';
import '../../features/documents/presentation/document_details_screen.dart';
import '../../features/documents/presentation/document_viewer_screen.dart';
import '../../features/expiry/presentation/expiry_dashboard_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/ocr/presentation/ocr_review_screen.dart';
import '../../features/onboarding/presentation/initial_security_setup_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/passwords/presentation/add_edit_password_screen.dart';
import '../../features/passwords/presentation/password_dashboard_screen.dart';
import '../../features/passwords/presentation/password_details_screen.dart';
import '../../features/passwords/presentation/password_generator_screen.dart';
import '../../features/passwords/presentation/password_list_screen.dart';
import '../../features/passwords/presentation/password_security_dashboard_screen.dart';
import '../../features/bank_vault/presentation/add_edit_bank_account_screen.dart';
import '../../features/bank_vault/presentation/bank_account_details_screen.dart';
import '../../features/bank_vault/presentation/bank_account_list_screen.dart';
import '../../features/bank_vault/presentation/bank_vault_dashboard_screen.dart';
import '../../features/scanner/presentation/camera_scanner_screen.dart';
import '../../features/scanner/presentation/scanner_preview_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/settings/presentation/about_privacy_screen.dart';
import '../../features/settings/presentation/general_settings_screen.dart';
import '../../features/settings/presentation/security_settings_screen.dart';
import '../../features/settings/presentation/storage_info_screen.dart';
import '../../features/settings/presentation/theme_selection_screen.dart';
import '../../features/timeline/presentation/activity_timeline_screen.dart';
import '../../features/trash/presentation/trash_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(vaultSessionProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.uri.toString();
      final isAuthFlow = loc == '/splash' ||
          loc == '/welcome' ||
          loc == '/setup' ||
          loc == '/pin-unlock' ||
          loc == '/biometric-unlock';

      // If locked and trying to access sensitive vault pages, redirect to Factor 1 Biometric unlock
      if (!session.isUnlocked && !isAuthFlow) {
        return '/biometric-unlock';
      }

      // If trying to access /pin-unlock without Factor 1 biometric verification, redirect to /biometric-unlock
      if (loc == '/pin-unlock') {
        final coordinator = ref.read(twoFactorCoordinatorProvider);
        if (!coordinator.hasActiveBiometricVerification) {
          return '/biometric-unlock';
        }
      }

      // If unlocked and still sitting on auth/welcome pages, route to dashboard
      if (session.isUnlocked && (loc == '/pin-unlock' || loc == '/biometric-unlock' || loc == '/welcome')) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const InitialSecuritySetupScreen(),
      ),
      GoRoute(
        path: '/biometric-unlock',
        builder: (context, state) => const BiometricAuthScreen(),
      ),
      GoRoute(
        path: '/pin-unlock',
        builder: (context, state) => const PinAuthScreen(),
      ),

      // Main Shell with Bottom Navigation Bar (5 tabs)
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const HomeDashboardScreen(),
          ),
          GoRoute(
            path: '/all-documents',
            builder: (context, state) => const AllDocumentsScreen(),
          ),
          GoRoute(
            path: '/passwords',
            builder: (context, state) => const PasswordDashboardScreen(),
          ),
          GoRoute(
            path: '/bank-vault',
            builder: (context, state) => const BankVaultDashboardScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const GeneralSettingsScreen(),
          ),
        ],
      ),

      // Favorites
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),

      // Passwords Subroutes
      GoRoute(
        path: '/passwords-list',
        builder: (context, state) {
          final cat = state.uri.queryParameters['category'];
          final fav = state.uri.queryParameters['filter'] == 'favorites';
          return PasswordListScreen(initialCategory: cat, filterFavorites: fav);
        },
      ),
      GoRoute(
        path: '/add-password',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final initialPwd = extra?['initialPassword'] as String?;
          return AddEditPasswordScreen(initialPassword: initialPwd);
        },
      ),
      GoRoute(
        path: '/edit-password/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          return AddEditPasswordScreen(entryId: id);
        },
      ),
      GoRoute(
        path: '/password/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return PasswordDetailsScreen(passwordId: id);
        },
      ),
      GoRoute(
        path: '/password-generator',
        builder: (context, state) => const PasswordGeneratorScreen(),
      ),
      GoRoute(
        path: '/password-security',
        builder: (context, state) => const PasswordSecurityDashboardScreen(),
      ),

      // Bank Vault Subroutes
      GoRoute(
        path: '/bank-accounts-list',
        builder: (context, state) {
          final type = state.uri.queryParameters['type'];
          final fav = state.uri.queryParameters['filter'] == 'favorites';
          return BankAccountListScreen(initialType: type, filterFavorites: fav);
        },
      ),
      GoRoute(
        path: '/add-bank-account',
        builder: (context, state) => const AddEditBankAccountScreen(),
      ),
      GoRoute(
        path: '/edit-bank-account/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'];
          return AddEditBankAccountScreen(accountId: id);
        },
      ),
      GoRoute(
        path: '/bank-account/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return BankAccountDetailsScreen(accountId: id);
        },
      ),

      // Category Documents
      GoRoute(
        path: '/category/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? 'other';
          final name = (state.extra as String?) ?? 'Category Documents';
          return CategoryDocumentsScreen(categoryId: id, categoryName: name);
        },
      ),

      // Document Details
      GoRoute(
        path: '/document/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return DocumentDetailsScreen(documentId: id);
        },
      ),

      // Add Document
      GoRoute(
        path: '/add-document',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AddDocumentScreen(
            initialFilePath: extra?['initialFilePath'] as String?,
            mimeType: extra?['mimeType'] as String?,
            initialFileName: extra?['initialFileName'] as String?,
            ocrData: extra?['ocrData'] as Map<String, dynamic>?,
          );
        },
      ),

      // Camera Scanner
      GoRoute(
        path: '/camera-scanner',
        builder: (context, state) => const CameraScannerScreen(),
      ),

      // Scanner Preview
      GoRoute(
        path: '/scanner-preview',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final pagePaths = (extra['pagePaths'] as List<dynamic>?) ?? (extra['scannedPages'] as List<dynamic>);
          return ScannerPreviewScreen(
            pagePaths: pagePaths.cast<String>(),
          );
        },
      ),

      // OCR Review
      GoRoute(
        path: '/ocr-review',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final imagePath = extra['imagePath'] as String;
          return OcrReviewScreen(imagePath: imagePath);
        },
      ),

      // Document Viewer
      GoRoute(
        path: '/document-viewer',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final docName = (extra['documentName'] as String?) ??
              (extra['document'] as DocumentModel?)?.name ??
              'Document';
          final encPath = (extra['encryptedFilePath'] as String?) ??
              (extra['filePath'] as String?) ??
              '';
          final mime = extra['mimeType'] as String? ?? 'application/pdf';
          final fName = extra['fileName'] as String? ?? 'document';
          return DocumentViewerScreen(
            documentName: docName,
            encryptedFilePath: encPath,
            mimeType: mime,
            fileName: fName,
          );
        },
      ),

      // Expiry Dashboard
      GoRoute(
        path: '/expiry-dashboard',
        builder: (context, state) => const ExpiryDashboardScreen(),
      ),

      // Activity Timeline
      GoRoute(
        path: '/activity-timeline',
        builder: (context, state) => const ActivityTimelineScreen(),
      ),

      // Trash & Recovery
      GoRoute(
        path: '/trash',
        builder: (context, state) => const TrashScreen(),
      ),

      // Search
      GoRoute(
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),

      // Security Settings
      GoRoute(
        path: '/security-settings',
        builder: (context, state) => const SecuritySettingsScreen(),
      ),

      // Storage Info
      GoRoute(
        path: '/storage-info',
        builder: (context, state) => const StorageInfoScreen(),
      ),

      // Category Management
      GoRoute(
        path: '/category-management',
        builder: (context, state) => const CategoryManagementScreen(),
      ),

      // About & Privacy
      GoRoute(
        path: '/about-privacy',
        builder: (context, state) => const AboutPrivacyScreen(),
      ),

      // Theme Selection Screen
      GoRoute(
        path: '/theme-selector',
        builder: (context, state) => const ThemeSelectionScreen(),
      ),
    ],
  );
});
