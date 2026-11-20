import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// A scrollable card can shrink while its separate close control stays visible.
class FloatingCardPanel extends StatelessWidget {
  final Widget child;
  final String closeIdentifier;

  const FloatingCardPanel({
    super.key,
    required this.child,
    required this.closeIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: Material(
            color: palette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: Dimens.borderRadiusXL,
              side: BorderSide(color: palette.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Semantics(
            identifier: closeIdentifier,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: S.of(context).dialogCloseLabel,
              style: IconButton.styleFrom(
                fixedSize: const Size.square(56),
                shape: const CircleBorder(),
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                foregroundColor: theme.colorScheme.onSurface,
              ),
              icon: const Icon(Icons.close_rounded, size: 26),
            ),
          ),
        ),
      ],
    );
  }
}
