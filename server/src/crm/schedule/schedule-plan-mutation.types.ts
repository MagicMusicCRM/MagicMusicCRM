export interface SchedulePlanMutationResult {
  id: string;
  seriesIds: string[];
  lessonIds: string[];
  version: number;
  replayed: boolean;
}

export interface SchedulePlanMutationReference extends Record<string, unknown> {
  planId: string;
  seriesIds: string[];
  lessonIds: string[];
}
