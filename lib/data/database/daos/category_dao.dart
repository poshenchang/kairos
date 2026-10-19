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

  /// Canonical category ordering: schoolwork -> work -> research -> personal -> social -> commute -> custom -> other (last).
  static List<Category> sortCategories(List<Category> list) {
    final sorted = List<Category>.from(list);
    const preferredOrder = [
      'schoolwork',
      'work',
      'research',
      'personal',
      'social',
      'transportation',
      'commute',
    ];

    sorted.sort((a, b) {
      final slugA = a.slug.toLowerCase();
      final slugB = b.slug.toLowerCase();

      // 'other' always comes last
      if (slugA == 'other' && slugB != 'other') return 1;
      if (slugB == 'other' && slugA != 'other') return -1;

      final idxA = preferredOrder.indexOf(slugA);
      final idxB = preferredOrder.indexOf(slugB);

      if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
      if (idxA != -1) return -1;
      if (idxB != -1) return 1;

      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  /// Emits the full list of categories whenever the table changes.
  Stream<List<Category>> watchAllCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.id)]))
          .watch()
          .map(sortCategories);

  /// One-shot fetch of every category.
  Future<List<Category>> getAllCategories() async {
    final list = await (select(categories)..orderBy([(c) => OrderingTerm.asc(c.id)])).get();
    return sortCategories(list);
  }

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

