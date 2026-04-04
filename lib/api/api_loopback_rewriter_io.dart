import 'dart:io';

/// Android 模拟器里 `127.0.0.1` / `localhost` 指向模拟器自身，无法访问电脑上的后端。
/// 官方约定用 [10.0.2.2](https://developer.android.com/studio/run/emulator-networking) 访问宿主机。
///
/// 真机调试请使用 `--dart-define=API_BASE_URL=http://<电脑局域网IP>:8080`。
String applyAndroidEmulatorLoopbackRewrite(String url) {
  if (!Platform.isAndroid) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final h = uri.host.toLowerCase();
  if (h == '127.0.0.1' || h == 'localhost') {
    return uri.replace(host: '10.0.2.2').toString();
  }
  return url;
}
