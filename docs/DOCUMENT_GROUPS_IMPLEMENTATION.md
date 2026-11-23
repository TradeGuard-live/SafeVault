# SafeVault — Custom Document Groups Implementation Report

## Executive Summary
This document provides a comprehensive technical overview of the **Custom Document Groups** organization feature in SafeVault (`com.vault.vault`).

The feature empowers users to create unlimited custom groups (e.g., *Tax 2026*, *Family Health*, *Vehicle Documents*, *Home Purchase*, *Travel 2026*) with customizable icons and color themes. Documents can belong to multiple groups simultaneously (a true many-to-many relationship), enabling rich, flexible organization without duplicating files or database records.

---

## 1. Database Architecture & Schema (Version 9)

### 1.1 Tables and Schema Definitions
In [`lib/core/database/vault_database.dart`](file:///home/naman/Desktop/vault/lib/core/database/vault_database.dart), two dedicated tables support custom groups and relationships:

```sql
-- 1. Document Groups Table
CREATE TABLE document_groups (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT NOT NULL DEFAULT 'folder_rounded',
  color_value INTEGER NOT NULL DEFAULT 4280391411,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_groups_name ON document_groups(name);

-- 2. Many-to-Many Membership Join Table
CREATE TABLE document_group_memberships (
  document_id TEXT NOT NULL,
  group_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (document_id, group_id),
  FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
  FOREIGN KEY (group_id) REFERENCES document_groups(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_memberships_doc ON document_group_memberships(document_id);
CREATE INDEX IF NOT EXISTS idx_memberships_group ON document_group_memberships(group_id);
```

### 1.2 Relationship & Cascade Behavior
- **Many-to-Many**: A document can belong to 0, 1, or multiple groups; a group can contain multiple documents.
- **Group Deletion Safety**: Deleting a group removes only its rows in `document_group_memberships`. **The member documents themselves are NEVER deleted.**
- **Document Deletion**: Permanently deleting a document automatically removes its membership associations via cascading foreign key and repository cleanup.
- **Soft Deletion (Trash)**: When a document is moved to Trash (`deleted_at IS NOT NULL`), its memberships remain preserved, so restoring the document immediately restores all its previous group associations.

---

## 2. Real-Time Document Counting & Queries

### 2.1 Active Document Count Calculation
To ensure document counts on group cards are always accurate and exclude trashed documents, [`DocumentGroupRepository`](file:///home/naman/Desktop/vault/lib/features/groups/data/document_group_repository.dart) computes counts via SQL subqueries:

```sql
SELECT g.*, 
  (SELECT COUNT(DISTINCT m.document_id) 
   FROM document_group_memberships m 
   INNER JOIN documents d ON d.id = m.document_id 
   WHERE m.group_id = g.id AND d.deleted_at IS NULL) AS doc_count
FROM document_groups g
ORDER BY g.name COLLATE NOCASE ASC;
```

---

## 3. UI & User Experience

### 3.1 Group Creation & Editing (`AddEditGroupDialog`)
- **Name Field**: With mandatory required-field validation.
- **Optional Description**: For context (e.g., "Car insurance, RC, and driver license").
- **Curated Icon Palette**:
  - `folder_rounded`, `person_rounded`, `directions_car_rounded`, `school_rounded`,
  - `local_hospital_rounded`, `account_balance_rounded`, `home_rounded`, `shield_rounded`,
  - `family_restroom_rounded`, `work_rounded`, `flight_rounded`, `receipt_long_rounded`,
  - `business_center_rounded`, `card_membership_rounded`, `badge_rounded`.
- **Curated Color Palette**:
  - Emerald Green (`0xFF10B981`), Sapphire Blue (`0xFF2563EB`), Violet (`0xFF8B5CF6`),
  - Ruby Red (`0xFFEF4444`), Amber Orange (`0xFFF59E0B`), Cyan (`0xFF06B6D4`),
  - Rose Pink (`0xFFEC4899`), Charcoal Slate (`0xFF475569`).

### 3.2 Groups Overview Screen (`/document-groups`)
- Visual card for each group showing custom icon, custom color badge, name, description, and document count.
- Live search bar filtering groups by name or description.
- Popup menu on each card: Open Group, Edit Group, Delete Group.
- Delete confirmation dialog explicitly informing the user that member documents will not be deleted.
- Empty state with direct "Create First Group" action.

### 3.3 Group Documents Screen (`/group-documents/:id`)
- Prominent header card displaying group color, icon, name, description, and total document count.
- Search and sorting within the group (`Recently Added`, `Name A-Z`, `Expiry Date`).
- **Add Documents to Group Sheet (`AddDocumentsToGroupSheet`)**:
  - Lists existing vault documents not yet in this group.
  - Search and multi-select checkboxes for batch addition.
- **Multi-Select Batch Operations**:
  - Remove selected from group.
  - Assign / Add selected to another group (`GroupPickerSheet`).
  - Move selected documents to Trash.
- Empty state with "Add Documents to Group" button.

### 3.4 Integration in Existing Screens
- **Document Details Screen**: Displays assigned group chips with custom colors and icons; tapping a chip navigates to that group; "Manage Groups" button opens `GroupPickerSheet`.
- **Add / Edit Document Screen**: Dedicated "Document Groups" section with interactive group picker.
- **All Documents Screen**: Horizontal filter bar contains custom group chips; selecting a group filters documents to that group.
- **Home Dashboard**: Two-card quick hub displaying total custom groups and temporary document count with one-tap navigation.

---

## 4. Automated Test Verification
All group features and cascade invariants are verified in [`test/temporary_documents_and_groups_test.dart`](file:///home/naman/Desktop/vault/test/temporary_documents_and_groups_test.dart):
- Group creation, update, and search.
- Many-to-many relationship mapping and membership toggles.
- Real-time `doc_count` dynamic calculation excluding trashed documents.
- Cascade safety: group deletion leaves underlying documents intact.
- UI dialog validation and color/icon palette selection.
