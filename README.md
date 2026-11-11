# CatchUP - Cloud Inventory and Stock Management System

## 1. System Overview

CatchUP is a cross-platform inventory, stock tracking, and business management application built for desktop (Windows) and mobile (Android) devices. The system is designed to provide end-to-end visibility over inventory levels, daily stock movements, supplier engagements, cold storage utilization, spoilage/waste tracking, and staff accounting.

The application operates on Google Firebase services, utilizing Cloud Firestore as its primary real-time database, Firebase Authentication for secure identity management, and Cloud Storage for asset handling. All data is synchronized centrally through the cloud, ensuring that changes made on an Android phone or Windows workstation reflect instantaneously across all authorized devices in real time.

---

## 2. Cloud Architecture and Multi-Client Synchronization

### 2.1 Centralized Cloud Engine
The database backend runs on Google Cloud Firestore under a single unified project schema. Unlike traditional local databases that require manual export/import or file transfer, CatchUP uses continuous real-time snapshot listeners.

### 2.2 Live Multi-Device Sync Flow
- When Client A (e.g., using an Android phone at a delivery bay) records a "Stock In" transaction, the payload is transmitted to Cloud Firestore.
- Firestore executes the write operation and decrements or increments product stock counters atomically.
- All other active sessions (e.g., Client B running the Windows desktop client at the back office) receive the snapshot event through Firestore subscriptions.
- Local UI state updates immediately without requiring a page refresh or manual sync trigger.

---

## 3. CRUD Architecture in CatchUP

The system implements strict Create, Read, Update, and Delete (CRUD) standards tailored for business accounting and audit reliability.

### 3.1 Create (C)
- New records across all domains (Products, Stock In/Out Transactions, Waste Entries, Suppliers, Storage Locations, and User Profiles) are created with structured validation.
- Auto-generated unique identifiers or custom business codes (e.g., product SKUs, transaction reference IDs) ensure data integrity and prevent collision.
- Stock movements validate current stock levels before creating records to prevent negative inventory balances.

### 3.2 Read (R)
- Read operations are performed via asynchronous Firestore collection and document queries.
- Data is mapped into typed Dart domain models before presentation to the UI.
- The UI features real-time search, category filters, supplier filters, and status toggles (Active vs. Archived/Deleted).
- Cached local storage allows swift reading and resilient session recovery even when network connections fluctuate.

### 3.3 Update (U)
- Records such as Product specifications, pricing, low-stock thresholds, supplier contact details, storage facility capacities, and system settings can be modified at any time by authorized roles.
- When an update occurs, updated timestamps and user identifiers are recorded to maintain audit accountability.
- Critical numerical records (such as completed stock transactions) are non-destructive; instead of editing past entries, the system records counterbalancing adjustment or void transactions to keep transaction history verifiable.

### 3.4 Delete (D) - Soft Delete Pattern and Trash Lifecycle
To prevent accidental data loss, inventory discrepancies, and broken relational references, CatchUP uses a Two-Stage Soft Delete architecture:

1. Stage 1: Soft Delete (Move to Trash)
   - When a user deletes a product, supplier, or storage location, the system does not physically erase the document from the cloud database.
   - Instead, the document's `isDeleted` flag is set to `true`, and a `deletedAt` timestamp is attached.
   - The entity is instantly hidden from standard views (Inventory tables, dropdown pickers in Transactions, Supplier lists).
   - This ensures that historical transactions, past waste logs, and financial records that reference this entity remain completely intact and valid.

2. Stage 2: Trash Management (Settings > Trash Bin)
   - The Trash Bin serves as a quarantine holding area accessible to administrators.
   - Administrators can review all soft-deleted items along with their deletion dates.
   - Restore Action: Clears the `isDeleted` flag (`false`), immediately restoring the item back into active inventory, dropdowns, and views.
   - Permanent Delete Action: Executes a hard cloud deletion from Firestore once the administrator verifies that the entity is no longer needed.

---

## 4. User Roles and Access Control

CatchUP enforces role-based permissions to maintain security, operational separation, and accountability:

- Admin: Unrestricted access to all modules, including User Management, Account Provisioning, Global System Settings, and the Soft Delete Trash Bin.
- Manager: Full operational access to Products, Inventory, Stock In/Out Transactions, Waste Records, Suppliers, Storage Facilities, and Analytics Reports. Restricted from user administration and system-level configuration.
- Staff: Operational access to log daily Stock In, Stock Out, and Waste records, as well as viewing products, inventory levels, and storage locations. Restricted from reports, administrative settings, and user management.

---

## 5. Complete System Walkthrough

### 5.1 Authentication and Session Management
- Login Interface: Users sign in using their registered username/email and password.
- Account Self-Registration: New staff and administrators can select "Don't have an account? Create Account" directly on the login screen. Submitting the form securely creates credentials in Firebase Authentication and generates a linked user profile document in Cloud Firestore.
- Session Persistence: A dedicated session manager stores credentials and auth tokens locally. When users reopen the application or reboot their computer, their authenticated session is automatically validated and restored without forcing them back to the login screen.
- Secure Logout: Users can log out at any time from the navigation bar, which terminates the local session and cleans sensitive tokens from memory.

### 5.2 Dashboard Overview
The Dashboard serves as the central command center, offering immediate operational intelligence:
- High-level KPI cards displaying Total Products, In Stock items, Low Stock alerts, and Out of Stock counts.
- Financial overview showing Total Stock Valuation based on unit cost and retail values.
- Real-time Alert Banners highlighting items that have reached or dropped below their minimum stock threshold.
- Quick Action buttons allowing one-click navigation to log Stock In, Stock Out, or new Products.
- Recent Activity Feed showing the latest transaction timestamps, quantities, and operators.

### 5.3 Inventory and Product Management
The Inventory module handles the master product catalog:
- Comprehensive Product Details: Product Name, SKU, Category (e.g., Fish, Crustaceans, Mollusks, Processed), Unit of Measure (kg, boxes, tubs, packs), Unit Cost, Selling Price, Minimum Reorder Threshold, and designated Storage Location.
- Filtering and Search: Fast keyword search across names and SKUs with instant category filtering.
- Visual Identification: Support for product photography stored in Cloud Storage.
- Low Stock Highlighting: Visual color-coded status badges for Normal, Low Stock, and Out of Stock.
- Action Menu: View full item history, edit specifications, or soft-delete items to the Trash Bin.

### 5.4 Stock Transactions (Stock In and Stock Out)
The Transactions module manages all material inward and outward workflows:
- Stock In (Receiving):
  - Records incoming goods from suppliers.
  - Captures Supplier Name, Destination Storage Location, Quantity Received, Batch/Lot Number, Reference/Invoice Number, and Notes.
  - Automatically increments the product's current stock level in the cloud.
- Stock Out (Sales, Dispatch, or Transfer):
  - Records stock leaving the facility.
  - Captures Destination, Customer/Order Reference, Quantity Dispatched, and Date.
  - Validates requested quantity against actual on-hand stock to prevent negative inventory balances.
  - Automatically decrements the product's stock count upon confirmation.
- Transaction Ledger: A chronological, non-editable audit trail showing every stock movement with reference codes, timestamps, and operator IDs.

### 5.5 Waste and Spoilage Tracking
Designed specifically for perishable goods and seafood operations:
- Waste Logging: Allows staff to log unsellable or expired inventory.
- Reason Categorization: Tracks spoilage reasons such as Expired, Freezer Burn, Transit Damage, Handling Loss, or Quality Rejection.
- Automatic Inventory Adjustment: Submitting a waste record immediately deducts the logged quantity from the active product stock.
- Accountability: Keeps an immutable record of financial and physical losses to help managers pinpoint refrigeration issues or handling problems.

### 5.6 Supplier Management
The Suppliers module maintains full contact and procurement histories:
- Supplier Profile: Company Name, Contact Person, Phone, Email, Physical Address, and Supplied Categories.
- Associated Sourcing: Quick cross-referencing of all products supplied by a specific vendor.
- Supplier Status: Active status management with soft-delete capabilities.

### 5.7 Storage Location Management
The Storage module maps out physical warehouse and cold chain facilities:
- Facility Details: Location Name (e.g., Freezer A, Cold Room 2, Dry Warehouse), Facility Type, Temperature Range, and Storage Capacity.
- Product Mapping: View all products currently stored within each physical zone.
- Capacity Auditing: Prevents inventory misplacement and aids temperature-controlled compliance.

### 5.8 Reports, Analytics, and Data Export
The Reporting module provides business intelligence and export capabilities:
- Inventory Valuation Reports: Summarizes current asset value by category and storage location.
- Stock Movement Analysis: Breaks down inward versus outward trends over daily, weekly, or monthly date ranges.
- Waste Loss Analysis: Aggregates financial loss attributable to spoilage, helping reduce future shrinkage.
- Export Capabilities:
  - Formatted PDF generation for formal printing and filing.
  - Spreadsheet (Excel/CSV) export for external accounting and tax auditing.

### 5.9 User Management (Admin Only)
- User Roster: View all system users, their assigned roles, and account activity.
- User Creation and Editing: Administrators can provision accounts and adjust permissions between Admin, Manager, and Staff.
- Deactivation: Allows revoking system access without deleting past transaction records tied to the user.

### 5.10 System Settings and Trash Management
The Settings module controls global parameters and data safety:
- Business Profile: Company Name, Business Registration Number, Contact Information, and Official Address used on exported documents.
- Regional Configuration: Currency formatting (Philippine Peso), timezone, and date format standards.
- Low Stock Threshold Defaults: Sets baseline alerts for new items.
- Trash Bin:
  - View all soft-deleted records.
  - Restore accidentally deleted products, suppliers, or locations with one click.
  - Permanently purge retired records from the cloud database.

---

## 6. Business Logic and Integrity Rules

1. Stock Balance Guarantee: Stock Out and Waste operations are strictly rejected if the entered quantity exceeds available on-hand stock.
2. Relational Integrity: Deleting a product or supplier never invalidates previous historical transactions. Past records retain their historic snapshot data.
3. Single Source of Truth: No business data is hardcoded into client applications. All information is loaded from and verified against Cloud Firestore.
4. Concurrency Safety: Stock movements execute within cloud transactions to prevent race conditions when multiple operators log movements simultaneously.

---

## 7. Deployment and Distribution

The system produces standalone, production-ready release packages for both desktop and mobile platforms:

### 7.1 Android Package (APK)
- Path: `build/app/outputs/flutter-apk/app-release.apk`
- Branded with the custom CatchUP launcher icon.
- Can be distributed directly to Android smartphones and tablets (Android 5.0 and newer).
- Requires standard internet access to communicate with Firebase Cloud services.

### 7.2 Windows Desktop Application (Single Standalone Executable)
- Path: `CatchUP.exe` (or `build/CatchUP.exe`)
- Branded with the custom multi-resolution CatchUP icon.
- Self-contained single executable: All necessary runtime engines, DLL dependencies, assets, and compiled Flutter libraries are bundled directly inside the single executable file.
- Clients do not need to extract ZIP files, configure folders, or install external frameworks. They can place `CatchUP.exe` anywhere (Desktop, Downloads, USB flash drive) and double-click to launch immediately.
- Native 64-bit performance with integrated Firebase desktop synchronization.
