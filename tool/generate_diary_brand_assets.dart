// Regenerate PNGs from SVG: flutter test tool/generate_diary_brand_assets.dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _render(String svg, String path, int size) async {
  final source = await vg.loadPicture(SvgStringLoader(svg), null);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(size / 256);
  canvas.drawPicture(source.picture);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Could not render $path');
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  source.picture.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate diary brand assets from SVG masters', () async {
    final icon = await File('assets/icon/diet_diary_icon.svg').readAsString();
    // Launchers apply their own mask: leave no transparent rounded corners.
    final fullBleed = icon.replaceFirst('rx="58"', 'rx="0"');
    final foreground = icon.replaceFirst(
      RegExp(r'<rect id="background"[^>]*/>'),
      '',
    );
    final mono = await File(
      'assets/icon/diet_diary_monochrome.svg',
    ).readAsString();
    await _render(fullBleed, 'assets/icon/diet_diary_icon.png', 1024);
    await _render(foreground, 'assets/icon/diet_diary_foreground.png', 1024);
    await _render(mono, 'assets/icon/diet_diary_monochrome.png', 1024);
    await _render(icon, 'web/favicon.png', 64);
    for (final size in [192, 512]) {
      await _render(icon, 'web/icons/Icon-$size.png', size);
      await _render(fullBleed, 'web/icons/Icon-maskable-$size.png', size);
    }
  });
}
