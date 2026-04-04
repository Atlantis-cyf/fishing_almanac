# 当前会话将 Flutter SDK 加入 PATH（按本机安装路径修改首行）。
# 使用：在 PowerShell 中 `.\tool\flutter_env.ps1` 后再运行 `dart analyze` / `flutter test`
$flutterBin = "C:\Users\cyf32\flutter\bin"
if (-not (Test-Path "$flutterBin\flutter.bat")) {
  $flutterBin = "C:\src\flutter\bin"
}
if (Test-Path "$flutterBin\flutter.bat") {
  $env:Path = "$flutterBin;$env:Path"
  Write-Host "PATH 已包含: $flutterBin"
} else {
  Write-Warning "未找到 flutter.bat，请编辑 tool/flutter_env.ps1 中的 `$flutterBin"
}
