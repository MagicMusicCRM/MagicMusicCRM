describe("Campaign-12 internal contract modules", () => {
  it("keeps payroll contracts free of runtime exports", async () => {
    const contracts = await import("./payroll/payroll.types");

    expect(Object.keys(contracts)).toEqual([]);
  });

  it("keeps lesson transition contracts free of runtime exports", async () => {
    const contracts = await import("./schedule/lesson-transition.types");

    expect(Object.keys(contracts)).toEqual([]);
  });
});
