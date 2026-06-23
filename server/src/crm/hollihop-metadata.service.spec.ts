import { ConfigService } from "@nestjs/config";
import { HolliHopMetadataService } from "./hollihop-metadata.service";

describe("HolliHopMetadataService", () => {
  function createService(overrides: Record<string, unknown> = {}) {
    const values: Record<string, unknown> = {
      HOLLIHOP_BASE_URL: "https://example.test/Api/V2/",
      HOLLIHOP_AUTH_KEY: "",
      HOLLIHOP_TIMEOUT_MS: 1000,
      ...overrides,
    };
    const config = {
      get: jest.fn((key: string, fallback?: unknown) => values[key] ?? fallback),
    };
    return new HolliHopMetadataService(config as unknown as ConfigService);
  }

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("returns empty unconfigured metadata without calling HolliHop", async () => {
    const service = createService();
    const fetchMock = jest.spyOn(global, "fetch");

    await expect(service.listDisciplines()).resolves.toEqual({
      configured: false,
      items: [],
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("normalizes HolliHop discipline and lead status payloads", async () => {
    const service = createService({ HOLLIHOP_AUTH_KEY: "test-key" });
    const fetchMock = jest
      .spyOn(global, "fetch")
      .mockResolvedValueOnce(
        new Response(JSON.stringify(["Вокал", " Фортепиано "]), { status: 200 }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ Items: ["Дети", " Взрослые "] }), {
          status: 200,
        }),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            Statuses: [
              { Id: 10, Name: "Новый", Color: "C5A059", SortOrder: "2" },
              { Id: 11, Name: "" },
            ],
          }),
          { status: 200 },
        ),
      );

    await expect(service.listDisciplines()).resolves.toEqual({
      configured: true,
      items: ["Вокал", "Фортепиано"],
    });
    await expect(service.listCategories()).resolves.toEqual({
      configured: true,
      items: ["Дети", "Взрослые"],
    });
    await expect(service.listLeadStatuses()).resolves.toEqual({
      configured: true,
      items: [
        {
          externalId: "10",
          name: "Новый",
          color: "C5A059",
          sortOrder: 2,
        },
      ],
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://example.test/Api/V2/GetDisciplines?authkey=test-key",
      expect.objectContaining({ method: "GET" }),
    );
  });

  it("opens the circuit breaker after consecutive failures and stops calling fetch", async () => {
    const service = createService({ HOLLIHOP_AUTH_KEY: "test-key" });
    let now = 0;
    jest
      .spyOn(service as unknown as { now(): number }, "now")
      .mockImplementation(() => now);

    const fetchMock = jest
      .spyOn(global, "fetch")
      .mockRejectedValue(new Error("network down"));

    // 5 consecutive failures should open the breaker.
    for (let i = 0; i < 5; i += 1) {
      await expect(service.listDisciplines()).resolves.toEqual({
        configured: true,
        items: [],
      });
    }
    expect(fetchMock).toHaveBeenCalledTimes(5);

    // Breaker is OPEN: the next call must NOT touch fetch (fast-fail / degraded).
    fetchMock.mockClear();
    await expect(service.listDisciplines()).resolves.toEqual({
      configured: true,
      items: [],
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("closes the circuit breaker after cooldown on a successful probe", async () => {
    const service = createService({ HOLLIHOP_AUTH_KEY: "test-key" });
    let now = 0;
    jest
      .spyOn(service as unknown as { now(): number }, "now")
      .mockImplementation(() => now);

    const fetchMock = jest
      .spyOn(global, "fetch")
      .mockRejectedValue(new Error("network down"));

    for (let i = 0; i < 5; i += 1) {
      await service.listDisciplines();
    }
    expect(fetchMock).toHaveBeenCalledTimes(5);

    // Still within cooldown -> OPEN -> no fetch.
    fetchMock.mockClear();
    now += 10_000;
    await service.listDisciplines();
    expect(fetchMock).not.toHaveBeenCalled();

    // After cooldown -> HALF-OPEN probe is allowed and succeeds -> CLOSED.
    now += 30_000;
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify(["Вокал"]), { status: 200 }),
    );
    await expect(service.listDisciplines()).resolves.toEqual({
      configured: true,
      items: ["Вокал"],
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    // Breaker CLOSED: subsequent calls reach fetch again.
    fetchMock.mockResolvedValueOnce(
      new Response(JSON.stringify(["Гитара"]), { status: 200 }),
    );
    await expect(service.listDisciplines()).resolves.toEqual({
      configured: true,
      items: ["Гитара"],
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
