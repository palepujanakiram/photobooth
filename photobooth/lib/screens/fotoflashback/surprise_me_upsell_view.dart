import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import '../photo_generate/photo_generate_viewmodel.dart';

/// Guest choice on the Classic Surprise Me interstitial.
enum SurpriseMeUpsellChoice { accept, decline, exploreMore }

/// Classic Surprise Me interstitial: show ready AI look + ask for an extra copy.
class SurpriseMeUpsellScreen extends StatelessWidget {
  const SurpriseMeUpsellScreen({
    super.key,
    required this.surpriseImage,
    required this.additionalPrintPrice,
  });

  final GeneratedImage surpriseImage;
  final int additionalPrintPrice;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStrings.surpriseMeUpsellTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.textColor,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.surpriseMeUpsellSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.secondaryTextColor,
                    ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: surpriseImage.imageUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.surpriseMeUpsellPrice(additionalPrintPrice),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colors.textColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(SurpriseMeUpsellChoice.accept),
                child: const Text(AppStrings.surpriseMeUpsellYes),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context)
                    .pop(SurpriseMeUpsellChoice.exploreMore),
                child: const Text(AppStrings.surpriseMeUpsellExploreMore),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(SurpriseMeUpsellChoice.decline),
                child: const Text(AppStrings.surpriseMeUpsellNo),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
