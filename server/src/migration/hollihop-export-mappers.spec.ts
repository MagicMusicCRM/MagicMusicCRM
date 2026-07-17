import {
  cleanResponsible,
  historyFieldName,
  leadCommentFromRow,
  leadExternalId,
  parseRuDate,
  responsibleFromDescription,
  studentExternalId,
  studentNoteFromRow,
  taskFromRow,
  taskHistoryFromRow,
  taskStatusFromRow,
  taskTitle,
} from "./hollihop-export-mappers";

describe("parseRuDate", () => {
  it("parses date with a single-digit hour", () => {
    expect(parseRuDate("18.03.2026 9:55")).toBe("2026-03-18T09:55:00.000Z");
  });

  it("parses a date split across a newline", () => {
    // Real exports wrap the time onto the next line inside one cell.
    expect(parseRuDate("18.03.2026\n9:55")).toBe("2026-03-18T09:55:00.000Z");
  });

  it("parses a date with no time as midnight", () => {
    expect(parseRuDate("18.03.2026")).toBe("2026-03-18T00:00:00.000Z");
  });

  it("rejects a day that does not exist instead of rolling over", () => {
    // Date() would happily turn 31.02 into 03.03 and import a wrong deadline.
    expect(parseRuDate("31.02.2026")).toBeNull();
  });

  it("rejects an impossible time", () => {
    expect(parseRuDate("18.03.2026 25:00")).toBeNull();
  });

  it("returns null for junk rather than an epoch date", () => {
    expect(parseRuDate("")).toBeNull();
    expect(parseRuDate("не указано")).toBeNull();
    expect(parseRuDate(null)).toBeNull();
  });
});

describe("taskTitle", () => {
  it("takes the first non-empty line", () => {
    expect(taskTitle("\n\nПозвонить клиенту\nвторая строка")).toBe(
      "Позвонить клиенту",
    );
  });

  it("caps the length so a wall of text does not become a title", () => {
    expect(taskTitle("а".repeat(200))).toHaveLength(120);
  });

  it("names an empty description rather than producing a blank title", () => {
    expect(taskTitle("   ")).toBe("Задача (HolliHop)");
  });
});

describe("responsibleFromDescription", () => {
  // Колонка «Ответственный» бесполезна: у всех 544 строк выгрузки там «[Для
  // всех]», а настоящее имя лежит в тексте.
  //
  // ⚠️ Здесь раньше стояло «известный дефект: у всех 514 задач assigned_to =
  // NULL». Это неправда (прод, 17.07: исполнитель есть у 513 из 514). Пробел
  // другой — `created_by` пуст у всех 514.
  it("pulls the author out of a «(поставил …)» tail", () => {
    expect(
      responsibleFromDescription("Позвонить (поставил Иванов И.И. - 12.03.2026)"),
    ).toBe("Иванов И.И.");
  });

  it("handles the feminine form and a missing date", () => {
    expect(responsibleFromDescription("Текст (поставила Петрова А.)")).toBe(
      "Петрова А.",
    );
  });

  it("returns null when nobody is named", () => {
    expect(responsibleFromDescription("Просто описание без автора")).toBeNull();
    expect(responsibleFromDescription("")).toBeNull();
  });
});

describe("cleanResponsible", () => {
  it("drops bracketed placeholders that name nobody", () => {
    expect(cleanResponsible("[Для всех]")).toBeNull();
  });

  it("keeps a real name", () => {
    expect(cleanResponsible(" Иванов И.И. ")).toBe("Иванов И.И.");
  });
});

describe("taskFromRow", () => {
  it("reads a row and prefers the column over the text for the author", () => {
    const task = taskFromRow({
      // Колонки id в выгрузке задач нет (0 из 527 строк у заказчика), а
      // «ID клиента» здесь стоит намеренно: он НЕ должен читаться — это
      // ClientId, и в ученическом namespace он указал бы на чужого человека.
      "ID клиента": "12345",
      "Моб. телефон": "+7 (916) 123-45-67",
      Клиент: "Анна Иванова",
      Описание: "Позвонить (поставил Иванов И.И. - 12.03.2026)",
      "Дата выполнения": "18.03.2026 9:55",
      Ответственный: "Петрова А.",
    });

    expect(task).toEqual({
      externalId: "",
      phoneRaw: "+7 (916) 123-45-67",
      clientName: "Анна Иванова",
      description: "Позвонить (поставил Иванов И.И. - 12.03.2026)",
      dueRaw: "18.03.2026 9:55",
      responsible: "Петрова А.",
      completedRaw: "",
      status: "",
    });
  });

  it("falls back to the name in the text when the column is a placeholder", () => {
    const task = taskFromRow({
      Описание: "Позвонить (поставил Иванов И.И. - 12.03.2026)",
      Ответственный: "[Для всех]",
    });

    expect(task?.responsible).toBe("Иванов И.И.");
  });

  it("falls back to the Телефон column when Моб. телефон is absent", () => {
    expect(taskFromRow({ Описание: "x", Телефон: "89161234567" })?.phoneRaw).toBe(
      "89161234567",
    );
  });

  it("skips a row with neither description nor client", () => {
    expect(taskFromRow({ "Дата выполнения": "18.03.2026" })).toBeNull();
  });
});

describe("taskStatusFromRow", () => {
  it("maps the Russian statuses", () => {
    expect(taskStatusFromRow("Выполнена", null)).toBe("done");
    expect(taskStatusFromRow("Отменена", null)).toBe("cancelled");
    expect(taskStatusFromRow("В работе", null)).toBe("in_progress");
  });

  it("treats a completion date as done even with no status", () => {
    expect(taskStatusFromRow("", "2026-03-18T09:55:00.000Z")).toBe("done");
  });

  it("defaults to open", () => {
    expect(taskStatusFromRow("", null)).toBe("open");
  });
});

describe("studentNoteFromRow / leadCommentFromRow", () => {
  it("builds a student note and joins the name", () => {
    expect(
      studentNoteFromRow({
        Фамилия: "Иванова",
        Имя: "Анна",
        "Моб. телефон": "89161234567",
        Описание: "Заметка",
      }),
    ).toEqual({
      externalId: "",
      phoneRaw: "89161234567",
      name: "Иванова Анна",
      note: "Заметка",
      createdRaw: "",
    });
  });

  it("appends the custom-fields column to a lead comment", () => {
    expect(
      leadCommentFromRow({
        ФИО: "Анна Иванова",
        Комментарий: "Звонила",
        "Пользовательские поля": "Уровень: A1",
      })?.note,
    ).toBe("Звонила\nУровень: A1");
  });

  it("skips an empty note", () => {
    expect(studentNoteFromRow({ Фамилия: "Иванова" })).toBeNull();
  });
});

describe("внешние id: Student.Id vs ClientId", () => {
  // Все три случая — не гипотезы: измерены на выгрузке заказчика и сверены с
  // боевой базой 17.07.

  it("reads the Cyrillic «ИД» the export actually writes", () => {
    // Выгрузка пишет «ИД» КИРИЛЛИЦЕЙ (U+0418 U+0414), а маппер искал латинское
    // «ID» — и не находил ничего: 0 из 956 строк. Матчинг по внешнему id у
    // учеников не срабатывал ни разу, всё падало на телефон.
    expect(studentExternalId({ ИД: 1342, "ИД клиента": 1110 })).toBe("1342");
  });

  it("never takes ClientId for the student id", () => {
    // ⚠️ Первичный ключ выведен из Student.Id. У 113 из 1055 учеников
    // «ИД клиента» равен «ИД» ДРУГОГО ученика — на проде проверено живьём:
    // id 2512 как ClientId это Вероника Кочергина, как Student.Id — Мария
    // Кивелиди. Прими ClientId за Id, и заметки уедут в чужую карточку.
    expect(studentExternalId({ "ИД клиента": 1110 })).toBe("");
    expect(studentExternalId({ ClientId: 1110 })).toBe("");
  });

  it("reads the Latin ID the lead export writes", () => {
    // У лида ClientId нет вовсе (проверено по дампу API), путать не с чем.
    expect(leadExternalId({ ID: "6045" })).toBe("6045");
  });

  it("keeps the two id spaces apart", () => {
    // 58 чисел существуют и как Student.Id, и как Lead.Id. Один и тот же
    // «102» — разные люди, и хелперы не должны читать чужую колонку.
    expect(studentExternalId({ ID: "102" })).toBe("102");
    expect(leadExternalId({ ИД: "102" })).toBe("102");
    // …но ClientId не проходит ни в один namespace.
    expect(studentExternalId({ "ИД клиента": "102" })).toBe("");
  });

  it("does not read an id out of the tasks export, which has none", () => {
    // В tasks.json колонки id нет вовсе (0 из 527 строк) — задачи
    // сопоставляются телефоном, и это не фолбэк, а единственный способ.
    const task = taskFromRow({
      Описание: "перезвонить",
      Клиент: "Иванова Анна",
      "Моб. телефон": "89161234567",
    });
    expect(task?.externalId).toBe("");
    expect(task?.phoneRaw).toBe("89161234567");
  });
});

describe("taskHistoryFromRow", () => {
  it("reads a history row", () => {
    expect(
      taskHistoryFromRow({
        "Дата изменения": "18.03.2026 9:55",
        Поле: "Срок",
        Было: "12.03.2026",
        Стало: "18.03.2026",
        Автор: "Иванов И.И.",
      }),
    ).toEqual({
      field: "Срок",
      oldValue: "12.03.2026",
      newValue: "18.03.2026",
      author: "Иванов И.И.",
      changedRaw: "18.03.2026 9:55",
    });
  });

  it("drops a history row with no usable date", () => {
    // Spec §2.2 wants history «по датам и времени». An undated entry would sort
    // to the epoch and read as though it happened in 1970.
    expect(
      taskHistoryFromRow({ Поле: "Срок", "Дата изменения": "" }),
    ).toBeNull();
  });

  it("drops a history row that names no field", () => {
    expect(taskHistoryFromRow({ "Дата изменения": "18.03.2026" })).toBeNull();
  });
});

describe("historyFieldName", () => {
  it("maps Russian labels onto our task_history fields", () => {
    expect(historyFieldName("Срок")).toBe("due_at");
    expect(historyFieldName("Дата выполнения")).toBe("due_at");
    expect(historyFieldName("Статус")).toBe("status");
    expect(historyFieldName("Ответственный")).toBe("assigned_to");
  });

  it("passes an unknown label through instead of guessing", () => {
    expect(historyFieldName("Приоритет")).toBe("Приоритет");
  });
});
