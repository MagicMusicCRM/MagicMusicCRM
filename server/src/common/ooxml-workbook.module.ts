import { Module } from "@nestjs/common";
import { OoxmlWorkbookBuilder } from "./ooxml-workbook.builder";

@Module({
  providers: [OoxmlWorkbookBuilder],
  exports: [OoxmlWorkbookBuilder],
})
export class OoxmlWorkbookModule {}
