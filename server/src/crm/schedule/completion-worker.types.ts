export interface LessonCompletionClaim {
  lessonId: string;
  lessonVersion: number;
  scheduledEndAt: Date;
  attempts: number;
  claimedAt: Date;
  workerId: string;
}

export interface LessonCompletionResultRef {
  [key: string]: unknown;
  lessonId: string;
  state: "settlement_pending";
}

export interface LessonCompletionWorkerMetrics {
  due: number;
  claimed: number;
  retry: number;
  poison: number;
  completed: number;
  oldestDueSeconds: number | null;
  maxAttempts: number;
}

export interface LessonCompletionRunResult {
  claimed: number;
  completed: number;
  terminalObserved: number;
  retry: number;
  poison: number;
}
