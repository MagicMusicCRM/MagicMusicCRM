import { HttpException } from "@nestjs/common";

export function isLessonFundingReview(code: string): boolean {
  return ["LESSON_ACCOUNT_INSUFFICIENT_BALANCE", "LESSON_ACCOUNT_PAYER_REQUIRED",
    "LESSON_SUBSCRIPTION_PAYMENT_REQUIRED", "SUBSCRIPTION_CAPACITY"].includes(code);
}

/** Store safe business identifiers, not HTTP exception class names or messages. */
export function lessonCompletionFailureCode(error: unknown): string {
  if (error instanceof HttpException) {
    const response = error.getResponse();
    if (typeof response === "object" && response !== null && "code" in response) {
      const code = response.code;
      if (typeof code === "string" && /^[A-Z][A-Z0-9_]{0,119}$/.test(code)) return code;
    }
  }
  return error instanceof Error && error.name
    ? error.name.slice(0, 120)
    : "LessonCompletionFailure";
}
