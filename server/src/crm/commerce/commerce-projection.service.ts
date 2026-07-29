import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../../common/security/actor-context";
import { CommerceProjectionFactory } from "./commerce-projection.factory";
import { CommerceProjectionRepository } from "./commerce-projection.repository";
import {
  CommerceSelfResponse,
  CommerceStudentResponse,
} from "./commerce-projection.types";

@Injectable()
export class CommerceProjectionService {
  constructor(
    private readonly repository: CommerceProjectionRepository,
    private readonly factory: CommerceProjectionFactory,
  ) {}

  async readSelf(actor: ActorContext): Promise<CommerceSelfResponse> {
    this.assertNotTeacher(actor);
    const scopes = await this.repository.resolveSelfScopes(actor);
    const sources = await this.repository.loadProjection(actor, scopes);
    return {
      projection: this.factory.profileFor(actor),
      students: sources.map((source) =>
        this.factory.projectStudent(actor, source),
      ),
    };
  }

  async readStudent(
    actor: ActorContext,
    studentId: string,
  ): Promise<CommerceStudentResponse> {
    this.assertNotTeacher(actor);
    const scope = await this.repository.resolveStudentScope(actor, studentId);
    const [source] = await this.repository.loadProjection(actor, [scope]);
    if (!source) {
      throw new NotFoundException({
        code: "COMMERCE_CLIENT_NOT_FOUND",
        message: "Student commerce was not found.",
      });
    }
    return {
      projection: this.factory.profileFor(actor),
      student: this.factory.projectStudent(actor, source),
    };
  }

  private assertNotTeacher(actor: ActorContext): void {
    if (actor.role === "teacher") {
      throw new ForbiddenException({
        code: "COMMERCE_PROJECTION_TEACHER_DENIED",
        message: "Teacher commerce projections are not available.",
      });
    }
  }
}
