-- CreateEnum
CREATE TYPE "CommunityPostType" AS ENUM ('HIRING', 'JOB_SEEKER');

-- CreateEnum
CREATE TYPE "CommunityPostStatus" AS ENUM ('PENDING_REVIEW', 'APPROVED', 'REJECTED', 'EXPIRED');

-- CreateTable
CREATE TABLE "community_posts" (
    "id" TEXT NOT NULL,
    "source" "SourceKind" NOT NULL DEFAULT 'FACEBOOK',
    "source_name" TEXT NOT NULL,
    "source_post_id" TEXT,
    "source_url" TEXT NOT NULL,
    "source_group_name" TEXT,
    "source_group_url" TEXT,
    "post_type" "CommunityPostType" NOT NULL,
    "title" TEXT,
    "body" TEXT,
    "industry" TEXT,
    "employer_name" TEXT,
    "work_location" TEXT,
    "salary_min" INTEGER,
    "salary_max" INTEGER,
    "salary_currency" TEXT,
    "salary_period" TEXT,
    "salary_text_original" TEXT,
    "employment_type" TEXT,
    "work_schedule" TEXT,
    "experience_required" TEXT,
    "benefits" TEXT,
    "contact_method" TEXT,
    "contact_public" BOOLEAN NOT NULL DEFAULT false,
    "contacts_raw" JSONB,
    "data_quality" TEXT,
    "duplicate_of_id" TEXT,
    "posted_at" TIMESTAMP(3),
    "collected_at" TIMESTAMP(3),
    "status" "CommunityPostStatus" NOT NULL DEFAULT 'PENDING_REVIEW',
    "moderated_at" TIMESTAMP(3),
    "moderated_by" TEXT,
    "moderation_note" TEXT,
    "expires_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "community_posts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "community_posts_source_url_key" ON "community_posts"("source_url");

-- CreateIndex
CREATE INDEX "community_posts_post_type_status_posted_at_idx" ON "community_posts"("post_type", "status", "posted_at");

-- CreateIndex
CREATE INDEX "community_posts_status_idx" ON "community_posts"("status");

-- CreateIndex
CREATE INDEX "community_posts_work_location_idx" ON "community_posts"("work_location");
