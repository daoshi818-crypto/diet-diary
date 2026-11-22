import 'package:flutter/material.dart';
import 'package:opennutritracker/generated/l10n.dart';

class AppModalSheet extends StatelessWidget {
  final Widget child;
  final String identifier;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final ScrollController? controller;
  final VoidCallback? onClose;
  final Key? panelKey;
  final String? closeIdentifier;

  const AppModalSheet({
    super.key,
    required this.child,
    required this.identifier,
    this.padding = const EdgeInsets.all(20),
    this.scrollable = true,
    this.controller,
    this.onClose,
    this.panelKey,
    this.closeIdentifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: Material(
                      key: panelKey,
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: scrollable
                          ? Scrollbar(
                              controller: controller,
                              thumbVisibility: controller != null,
                              child: SingleChildScrollView(
                                controller: controller,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: padding,
                                child: child,
                              ),
                            )
                          : Padding(padding: padding, child: child),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Semantics(
                      identifier: closeIdentifier ?? '$identifier-close',
                      child: IconButton.filledTonal(
                        tooltip: S.of(context).dialogCloseLabel,
                        style: IconButton.styleFrom(
                          fixedSize: const Size.square(48),
                          backgroundColor: colors.surface,
                          foregroundColor: colors.onSurface,
                        ),
                        onPressed: onClose ?? () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
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
