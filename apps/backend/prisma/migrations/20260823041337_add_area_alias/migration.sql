-- CreateTable
CREATE TABLE "area_aliases" (
    "id" TEXT NOT NULL,
    "area_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "normalized_name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "area_aliases_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "area_aliases_normalized_name_idx" ON "area_aliases"("normalized_name");

-- CreateIndex
CREATE UNIQUE INDEX "area_aliases_area_id_normalized_name_key" ON "area_aliases"("area_id", "normalized_name");

-- AddForeignKey
ALTER TABLE "area_aliases" ADD CONSTRAINT "area_aliases_area_id_fkey" FOREIGN KEY ("area_id") REFERENCES "areas"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
