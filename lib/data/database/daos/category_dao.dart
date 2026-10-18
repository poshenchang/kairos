// lib/data/database/daos/category_dao.dart
//
// Drift DAO for the Categories table.

import 'package:drift/drift.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/tables/categories_table.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  /// Emits the full list of categories whenever the table changes.
  Stream<List<Category>> watchAllCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.id)])).watch();

  /// One-shot fetch of every category.
  Future<List<Category>> getAllCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.id)])).get();

  /// Returns the category with [id], or `null` if it does not exist.
  Future<Category?> getCategoryById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Returns category by slug (e.g. 'schoolwork')
  Future<Category?> getCategoryBySlug(String slug) =>
      (select(categories)..where((c) => c.slug.equals(slug))).getSingleOrNull();

  /// Inserts [category] and returns the new row's auto-incremented id.
  Future<int> insertCategory(CategoriesCompanion category) =>
      into(categories).insert(category);

  /// Updates [category] by primary key. Returns `true` if a row was changed.
  Future<bool> updateCategory(CategoriesCompanion category) =>
      update(categories).replace(category);

  /// Deletes non-system category with [id]. Returns the number of deleted rows.
  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((c) => c.id.equals(id) & c.isSystem.equals(false))).go();
}

