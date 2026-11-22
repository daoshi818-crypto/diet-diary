import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/activity_card.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_activity_payload.dart';
import 'package:opennutritracker/generated/l10n.dart';

enum _ActivityPopupMenuSelection { onCopy, onShare, onImport }

class ActivityVerticalList extends StatefulWidget {
  final DateTime day;
  final String title;
  final List<UserActivityEntity> userActivityList;
  final Function(BuildContext, UserActivityEntity) onItemLongPressedCallback;
  final Function(BuildContext, UserActivityEntity)? onItemTappedCallback;
  final Function(bool isDragging)? onItemDragCallback;
  final Function(UserActivityEntity)? onCopyActivityCallback;

  const ActivityVerticalList({
    super.key,
    required this.day,
    required this.title,
    required this.userActivityList,
    required this.onItemLongPressedCallback,
    this.onItemTappedCallback,
    this.onItemDragCallback,
    this.onCopyActivityCallback,
  });

  @override
  State<ActivityVerticalList> createState() => _ActivityVerticalListState();
}

class _ActivityVerticalListState extends State<ActivityVerticalList> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final palette = theme.brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
            Dimens.spacing16,
            Dimens.spacing8,
            Dimens.spacing16 + Dimens.spacing12 + Dimens.hairline,
            Dimens.spacing8,
          ),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(Dimens.spacing8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: Dimens.borderRadiusS,
                ),
                child: Icon(
                  UserActivityEntity.getIconData(),
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: Dimens.spacing12),
              Expanded(
                child: AutoSizeText(
                  widget.title,
                  maxLines: 1,
                  minFontSize: 14,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: palette.textStrong,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Dimens.spacing8),
              Semantics(
                identifier: 'activity-section-menu',
                container: true,
                child: PopupMenuButton<_ActivityPopupMenuSelection>(
                  icon: Icon(Icons.more_vert_rounded, color: palette.textMuted),
                  shape: Dimens.shapeM,
                  onSelected: (_ActivityPopupMenuSelection selection) async {
                    switch (selection) {
                      case _ActivityPopupMenuSelection.onCopy:
                        for (final activity in widget.userActivityList) {
                          widget.onCopyActivityCallback!(activity);
                        }
                      case _ActivityPopupMenuSelection.onShare:
                        if (context.mounted) {
                          final code =
                              SharedActivityPayload.fromUserActivityList(
                                widget.userActivityList,
                              ).toJsonString();
                          await showDialog(
                            context: context,
                            builder: (_) => ShareQrDialog(
                              title: S.of(context).shareActivityLabel,
                              code: code,
                              fileBaseName: 'workout_qr',
                            ),
                          );
                        }
                      case _ActivityPopupMenuSelection.onImport:
                        if (context.mounted) {
                          Navigator.of(context).pushNamed(
                            NavigationOptions.importActivityScannerRoute,
                          );
                        }
                    }
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<_ActivityPopupMenuSelection>>[
                        if (widget.onCopyActivityCallback != null &&
                            widget.userActivityList.isNotEmpty)
                          PopupMenuItem<_ActivityPopupMenuSelection>(
                            value: _ActivityPopupMenuSelection.onCopy,
                            child: Text(S.of(context).dialogCopyLabel),
                          ),
                        if (widget.userActivityList.isNotEmpty)
                          PopupMenuItem<_ActivityPopupMenuSelection>(
                            value: _ActivityPopupMenuSelection.onShare,
                            child: Text(S.of(context).shareActivityLabel),
                          ),
                        PopupMenuItem<_ActivityPopupMenuSelection>(
                          value: _ActivityPopupMenuSelection.onImport,
                          child: Text(S.of(context).importActivityLabel),
                        ),
                      ],
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            for (final userActivity in widget.userActivityList)
              ActivityCard(
                activityEntity: userActivity,
                onItemLongPressed: widget.onItemLongPressedCallback,
                onItemTapped: widget.onItemTappedCallback,
                onItemDragCallback: widget.onItemDragCallback,
                firstListElement: false,
              ),
          ],
        ),
      ],
    );
  }
}
