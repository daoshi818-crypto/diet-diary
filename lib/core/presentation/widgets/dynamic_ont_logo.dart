import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:opennutritracker/generated/l10n.dart';

class DynamicOntLogo extends StatelessWidget {
  const DynamicOntLogo({super.key});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icon/diet_diary_icon.svg',
    semanticsLabel: S.of(context).appTitle,
  );
}
