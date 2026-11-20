param([int]$Port = 4173, [switch]$Rebuild)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$flutter = Join-Path $PSScriptRoot '.tools/flutter/bin/flutter.bat'
$dart = Join-Path $PSScriptRoot '.tools/flutter/bin/dart.bat'
if (!(Test-Path $flutter)) { throw '请先按 .fvmrc 安装 Flutter 3.44.6 到 .tools/flutter。' }
if ($Rebuild -or !(Test-Path 'build/web/main.dart.js')) {
    & $flutter pub get
    if ($LASTEXITCODE) { throw 'Flutter 依赖安装失败。' }
    & $dart run build_runner build --force-jit --build-filter=lib/core/utils/env.g.dart
    if ($LASTEXITCODE) { throw '环境配置生成失败。' }
    function Build-OfficialWeb {
        & $flutter build web --profile --no-wasm-dry-run --no-pub --target lib/dev/main_dev.dart --dart-define=PREVIEW_LOCALE=zh
        if ($LASTEXITCODE) { throw 'Flutter Web 构建失败。' }
    }
    Build-OfficialWeb
    # Flutter compares cached output paths literally. Switching between a
    # Windows junction and its target can remove the just-built assets.
    if (!(Test-Path 'build/web/assets/AssetManifest.bin.json')) {
        Write-Warning '检测到路径别名切换后的 Flutter 资源清理问题，正在重新生成缺失资源。'
        Build-OfficialWeb
    }
}
foreach ($asset in @('AssetManifest.bin.json', 'FontManifest.json', 'fonts/MaterialIcons-Regular.otf')) {
    if (!(Test-Path (Join-Path 'build/web/assets' $asset))) {
        throw "Flutter Web 资源不完整（$asset），请使用 -Rebuild 重新构建。"
    }
}
& node tool/serve_web_preview.mjs $Port
