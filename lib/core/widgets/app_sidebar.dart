import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/models/app_user.dart';
import 'package:flutter/material.dart';

/// Represents a menu item in the CatchUP sidebar.
class SidebarMenuItem {
  final String label;
  final String route;
  final IconData icon;
  final List<UserRole> allowedRoles;

  const SidebarMenuItem({
    required this.label,
    required this.route,
    required this.icon,
    required this.allowedRoles,
  });

  bool isVisibleFor(UserRole role) => allowedRoles.contains(role);
}

/// The exact 10 menu items in the required order and role visibility:
/// - Admin: manages all 10 modules
/// - Manager: manages all except Inventory, Storage Locations, and Waste Records
/// - Staff: manages Dashboard, Inventory, Storage Locations, and Waste Records
const List<SidebarMenuItem> catchUpMenuItems = [
  SidebarMenuItem(
    label: 'Dashboard',
    route: '/dashboard',
    icon: Icons.home_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager, UserRole.staff],
  ),
  SidebarMenuItem(
    label: 'Inventory',
    route: '/inventory',
    icon: Icons.inventory_2_outlined,
    allowedRoles: [UserRole.admin, UserRole.staff],
  ),
  SidebarMenuItem(
    label: 'Transactions',
    route: '/transactions',
    icon: Icons.swap_horiz_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
  SidebarMenuItem(
    label: 'Products',
    route: '/products',
    icon: Icons.view_in_ar_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
  SidebarMenuItem(
    label: 'Suppliers',
    route: '/suppliers',
    icon: Icons.people_outline,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
  SidebarMenuItem(
    label: 'Storage Locations',
    route: '/storage',
    icon: Icons.location_on_outlined,
    allowedRoles: [UserRole.admin, UserRole.staff],
  ),
  SidebarMenuItem(
    label: 'Waste Records',
    route: '/waste',
    icon: Icons.delete_outline,
    allowedRoles: [UserRole.admin, UserRole.staff],
  ),
  SidebarMenuItem(
    label: 'Reports',
    route: '/reports',
    icon: Icons.bar_chart_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
  SidebarMenuItem(
    label: 'Users',
    route: '/users',
    icon: Icons.group_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
  SidebarMenuItem(
    label: 'Settings',
    route: '/settings',
    icon: Icons.settings_outlined,
    allowedRoles: [UserRole.admin, UserRole.manager],
  ),
];

/// Reusable sidebar widget matching the design reference:
/// - Full-height panel on the left, dark navy blue (#0B3556), rounded right corners, ~220px wide
/// - Top: CatchUP fish + wave icon and centered "CatchUP" wordmark
/// - Role-filtered menu items with active (#1E6FA8) and hover states
/// - Signed-in user's name, role, and Logout button just above the decorative bottom wave
class AppSidebar extends StatelessWidget {
  final String currentLocation;
  final AppUser user;
  final ValueChanged<String> onNavigate;
  final VoidCallback onLogout;
  final bool isDrawer;

  const AppSidebar({
    super.key,
    required this.currentLocation,
    required this.user,
    required this.onNavigate,
    required this.onLogout,
    this.isDrawer = false,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = catchUpMenuItems
        .where((item) => item.isVisibleFor(user.role))
        .toList();

    return Container(
      width: 230,
      height: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.sidebarNavy,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(22),
          bottomRight: Radius.circular(22),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Top Logo + Wordmark + Tagline (crisp vector rendering)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: CatchUpLogo(
                iconSize: 48,
                fontSize: 22,
                showTagline: true,
                forDarkBackground: true,
              ),
            ),
            const SizedBox(height: 14),
            // Menu items list
            Expanded(
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                itemCount: visibleItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final item = visibleItems[index];
                  final isActive = currentLocation == item.route ||
                      currentLocation.startsWith('${item.route}/');
                  return _SidebarItemTile(
                    item: item,
                    isActive: isActive,
                    onTap: () => onNavigate(item.route),
                  );
                },
              ),
            ),
            // User info and Logout just above the bottom ocean wave
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.sidebarActiveBlue,
                      child: Text(
                        user.fullName.isNotEmpty
                            ? user.fullName[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            user.role.label,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onLogout,
                      tooltip: 'Logout',
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
            // Decorative wave graphic at the bottom of the sidebar
            const SidebarBottomWave(height: 50),
          ],
        ),
      ),
    );
  }
}

class _SidebarItemTile extends StatefulWidget {
  final SidebarMenuItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItemTile({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarItemTile> createState() => _SidebarItemTileState();
}

class _SidebarItemTileState extends State<_SidebarItemTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isActive
        ? AppColors.sidebarActiveBlue
        : _isHovered
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent;

    final textColor = widget.isActive
        ? Colors.white
        : Colors.white.withValues(alpha: 0.85);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                widget.item.icon,
                color: textColor,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13.5,
                    height: 1.2,
                    fontWeight:
                        widget.isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
