import { ClientReferenceService } from "./clients/client-reference.service";
import { ClientConversionService } from "./clients/client-conversion.service";
import { ClientArchiveService } from "./clients/client-archive.service";
import { CrmClientsController } from "./crm-clients.controller";

describe("CrmClientsController", () => {
  const actor = { userId: "actor-1", role: "teacher" as const };
  const clientReferences = {
    resolve: jest.fn(),
    search: jest.fn(),
  };
  const archives = {
    preview: jest.fn(),
    archive: jest.fn(),
    archiveConvertedLead: jest.fn(),
  };
  const controller = new CrmClientsController(
    clientReferences as unknown as ClientReferenceService,
    {
      convert: jest.fn(),
    } as unknown as ClientConversionService,
    archives as unknown as ClientArchiveService,
  );

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("forwards the typed resolver contract", async () => {
    const ref = {
      type: "lead" as const,
      id: "2208d64d-3eca-4a5c-9417-e763582fce11",
    };
    clientReferences.resolve.mockResolvedValue({ ref });

    await expect(controller.resolve(actor, ref)).resolves.toEqual({ ref });
    expect(clientReferences.resolve).toHaveBeenCalledWith(actor, ref);
  });

  it("forwards the scoped search contract", async () => {
    const query = { q: "Анна", type: "student" as const, limit: 10 };
    clientReferences.search.mockResolvedValue({ items: [] });

    await expect(controller.search(actor, query)).resolves.toEqual({
      items: [],
    });
    expect(clientReferences.search).toHaveBeenCalledWith(actor, query);
  });

  it("forwards preview and versioned archive commands", async () => {
    const ref = {
      type: "student" as const,
      id: "2208d64d-3eca-4a5c-9417-e763582fce11",
    };
    const command = {
      ...ref,
      expectedVersion: 3,
      confirm: true as const,
      reason: "test.client-archive",
    };
    archives.preview.mockResolvedValue({ ref });
    archives.archive.mockResolvedValue({ tombstone: { ref } });

    await expect(controller.archivePreview(actor, ref)).resolves.toEqual({
      ref,
    });
    await expect(controller.archiveClient(actor, command)).resolves.toEqual({
      tombstone: { ref },
    });
    expect(archives.preview).toHaveBeenCalledWith(actor, ref);
    expect(archives.archive).toHaveBeenCalledWith(actor, command);
  });
});
