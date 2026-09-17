import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/app_localizations.dart';
import '../utils/responsive.dart';

class LegalAgreementDialog extends StatelessWidget {
  final String title;
  final String content;
  final bool isDialog;

  const LegalAgreementDialog({
    super.key,
    required this.title,
    required this.content,
    this.isDialog = false,
  });

  static void show(BuildContext context, {required bool isTerms}) {
    final bool isWide = Responsive.isTablet(context) || Responsive.isDesktop(context);

    if (isWide) {
      showDialog(
        context: context,
        builder: (context) => ValueListenableBuilder(
          valueListenable: AppLocalizations.currentLanguage,
          builder: (context, lang, child) {
            return LegalAgreementDialog(
              title: isTerms ? AppLocalizations.get('terms_conditions') : AppLocalizations.get('privacy_policy'),
              content: isTerms ? AppLocalizations.getTerms() : AppLocalizations.getPrivacy(),
              isDialog: true,
            );
          }
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ValueListenableBuilder(
          valueListenable: AppLocalizations.currentLanguage,
          builder: (context, lang, child) {
            return LegalAgreementDialog(
              title: isTerms ? AppLocalizations.get('terms_conditions') : AppLocalizations.get('privacy_policy'),
              content: isTerms ? AppLocalizations.getTerms() : AppLocalizations.getPrivacy(),
              isDialog: false,
            );
          }
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isModalLoading = true;
    return StatefulBuilder(
      builder: (context, setState) {
        if (isModalLoading) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (context.mounted) setState(() => isModalLoading = false);
          });
        }

        // Calculation for responsive width and height
        final double screenWidth = MediaQuery.of(context).size.width;
        final double screenHeight = MediaQuery.of(context).size.height;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutCubic,
              margin: isDialog ? const EdgeInsets.all(24) : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: isDialog 
                    ? BorderRadius.circular(32) 
                    : const BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: isDialog ? [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10))
                ] : null,
              ),
              constraints: BoxConstraints(
                maxWidth: isDialog ? 600 : screenWidth,
                maxHeight: isModalLoading 
                    ? 250 
                    : (isDialog ? 650 : screenHeight * 0.85),
              ),
              child: _buildModalContent(context, isModalLoading),
            ),
          ),
        );
      }
    );
  }

  Widget _buildModalContent(BuildContext context, bool isModalLoading) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isDialog)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(32, isDialog ? 32 : 16, 32, 0),
          child: Row(
            children: [
              Icon(
                title.contains('Terms') || title.contains('Tuntunin') || title.contains('Termino') 
                  ? Icons.gavel_rounded 
                  : Icons.privacy_tip_rounded,
                color: AppColors.tealText,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.tealText,
                  ),
                ),
              ),
              if (isDialog)
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          child: Divider(height: 1, color: Color(0xFFEEEEEE)),
        ),
        if (isModalLoading)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.tealText, strokeWidth: 3),
                  const SizedBox(height: 16),
                  Text("Loading agreement content...",
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          )
        else
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        if (isDialog && !isModalLoading) const SizedBox(height: 24),
      ],
    );
  }
}
