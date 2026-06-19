import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { CrmService } from "../crm/crm.service";
import { CrmPolicy } from "../crm/crm.policy";

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly crmService: CrmService,
    private readonly crmPolicy: CrmPolicy,
  ) {}
}
