import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Response } from 'express';
import { ActorContext } from '../common/security/actor-context';
import { CurrentActor } from '../common/security/current-actor.decorator';
import { JwtAuthGuard } from '../common/security/jwt-auth.guard';
import { UploadFileDto } from './dto/upload-file.dto';
import { UploadedMemoryFile } from './file-upload.types';
import { FilesService } from './files.service';

@Controller('files')
export class FilesController {
  constructor(private readonly files: FilesService) {}

  @Post()
  @UseGuards(JwtAuthGuard)
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 26 * 1024 * 1024 } }))
  upload(
    @CurrentActor() actor: ActorContext,
    @Body() dto: UploadFileDto,
    @UploadedFile() file: UploadedMemoryFile
  ) {
    return this.files.upload(actor, dto, file);
  }

  @Get('download/:token')
  @Header('Cache-Control', 'private, no-store')
  async download(
    @Param('token') token: string,
    @Res({ passthrough: true }) response: Response
  ): Promise<StreamableFile> {
    const download = await this.files.downloadByToken(token);
    response.setHeader('Content-Type', download.mimeType);
    response.setHeader('Content-Length', String(download.sizeBytes));
    response.setHeader(
      'Content-Disposition',
      `attachment; filename="${download.fileName.replace(/"/g, '_')}"`
    );
    return download.stream;
  }

  @Get(':id')
  @UseGuards(JwtAuthGuard)
  getMetadata(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.getMetadata(actor, id);
  }

  @Post(':id/download-token')
  @UseGuards(JwtAuthGuard)
  issueDownloadToken(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.issueDownloadToken(actor, id);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard)
  delete(@CurrentActor() actor: ActorContext, @Param('id', ParseUUIDPipe) id: string) {
    return this.files.delete(actor, id);
  }
}
