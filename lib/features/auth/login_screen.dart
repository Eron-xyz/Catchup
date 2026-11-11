import 'dart:async';
import 'dart:math' as math;

import 'package:catchup/core/theme/app_theme.dart';
import 'package:catchup/core/utils/firestore_providers.dart';
import 'package:catchup/core/utils/formatters.dart';
import 'package:catchup/core/utils/local_demo_store.dart';
import 'package:catchup/core/utils/session_manager.dart';
import 'package:catchup/core/widgets/catchup_logo.dart';
import 'package:catchup/core/widgets/common_widgets.dart';
import 'package:catchup/features/auth/auth_provider.dart';
import 'package:catchup/models/app_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Seamless 50/50 Split-Screen Login Page:
/// - Unified Ocean Navy background and continuous bottom ocean waves across the entire screen
///   (no dividing line in the middle, no outer card boxes on either side).
/// - Left Side: Extra-large, high-contrast CatchUP logo with live eye animation +
///   large, readable Business Info text & consistent Material outline icons underneath.
/// - Right Side: Large, frameless Sign In form directly on the background with high-contrast
///   white headings/labels and crisp white pill input fields.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final GlobalKey _logoKey = GlobalKey();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isSuccess = false;
  String _successName = '';
  String? _errorMessage;

  /// Normalized vector [-1..1, -1..1] for the logo eyes.
  Offset _eyeLook = const Offset(0.35, 0.10);
  bool _eyesShy = false;
  bool _hasMouseCursor = false;
  Timer? _mobileIdleTimer;
  int _mobileStep = 0;

  static const List<Offset> _mobileIdleTargets = [
    Offset(0.0, 0.35),
    Offset(-0.45, 0.15),
    Offset(0.45, 0.15),
    Offset(0.0, 0.55),
    Offset(0.25, -0.25),
  ];

  @override
  void initState() {
    super.initState();
    _emailFocus.addListener(_onFocusChange);
    _passwordFocus.addListener(_onFocusChange);

    _mobileIdleTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      if (!mounted) return;
      if (_emailFocus.hasFocus || _passwordFocus.hasFocus) return;
      if (_hasMouseCursor) return;

      setState(() {
        _mobileStep = (_mobileStep + 1) % _mobileIdleTargets.length;
        _eyeLook = _mobileIdleTargets[_mobileStep];
      });
    });
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_passwordFocus.hasFocus) {
      setState(() {
        _eyesShy = _obscurePassword;
        _eyeLook = const Offset(0.45, 0.45);
      });
    } else if (_emailFocus.hasFocus) {
      setState(() {
        _eyesShy = false;
        _updateEmailScanLook(_emailController.text);
      });
    } else {
      setState(() {
        _eyesShy = false;
      });
    }
  }

  void _updateEmailScanLook(String text) {
    final progress = ((text.length % 18) / 18.0) * 1.2 - 0.6;
    _eyeLook = Offset(progress.clamp(-0.75, 0.75), 0.45);
  }

  @override
  void dispose() {
    _mobileIdleTimer?.cancel();
    _emailFocus.removeListener(_onFocusChange);
    _passwordFocus.removeListener(_onFocusChange);
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _updatePointLook(Offset globalPosition, {required bool isMouse}) {
    if (isMouse) {
      _hasMouseCursor = true;
    }
    if (_passwordFocus.hasFocus && _obscurePassword && !isMouse) {
      return;
    }

    final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
    Offset center;
    if (box != null && box.hasSize) {
      center = box.localToGlobal(box.size.center(Offset.zero));
    } else {
      final size = MediaQuery.sizeOf(context);
      center = Offset(size.width * 0.25, size.height * 0.38);
    }

    final delta = globalPosition - center;
    final distance = delta.distance;
    if (distance < 1.0) {
      setState(() {
        _eyesShy = false;
        _eyeLook = Offset.zero;
      });
      return;
    }

    const maxRadius = 280.0;
    final factor = (distance / maxRadius).clamp(0.0, 1.0);
    final angle = math.atan2(delta.dy, delta.dx);
    final nextLook = Offset(
      math.cos(angle) * factor,
      math.sin(angle) * factor,
    );

    if ((nextLook - _eyeLook).distance > 0.015 || _eyesShy) {
      setState(() {
        _eyesShy = false;
        _eyeLook = nextLook;
      });
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _eyesShy = false;
    });

    try {
      final user = await ref.read(authServiceProvider).signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
      await SessionManager.instance.saveSession(user);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
          _successName = user.fullName;
        });
        await Future.delayed(const Duration(milliseconds: 750));
        if (mounted) {
          CatchUpToast.success(
            context,
            'Signed in as ${user.fullName} (${user.role.label})',
          );
          context.go('/dashboard');
        }
      }
    } catch (e) {
      final msg = AuthService.friendlyErrorMessage(e);
      setState(() {
        _errorMessage = msg;
      });
      if (mounted) {
        CatchUpToast.error(context, msg);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (AppValidators.email(email) != null) {
      CatchUpToast.info(
        context,
        'Enter your registered email address first to reset your password.',
      );
      return;
    }

    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (mounted) {
        CatchUpToast.success(context, 'Password reset email sent to $email.');
      }
    } catch (e) {
      if (mounted) {
        CatchUpToast.error(context, AuthService.friendlyErrorMessage(e));
      }
    }
  }

  Future<void> _showRegisterDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final regFormKey = GlobalKey<FormState>();
    var isRegistering = false;
    var obscurePass = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Color(0xFF003057)),
                  SizedBox(width: 10),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      color: Color(0xFF003057),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Form(
                    key: regFormKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Create your administrator account to manage your CatchUP inventory.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Full Name *',
                            prefixIcon: const Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) =>
                              AppValidators.requiredField(v, 'Full Name'),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Username or Email *',
                            hintText: 'e.g. admin or admin@catchup.ph',
                            prefixIcon: const Icon(Icons.alternate_email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) =>
                              AppValidators.requiredField(v, 'Username or Email'),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: passCtrl,
                          obscureText: obscurePass,
                          decoration: InputDecoration(
                            labelText: 'Password *',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePass
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () {
                                setDlgState(() => obscurePass = !obscurePass);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length < 5) {
                              return 'Password must be at least 5 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: confirmCtrl,
                          obscureText: obscurePass,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password *',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (v) {
                            if (v != passCtrl.text) {
                              return 'Passwords do not match.';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isRegistering ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isRegistering
                      ? null
                      : () async {
                          if (!regFormKey.currentState!.validate()) return;
                          setDlgState(() => isRegistering = true);
                          try {
                            final user = await ref
                                .read(authServiceProvider)
                                .registerUser(
                                  fullName: nameCtrl.text.trim(),
                                  email: emailCtrl.text.trim(),
                                  password: passCtrl.text,
                                );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              CatchUpToast.success(
                                context,
                                'Account created! Welcome, ${user.fullName}.',
                              );
                              context.go('/dashboard');
                            }
                          } catch (e) {
                            setDlgState(() => isRegistering = false);
                            final msg = AuthService.friendlyErrorMessage(e);
                            if (mounted) {
                              CatchUpToast.error(context, msg);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003057),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isRegistering
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  InputDecoration _pillInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: Colors.blueGrey.shade400,
        fontSize: 16,
      ),
      filled: true,
      fillColor: Colors.white,
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 18, right: 12),
        child: Icon(
          prefixIcon,
          color: const Color(0xFF0A2E52),
          size: 24,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 52),
      suffixIcon: suffixIcon != null
          ? Padding(
              padding: const EdgeInsets.only(right: 10),
              child: suffixIcon,
            )
          : null,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 20,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(32),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(32),
        borderSide: const BorderSide(
          color: Colors.white,
          width: 2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(32),
        borderSide: const BorderSide(
          color: Color(0xFF29C5F6),
          width: 3,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(32),
        borderSide: const BorderSide(
          color: Color(0xFFFF6B6B),
          width: 2.2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(32),
        borderSide: const BorderSide(
          color: Color(0xFFFF6B6B),
          width: 2.8,
        ),
      ),
      errorStyle: const TextStyle(
        color: Color(0xFFFFB4B4),
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildLeftBrandSection(
    BuildContext context,
    AppSettings settings, {
    required bool isDesktop,
  }) {
    final businessName = settings.businessName.isNotEmpty
        ? settings.businessName
        : 'CatchUP Seafood Trading';
    final address = settings.address.isNotEmpty
        ? settings.address
        : 'Baybay, Roxas City, Capiz, Philippines';
    final contact = settings.contactNumber.isNotEmpty
        ? settings.contactNumber
        : '0917-452-8810';

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 48 : 16,
          vertical: isDesktop ? 32 : 8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Extra-large, crystal-clear CatchUP logo directly on the background
              Container(
                key: _logoKey,
                child: CatchUpLogo(
                  iconSize: isDesktop ? 225 : 115,
                  fontSize: isDesktop ? 74 : 40,
                  showTagline: true,
                  forDarkBackground: true,
                  eyeOffset: _eyeLook,
                  eyesShy: _eyesShy,
                ),
              ),
              SizedBox(height: isDesktop ? 42 : 16),

              // Scaled-up Business Info Output from Settings (clean text & consistent Material outline icons)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        color: const Color(0xFF29C5F6),
                        size: isDesktop ? 28 : 22,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          businessName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isDesktop ? 27 : 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isDesktop ? 14 : 8),
                  _BusinessInfoLine(
                    icon: Icons.location_on_outlined,
                    text: address,
                    isDesktop: isDesktop,
                  ),
                  SizedBox(height: isDesktop ? 10 : 6),
                  _BusinessInfoLine(
                    icon: Icons.phone_outlined,
                    text: contact,
                    isDesktop: isDesktop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightLoginForm(
    BuildContext context,
    AppSettings settings, {
    required bool isDesktop,
  }) {
    final businessName = settings.businessName.isNotEmpty
        ? settings.businessName
        : 'CatchUP Seafood Trading';

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 56 : 16,
          vertical: isDesktop ? 32 : 8,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              return FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
                  child: child,
                ),
              );
            },
            child: _isSuccess
                ? _buildLoginSuccessCard(isDesktop: isDesktop)
                : Form(
                    key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: isDesktop ? 42 : 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in to manage your $businessName inventory',
                  style: TextStyle(
                    fontSize: isDesktop ? 17 : 14,
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isDesktop ? 34 : 18),
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF991B1B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: const Color(0xFFFCA5A5),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Username label + high-contrast white pill input
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    'Username',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextFormField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  keyboardType: TextInputType.text,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Color(0xFF07263E),
                    fontWeight: FontWeight.w600,
                  ),
                  onChanged: (val) {
                    setState(() {
                      _eyesShy = false;
                      _updateEmailScanLook(val);
                    });
                  },
                  decoration: _pillInputDecoration(
                    hintText: 'Enter your username',
                    prefixIcon: Icons.person_outline,
                  ),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Username'),
                ),
                const SizedBox(height: 22),

                // Password label + high-contrast white pill input
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    'Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _obscurePassword,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Color(0xFF07263E),
                    fontWeight: FontWeight.w600,
                  ),
                  onFieldSubmitted: (_) => _handleLogin(),
                  onChanged: (_) {
                    setState(() {
                      _eyesShy = _obscurePassword;
                      _eyeLook = const Offset(0.45, 0.45);
                    });
                  },
                  decoration: _pillInputDecoration(
                    hintText: 'Enter your password',
                    prefixIcon: Icons.lock_outline,
                    suffixIcon: IconButton(
                      tooltip:
                          _obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF0A2E52),
                        size: 23,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                          if (_passwordFocus.hasFocus) {
                            _eyesShy = _obscurePassword;
                            if (!_obscurePassword) {
                              _eyeLook = const Offset(0.50, 0.40);
                            }
                          }
                        });
                      },
                    ),
                  ),
                  validator: (v) =>
                      AppValidators.requiredField(v, 'Password'),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _handleForgotPassword,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF29C5F6),
                    ),
                    icon: const Icon(Icons.lock_reset_outlined, size: 19),
                    label: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 58,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0696C7),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    icon: _isLoading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.login_rounded, size: 22),
                    label: _isLoading
                        ? const CatchUpButtonLoading(
                            label: 'Loading...',
                            forDarkBackground: true,
                          )
                        : const Text(
                            'Login',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton(
                      onPressed: _showRegisterDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF29C5F6),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginSuccessCard({required bool isDesktop}) {
    return Container(
      key: const ValueKey('login_success_card'),
      padding: EdgeInsets.all(isDesktop ? 36 : 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF29C5F6).withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF29C5F6).withValues(alpha: 0.2),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF29C5F6),
              size: 54,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Welcome back,',
            style: TextStyle(
              fontSize: isDesktop ? 18 : 15,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _successName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isDesktop ? 26 : 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF29C5F6),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Opening CatchUP dashboard...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsStreamProvider).value ??
        LocalDemoStore.instance.settings;

    return Theme(
      data: AppTheme.lightTheme,
      child: Scaffold(
        body: MouseRegion(
          onHover: (event) => _updatePointLook(
            event.position,
            isMouse: event.kind == PointerDeviceKind.mouse,
          ),
          child: Listener(
            onPointerDown: (event) => _updatePointLook(
              event.position,
              isMouse: event.kind == PointerDeviceKind.mouse,
            ),
            onPointerMove: (event) => _updatePointLook(
              event.position,
              isMouse: event.kind == PointerDeviceKind.mouse,
            ),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF07263E),
                    Color(0xFF0B3C5D),
                    Color(0xFF11517C),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: SidebarBottomWave(height: 135),
                  ),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth >= 820;
                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _buildLeftBrandSection(
                                  context,
                                  settings,
                                  isDesktop: true,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: _buildRightLoginForm(
                                  context,
                                  settings,
                                  isDesktop: true,
                                ),
                              ),
                            ],
                          );
                        }

                        return Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildLeftBrandSection(
                                    context,
                                    settings,
                                    isDesktop: false,
                                  ),
                                  const SizedBox(height: 12),
                                  _buildRightLoginForm(
                                    context,
                                    settings,
                                    isDesktop: false,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BusinessInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDesktop;

  const _BusinessInfoLine({
    required this.icon,
    required this.text,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: const Color(0xFF29C5F6),
          size: isDesktop ? 22 : 19,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: isDesktop ? 17.5 : 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
