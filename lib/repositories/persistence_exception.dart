/// 本地持久化（SharedPreferences 等）失败时抛出，供上层展示 SnackBar / 对话框。
class PersistenceException implements Exception {
  PersistenceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PersistenceException: $message';
}
