/// [Level]s to control logging output. Logging can be enabled to include all
/// levels above certain [Level].
enum Level {
  all(0),
  @Deprecated('[verbose] is being deprecated in favor of [trace].')
  verbose(1000),
  trace(1000),
  debug(2000),
  info(3000),
  warning(4000),
  error(5000),
  @Deprecated('[wtf] is being deprecated in favor of [fatal].')
  wtf(5999),
  fatal(6000),
  @Deprecated('[nothing] is being deprecated in favor of [off].')
  nothing(9999),
  off(10000),
  ;

  final int value;
  // ignore: sort_constructors_first
  const Level(this.value);
}
