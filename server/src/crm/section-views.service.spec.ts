import { BadRequestException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { SectionViewsService, isSectionKey } from "./section-views.service";

describe("SectionViewsService", () => {
  const manager = { userId: "manager-a", role: "manager" as const };

  const createService = (rows: Record<string, unknown>[] = []) => {
    const query = jest.fn().mockResolvedValue({ rows });
    const service = new SectionViewsService({ query } as unknown as DatabaseService);
    return { service, query };
  };

  describe("unseenCounts", () => {
    it("отдаёт счётчики по разделам", async () => {
      const { service } = createService([
        { clients: "3", tasks: "1", schedule: "0", finance: "12" },
      ]);

      await expect(service.unseenCounts(manager)).resolves.toEqual({
        clients: 3,
        tasks: 1,
        schedule: 0,
        finance: 12,
      });
    });

    it("считает от отметки раздела, а нет её — от появления пользователя", async () => {
      const { service, query } = createService([
        { clients: "0", tasks: "0", schedule: "0", finance: "0" },
      ]);

      await service.unseenCounts(manager);

      const sql = String(query.mock.calls[0][0]);
      // Запас на случай, если отметки нет: иначе новый сотрудник увидел бы
      // счётчик от начала времён.
      expect(sql).toContain("u.created_at");
      expect(sql).toContain("app.section_views");
      expect(query.mock.calls[0][1]).toEqual(["manager-a"]);
    });

    /**
     * ⚠️ Задачи — только свои. Чужая задача не требует от человека действия, а
     * бейдж зовёт именно его. У школы 12 483 задачи: считай мы все, цифра стала
     * бы фоном, на который перестают смотреть.
     */
    it("задачи считает ТОЛЬКО для канонического получателя", async () => {
      const { service, query } = createService([
        { clients: "0", tasks: "0", schedule: "0", finance: "0" },
      ]);

      await service.unseenCounts(manager);

      expect(String(query.mock.calls[0][0])).toContain(
        "app.shared_task_recipients",
      );
    });

    it.each([["client"], ["teacher"]])(
      "роль %s не получает счётчиков CRM и не ходит в базу",
      async (role) => {
        const { service, query } = createService();

        await expect(
          service.unseenCounts({ userId: "u-1", role: role as never }),
        ).resolves.toEqual({ clients: 0, tasks: 0, schedule: 0, finance: 0 });
        // Ни одного запроса: у этих ролей таких вкладок нет вовсе.
        expect(query).not.toHaveBeenCalled();
      },
    );

    it("пользователь исчез между запросами — нули, а не падение", async () => {
      const { service } = createService([]);
      await expect(service.unseenCounts(manager)).resolves.toEqual({
        clients: 0,
        tasks: 0,
        schedule: 0,
        finance: 0,
      });
    });
  });

  describe("markSeen", () => {
    it("сдвигает отметку раздела на сейчас", async () => {
      const { service, query } = createService();

      await expect(service.markSeen(manager, "clients")).resolves.toEqual({
        section: "clients",
      });

      const sql = String(query.mock.calls[0][0]);
      expect(sql).toContain("insert into app.section_views");
      // Повторное открытие вкладки не должно ронять запрос.
      expect(sql).toContain("on conflict (user_id, section) do update");
      expect(query.mock.calls[0][1]).toEqual(["manager-a", "clients"]);
    });

    it("незнакомый раздел — отказ, а не молчаливая запись мусора", async () => {
      const { service, query } = createService();
      await expect(service.markSeen(manager, "чтотоневедомое")).rejects.toThrow(
        BadRequestException,
      );
      expect(query).not.toHaveBeenCalled();
    });
  });

  describe("isSectionKey", () => {
    it.each([["clients"], ["tasks"], ["schedule"], ["finance"]])(
      "%s — известный раздел",
      (key) => expect(isSectionKey(key)).toBe(true),
    );

    /**
     * ⚠️ «Чата» здесь нет намеренно: у него непрочитанные считаются точно, по
     * факту прочтения каждого сообщения. Подменять их приблизительным «когда я
     * заглядывал» значило бы ухудшить работающее.
     */
    it("chat НЕ в списке: у него свой, точный счётчик", () => {
      expect(isSectionKey("chat")).toBe(false);
    });

    it("выдуманное — не раздел", () => {
      expect(isSectionKey("reports")).toBe(false);
      expect(isSectionKey("")).toBe(false);
    });
  });
});
