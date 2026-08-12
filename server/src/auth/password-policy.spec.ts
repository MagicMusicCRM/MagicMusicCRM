import "reflect-metadata";
import { ClassConstructor, plainToInstance } from "class-transformer";
import { validate } from "class-validator";
import { CreateStaffDto } from "../crm/dto/create-staff.dto";
import { CreateTeacherDto } from "../crm/dto/create-teacher.dto";
import { ProvisionPersonAccessDto } from "../crm/dto/provision-person-access.dto";
import { ChangeEmailDto } from "./dto/change-email.dto";
import { ResetPasswordDto } from "./dto/reset-password.dto";
import { SetPasswordDto } from "./dto/set-password.dto";
import { SignupDto } from "./dto/signup.dto";
import { MIN_PASSWORD_LENGTH } from "./password-policy";

describe("password policy", () => {
  const cases: Array<
    [ClassConstructor<object>, Record<string, unknown>, string]
  > = [
    [
      SignupDto,
      { email: "owner@example.test", fullName: "School Owner" },
      "password",
    ],
    [ChangeEmailDto, { email: "owner@example.test" }, "currentPassword"],
    [ResetPasswordDto, { token: "123456" }, "password"],
    [SetPasswordDto, {}, "password"],
    [
      CreateStaffDto,
      {
        firstName: "Наталия",
        lastName: "Назарова",
        branchIds: ["20000000-0000-4000-8000-000000000001"],
      },
      "password",
    ],
    [
      CreateTeacherDto,
      {
        firstName: "Мария",
        branchIds: ["20000000-0000-4000-8000-000000000001"],
      },
      "password",
    ],
    [ProvisionPersonAccessDto, {}, "password"],
  ];

  it("uses one eight-character minimum across every password DTO", async () => {
    expect(MIN_PASSWORD_LENGTH).toBe(8);

    for (const [Dto, seed, property] of cases) {
      const accepted = plainToInstance(Dto, {
        ...seed,
        [property]: "12345678",
      });
      const rejected = plainToInstance(Dto, {
        ...seed,
        [property]: "1234567",
      });
      const passwordErrors = (value: object) =>
        validate(value).then((errors) =>
          errors.filter((error) => error.property === property),
        );

      await expect(passwordErrors(accepted)).resolves.toHaveLength(0);
      await expect(passwordErrors(rejected)).resolves.toHaveLength(1);
    }
  });
});
