// lib/ui/widgets/category_badge.dart
//
// Chip badge rendering category emoji, name, and color.

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/theme/app_theme.dart';

class CategoryBadge extends ConsumerWidget {
  final String categorySlugOrName;
  final bool compact;

  const CategoryBadge({
    super.key,
    required this.categorySlugOrName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];

    final matched = categories.firstWhereOrNull(
      (c) =>
          c.slug.toLowerCase() == categorySlugOrName.toLowerCase() ||
          c.name.toLowerCase() == categorySlugOrName.toLowerCase(),
    );

    final emoji = matched?.emoji ?? '📌';
    final name = matched?.name ?? categorySlugOrName;
    final color = matched != null
        ? AppTheme.colorFromHex(matched.colorHex)
        : Colors.blueGrey;

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

