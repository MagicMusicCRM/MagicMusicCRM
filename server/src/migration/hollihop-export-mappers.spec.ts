// server/src/migration/hollihop-export-mappers.spec.ts
import {
  parseRuDate, taskTitle, taskFromRow, studentNoteFromRow, leadCommentFromRow, cleanResponsible,
} from "./hollihop-export-mappers";

describe("parseRuDate", () => {
  it("parses dd.mm.yyyy and dd.mm.yyyy hh:mm", () => {
    expect(parseRuDate("18.01.2027")).toBe("2027-01-18T00:00:00.000Z");
    expect(parseRuDate("19.06.2026 17:18")).toBe("2026-06-19T17:18:00.000Z");
  });
  it("returns null for junk/empty", () => {
    expect(parseRuDate("")).toBeNull();
    expect(parseRuDate("нет")).toBeNull();
    expect(parseRuDate(null)).toBeNull();
  });
});

describe("taskTitle", () => {
  it("takes the first line trimmed to 120 chars", () => {
    expect(taskTitle("Звонок\nЕсли на Спортивной есть препод")).toBe("Звонок");
    expect(taskTitle("")).toBe("Задача (HolliHop)");
    expect(taskTitle("x".repeat(200)).length).toBe(120);
  });
});

describe("taskFromRow", () => {
  it("extracts the task fields", () => {
    expect(
      taskFromRow({
        "Дата выполнения": "18.01.2027",
        "Описание": "летом 26 не готова вернуться",
        "Клиент": "Кивелиди Мария",
        "Моб. телефон": "+79161037743",
        "Ответственный": "[Для всех]",
      }),
    ).toEqual({
      phoneRaw: "+79161037743",
      clientName: "Кивелиди Мария",
      description: "летом 26 не готова вернуться",
      dueRaw: "18.01.2027",
      responsible: "[Для всех]",
    });
  });
  it("returns null when there is neither description nor client", () => {
    expect(taskFromRow({ "Моб. телефон": "+79161037743" })).toBeNull();
  });
});

describe("studentNoteFromRow", () => {
  it("extracts the note from «Описание»", () => {
    expect(
      studentNoteFromRow({ "Моб. телефон": "89991234567", "Имя": "Петя", "Описание": "интерес пропал" }),
    ).toEqual({ phoneRaw: "89991234567", name: "Петя", note: "интерес пропал" });
  });
  it("returns null when «Описание» empty", () => {
    expect(studentNoteFromRow({ "Моб. телефон": "8999", "Описание": "" })).toBeNull();
  });
});

describe("leadCommentFromRow", () => {
  it("combines «Комментарий» + «Пользовательские поля»", () => {
    expect(
      leadCommentFromRow({ "Моб. телефон": "8999", "ФИО": "Иван", "Комментарий": "перезвонить", "Пользовательские поля": "тег: VIP" }),
    ).toEqual({ phoneRaw: "8999", name: "Иван", body: "перезвонить\nтег: VIP" });
  });
  it("returns null when «Комментарий» empty", () => {
    expect(leadCommentFromRow({ "Комментарий": "" })).toBeNull();
  });
});

describe("cleanResponsible", () => {
  it("nulls placeholders, trims names", () => {
    expect(cleanResponsible("[Для всех]")).toBeNull();
    expect(cleanResponsible("")).toBeNull();
    expect(cleanResponsible("Сусарина Анна Владимировна")).toBe("Сусарина Анна Владимировна");
  });
});
