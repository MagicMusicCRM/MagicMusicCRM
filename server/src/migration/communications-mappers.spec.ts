import {
  communicationFromRow,
  communicationTaskKey,
  parseRowDate,
  parseTaskDescription,
  resolveYear,
  taskStatusFromEvents,
  taskTitleFromBody,
  toInstant,
} from "./communications-mappers";

/**
 * Все строки здесь — НАСТОЯЩИЕ, из выгрузки заказчика от 17.07. Придуманные
 * фикстуры в прошлый раз и позволили дефектам проехать: они описывали формат,
 * которого в файле нет.
 */
describe("parseTaskDescription", () => {
  it("вытаскивает автора, дату и событие закрытия из текста", () => {
    // Реальная строка «Маг Анри», закрытая задача.
    const parsed = parseTaskDescription(
      'надо записать душнилу на пробный, переписка в тг\n' +
        '(поставил Богатырёва М. В. - 15.06)\n' +
        'Статус "Закрыта" (установил Мазалова А. Ю.) - 16.06 19:42',
    );

    expect(parsed.body).toBe("надо записать душнилу на пробный, переписка в тг");
    expect(parsed.createdBy).toBe("Богатырёва М. В.");
    expect(parsed.createdDay).toBe(15);
    expect(parsed.createdMonth).toBe(6);
    expect(parsed.createdYear).toBeNull(); // года в строке нет
    expect(parsed.statusEvents).toEqual([
      {
        status: "Закрыта",
        actor: "Мазалова А. Ю.",
        day: 16,
        month: 6,
        year: null,
        hour: 19,
        minute: 42,
      },
    ]);
  });

  it("режет служебные строки из тела — им место в полях", () => {
    // Прошлый импорт оставил их внутри, и на проде 8 579 «комментариев»
    // выглядят как «Сайт · Исходящая: Контроль ⏎ (поставил …) ⏎ Статус "…"».
    const parsed = parseTaskDescription(
      'Контроль\n(поставил Каралкина А. А. - 06.04.24)\nСтатус "Закрыта" - 09.04.24 12:29',
    );
    expect(parsed.body).toBe("Контроль");
    expect(parsed.body).not.toContain("поставил");
    expect(parsed.body).not.toContain("Статус");
  });

  it("читает двузначный год, когда он есть", () => {
    // 5 062 строки из 12 269 пишут год: «(поставил X - 09.07.25)».
    const parsed = parseTaskDescription(
      'ЗАПИСАТЬ\n(поставил Назарова Н. Н. - 09.07.25)\nСтатус "Закрыта" - 10.07.25 11:00',
    );
    expect(parsed.createdYear).toBe(2025);
    expect(parsed.statusEvents[0].year).toBe(2025);
  });

  it("берёт событие закрытия БЕЗ автора, а не теряет его", () => {
    // 316 строк из 12 162 записаны без «установил». Пропусти форму — и 316
    // закрытий исчезли бы целиком, а не просто остались без автора.
    const parsed = parseTaskDescription(
      'Написала сама\nСтатус "Закрыта" - 10.02.25 21:15',
    );
    expect(parsed.statusEvents).toHaveLength(1);
    expect(parsed.statusEvents[0].actor).toBeNull();
    expect(parsed.statusEvents[0].status).toBe("Закрыта");
    expect(parsed.statusEvents[0].year).toBe(2025);
  });

  it("не приклеивает «а» к имени в женской форме", () => {
    // `поставил|поставила` совпало бы с короткой веткой и оставило «а» имени.
    const parsed = parseTaskDescription("Текст\n(поставила Петрова А. - 01.02)");
    expect(parsed.createdBy).toBe("Петрова А.");
  });

  it("оставляет открытую задачу без событий", () => {
    // Реальная открытая задача «Маг Анри» — статуса в тексте нет.
    const parsed = parseTaskDescription(
      "инфо задача: если будут новые педагоги по вокалу, выслать визитку и предложить ему пробник\n" +
        "(поставил Мазалова А. Ю. - 21.06)",
    );
    expect(parsed.statusEvents).toEqual([]);
    expect(parsed.createdBy).toBe("Мазалова А. Ю.");
  });

  it("сохраняет многострочное тело и хвост после статуса", () => {
    const parsed = parseTaskDescription(
      'надо записать душнилу на пробный\n' +
        '(поставил Богатырёва М. В. - 15.06)\n' +
        'Статус "Закрыта" (установил Мазалова А. Ю.) - 16.06 19:42\n' +
        'ему надо видео, у миши видео не понравилось',
    );
    expect(parsed.body).toBe(
      "надо записать душнилу на пробный\nему надо видео, у миши видео не понравилось",
    );
  });

  it("переживает строку без служебных пометок", () => {
    const parsed = parseTaskDescription("В отъезде");
    expect(parsed.body).toBe("В отъезде");
    expect(parsed.createdBy).toBeNull();
    expect(parsed.statusEvents).toEqual([]);
  });

  it("вычищает ВСЕ «поставил», когда в ячейке склеено несколько задач", () => {
    // Реальный случай: 2 строки из 12 744 — HolliHop склеил в одну ячейку
    // задачу и дописанную поверх следующую. `replace` без флага `g` убирал
    // только первое «(поставил …)», и второе оставалось в теле.
    const parsed = parseTaskDescription(
      "не ставить Ксюше занятия с 23.05\n" +
        "(поставил Нестер К. И. - 06.05)\n" +
        "(поставил Нестер К. И. - 06.05.25)\n" +
        'Статус "Закрыта" (установил Нестер К. И.) - 06.05.25 22:16',
    );
    expect(parsed.body).toBe("не ставить Ксюше занятия с 23.05");
    expect(parsed.body).not.toContain("поставил");
    // Автор — ПЕРВЫЙ: он поставил задачу раньше.
    expect(parsed.createdBy).toBe("Нестер К. И.");
    expect(parsed.createdDay).toBe(6);
    expect(parsed.createdYear).toBeNull(); // у первого года нет
  });

  it("берёт все события, когда закрытий несколько", () => {
    const parsed = parseTaskDescription(
      "попробовать пригласить на концерт\n" +
        "(поставил Богатырёва М. В. - 09.12)\n" +
        'Статус "Закрыта" (установил Крошкин Д. А.) - 11.12 13:34\n' +
        "Попробовать дозвонится маме\n" +
        "(поставил Крошкин Д. А. - 11.12.25)\n" +
        'Статус "Закрыта" (установил Сусарина А. В.) - 13.12.25 17:23',
    );
    expect(parsed.statusEvents).toHaveLength(2);
    expect(parsed.statusEvents[1].actor).toBe("Сусарина А. В.");
    expect(parsed.body).not.toContain("поставил");
    expect(parsed.body).not.toContain("Статус");
  });
});

describe("resolveYear", () => {
  const anchor = { day: 16, month: 6, year: 2026 };

  it("берёт явный год, если он есть", () => {
    expect(resolveYear({ day: 9, month: 7, year: 2025 }, anchor)).toBe(2025);
  });

  it("берёт год якоря для даты раньше него", () => {
    // «поставил 15.06» при закрытии 16.06.2026 → 2026.
    expect(resolveYear({ day: 15, month: 6, year: null }, anchor)).toBe(2026);
  });

  it("откатывает год, когда дата иначе окажется позже якоря", () => {
    // Задача поставлена 28.12 и закрыта 16.06.2026 → поставлена в 2025.
    expect(resolveYear({ day: 28, month: 12, year: null }, anchor)).toBe(2025);
  });

  it("тот же день, что и якорь, — это год якоря", () => {
    expect(resolveYear({ day: 16, month: 6, year: null }, anchor)).toBe(2026);
  });
});

describe("toInstant", () => {
  it("собирает UTC-инстант", () => {
    expect(toInstant(16, 6, 2026, 19, 42)).toBe("2026-06-16T19:42:00.000Z");
  });

  it("отвергает несуществующую дату вместо переноса", () => {
    // Date.UTC молча превратил бы 31.02 в 03.03.
    expect(toInstant(31, 2, 2026)).toBeNull();
  });
});

describe("parseRowDate", () => {
  it("читает дату со временем на другой строке", () => {
    // В ячейке выгрузки время переносится: «21.06.2026\n14:14».
    expect(parseRowDate("21.06.2026\n14:14")?.iso).toBe(
      "2026-06-21T14:14:00.000Z",
    );
  });

  it("читает дату без времени", () => {
    const d = parseRowDate("11.08.2027");
    expect(d?.iso).toBe("2027-08-11T00:00:00.000Z");
    expect(d?.year).toBe(2027);
  });

  it("возвращает null на мусоре", () => {
    expect(parseRowDate("")).toBeNull();
    expect(parseRowDate("не указано")).toBeNull();
  });
});

describe("communicationFromRow", () => {
  const MAG_ANRI = {
    Дата: "11.08.2027",
    Ученик: "Маг Анри",
    Способ: "Сайт",
    Направление: "Исходящая",
    Описание:
      "инфо задача: если будут новые педагоги по вокалу, выслать визитку и предложить ему пробник\n(поставил Мазалова А. Ю. - 21.06)",
    "ИД ученика": "",
  };

  it("разбирает реальную строку заказчика", () => {
    const c = communicationFromRow(MAG_ANRI);
    expect(c?.isTask).toBe(true);
    expect(c?.clientName).toBe("Маг Анри");
    expect(c?.channel).toBe("Сайт");
    expect(c?.direction).toBe("Исходящая");
    // Способ и направление — метаданные, в тело не попадают.
    expect(c?.parsed.body).not.toContain("Сайт");
    expect(c?.parsed.body).not.toContain("Исходящая");
    // У лида «ИД ученика» пуст — это норма, матчинг пойдёт по имени.
    expect(c?.studentExternalId).toBe("");
  });

  it("читает «ИД ученика» как Student.Id", () => {
    // Проверено на проде: 2512 → Мария Кивелиди (hollihopId), а НЕ Вероника
    // Кочергина (это был бы hollihopClientId).
    const c = communicationFromRow({
      Дата: "18.01.2027",
      Ученик: "Кивелиди Мария Владиславовна",
      Описание: "летом 26 не готова вернуться\n(поставил Мазалова А. Ю. - 31.05)",
      "ИД ученика": "2512",
    });
    expect(c?.studentExternalId).toBe("2512");
  });

  it("отличает обычную коммуникацию от задачи", () => {
    // 475 строк из 12 744 — не задачи: в тексте нет «поставил».
    const c = communicationFromRow({
      Дата: "01.03.2026",
      Ученик: "Иванов Иван",
      Описание: "В отъезде",
    });
    expect(c?.isTask).toBe(false);
  });

  it("считает задачей строку со статусом, но без «поставил»", () => {
    const c = communicationFromRow({
      Дата: "10.02.2025",
      Ученик: "Иванов Иван",
      Описание: 'Статус "Закрыта" - 10.02.25 21:15',
    });
    expect(c?.isTask).toBe(true);
  });

  it("пропускает пустой хвост выгрузки", () => {
    // В файле 127 459 строк, реальных 12 744 — остальное пустое.
    expect(communicationFromRow({})).toBeNull();
    expect(communicationFromRow({ Дата: "", Ученик: "", Описание: "" })).toBeNull();
  });
});

describe("taskStatusFromEvents", () => {
  it("нет событий — задача открыта", () => {
    expect(taskStatusFromEvents([])).toBe("open");
  });

  it("«Закрыта» — единственное значение во всех 12 162 закрытиях", () => {
    expect(
      taskStatusFromEvents([
        { status: "Закрыта", actor: null, day: 1, month: 1, year: null, hour: null, minute: null },
      ]),
    ).toBe("done");
  });

  it("берёт ПОСЛЕДНЕЕ событие, а не первое", () => {
    expect(
      taskStatusFromEvents([
        { status: "Закрыта", actor: null, day: 1, month: 1, year: null, hour: null, minute: null },
        { status: "В работе", actor: null, day: 2, month: 1, year: null, hour: null, minute: null },
      ]),
    ).toBe("in_progress");
  });
});

describe("taskTitleFromBody", () => {
  it("берёт первую строку", () => {
    expect(taskTitleFromBody("записать на пробный\nвторая строка")).toBe(
      "записать на пробный",
    );
  });

  it("не падает на пустом теле", () => {
    expect(taskTitleFromBody("")).toBe("Задача (HolliHop)");
  });

  it("обрезает длинный заголовок", () => {
    expect(taskTitleFromBody("х".repeat(200))).toHaveLength(120);
  });
});

describe("communicationTaskKey", () => {
  const open = parseTaskDescription("записать на пробный\n(поставил Иванов И. - 15.06)");
  const closed = parseTaskDescription(
    'записать на пробный\n(поставил Иванов И. - 15.06)\nСтатус "Закрыта" (установил Петров П.) - 16.06 19:42',
  );

  it("ключ НЕ меняется, когда задачу закрыли", () => {
    // ⚠️ Задача живёт: сегодня открыта, завтра закрыта. Попади статус в ключ —
    // следующая выгрузка породила бы ВТОРУЮ задачу вместо обновления первой.
    expect(communicationTaskKey("lead-1", open)).toBe(
      communicationTaskKey("lead-1", closed),
    );
  });

  it("различает две задачи одного клиента", () => {
    const other = parseTaskDescription("позвонить маме\n(поставил Иванов И. - 15.06)");
    expect(communicationTaskKey("lead-1", open)).not.toBe(
      communicationTaskKey("lead-1", other),
    );
  });

  it("различает одинаковый текст у разных клиентов", () => {
    expect(communicationTaskKey("lead-1", open)).not.toBe(
      communicationTaskKey("lead-2", open),
    );
  });
});
