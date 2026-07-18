export class SafeLogger {
  constructor(vault, sink = console) {
    this.vault = vault;
    this.sink = sink;
  }

  info(message) {
    this.sink.log(this.vault.redact(message));
  }

  warn(message) {
    this.sink.warn(this.vault.redact(message));
  }

  error(message) {
    this.sink.error(this.vault.redact(message));
  }
}
