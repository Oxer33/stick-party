/// Lightweight success/failure envelope.
///
/// Boundaries (save load, json parse, store calls) return a [Result] instead of
/// throwing into the game loop. No silent swallow: an [Err] always carries a
/// human-readable [message]. KISS — no external dependency.
library;

sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// The value when [isOk], else null.
  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;

  /// The value when [isOk], else [fallback].
  T orElse(T fallback) => this is Ok<T> ? (this as Ok<T>).value : fallback;

  /// Collapse both branches to a single value.
  R fold<R>(R Function(T value) onOk, R Function(Err<T> err) onErr) {
    final self = this;
    return self is Ok<T> ? onOk(self.value) : onErr(self as Err<T>);
  }
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final String message;
  final Object? cause;
  const Err(this.message, {this.cause});
}
