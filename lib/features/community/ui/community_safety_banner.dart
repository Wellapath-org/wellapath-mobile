import 'package:flutter/material.dart';

import '../../../shared/theme/brand.dart';

/// Persistent safety notice shown at the top of every Community space screen.
///
/// It is not dismissible and is not a link: Community never routes anyone to
/// emergency care or presents itself as clinical consultation.
class CommunitySafetyBanner extends StatelessWidget {
  const CommunitySafetyBanner({super.key});

  // CLINICAL REVIEW REQUIRED — placeholder wording, neutral by intent. Must
  // be approved by clinical review before any external tester sees it.
  static const String text =
      'Community posts are not medical advice. In an emergency, call 112.';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: text,
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Brand.space4,
          vertical: Brand.space3,
        ),
        decoration: BoxDecoration(
          color: Brand.surfaceMuted,
          borderRadius: BorderRadius.circular(Brand.radiusControl),
          border: Border.all(color: Brand.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Brand.inkSoft, size: 20),
            SizedBox(width: Brand.space3),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 14, height: 1.4, color: Brand.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
