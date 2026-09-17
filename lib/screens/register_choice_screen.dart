import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../widgets/legal_agreement_dialog.dart';
import '../widgets/animated_auth_background.dart';
import '../widgets/fade_slide_entrance.dart';
import '../utils/app_localizations.dart';
import '../utils/responsive_text.dart';
import '../utils/responsive.dart';
import 'resident_register.dart';
import 'driver_register.dart';

class RegisterChoiceScreen extends StatefulWidget {
  const RegisterChoiceScreen({super.key});

  @override
  State<RegisterChoiceScreen> createState() => _RegisterChoiceScreenState();
}

class _RegisterChoiceScreenState extends State<RegisterChoiceScreen> {
  IconData _currentLogoIcon = Icons.person_add_rounded;

  @override
  void initState() {
    super.initState();
    AppLocalizations.currentLanguage.addListener(_onLanguageChanged);
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLocalizations.currentLanguage.removeListener(_onLanguageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final bool isMobile = Responsive.isMobile(context);
    
    return AnimatedAuthBackground(
      resizeToAvoidBottomInset: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Stack(
            children: [
              // Main Scrollable Content
              Positioned.fill(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth > 600 ? 40 : 24,
                    vertical: screenHeight * 0.02,
                  ),
                  child: Column(
                    children: [
                      // Header Spacer for fixed back button
                      const SizedBox(height: 60),
                      FadeSlideEntrance(
                        key: const ValueKey('reg_choice_branding'),
                        delay: const Duration(milliseconds: 100),
                        child: _buildBranding(),
                      ),
                      const SizedBox(height: 48),
                      // Options (Always Vertical Stack as requested)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 450),
                        child: Column(
                          children: [
                            FadeSlideEntrance(
                              key: const ValueKey('reg_choice_resident_col'),
                              delay: const Duration(milliseconds: 200),
                              child: _buildChoiceCard(
                                context: context,
                                title: AppLocalizations.get('resident'),
                                subtitle: AppLocalizations.get('track_trucks'),
                                icon: Icons.home_rounded,
                                iconColor: const Color(0xFF2196F3),
                                bgColor: const Color(0xFFE3F2FD),
                                route: '/register_resident',
                              ),
                            ),
                            const SizedBox(height: 20),
                            FadeSlideEntrance(
                              key: const ValueKey('reg_choice_driver_col'),
                              delay: const Duration(milliseconds: 300),
                              child: _buildChoiceCard(
                                context: context,
                                title: AppLocalizations.get('driver'),
                                subtitle: AppLocalizations.get('manage_routes'),
                                icon: Icons.local_shipping_rounded,
                                iconColor: const Color(0xFF4CAF50),
                                bgColor: const Color(0xFFE8F5E9),
                                route: '/register_driver',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Footer inside scroll for Web/Tablet
                      if (!isMobile) ...[
                        const SizedBox(height: 80), // Adjusted spacing for Web
                        FadeSlideEntrance(
                          key: const ValueKey('reg_choice_footer'),
                          delay: const Duration(milliseconds: 800),
                          child: _buildFooter(context),
                        ),
                        const SizedBox(height: 40),
                      ],
                      // Keyboard Spacer
                      SizedBox(height: keyboardHeight),
                      // Extra buffer for mobile fixed footer
                      if (isMobile && keyboardHeight == 0) const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),

              // Fixed Back Button (Reverted to fixed top-left position)
              Positioned(
                top: 20,
                left: 24,
                child: FadeSlideEntrance(
                  key: const ValueKey('reg_choice_back'),
                  delay: const Duration(milliseconds: 100),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(150),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: const Color(0xFF00796B), size: ResponsiveText.getIconSize(context, 20)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),

              // Fixed Footer for Mobile
              if (isMobile)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20,
                  child: FadeSlideEntrance(
                    key: const ValueKey('reg_choice_footer_mobile'),
                    delay: const Duration(milliseconds: 800),
                    child: _buildFooter(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranding() {
    final double containerSize = ResponsiveText.getIconSize(context, 80);
    final double iconSize = ResponsiveText.getIconSize(context, 40);

    return Column(
      children: [
        Hero(
          tag: 'app_logo',
          flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
            final Hero fromHero = fromHeroContext.widget as Hero;
            final Hero toHero = toHeroContext.widget as Hero;
            final Widget fromChild = fromHero.child;
            final Widget toChild = toHero.child;

            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final double scale = 1.0 + (0.1 * (1.0 - (animation.value - 0.5).abs() * 2));
                final double rotation = (flightDirection == HeroFlightDirection.push ? 1 : -1) * 
                                      (1.0 - animation.value) * 0.2;
                
                return Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: rotation,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: (1.0 - animation.value).clamp(0.0, 1.0),
                            child: fromChild,
                          ),
                          Opacity(
                            opacity: animation.value.clamp(0.0, 1.0),
                            child: toChild,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
          child: Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.loginButtonStart, AppColors.loginButtonEnd], begin: Alignment.topLeft, end: Alignment.bottomRight),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: AppColors.loginButtonEnd.withAlpha(60), blurRadius: 20, offset: const Offset(0, 10)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: Icon(
                _currentLogoIcon, 
                key: ValueKey(_currentLogoIcon),
                size: iconSize, 
                color: Colors.white
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(AppLocalizations.get('create_account'), style: ResponsiveText.brandingTitle(context)),
        Text(AppLocalizations.get('select_type'), style: ResponsiveText.brandingSubtitle(context)),
      ],
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String route,
  }) {
    return _HoverZoomCard(
      onTap: () {
        setState(() => _currentLogoIcon = route == '/register_resident' ? Icons.home_rounded : Icons.local_shipping_rounded);
        Future.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => route == '/register_resident' ? const ResidentRegisterScreen() : const DriverRegisterScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return FadeTransition(
                  opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
                  child: child,
                );
              },
              transitionDuration: const Duration(milliseconds: 500),
            ),
          ).then((_) {
            if (mounted) setState(() => _currentLogoIcon = Icons.person_add_rounded);
          });
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: AppDecorations.authCardDecoration(radius: 32), // Applied High-Depth Shadow
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                width: ResponsiveText.getIconSize(context, 60),
                height: ResponsiveText.getIconSize(context, 60),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: iconColor, size: ResponsiveText.getIconSize(context, 30)),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ResponsiveText.screenHeader(context).copyWith(fontSize: ResponsiveText.getFontSize(context, 20), letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: ResponsiveText.body(context),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade300, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(children: [
      Wrap(alignment: WrapAlignment.center, spacing: 16, children: [
        _HoverZoomLink(onTap: () => LegalAgreementDialog.show(context, isTerms: true), child: Text(AppLocalizations.get('terms_conditions'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline))),
        Text('•', style: ResponsiveText.footer(context)),
        _HoverZoomLink(onTap: () => LegalAgreementDialog.show(context, isTerms: false), child: Text(AppLocalizations.get('privacy_policy'), style: ResponsiveText.footer(context, bold: true).copyWith(decoration: TextDecoration.underline))),
      ]),
      const SizedBox(height: 16),
      Text(AppLocalizations.get('brgy_footer'), style: ResponsiveText.footer(context, bold: true)),
      Text(AppLocalizations.get('all_rights_reserved'), style: ResponsiveText.footer(context, size: 10)),
    ]);
  }
}

class _HoverZoomCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HoverZoomCard({required this.child, required this.onTap});
  @override
  State<_HoverZoomCard> createState() => _HoverZoomCardState();
}
class _HoverZoomCardState extends State<_HoverZoomCard> {
  bool _isActive = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = true),
      onExit: (_) => setState(() => _isActive = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isActive = true),
        onTapUp: (_) => setState(() => _isActive = false),
        onTapCancel: () => setState(() => _isActive = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isActive ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}

class _HoverZoomLink extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _HoverZoomLink({required this.child, required this.onTap});
  @override
  State<_HoverZoomLink> createState() => _HoverZoomLinkState();
}
class _HoverZoomLinkState extends State<_HoverZoomLink> {
  bool _isActive = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isActive = true),
      onExit: (_) => setState(() => _isActive = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isActive = true),
        onTapUp: (_) => setState(() => _isActive = false),
        onTapCancel: () => setState(() => _isActive = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isActive ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: widget.child,
        ),
      ),
    );
  }
}
