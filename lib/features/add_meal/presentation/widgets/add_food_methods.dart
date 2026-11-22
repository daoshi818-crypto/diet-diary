import 'package:flutter/material.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/custom_icons.dart';
import 'package:opennutritracker/features/add_meal/presentation/voice/voice_input_button.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AddFoodMethodTiles extends StatelessWidget {
  final VoidCallback onBarcodePressed;
  final VoidCallback onSnapMealPressed;
  final VoidCallback onDescribePressed;

  final bool describeOpen;
  final bool compact;
  final VoidCallback? onNutritionLabelPressed;

  /// False once the user has hidden the AI features (#1518): the Snap meal
  /// tile goes, since only a model can read a photo, and Describe stays
  /// without its badge, since the offline parser reads it then.
  final bool showAi;

  const AddFoodMethodTiles({
    super.key,
    required this.onBarcodePressed,
    required this.onSnapMealPressed,
    required this.onDescribePressed,
    required this.describeOpen,
    this.showAi = true,
    this.compact = false,
    this.onNutritionLabelPressed,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final scheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    final compact = this.compact || MediaQuery.textScalerOf(context).scale(12) > 18;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            identifier: 'add-meal-method-barcode',
            container: true,
            child: _MethodTile(
              compact: compact,
              icon: CustomIcons.barcode_scan,
              label: s.customMealBarcodeLabel,
              background: palette.surface,
              foreground: palette.textStrong,
              border: palette.border,
              onPressed: onBarcodePressed,
            ),
          ),
        ),
        const SizedBox(width: Dimens.spacing8),
        if (showAi) ...[
          Expanded(
            child: Semantics(
              identifier: 'add-meal-method-photo',
              container: true,
              child: _MethodTile(
                compact: compact,
                icon: Icons.photo_camera_rounded,
                label: s.addMealSnapMealLabel,
                background: scheme.primary,
                foreground: scheme.onPrimary,
                ai: true,
                onPressed: onSnapMealPressed,
              ),
            ),
          ),
          const SizedBox(width: Dimens.spacing8),
        ],
        Expanded(
          child: Semantics(
            identifier: 'add-meal-method-describe',
            container: true,
            selected: describeOpen,
            child: _MethodTile(
              compact:
                  compact, // The sparkle reads as AI on its own, so it goes with the badge.
              icon: showAi ? Icons.auto_awesome_rounded : Icons.notes_rounded,
              label: s.addMealDescribeLabel,
              background: describeOpen
                  ? Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.16),
                      palette.surfaceMuted,
                    )
                  : palette.surfaceMuted,
              foreground: palette.textStrong,
              border: describeOpen
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.35),
              ai: showAi,
              onPressed: onDescribePressed,
            ),
          ),
        ),
        if (showAi && onNutritionLabelPressed != null) ...[
          const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Semantics(
              identifier: 'add-meal-nutrition-label',
              container: true,
              child: _MethodTile(
                compact: compact,
                icon: Icons.document_scanner_outlined,
                label: s.labelScanShortTitle,
                background: palette.surfaceMuted,
                foreground: palette.textStrong,
                onPressed: onNutritionLabelPressed!,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final bool ai;
  final bool compact;

  final VoidCallback onPressed;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.border,
    this.ai = false,
    this.compact = false,

  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Material(
      color: background,
      shape: RoundedRectangleBorder(
        borderRadius: Dimens.borderRadiusS,
        side: BorderSide(color: border ?? Colors.transparent),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 14 : 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              if (!compact) const SizedBox(height: 3),
              if (!compact)
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: foreground),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class DescribeMealPanel extends StatefulWidget {
  final ValueChanged<String> onFindFoods;

  const DescribeMealPanel({super.key, required this.onFindFoods});

  @override
  State<DescribeMealPanel> createState() => _DescribeMealPanelState();
}

class _DescribeMealPanelState extends State<DescribeMealPanel> {
  final _controller = TextEditingController();
  final _voice = GlobalKey<VoiceInputButtonState>();

  @override
  void initState() {
    super.initState();
    // Every change, not only typing: dictation writes the field too, and
    // Find foods has to turn on as its words appear.
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: palette.surfaceMuted,
        borderRadius: const BorderRadius.all(Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            identifier: 'add-meal-describe-input',
            child: TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: S.of(context).bulkAddInputHint,
                hintStyle: textTheme.bodyLarge?.copyWith(
                  color: palette.textMuted,
                ),
                // Dictate the meal and go straight to the matches.
                suffixIcon: VoiceInputButton(
                  key: _voice,
                  controller: _controller,
                  onDictated: widget.onFindFoods,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Dimens.spacing12,
                  vertical: Dimens.spacing8,
                ),
              ),
            ),
          ),
          Semantics(
            identifier: 'add-meal-describe-submit',
            child: FilledButton.icon(
              onPressed: _controller.text.trim().isEmpty
                  ? null
                  : () {
                      FocusScope.of(context).unfocus();
                      // Submitted by hand: dictation must not submit again.
                      _voice.currentState?.cancel();
                      widget.onFindFoods(_controller.text);
                    },
              icon: const Icon(Icons.search_rounded, size: 18),
              label: Text(S.of(context).bulkAddParseLabel),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: const StadiumBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
