import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');
  app.enableCors();
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Swagger phản ánh DTO/schema thực tế qua @nestjs/swagger CLI plugin (đọc class-validator
  // decorators để suy ra ApiProperty) - không viết docs tay tách rời code (Phase 2 §8).
  const swaggerConfig = new DocumentBuilder()
    .setTitle('VIỆC NHA TRANG API')
    .setDescription('API tuyển dụng/tìm việc khu vực Nha Trang - xem docs/ARCHITECTURE.md để biết bối cảnh đầy đủ.')
    .setVersion('0.1.0')
    .addBearerAuth()
    .build();
  const swaggerDocument = SwaggerModule.createDocument(app, swaggerConfig);
  SwaggerModule.setup('api/docs', app, swaggerDocument);

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
  // eslint-disable-next-line no-console
  console.log(`VIỆC NHA TRANG API đang chạy tại http://localhost:${port}/api/v1`);
  // eslint-disable-next-line no-console
  console.log(`Swagger docs tại http://localhost:${port}/api/docs`);
}

bootstrap();
