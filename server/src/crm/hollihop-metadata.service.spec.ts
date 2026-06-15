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
});
