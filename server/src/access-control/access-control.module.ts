import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { RolesGuard } from "../common/security/roles.guard";
import { DatabaseModule } from "../db/database.module";
import { PlatformModule } from "../platform/platform.module";
import { AccessMutationsController } from "./access-mutations.controller";
import { AccessMutationsRepository } from "./access-mutations.repository";
import { AccessMutationsService } from "./access-mutations.service";
import { ActorClientProjectionFactory } from "./actor-client-projection.factory";
import { CapabilityRegistryRepository } from "./capability-registry.repository";
import { EffectiveAccessEvaluator } from "./effective-access-evaluator";
import { HardInvariantPolicy } from "./hard-invariant.policy";

@Module({
  imports: [DatabaseModule, JwtModule.register({}), PlatformModule],
  controllers: [AccessMutationsController],
  providers: [
    AccessMutationsRepository,
    AccessMutationsService,
    ActorClientProjectionFactory,
    CapabilityRegistryRepository,
    EffectiveAccessEvaluator,
    HardInvariantPolicy,
    JwtAuthGuard,
    RolesGuard,
  ],
  exports: [
    AccessMutationsRepository,
    AccessMutationsService,
    ActorClientProjectionFactory,
    CapabilityRegistryRepository,
    EffectiveAccessEvaluator,
    HardInvariantPolicy,
  ],
})
export class AccessControlModule {}
