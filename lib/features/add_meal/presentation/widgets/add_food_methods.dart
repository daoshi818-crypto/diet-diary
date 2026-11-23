import 'package:flutter/material.dart';
import 'package:opennutritracker/core/presentation/widgets/app_modal_sheet.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/custom_icons.dart';
import 'package:opennutritracker/features/add_meal/presentation/voice/voice_input_button.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AddFoodMethodTiles extends StatelessWidget {
  final VoidCallback onBarcodePressed;
  final VoidCallback onSnapMealPressed;
  final VoidCallback onDescribePressed;
  final VoidCallback? onLocalBatchPressed;
  final bool describeOpen;
  final bool compact;
  final bool singleRow;
  final VoidCallback? onNutritionLabelPressed;
  final bool showAi;

  const AddFoodMethodTiles({
    super.key,
    required this.onBarcodePressed,
    required this.onSnapMealPressed,
    required this.onDescribePressed,
    required this.describeOpen,
    this.showAi = true,
    this.compact = false,
    this.singleRow = false,
    this.onNutritionLabelPressed,
    this.onLocalBatchPressed,
  });

  Future<void> _chooseAiMethod(BuildContext context) async {
    final s = S.of(context);
    final action = await showModalBottomSheet<VoidCallback>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AppModalSheet(
        identifier: 'food-ai-methods',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.foodLibraryAiEntry,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final option in [
              (
                'add-meal-method-describe',
                Icons.edit_note_rounded,
                s.localBatchAiLabel,
                onDescribePressed,
              ),
              (
                'add-meal-method-photo',
                Icons.photo_camera_rounded,
                s.aiFoodPhotoTitle,
                onSnapMealPressed,
              ),
              if (onNutritionLabelPressed != null)
                (
                  'add-meal-nutrition-label',
                  Icons.document_scanner_outlined,
                  s.labelScanShortTitle,
                  onNutritionLabelPressed!,
                ),
            ])
              Semantics(
                identifier: option.$1,
                child: ListTile(
                  leading: Icon(option.$2),
                  title: Text(option.$3),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, option.$4),
                ),
              ),
          ],
        ),
      ),
    );
    if (context.mounted) action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    final s = S.of(context);
    final tiles = [
      (
        'add-meal-method-barcode',
        CustomIcons.barcode_scan,
        s.customMealBarcodeLabel,
        onBarcodePressed,
      ),
      if (onLocalBatchPressed != null)
        (
          'add-meal-method-local-batch',
          Icons.playlist_add_rounded,
          s.localBatchTitle,
          onLocalBatchPressed!,
        ),
      if (showAi)
        (
          'add-meal-method-ai',
          Icons.auto_awesome_outlined,
          s.foodLibraryAiEntry,
          () => _chooseAiMethod(context),
        ),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: Dimens.spacing8),
          Expanded(
            child: Semantics(
              identifier: tiles[i].$1,
              container: true,
              child: _MethodTile(
                compact: true,
                singleRow: true,
                icon: tiles[i].$2,
                label: tiles[i].$3,
                background: palette.surfaceMuted,
                foreground: palette.textStrong,
                border: palette.border,
                onPressed: tiles[i].$4,
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
  final bool compact;
  final bool singleRow;

  final VoidCallback onPressed;
  const _MethodTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.border,
    this.compact = false,
    this.singleRow = false,
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
        child: singleRow
            ? SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 17, color: foreground),
                      const SizedBox(height: 2),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _label(context),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: compact ? 6 : 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: foreground),
                    const SizedBox(height: 3),
                    _label(context),
                  ],
                ),
              ),
      ),
    ),
  );

  Widget _label(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground),
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
