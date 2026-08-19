-- CreateEnum
CREATE TYPE "JobProvenance" AS ENUM ('USER_CREATED', 'IMPORTED', 'SYNTHETIC');

-- CreateEnum
CREATE TYPE "SourceKind" AS ENUM ('WEBSITE', 'FACEBOOK', 'API', 'RSS', 'PARTNER', 'USER_CREATED', 'SYNTHETIC');

-- CreateEnum
CREATE TYPE "SourceStatus" AS ENUM ('ACTIVE', 'MANUAL', 'UNSUPPORTED', 'DISABLED', 'ERROR');

-- AlterTable
ALTER TABLE "jobs" ADD COLUMN     "duplicate_of_id" TEXT,
ADD COLUMN     "imported_at" TIMESTAMP(3),
ADD COLUMN     "source_id" TEXT,
ADD COLUMN     "source_job_id" TEXT,
ADD COLUMN     "source_name" TEXT,
ADD COLUMN     "source_published_at" TIMESTAMP(3),
ADD COLUMN     "source_type" "JobProvenance" NOT NULL DEFAULT 'USER_CREATED',
ADD COLUMN     "source_updated_at" TIMESTAMP(3),
ADD COLUMN     "source_url" TEXT;

-- CreateTable
CREATE TABLE "job_sources" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "type" "SourceKind" NOT NULL,
    "url" TEXT,
    "enabled" BOOLEAN NOT NULL DEFAULT true,
    "crawl_interval" INTEGER,
    "last_crawled_at" TIMESTAMP(3),
    "parser" TEXT,
    "status" "SourceStatus" NOT NULL DEFAULT 'MANUAL',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "job_sources_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "job_sources_name_key" ON "job_sources"("name");

-- CreateIndex
CREATE INDEX "jobs_source_type_idx" ON "jobs"("source_type");

-- CreateIndex
CREATE INDEX "jobs_duplicate_of_id_idx" ON "jobs"("duplicate_of_id");

-- CreateIndex
CREATE UNIQUE INDEX "jobs_source_name_source_job_id_key" ON "jobs"("source_name", "source_job_id");

-- AddForeignKey
ALTER TABLE "jobs" ADD CONSTRAINT "jobs_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "job_sources"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "jobs" ADD CONSTRAINT "jobs_duplicate_of_id_fkey" FOREIGN KEY ("duplicate_of_id") REFERENCES "jobs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

