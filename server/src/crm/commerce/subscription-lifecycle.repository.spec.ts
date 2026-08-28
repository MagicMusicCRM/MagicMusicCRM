import { SubscriptionLifecycleRepository } from "./subscription-lifecycle.repository";

describe("SubscriptionLifecycleRepository replacement context mapping", () => {
  const issuedSubscriptionId = "issued-a";
  const newPackageId = "package-a";

  function replacementRow(overrides: Record<string, unknown> = {}) {
    return {
      issued_id: issuedSubscriptionId,
      student_id: "student-a",
      payer_student_id: "payer-a",
      funding_mode: "personal_account",
      purchase_reason: "renewal",
      old_package_id: "package-old",
      old_status: "active",
      old_version: "7",
      old_final_price_minor: "120000",
      old_currency_code: "RUB",
      legacy_lessons_used: "3.00",
      new_package_id: newPackageId,
      new_package_name: "Новый пакет",
      new_package_units: "12",
      new_package_price_minor: "150000",
      new_package_currency_code: "RUB",
      new_package_validity_days: 90,
      new_package_active: true,
      new_package_version: "4",
      new_package_deleted_at: null,
      used_units: "3.00",
      actual_paid_minor: "90000",
      reserved_lesson_count: "1",
      reserved_units: "1.00",
      reserved_rows: [
        {
          reservationId: "reservation-a",
          lessonId: "lesson-a",
          scheduledAt: null,
          units: "1.00",
        },
      ],
      future_lesson_count: "2",
      future_units: "2.00",
      ...overrides,
    };
  }

  function createRepository(rows: unknown[]) {
    const query = jest.fn().mockResolvedValue({ rows });
    const [database] = [{ query }] as unknown as ConstructorParameters<
      typeof SubscriptionLifecycleRepository
    >;
    const repository = new SubscriptionLifecycleRepository(database);
    return { repository, query };
  }

  async function readRow(overrides: Record<string, unknown> = {}) {
    const { repository } = createRepository([replacementRow(overrides)]);
    return repository.readReplacementContext(
      issuedSubscriptionId,
      newPackageId,
    );
  }

  describe("missing rows", () => {
    it.each([
      ["an empty query result", []],
      ["an explicit runtime null row", [null]],
    ])("maps %s to null with exact query parameters", async (_label, rows) => {
      const { repository, query } = createRepository(rows);

      await expect(
        repository.readReplacementContext(
          issuedSubscriptionId,
          newPackageId,
        ),
      ).resolves.toBeNull();

      expect(query).toHaveBeenCalledTimes(1);
      expect(query).toHaveBeenCalledWith(expect.any(String), [
        issuedSubscriptionId,
        newPackageId,
      ]);
    });
  });

  describe("full mapped context", () => {
    it("preserves exact objects, key order, falsy required values, and deletedAt identity", async () => {
      const deletedAt = new Date("2026-08-28T06:00:00.000Z");
      const reservedRows = [
        {
          reservationId: "reservation-a",
          lessonId: "lesson-a",
          scheduledAt: null,
          units: "-0.00",
        },
      ];
      const { repository } = createRepository([
        replacementRow({
          purchase_reason: null,
          old_version: "0",
          old_final_price_minor: "0012.3400",
          old_currency_code: "rub",
          legacy_lessons_used: "12.000",
          new_package_name: "",
          new_package_units: "",
          new_package_price_minor: "",
          new_package_currency_code: "",
          new_package_validity_days: null,
          new_package_active: false,
          new_package_version: 0,
          new_package_deleted_at: deletedAt,
          used_units: "12.3400",
          actual_paid_minor: "000500.00",
          reserved_lesson_count: "0",
          reserved_units: "-0.00",
          reserved_rows: reservedRows,
          future_lesson_count: 0,
          future_units: "1.",
        }),
      ]);

      const result = await repository.readReplacementContext(
        issuedSubscriptionId,
        newPackageId,
      );

      expect(result).toEqual({
        issuedSubscriptionId: "issued-a",
        studentId: "student-a",
        payerStudentId: "payer-a",
        fundingMode: "personal_account",
        purchaseReason: null,
        oldPackageId: "package-old",
        oldStatus: "active",
        oldVersion: 0,
        oldFinalPriceMinor: "0012.3400",
        oldCurrencyCode: "rub",
        legacyLessonsUsed: "12.000",
        newPackage: {
          id: "package-a",
          name: "",
          unitCount: "",
          basePriceMinor: "",
          currencyCode: "",
          validityDays: null,
          active: false,
          version: 0,
          deletedAt,
        },
        usedUnits: "12.34",
        actualPaidMinor: "000500.00",
        reservedLessonCount: 0,
        reservedUnits: "0",
        reservedRows: [
          {
            reservationId: "reservation-a",
            lessonId: "lesson-a",
            scheduledAt: null,
            units: "0",
          },
        ],
        futureLessonCount: 0,
        futureUnits: "1",
      });
      expect(Object.keys(result!)).toEqual([
        "issuedSubscriptionId",
        "studentId",
        "payerStudentId",
        "fundingMode",
        "purchaseReason",
        "oldPackageId",
        "oldStatus",
        "oldVersion",
        "oldFinalPriceMinor",
        "oldCurrencyCode",
        "legacyLessonsUsed",
        "newPackage",
        "usedUnits",
        "actualPaidMinor",
        "reservedLessonCount",
        "reservedUnits",
        "reservedRows",
        "futureLessonCount",
        "futureUnits",
      ]);
      expect(Object.keys(result!.newPackage!)).toEqual([
        "id",
        "name",
        "unitCount",
        "basePriceMinor",
        "currencyCode",
        "validityDays",
        "active",
        "version",
        "deletedAt",
      ]);
      expect(Object.keys(result!.reservedRows[0]!)).toEqual([
        "reservationId",
        "lessonId",
        "scheduledAt",
        "units",
      ]);
      expect(result!.newPackage!.deletedAt).toBe(deletedAt);
    });
  });

  describe("package presence", () => {
    it.each([
      ["null ID", { new_package_id: null }],
      ["undefined ID", { new_package_id: undefined }],
      ["empty ID", { new_package_id: "" }],
      ["zero ID", { new_package_id: 0 }],
      ["false ID", { new_package_id: false }],
      ["NaN ID", { new_package_id: Number.NaN }],
      ["null name", { new_package_name: null }],
      ["null units", { new_package_units: null }],
      ["null price", { new_package_price_minor: null }],
      ["null currency", { new_package_currency_code: null }],
      ["null active flag", { new_package_active: null }],
      ["null version", { new_package_version: null }],
    ])("maps a package with %s to null", async (_label, overrides) => {
      const result = await readRow(overrides);

      expect(result!.newPackage).toBeNull();
    });

    it("accepts runtime undefined for every strict-null required package field", async () => {
      const result = await readRow({
        new_package_name: undefined,
        new_package_units: undefined,
        new_package_price_minor: undefined,
        new_package_currency_code: undefined,
        new_package_active: undefined,
        new_package_version: undefined,
      });

      expect(result!.newPackage).toEqual({
        id: "package-a",
        name: undefined,
        unitCount: undefined,
        basePriceMinor: undefined,
        currencyCode: undefined,
        validityDays: 90,
        active: undefined,
        version: Number.NaN,
        deletedAt: null,
      });
    });
  });

  describe("numeric conversion", () => {
    it.each([
      ["old_version", "oldVersion", "empty string", "", 0],
      ["old_version", "oldVersion", "null", null, 0],
      ["old_version", "oldVersion", "negative zero", "-0", -0],
      ["old_version", "oldVersion", "invalid text", "invalid", Number.NaN],
      ["old_version", "oldVersion", "Infinity", "Infinity", Infinity],
      [
        "reserved_lesson_count",
        "reservedLessonCount",
        "empty string",
        "",
        0,
      ],
      ["reserved_lesson_count", "reservedLessonCount", "null", null, 0],
      [
        "reserved_lesson_count",
        "reservedLessonCount",
        "negative zero",
        "-0",
        -0,
      ],
      [
        "reserved_lesson_count",
        "reservedLessonCount",
        "invalid text",
        "invalid",
        Number.NaN,
      ],
      [
        "reserved_lesson_count",
        "reservedLessonCount",
        "Infinity",
        "Infinity",
        Infinity,
      ],
      ["future_lesson_count", "futureLessonCount", "empty string", "", 0],
      ["future_lesson_count", "futureLessonCount", "null", null, 0],
      [
        "future_lesson_count",
        "futureLessonCount",
        "negative zero",
        "-0",
        -0,
      ],
      [
        "future_lesson_count",
        "futureLessonCount",
        "invalid text",
        "invalid",
        Number.NaN,
      ],
      [
        "future_lesson_count",
        "futureLessonCount",
        "Infinity",
        "Infinity",
        Infinity,
      ],
    ] as const)(
      "maps %s %s through Number for %s",
      async (inputField, outputField, _label, input, expected) => {
        const result = await readRow({ [inputField]: input });

        expect(result![outputField]).toBe(expected);
      },
    );

    it.each([
      ["empty string", "", 0],
      ["negative zero", "-0", -0],
      ["invalid text", "invalid", Number.NaN],
      ["Infinity", "Infinity", Infinity],
    ])("maps package version %s through Number", async (_label, input, expected) => {
      const result = await readRow({ new_package_version: input });

      expect(result!.newPackage!.version).toBe(expected);
    });

    it("normalizes only usage and reservation units while preserving package, money, and legacy strings", async () => {
      const result = await readRow({
        old_final_price_minor: "0012.3400",
        old_currency_code: "rub",
        legacy_lessons_used: "12.000",
        new_package_units: "12.000",
        new_package_price_minor: "001000.00",
        new_package_currency_code: "rUb",
        used_units: "-0.00",
        actual_paid_minor: "000500.00",
        reserved_units: "12.3400",
        reserved_rows: [
          {
            reservationId: "reservation-a",
            lessonId: "lesson-a",
            scheduledAt: null,
            units: "1.",
          },
          {
            reservationId: "reservation-b",
            lessonId: "lesson-b",
            scheduledAt: null,
            units: 7,
          },
        ],
        future_units: "12.000",
      });

      expect(result).toMatchObject({
        oldFinalPriceMinor: "0012.3400",
        oldCurrencyCode: "rub",
        legacyLessonsUsed: "12.000",
        newPackage: {
          unitCount: "12.000",
          basePriceMinor: "001000.00",
          currencyCode: "rUb",
        },
        usedUnits: "0",
        actualPaidMinor: "000500.00",
        reservedUnits: "12.34",
        reservedRows: [{ units: "1" }, { units: "7" }],
        futureUnits: "12",
      });
    });
  });

  describe("reservations", () => {
    it("preserves order and duplicates while cloning rows and canonicalizing dates", async () => {
      const reservedRows = [
        {
          reservationId: "reservation-null",
          lessonId: "lesson-null",
          scheduledAt: null,
          units: 2,
        },
        {
          reservationId: "reservation-duplicate",
          lessonId: "lesson-duplicate",
          scheduledAt: "2026-08-28T10:15:30+03:00",
          units: "12.3400",
        },
        {
          reservationId: "reservation-duplicate",
          lessonId: "lesson-duplicate",
          scheduledAt: "2026-08-28T10:15:30+03:00",
          units: "12.3400",
        },
        {
          reservationId: "reservation-iso",
          lessonId: "lesson-iso",
          scheduledAt: "2026-08-28T07:15:30.000Z",
          units: "-0.00",
        },
      ];
      const { repository } = createRepository([
        replacementRow({ reserved_rows: reservedRows }),
      ]);

      const result = await repository.readReplacementContext(
        issuedSubscriptionId,
        newPackageId,
      );

      expect(result!.reservedRows).toEqual([
        {
          reservationId: "reservation-null",
          lessonId: "lesson-null",
          scheduledAt: null,
          units: "2",
        },
        {
          reservationId: "reservation-duplicate",
          lessonId: "lesson-duplicate",
          scheduledAt: "2026-08-28T07:15:30.000Z",
          units: "12.34",
        },
        {
          reservationId: "reservation-duplicate",
          lessonId: "lesson-duplicate",
          scheduledAt: "2026-08-28T07:15:30.000Z",
          units: "12.34",
        },
        {
          reservationId: "reservation-iso",
          lessonId: "lesson-iso",
          scheduledAt: "2026-08-28T07:15:30.000Z",
          units: "0",
        },
      ]);
      expect(result!.reservedRows).not.toBe(reservedRows);
      result!.reservedRows.forEach((reservation, index) => {
        expect(reservation).not.toBe(reservedRows[index]);
      });
    });

    it.each(["not-a-date", "", undefined])(
      "rejects invalid reservation date %p with RangeError",
      async (scheduledAt) => {
        const { repository } = createRepository([
          replacementRow({
            reserved_rows: [
              {
                reservationId: "reservation-invalid",
                lessonId: "lesson-invalid",
                scheduledAt,
                units: "1",
              },
            ],
          }),
        ]);

        await expect(
          repository.readReplacementContext(
            issuedSubscriptionId,
            newPackageId,
          ),
        ).rejects.toBeInstanceOf(RangeError);
      },
    );
  });
});
