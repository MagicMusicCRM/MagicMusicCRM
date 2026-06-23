import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

export interface HolliHopResult<T> {
  configured: boolean;
  items: T[];
}

export interface HolliHopLeadStatus {
  externalId: string | null;
  name: string;
  color: string | null;
  sortOrder: number;
}

type CircuitState = "closed" | "open" | "half-open";

@Injectable()
export class HolliHopMetadataService {
  // Простой circuit-breaker вокруг исходящих вызовов HolliHop API.
  private static readonly FAILURE_THRESHOLD = 5;
  private static readonly COOLDOWN_MS = 30_000;

  private consecutiveFailures = 0;
  private circuitState: CircuitState = "closed";
  private openedAt = 0;

  constructor(private readonly config: ConfigService) {}

  async listDisciplines(): Promise<HolliHopResult<string>> {
    return {
      configured: this.isConfigured(),
      items: this.normalizeStringList(await this.read("GetDisciplines")),
    };
  }

  async listLevels(): Promise<HolliHopResult<string>> {
    return {
      configured: this.isConfigured(),
      items: this.normalizeStringList(await this.read("GetLevels")),
    };
  }

  async listCategories(): Promise<HolliHopResult<string>> {
    const categories = this.normalizeStringList(await this.read("GetCategories"));
    return {
      configured: this.isConfigured(),
      items: categories.length
        ? categories
        : this.normalizeStringList(await this.read("GetMaturities")),
    };
  }

  async listLeadStatuses(): Promise<HolliHopResult<HolliHopLeadStatus>> {
    const payload = await this.read("GetLeadStatuses");
    return {
      configured: this.isConfigured(),
      items: this.normalizeLeadStatuses(payload),
    };
  }

  private async read(method: string): Promise<unknown> {
    const authKey = this.config.get<string>("HOLLIHOP_AUTH_KEY", "").trim();
    if (!authKey) return null;

    // Если брейкер открыт и cooldown ещё не истёк — деградируем без вызова fetch.
    if (!this.canAttempt()) {
      return null;
    }

    const timeoutMs = this.config.get<number>("HOLLIHOP_TIMEOUT_MS", 5000);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(this.url(method, authKey), {
        method: "GET",
        signal: controller.signal,
      });
      if (!response.ok) {
        this.recordFailure();
        return null;
      }
      this.recordSuccess();
      return await response.json();
    } catch {
      this.recordFailure();
      return null;
    } finally {
      clearTimeout(timeout);
    }
  }

  // Возвращает true, если исходящий вызов разрешён (closed/half-open probe).
  private canAttempt(): boolean {
    if (this.circuitState === "open") {
      if (this.now() - this.openedAt >= HolliHopMetadataService.COOLDOWN_MS) {
        // Cooldown истёк — пропускаем один пробный вызов.
        this.circuitState = "half-open";
        return true;
      }
      return false;
    }
    return true;
  }

  private recordSuccess(): void {
    this.consecutiveFailures = 0;
    this.circuitState = "closed";
  }

  private recordFailure(): void {
    this.consecutiveFailures += 1;
    if (
      this.circuitState === "half-open" ||
      this.consecutiveFailures >= HolliHopMetadataService.FAILURE_THRESHOLD
    ) {
      this.circuitState = "open";
      this.openedAt = this.now();
    }
  }

  private now(): number {
    return Date.now();
  }

  private url(method: string, authKey: string): string {
    const base = this.config.get<string>(
      "HOLLIHOP_BASE_URL",
      "https://sokol.t8s.ru/Api/V2/",
    );
    const normalizedBase = base.endsWith("/") ? base : `${base}/`;
    const url = new URL(method, normalizedBase);
    url.searchParams.set("authkey", authKey);
    return url.toString();
  }

  private isConfigured(): boolean {
    return this.config.get<string>("HOLLIHOP_AUTH_KEY", "").trim().length > 0;
  }

  private normalizeStringList(payload: unknown): string[] {
    const source =
      Array.isArray(payload)
        ? payload
        : this.record(payload)?.Items ?? this.record(payload)?.items ?? [];
    if (!Array.isArray(source)) return [];
    return source
      .map((item) => (typeof item === "string" ? item : this.record(item)?.Name))
      .filter((item): item is string => typeof item === "string" && item.trim().length > 0)
      .map((item) => item.trim());
  }

  private normalizeLeadStatuses(payload: unknown): HolliHopLeadStatus[] {
    const source =
      Array.isArray(payload)
        ? payload
        : this.record(payload)?.Statuses ?? this.record(payload)?.items ?? [];
    if (!Array.isArray(source)) return [];
    return source.flatMap((item, index) => {
      const row = this.record(item);
      if (!row) return [];
      const name = this.firstString(row, ["Name", "name", "Title", "title", "Label", "label"]);
      if (!name) return [];
      return [
        {
          externalId: this.firstString(row, ["Id", "id", "ID", "ExternalId", "externalId"]),
          name,
          color: this.firstString(row, ["Color", "color"]) ?? null,
          sortOrder: this.firstNumber(row, ["SortOrder", "sortOrder", "Order", "order"]) ?? index,
        },
      ];
    });
  }

  private firstString(row: Record<string, unknown>, keys: string[]): string | null {
    for (const key of keys) {
      const value = row[key];
      if (typeof value === "string" && value.trim().length > 0) return value.trim();
      if (typeof value === "number" && Number.isFinite(value)) return String(value);
    }
    return null;
  }

  private firstNumber(row: Record<string, unknown>, keys: string[]): number | null {
    for (const key of keys) {
      const value = row[key];
      if (typeof value === "number" && Number.isFinite(value)) return value;
      if (typeof value === "string") {
        const numeric = Number(value);
        if (Number.isFinite(numeric)) return numeric;
      }
    }
    return null;
  }

  private record(value: unknown): Record<string, unknown> | null {
    return value !== null && typeof value === "object"
      ? (value as Record<string, unknown>)
      : null;
  }
}
