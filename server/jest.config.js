module.exports = {
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: ".",
  roots: ["<rootDir>/src"],
  testRegex: ".*\\.spec\\.ts$",
  transform: {
    "^.+\\.(t|j)s$": ["ts-jest", { tsconfig: "tsconfig.json" }]
  },
  collectCoverageFrom: ["src/**/*.(t|j)s", "!src/**/*.spec.ts", "!src/**/*.fixture.ts"],
  testEnvironment: "node"
};
