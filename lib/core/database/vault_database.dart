import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../constants/app_constants.dart';
import '../constants/category_constants.dart';
import '../errors/exceptions.dart';

class VaultDatabase {
  static VaultDatabase? _instance;
  static Database? _db;

  VaultDatabase._();

  static VaultDatabase get instance => _instance ??= VaultDatabase._();

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbPath = join(appDir.path, AppConstants.dbName);

      return await openDatabase(
        dbPath,
        version: 9, // v9 adds temporary documents and custom document groups
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await _createTables(db);
          await _seedDefaultCategories(db);
          await _seedDefaultSettings(db);
          await _createPasswordAndBankTables(db);
          await _seedDefaultPasswordCategories(db);
          await _createExtractionTables(db);
          await _createDraftTables(db);
          await _createCardTables(db);
          await _createGroupTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _createPasswordAndBankTables(db);
            await _seedDefaultPasswordCategories(db);
          }
          if (oldVersion < 3) {
            await _migrateToV3(db);
          }
          if (oldVersion < 4) {
            await _migrateToV4(db);
          }
          if (oldVersion < 5) {
            await _migrateToV5(db);
          }
          if (oldVersion < 6) {
            await _migrateToV6(db);
          }
          if (oldVersion < 7) {
            await _migrateToV7(db);
          }
          if (oldVersion < 8) {
            await _migrateToV8(db);
          }
          if (oldVersion < 9) {
            await _migrateToV9(db);
          }
        },
      );
    } catch (e) {
      throw DatabaseOperationException(
        'Failed to initialize database: ${e.toString()}',
        e,
      );
    }
  }

  Future<void> _createTables(Database db) async {
    // 1. Categories Table (Documents)
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    // 2. Documents Table
    await db.execute('''
      CREATE TABLE documents (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category_id TEXT NOT NULL,
        document_number_enc TEXT,
        owner_name_enc TEXT,
        issuing_authority_enc TEXT,
        issue_date TEXT,
        expiry_date TEXT,
        notes_enc TEXT,
        tags_json TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        thumbnail_enc_path TEXT,
        document_type TEXT,
        is_temporary INTEGER NOT NULL DEFAULT 0,
        expires_at TEXT,
        expiry_status TEXT NOT NULL DEFAULT 'ACTIVE',
        FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE RESTRICT
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_docs_category ON documents(category_id);',
    );
    await db.execute('CREATE INDEX idx_docs_deleted ON documents(deleted_at);');
    await db.execute(
      'CREATE INDEX idx_docs_favorite ON documents(is_favorite);',
    );
    await db.execute('CREATE INDEX idx_docs_expiry ON documents(expiry_date);');
    await db.execute(
      'CREATE INDEX idx_docs_temporary ON documents(is_temporary, expires_at);',
    );

    // 3. Document Files Table
    await db.execute('''
      CREATE TABLE document_files (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        encrypted_file_path TEXT NOT NULL,
        original_file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        page_number INTEGER NOT NULL DEFAULT 1,
        encryption_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_files_doc ON document_files(document_id);',
    );

    // 4. Activities / Timeline Table
    await db.execute('''
      CREATE TABLE activities (
        id TEXT PRIMARY KEY,
        document_id TEXT,
        document_name TEXT NOT NULL,
        activity_type TEXT NOT NULL,
        details TEXT,
        timestamp TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX idx_activities_time ON activities(timestamp DESC);',
    );

    // 5. Expiry Reminders Table
    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        reminder_type TEXT NOT NULL,
        days_before INTEGER NOT NULL,
        scheduled_date TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        notification_id INTEGER NOT NULL,
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
      );
    ''');

    // 6. Settings Table
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        theme_mode TEXT NOT NULL DEFAULT 'system',
        biometric_enabled INTEGER NOT NULL DEFAULT 1,
        auto_lock_duration INTEGER NOT NULL DEFAULT 0,
        screenshot_protection INTEGER NOT NULL DEFAULT 1,
        notifications_enabled INTEGER NOT NULL DEFAULT 1,
        trash_retention_days INTEGER NOT NULL DEFAULT 30
      );
    ''');
  }

  Future<void> _createPasswordAndBankTables(Database db) async {
    // 7. Password Categories Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS password_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    // 8. Password Entries Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS password_entries (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        website_url TEXT,
        username_enc TEXT,
        email_enc TEXT,
        password_enc TEXT NOT NULL,
        notes_enc TEXT,
        category_id TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_accessed_at TEXT,
        FOREIGN KEY (category_id) REFERENCES password_categories (id) ON DELETE RESTRICT
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_passwords_cat ON password_entries(category_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_passwords_fav ON password_entries(is_favorite);',
    );

    // 9. Bank Accounts Table
    // Strictly NO ATM PINs, CVVs, UPI PINs, OTPs, or Netbanking passwords.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bank_accounts (
        id TEXT PRIMARY KEY,
        bank_name TEXT NOT NULL,
        account_holder_enc TEXT,
        account_number_enc TEXT NOT NULL,
        ifsc_enc TEXT,
        branch_enc TEXT,
        account_type TEXT NOT NULL DEFAULT 'savings',
        nickname TEXT,
        notes_enc TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_fav ON bank_accounts(is_favorite);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bank_type ON bank_accounts(account_type);',
    );
  }

  Future<void> _seedDefaultCategories(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    for (final cat in CategoryConstants.defaultCategories) {
      batch.insert('categories', {
        'id': cat.id,
        'name': cat.name,
        'icon': cat.icon,
        'color_value': cat.colorValue,
        'is_default': 1,
        'created_at': now,
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> _seedDefaultPasswordCategories(Database db) async {
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();

    final defaultPasswordCategories = [
      {
        'id': 'social',
        'name': 'Social Media',
        'icon': 'people_rounded',
        'color_value': 0xFF3B82F6,
      },
      {
        'id': 'email',
        'name': 'Email',
        'icon': 'email_rounded',
        'color_value': 0xFFEF4444,
      },
      {
        'id': 'banking',
        'name': 'Banking Services',
        'icon': 'account_balance_rounded',
        'color_value': 0xFF10B981,
      },
      {
        'id': 'shopping',
        'name': 'Shopping',
        'icon': 'shopping_bag_rounded',
        'color_value': 0xFFF59E0B,
      },
      {
        'id': 'developer',
        'name': 'Developer Accounts',
        'icon': 'code_rounded',
        'color_value': 0xFF8B5CF6,
      },
      {
        'id': 'work',
        'name': 'Work Accounts',
        'icon': 'business_center_rounded',
        'color_value': 0xFF06B6D4,
      },
      {
        'id': 'entertainment',
        'name': 'Entertainment',
        'icon': 'movie_rounded',
        'color_value': 0xFFEC4899,
      },
      {
        'id': 'government',
        'name': 'Government Services',
        'icon': 'account_balance_wallet_rounded',
        'color_value': 0xFF6366F1,
      },
      {
        'id': 'other',
        'name': 'Other',
        'icon': 'vpn_key_rounded',
        'color_value': 0xFF64748B,
      },
    ];

    for (final cat in defaultPasswordCategories) {
      batch.insert('password_categories', {
        'id': cat['id'],
        'name': cat['name'],
        'icon': cat['icon'],
        'color_value': cat['color_value'],
        'is_default': 1,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    await batch.commit(noResult: true);
  }

  Future<void> _seedDefaultSettings(Database db) async {
    await db.insert('settings', {
      'id': 1,
      'theme_mode': 'system',
      'biometric_enabled': 1,
      'auto_lock_duration': 0, // immediate
      'screenshot_protection': 1,
      'notifications_enabled': 1,
      'trash_retention_days': 30,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _createExtractionTables(Database db) async {
    // 1. Document Extractions Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_extractions (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        document_type TEXT,
        extracted_text_encrypted TEXT,
        encrypted_txt_file_path TEXT,
        extraction_engine TEXT NOT NULL,
        language TEXT NOT NULL,
        page_count INTEGER NOT NULL DEFAULT 1,
        extraction_status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_extractions_doc ON document_extractions(document_id);',
    );

    // 2. Extracted Fields Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS extracted_fields (
        id TEXT PRIMARY KEY,
        extraction_id TEXT NOT NULL,
        document_id TEXT,
        field_name TEXT NOT NULL,
        encrypted_value TEXT NOT NULL,
        confidence REAL NOT NULL,
        confidence_category TEXT NOT NULL,
        source_page INTEGER NOT NULL DEFAULT 1,
        verification_status TEXT NOT NULL DEFAULT 'unverified',
        is_selected INTEGER NOT NULL DEFAULT 1,
        is_verified INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (extraction_id) REFERENCES document_extractions (id) ON DELETE CASCADE
      );
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_fields_extraction ON extracted_fields(extraction_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_fields_doc ON extracted_fields(document_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_fields_selected ON extracted_fields(is_selected);',
    );
  }

  Future<void> _migrateToV3(Database db) async {
    await _createExtractionTables(db);
    // Add columns to existing documents table safely if not present
    try {
      await db.execute(
        'ALTER TABLE documents ADD COLUMN extraction_status TEXT DEFAULT "completed";',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE documents ADD COLUMN extracted_txt_enc_path TEXT;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE document_files ADD COLUMN encrypted_txt_path TEXT;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE document_files ADD COLUMN extraction_version INTEGER DEFAULT 1;',
      );
    } catch (_) {}
  }

  Future<void> _migrateToV4(Database db) async {
    await _createDraftTables(db);
  }

  Future<void> _migrateToV5(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE extracted_fields ADD COLUMN document_id TEXT;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE extracted_fields ADD COLUMN is_selected INTEGER NOT NULL DEFAULT 1;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE extracted_fields ADD COLUMN is_verified INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE document_extractions ADD COLUMN document_type TEXT;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_fields_doc ON extracted_fields(document_id);',
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_fields_selected ON extracted_fields(is_selected);',
      );
    } catch (_) {}
  }

  /// Password entries deliberately use their own category table so their
  /// defaults (Social, Banking, Developer, etc.) remain focused on accounts.
  /// Custom categories created in Manage Categories, however, are user-owned
  /// and should be usable everywhere. Mirror existing custom categories when
  /// upgrading an installed vault.
  Future<void> _migrateToV6(Database db) async {
    await _createPasswordAndBankTables(db);
    await db.execute('''
      INSERT OR IGNORE INTO password_categories
        (id, name, icon, color_value, is_default, created_at)
      SELECT id, name, icon, color_value, 0, created_at
      FROM categories
      WHERE is_default = 0
    ''');
  }

  Future<void> _migrateToV7(Database db) async {
    await _createCardTables(db);
  }

  Future<void> _migrateToV8(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE payment_cards ADD COLUMN card_number_enc TEXT;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE payment_cards ADD COLUMN start_month INTEGER;',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE payment_cards ADD COLUMN start_year INTEGER;',
      );
    } catch (_) {}
  }

  Future<void> _migrateToV9(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE documents ADD COLUMN is_temporary INTEGER NOT NULL DEFAULT 0;',
      );
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE documents ADD COLUMN expires_at TEXT;');
    } catch (_) {}
    try {
      await db.execute(
        "ALTER TABLE documents ADD COLUMN expiry_status TEXT NOT NULL DEFAULT 'ACTIVE';",
      );
    } catch (_) {}
    try {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_docs_temporary ON documents(is_temporary, expires_at);',
      );
    } catch (_) {}

    await _createGroupTables(db);
  }

  Future<void> _createGroupTables(Database db) async {
    // 11. Custom Document Groups Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        icon TEXT NOT NULL,
        color_value INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_groups_name ON document_groups(name);',
    );

    // 12. Document-to-Group Many-to-Many Join Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_group_memberships (
        document_id TEXT NOT NULL,
        group_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (document_id, group_id),
        FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE,
        FOREIGN KEY (group_id) REFERENCES document_groups (id) ON DELETE CASCADE
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grp_mem_doc ON document_group_memberships(document_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grp_mem_grp ON document_group_memberships(group_id);',
    );
  }

  Future<void> _createCardTables(Database db) async {
    // 10. Payment Cards Table (Credit & Debit Cards)
    // Strictly NO CVVs, ATM PINs, UPI PINs, OTPs, or Magnetic Stripe Data.
    // Card numbers are authenticated and encrypted at rest with AES-256-GCM.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_cards (
        id TEXT PRIMARY KEY,
        card_nickname TEXT NOT NULL,
        cardholder_name_enc TEXT,
        card_number_enc TEXT,
        bank_name TEXT NOT NULL,
        card_type TEXT NOT NULL,
        network TEXT NOT NULL,
        last_four_digits TEXT NOT NULL,
        start_month INTEGER,
        start_year INTEGER,
        expiry_month INTEGER NOT NULL,
        expiry_year INTEGER NOT NULL,
        card_color INTEGER NOT NULL DEFAULT 0,
        notes_enc TEXT,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_fav ON payment_cards(is_favorite);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_type ON payment_cards(card_type);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_network ON payment_cards(network);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_bank ON payment_cards(bank_name COLLATE NOCASE);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cards_expiry ON payment_cards(expiry_year, expiry_month);',
    );
  }

  Future<void> _createDraftTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_drafts (
        id TEXT PRIMARY KEY,
        encrypted_draft_data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }

  /// Erases and deletes the database file (for vault reset).
  Future<void> deleteDatabaseFile() async {
    await close();
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, AppConstants.dbName);
    await deleteDatabase(dbPath);
  }
}
