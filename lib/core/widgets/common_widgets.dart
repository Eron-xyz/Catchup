import 'dart:async';
import 'dart:convert';
import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:flutter/material.dart';

/// Standard 10-items-per-page pagination footer bar with CatchUP logo badge
/// and Previous / Next page controls. Automatically adapts to narrow mobile screens
/// so it never overflows.
class CatchUpPaginationBar extends StatelessWidget {
  final int currentPage; // 0-indexed
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const CatchUpPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalItems,
    this.pageSize = 10,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPages =
        totalItems == 0 ? 1 : ((totalItems - 1) ~/ pageSize) + 1;
    final safePage = currentPage.clamp(0, totalPages - 1);
    final startItem = totalItems == 0 ? 0 : (safePage * pageSize) + 1;
    final endItem = ((safePage + 1) * pageSize).clamp(0, totalItems);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 520;
        final borderColor =
            isDark ? AppColors.darkBorder : AppColors.lightBorder;
        final accentColor = Theme.of(context).colorScheme.secondary;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 4 : 8,
            vertical: isMobile ? 8 : 10,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: borderColor, width: 1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CatchUpLogo(
                      iconSize: isMobile ? 20 : 22,
                      fontSize: 0,
                      iconOnly: true,
                      forDarkBackground: isDark,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isMobile
                            ? '$startItem-$endItem of $totalItems'
                            : 'Showing $startItem-$endItem of $totalItems records ($pageSize per page)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isMobile ? 12 : 12.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous Page',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    onPressed: safePage > 0
                        ? () => onPageChanged(safePage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 22),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 10 : 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isMobile
                          ? '${safePage + 1} / $totalPages'
                          : 'Page ${safePage + 1} of $totalPages',
                      style: TextStyle(
                        fontSize: isMobile ? 12 : 12.5,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next Page',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    onPressed: safePage < totalPages - 1
                        ? () => onPageChanged(safePage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 22),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A filter item definition that takes [desktopWidth] on wide screens and
/// stretches to 100% full width on mobile screens for clean alignment.
class ResponsiveFilterItem {
  final double desktopWidth;
  final Widget child;

  const ResponsiveFilterItem({
    this.desktopWidth = 220,
    required this.child,
  });
}

/// Renders search/filter controls with a clean thin bottom divider line (no card box)
/// that wrap horizontally on desktop and stack cleanly at 100% full width on mobile.
class ResponsiveFilterCard extends StatelessWidget {
  final List<ResponsiveFilterItem> items;
  final List<Widget> trailingChips;

  const ResponsiveFilterCard({
    super.key,
    required this.items,
    this.trailingChips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      padding: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 640;
          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  items[i].child,
                ],
                if (trailingChips.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: trailingChips,
                  ),
                ],
              ],
            );
          }

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in items)
                SizedBox(
                  width: item.desktopWidth,
                  child: item.child,
                ),
              ...trailingChips,
            ],
          );
        },
      ),
    );
  }
}

/// Reusable page header that aligns title & subtitle on the left and action buttons
/// on the right on Desktop (`>= 640px`), and stacks action buttons at 100% full width
/// on Mobile (`< 640px`).
class ResponsivePageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const ResponsivePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 640;
        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  actions[i],
                ],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Mobile-first & Desktop-ready module layout:
/// - On Mobile (< 760px): Scrollable full-page view with compact padding, full-width
///   aligned header & filters, the 10 mobile item cards, and the pagination bar at the bottom.
/// - On Desktop (>= 760px): Full-height view with header, filter bar, expanded DataTable card,
///   and fixed pagination footer.
class ResponsiveModulePage extends StatelessWidget {
  final Widget header;
  final Widget filterBar;
  final bool isEmpty;
  final Widget emptyChild;
  final Widget desktopTable;
  final List<Widget> mobileCards;
  final Widget paginationBar;

  const ResponsiveModulePage({
    super.key,
    required this.header,
    required this.filterBar,
    required this.isEmpty,
    required this.emptyChild,
    required this.desktopTable,
    required this.mobileCards,
    required this.paginationBar,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;

        if (isDesktop) {
          return Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 16),
                filterBar,
                const SizedBox(height: 14),
                Expanded(
                  child: isEmpty
                      ? emptyChild
                      : Card(
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: desktopTable),
                              paginationBar,
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        // Mobile View (< 760px): 50/50 design — thin-line header & filter bar at top,
        // with mobile items and pagination inside curved cards separated by thin lines.
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            header,
            const SizedBox(height: 12),
            filterBar,
            const SizedBox(height: 12),
            if (isEmpty)
              emptyChild
            else ...[
              for (int i = 0; i < mobileCards.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                mobileCards[i],
              ],
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: paginationBar,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Full-width DataTable wrapper that stretches columns evenly across the card width
/// while still supporting horizontal scrolling on smaller screens.
class FullWidthDataTable extends StatelessWidget {
  final List<DataColumn> columns;
  final List<DataRow> rows;
  final bool showCheckboxColumn;

  const FullWidthDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.showCheckboxColumn = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                showCheckboxColumn: showCheckboxColumn,
                headingRowColor: WidgetStatePropertyAll(
                  isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : AppColors.sidebarNavy.withValues(alpha: 0.04),
                ),
                columnSpacing: 24,
                horizontalMargin: 20,
                columns: columns,
                rows: rows,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Friendly empty state widget shown when a collection has no records yet.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.sidebarActiveBlue.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: AppColors.sidebarActiveBlue,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Colored status pill badge used across Inventory, Transactions, Products, Storage.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Standard confirmation dialog before destructive actions (void, deactivate).
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  Color confirmColor = AppColors.statusRed,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Dialog that prompts for a required reason before voiding a transaction or waste record.
Future<String?> showVoidReasonDialog({
  required BuildContext context,
  required String title,
  required String subtitle,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for voiding *',
                hintText: 'Enter reason...',
              ),
              validator: (val) => (val == null || val.trim().isEmpty)
                  ? 'Reason is required'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.statusRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(ctx).pop(controller.text.trim());
            }
          },
          child: const Text('Void Record'),
        ),
      ],
    ),
  );
}

/// Animated shimmer skeleton block used for loading skeletons across tables,
/// KPI cards, and lazy-loaded route chunks.
class CatchUpSkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const CatchUpSkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  @override
  State<CatchUpSkeletonBox> createState() => _CatchUpSkeletonBoxState();
}

class _CatchUpSkeletonBoxState extends State<CatchUpSkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : AppColors.sidebarNavy.withValues(alpha: 0.06);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : AppColors.sidebarNavy.withValues(alpha: 0.13);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Color.lerp(baseColor, highlightColor, _controller.value),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          );
        },
      ),
    );
  }
}

/// Full module loading skeleton with the CatchUP logo badge and animated
/// row placeholders for smooth perceived performance during chunk/data loads.
class CatchUpModuleSkeleton extends StatelessWidget {
  final int rows;
  final String message;

  const CatchUpModuleSkeleton({
    super.key,
    this.rows = 5,
    this.message = 'Loading...',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CatchUpSkeletonBox(width: 190, height: 22),
                  SizedBox(height: 8),
                  CatchUpSkeletonBox(width: 280, height: 13),
                ],
              ),
              CatchUpSkeletonBox(width: 130, height: 38, borderRadius: 20),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Expanded(
                      child: Center(
                        child: CatchUpLoadingIndicator(message: 'Loading...'),
                      ),
                    ),
                    for (int i = 0; i < rows; i++) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: borderColor, width: 1),
                          ),
                        ),
                        child: const Row(
                          children: [
                            CatchUpSkeletonBox(width: 36, height: 36, borderRadius: 10),
                            SizedBox(width: 14),
                            Expanded(child: CatchUpSkeletonBox(height: 14)),
                            SizedBox(width: 18),
                            CatchUpSkeletonBox(width: 80, height: 14),
                            SizedBox(width: 18),
                            CatchUpSkeletonBox(width: 72, height: 22, borderRadius: 12),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optimized, sub-sampled image thumbnail widget that decodes images at exact
/// display dimensions (`cacheWidth` / `cacheHeight`) and wraps in `RepaintBoundary`.
class CatchUpCachedThumbnail extends StatelessWidget {
  final String? photoUrl;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;

  const CatchUpCachedThumbnail({
    super.key,
    required this.photoUrl,
    this.size = 40,
    this.borderRadius = 10,
    this.fallbackIcon = Icons.set_meal_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final targetPx = (size * 2).round();

    Widget fallback() => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.sidebarActiveBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Icon(
            fallbackIcon,
            size: size * 0.52,
            color: AppColors.sidebarActiveBlue,
          ),
        );

    if (url == null || url.isEmpty) {
      return fallback();
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: url.startsWith('data:image')
            ? Builder(
                builder: (_) {
                  try {
                    final commaIdx = url.indexOf(',');
                    final bytes = base64Decode(
                      commaIdx != -1 ? url.substring(commaIdx + 1) : url,
                    );
                    return Image.memory(
                      bytes,
                      width: size,
                      height: size,
                      cacheWidth: targetPx,
                      cacheHeight: targetPx,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => fallback(),
                    );
                  } catch (_) {
                    return fallback();
                  }
                },
              )
            : Image.network(
                url,
                width: size,
                height: size,
                cacheWidth: targetPx,
                cacheHeight: targetPx,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return CatchUpSkeletonBox(
                    width: size,
                    height: size,
                    borderRadius: borderRadius,
                  );
                },
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}

/// Floating top-right / top-center Toast notification system that replaces
/// bottom SnackBars across the entire application.
class CatchUpToast {
  CatchUpToast._();

  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  static void success(BuildContext context, String message) {
    show(context, message);
  }

  static void error(BuildContext context, String message) {
    show(context, message, isError: true);
  }

  static void info(BuildContext context, String message) {
    show(context, message, isInfo: true);
  }

  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
    bool isInfo = false,
    Duration duration = const Duration(milliseconds: 2400),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return;

    _dismissTimer?.cancel();
    _activeEntry?.remove();
    _activeEntry = null;

    final Color accentColor = isError
        ? AppColors.statusRed
        : (isInfo ? AppColors.sidebarActiveBlue : AppColors.statusGreen);
    final IconData icon = isError
        ? Icons.error_outline_rounded
        : (isInfo
              ? Icons.info_outline_rounded
              : Icons.check_circle_outline_rounded);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final screenWidth = MediaQuery.sizeOf(ctx).width;
        final isMobile = screenWidth < 640;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return Positioned(
          top: isMobile ? 16 : 20,
          right: isMobile ? 16 : 24,
          left: isMobile ? 16 : null,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) {
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * -14),
                    child: child,
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isMobile ? screenWidth - 32 : 390,
                  minWidth: isMobile ? 0 : 270,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A222C)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.55),
                      width: 1.3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: accentColor, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : AppColors.sidebarNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          _dismissTimer?.cancel();
                          if (_activeEntry == entry) {
                            _activeEntry?.remove();
                            _activeEntry = null;
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDark
                                ? Colors.white70
                                : Colors.blueGrey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        _activeEntry?.remove();
        _activeEntry = null;
      }
    });
  }
}

/// A compact, elegant calendar popup dialog for selecting a Date Range without
/// opening a full-screen Material page.
class CatchUpCompactDateRangeDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  final DateTime firstDate;
  final DateTime lastDate;

  const CatchUpCompactDateRangeDialog({
    super.key,
    this.initialRange,
    required this.firstDate,
    required this.lastDate,
  });

  static Future<DateTimeRange?> show({
    required BuildContext context,
    DateTimeRange? initialRange,
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    final now = DateTime.now();
    return showDialog<DateTimeRange>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CatchUpCompactDateRangeDialog(
        initialRange: initialRange,
        firstDate: firstDate ?? DateTime(2020),
        lastDate: lastDate ?? now.add(const Duration(days: 365)),
      ),
    );
  }

  @override
  State<CatchUpCompactDateRangeDialog> createState() =>
      _CatchUpCompactDateRangeDialogState();
}

class _CatchUpCompactDateRangeDialogState
    extends State<CatchUpCompactDateRangeDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialRange?.start;
    _endDate = widget.initialRange?.end;
    final base = _startDate ?? DateTime.now();
    _displayedMonth = DateTime(base.year, base.month, 1);
  }

  void _onDaySelected(DateTime day) {
    setState(() {
      final cleanDay = DateTime(day.year, day.month, day.day);
      if (_startDate == null || (_startDate != null && _endDate != null)) {
        _startDate = cleanDay;
        _endDate = null;
      } else {
        if (cleanDay.isBefore(_startDate!)) {
          _endDate = _startDate;
          _startDate = cleanDay;
        } else {
          _endDate = cleanDay;
        }
      }
    });
  }

  void _setPreset(int daysAgo) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _startDate = daysAgo == 0 ? today : today.subtract(Duration(days: daysAgo));
      _endDate = today;
      _displayedMonth = DateTime(_startDate!.year, _startDate!.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColors.sidebarActiveBlue;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header title & active selection preview
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month_outlined,
                          size: 20, color: primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Select Date Range',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Quick preset chips
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _PresetChip(label: 'Today', onTap: () => _setPreset(0)),
                  _PresetChip(label: 'Last 7 Days', onTap: () => _setPreset(7)),
                  _PresetChip(label: 'Last 30 Days', onTap: () => _setPreset(30)),
                  _PresetChip(label: 'Last 90 Days', onTap: () => _setPreset(90)),
                ],
              ),
              const SizedBox(height: 12),

              // Month Navigator (< Month Year >)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 22),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(
                          _displayedMonth.year,
                          _displayedMonth.month - 1,
                          1,
                        );
                      });
                    },
                  ),
                  Text(
                    AppFormatters.formatMonthYear(_displayedMonth),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 22),
                    onPressed: () {
                      setState(() {
                        _displayedMonth = DateTime(
                          _displayedMonth.year,
                          _displayedMonth.month + 1,
                          1,
                        );
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Calendar Days Grid
              _CalendarGrid(
                displayedMonth: _displayedMonth,
                startDate: _startDate,
                endDate: _endDate,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onDaySelected: _onDaySelected,
                isDark: isDark,
              ),

              const SizedBox(height: 10),

              // Selected label summary
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: primaryColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _startDate == null
                            ? 'Tap a start date'
                            : _endDate == null
                                ? 'Start: ${AppFormatters.formatDate(_startDate!)} (tap end date)'
                                : '${AppFormatters.formatDate(_startDate!)} – ${AppFormatters.formatDate(_endDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.grey.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Actions: Clear, Cancel, Apply
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_startDate != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _startDate = null;
                          _endDate = null;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    onPressed: _startDate == null
                        ? null
                        : () {
                            final start = _startDate!;
                            final end = _endDate ?? _startDate!;
                            Navigator.of(context).pop(
                              DateTimeRange(
                                start: start,
                                end: end,
                              ),
                            );
                          },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  final DateTime displayedMonth;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onDaySelected;
  final bool isDark;

  const _CalendarGrid({
    required this.displayedMonth,
    required this.startDate,
    required this.endDate,
    required this.firstDate,
    required this.lastDate,
    required this.onDaySelected,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(displayedMonth.year, displayedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(displayedMonth.year, displayedMonth.month, 1).weekday % 7;

    const weekdayHeaders = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        // Days of week header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdayHeaders
              .map((w) => SizedBox(
                    width: 38,
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white60 : Colors.blueGrey,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        // Days cells
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1.15,
          ),
          itemCount: daysInMonth + firstWeekday,
          itemBuilder: (context, index) {
            if (index < firstWeekday) {
              return const SizedBox.shrink();
            }
            final day = index - firstWeekday + 1;
            final date =
                DateTime(displayedMonth.year, displayedMonth.month, day);
            final isDisabled =
                date.isBefore(firstDate) || date.isAfter(lastDate);

            final isStart = startDate != null &&
                date.year == startDate!.year &&
                date.month == startDate!.month &&
                date.day == startDate!.day;

            final isEnd = endDate != null &&
                date.year == endDate!.year &&
                date.month == endDate!.month &&
                date.day == endDate!.day;

            final isInRange = startDate != null &&
                endDate != null &&
                date.isAfter(startDate!) &&
                date.isBefore(endDate!);

            Color? cellColor;
            Color textColor = isDark ? Colors.white : Colors.black87;

            if (isStart || isEnd) {
              cellColor = AppColors.sidebarActiveBlue;
              textColor = Colors.white;
            } else if (isInRange) {
              cellColor = AppColors.sidebarActiveBlue.withValues(alpha: 0.16);
              textColor = AppColors.sidebarActiveBlue;
            }

            if (isDisabled) {
              textColor = isDark ? Colors.white24 : Colors.black26;
            }

            return InkWell(
              onTap: isDisabled ? null : () => onDaySelected(date),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  color: cellColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: (isStart || isEnd || isInRange)
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: textColor,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}



