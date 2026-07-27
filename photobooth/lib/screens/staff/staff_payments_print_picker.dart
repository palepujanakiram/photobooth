import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import 'staff_payments_session_images.dart';

/// Staff picks one or more session photos to print (fallback after booth print).
Future<List<String>?> staffPaymentsPickImagesToPrint({
  required BuildContext context,
  required List<String> imageUrls,
}) async {
  if (imageUrls.isEmpty) return null;
  if (imageUrls.length == 1) return List<String>.from(imageUrls);

  final selected = <int>{for (var i = 0; i < imageUrls.length; i++) i};

  return showDialog<List<String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final colors = AppColors.of(ctx);
          return AlertDialog(
            title: const Text(AppStrings.staffPrintPhotosTitle),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.staffPrintSelectHint,
                    style: TextStyle(color: colors.secondaryTextColor),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: GridView.builder(
                      shrinkWrap: true,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: imageUrls.length,
                      itemBuilder: (_, i) {
                        final on = selected.contains(i);
                        return InkWell(
                          onTap: () {
                            setLocal(() {
                              if (on) {
                                selected.remove(i);
                              } else {
                                selected.add(i);
                              }
                            });
                          },
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: on
                                    ? colors.primaryColor
                                    : colors.borderColor,
                                width: on ? 2.5 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(9),
                                    ),
                                    child: CachedNetworkImage(
                                      imageUrl: StaffPaymentsSessionImages
                                          .previewUrl(imageUrls[i]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        on
                                            ? Icons.check_circle
                                            : Icons.radio_button_unchecked,
                                        size: 16,
                                        color: on
                                            ? colors.primaryColor
                                            : colors.secondaryTextColor,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          StaffPaymentsSessionImages
                                              .labelForIndex(
                                            i,
                                            imageUrls.length,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, List<String>.from(imageUrls));
                },
                child: const Text(AppStrings.staffPrintAll),
              ),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        final urls = selected.toList()
                          ..sort();
                        Navigator.pop(
                          ctx,
                          [for (final i in urls) imageUrls[i]],
                        );
                      },
                child: const Text(AppStrings.staffPrintSelected),
              ),
            ],
          );
        },
      );
    },
  );
}
