import { ApiProperty } from '@nestjs/swagger';

/** Wire response; business state remains owned by ExpenseService. */
export class ExpenseResponseDto {
  @ApiProperty({ type: String, format: 'uuid' })
  id!: string;

  @ApiProperty({ type: 'integer', minimum: 1 })
  version!: number;

  @ApiProperty({ type: String, format: 'date-time' })
  occurredAt!: string | Date;

  @ApiProperty({ type: Number, minimum: 0.01, description: 'Amount in rubles, at most two decimal places.' })
  amount!: number;

  @ApiProperty({ type: String, maxLength: 64 })
  category!: string;

  @ApiProperty({ type: String, nullable: true })
  description!: string | null;

  @ApiProperty({ type: String, format: 'uuid', nullable: true })
  branchId!: string | null;

  @ApiProperty({ type: String, nullable: true })
  branchName!: string | null;

  @ApiProperty({ type: String, format: 'date-time' })
  createdAt!: string | Date;
}

export class ExpensePageDto {
  @ApiProperty({ type: [ExpenseResponseDto] })
  items!: ExpenseResponseDto[];

  @ApiProperty({ type: String, nullable: true, description: 'Opaque cursor; null marks the last page.' })
  nextCursor!: string | null;

  @ApiProperty({ type: Number, description: 'Total for all matching expenses, independent of the cursor.' })
  total!: number;
}

export class ExpenseDeleteResponseDto {
  @ApiProperty({ type: Boolean, enum: [true] })
  success!: boolean;
}

