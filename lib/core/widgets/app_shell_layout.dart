import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/core/widgets/app_sidebar.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/app_settings.dart';
import 'package:catchup/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Responsive application shell that shows:
/// - Desktop (width >= 860): permanent left AppSidebar + Top Bar + main content area
/// - Android / Mobile (width < 860): Hamburger button opening a Drawer + BottomNavigationBar for primary modules
/// - Offline banner at the top when there is no internet connection
class AppShellLayout extends ConsumerWidget {
  final Widget child;
  final String currentLocation;

  const AppShellLayout({
    super.key,
    required this.child,
    required this.currentLocation,
  });

  List<SidebarMenuItem> _mobileNavItemsFor(UserRole role) {
    final allowed = catchUpMenuItems
        .where((item) => item.isVisibleFor(role))
        .toList();
    if (allowed.length <= 5) return allowed;
    // Keep top 4 primary modules for the role + Settings (or last allowed item)
    return [
      ...allowed.take(4),
      allowed.last,
    ];
  }

  String _shortMobileLabel(String label) {
    switch (label) {
      case 'Dashboard':
        return 'Home';
      case 'Transactions':
        return 'Txns';
      case 'Storage Locations':
        return 'Storage';
      case 'Waste Records':
        return 'Waste';
      default:
        return label;
    }
  }

  int _bottomNavIndex(List<SidebarMenuItem> navItems, String location) {
    for (int i = 0; i < navItems.length; i++) {
      final r = navItems[i].route;
      if (location == r || location.startsWith('$r/')) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProfileProvider);
    final isOffline = ref.watch(isOfflineProvider).value ?? false;
    final alerts = ref.watch(systemAlertsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final user =
        userAsync.value ??
        AppUser(
          uid: 'loading',
          userEmail: '',
          fullName: 'User',
          role: UserRole.staff,
          isActive: true,
          createdAt: DateTime.now(),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 860;
        final mobileNavItems = _mobileNavItemsFor(user.role);

        return Scaffold(
          drawer: isDesktop
              ? null
              : Drawer(
                  width: 250,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  child: AppSidebar(
                    currentLocation: currentLocation,
                    user: user,
                    isDrawer: true,
                    onNavigate: (route) {
                      Navigator.of(context).pop();
                      context.go(route);
                    },
                    onLogout: () async {
                      Navigator.of(context).pop();
                      await _performAnimatedLogout(context, ref);
                    },
                  ),
                ),
          bottomNavigationBar: isDesktop || mobileNavItems.length < 2
              ? null
              : NavigationBar(
                  height: 62,
                  selectedIndex: _bottomNavIndex(
                    mobileNavItems,
                    currentLocation,
                  ),
                  backgroundColor: isDark
                      ? AppColors.darkSurface
                      : AppColors.lightSurface,
                  indicatorColor: AppColors.sidebarActiveBlue.withValues(
                    alpha: 0.18,
                  ),
                  onDestinationSelected: (idx) {
                    if (idx >= 0 && idx < mobileNavItems.length) {
                      context.go(mobileNavItems[idx].route);
                    }
                  },
                  destinations: [
                    for (final item in mobileNavItems)
                      NavigationDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(
                          item.icon,
                          color: AppColors.sidebarActiveBlue,
                        ),
                        label: _shortMobileLabel(item.label),
                      ),
                  ],
                ),
          body: Row(
            children: [
              if (isDesktop)
                AppSidebar(
                  currentLocation: currentLocation,
                  user: user,
                  onNavigate: (route) => context.go(route),
                  onLogout: () => _performAnimatedLogout(context, ref),
                ),
              Expanded(
                child: Column(
                  children: [
                    // Top bar with hamburger (mobile), Notification Bell, and signed-in user avatar/name/role
                    _TopHeaderBar(
                      isDesktop: isDesktop,
                      user: user,
                      alerts: alerts,
                      currentLocation: currentLocation,
                    ),
                    // Offline banner when disconnected
                    if (isOffline)
                      Container(
                        width: double.infinity,
                        color: AppColors.statusOrange,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Offline mode - using cached data. Changes will sync when back online.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TopHeaderBar extends ConsumerWidget {
  final bool isDesktop;
  final AppUser user;
  final List<SystemAlert> alerts;
  final String currentLocation;

  const _TopHeaderBar({
    required this.isDesktop,
    required this.user,
    required this.alerts,
    required this.currentLocation,
  });

  String _pageTitle() {
    for (final item in catchUpMenuItems) {
      if (currentLocation == item.route ||
          currentLocation.startsWith('${item.route}/')) {
        return item.label;
      }
    }
    return 'CatchUP';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(appSettingsStreamProvider).value;

    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          if (!isDesktop) ...[
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: 'Menu',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              _pageTitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          // Quick Theme Toggle (Beige-White Light Mode <-> Smooth Black Dark Mode)
          IconButton(
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 22,
            ),
            onPressed: () async {
              final current = settings ?? const AppSettings();
              final updated = current.copyWith(isDarkMode: !isDark);
              LocalDemoStore.instance.saveSettings(updated);
              if (ref.read(firestoreActiveProvider)) {
                try {
                  await ref
                      .read(firestoreProvider)
                      .collection('settings')
                      .doc('general')
                      .set(updated.toMap());
                } catch (_) {
                  LocalDemoStore.instance.markFirestoreBlocked();
                }
              }
              if (context.mounted) {
                CatchUpToast.info(
                  context,
                  !isDark ? 'Switched to Dark Mode' : 'Switched to Light Mode',
                );
              }
            },
          ),
          const SizedBox(width: 4),
          // Notification bell with badge count
          PopupMenuButton<SystemAlert>(
            tooltip: 'Alerts & Notifications',
            offset: const Offset(0, 46),
            onSelected: (alert) {
              if (user.canAccessRoute(alert.route)) {
                context.go(alert.route);
              }
            },
            itemBuilder: (context) {
              if (alerts.isEmpty) {
                return [
                  const PopupMenuItem<SystemAlert>(
                    enabled: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No active alerts right now.'),
                    ),
                  ),
                ];
              }
              return alerts.take(8).map((alert) {
                return PopupMenuItem<SystemAlert>(
                  value: alert,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      alert.isCritical
                          ? Icons.error_outline
                          : Icons.warning_amber_rounded,
                      color: alert.isCritical
                          ? AppColors.statusRed
                          : AppColors.statusOrange,
                    ),
                    title: Text(
                      alert.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      alert.subtitle,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                );
              }).toList();
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Badge(
                isLabelVisible: alerts.isNotEmpty,
                label: Text('${alerts.length}'),
                backgroundColor: AppColors.statusRed,
                child: const Icon(Icons.notifications_none_rounded, size: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Signed-in user avatar, name and role
          PopupMenuButton<String>(
            tooltip: 'Account & Session Options',
            offset: const Offset(0, 46),
            onSelected: (val) {
              if (val == 'logout') {
                _performAnimatedLogout(context, ref);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${user.userEmail} (${user.role.label})',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppColors.statusRed,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color: AppColors.statusRed,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.sidebarNavy,
                  child: Text(
                    user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isDesktop) ...[
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        user.role.label,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.blueGrey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _performAnimatedLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showConfirmDialog(
    context: context,
    title: 'Log Out',
    message: 'Are you sure you want to end your session and log out of CatchUP?',
    confirmLabel: 'Log Out',
    confirmColor: AppColors.statusRed,
  );
  if (!confirmed || !context.mounted) return;

  // Show smooth animated full-screen logout overlay
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.65),
    builder: (_) => const _AnimatedLogoutOverlay(),
  );

  await Future.delayed(const Duration(milliseconds: 650));
  await ref.read(authServiceProvider).signOut();
  await SessionManager.instance.clearSession();
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
    context.go('/login');
  }
}

class _AnimatedLogoutOverlay extends StatefulWidget {
  const _AnimatedLogoutOverlay();

  @override
  State<_AnimatedLogoutOverlay> createState() => _AnimatedLogoutOverlayState();
}

class _AnimatedLogoutOverlayState extends State<_AnimatedLogoutOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 290,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            decoration: BoxDecoration(
              color: AppColors.sidebarNavy,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: const Color(0xFF29C5F6).withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CatchUpLogo(
                  iconSize: 52,
                  fontSize: 22,
                  showTagline: false,
                  forDarkBackground: true,
                ),
                SizedBox(height: 18),
                Text(
                  'Signing Out...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Securing session data',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 20),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF29C5F6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
