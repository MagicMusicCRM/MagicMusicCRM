import { IsIn } from "class-validator";
import { SECTION_KEYS } from "../section-views.service";

export class MarkSectionSeenDto {
  /**
   * Раздел, который человек открыл. Список — из одного места
   * (`SECTION_KEYS`), чтобы валидатор и счётчик не разъехались.
   */
  @IsIn(SECTION_KEYS as unknown as string[])
  section!: string;
}
