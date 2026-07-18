import { ArrayNotEmpty, IsArray, Matches } from "class-validator";

/**
 * PATCH /crm/lead-statuses/order. Previously an inline TS type — a non-class
 * metatype the global ValidationPipe skips entirely, so arbitrary JSON reached
 * the service layer (a non-array statusIds surfaced as an unlogged 500).
 */
export class ReorderLeadStatusesDto {
  @IsArray()
  @ArrayNotEmpty()
  @Matches(
    /^(?:unassigned|[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$/i,
    { each: true },
  )
  statusIds!: string[];
}
