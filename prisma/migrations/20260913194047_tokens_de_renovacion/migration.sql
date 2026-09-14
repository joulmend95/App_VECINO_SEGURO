-- CreateTable
CREATE TABLE "TokenRenovacion" (
    "id_token" SERIAL NOT NULL,
    "hash" TEXT NOT NULL,
    "expira_en" TIMESTAMP(3) NOT NULL,
    "revocado" BOOLEAN NOT NULL DEFAULT false,
    "creado_en" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "id_usuario" INTEGER NOT NULL,

    CONSTRAINT "TokenRenovacion_pkey" PRIMARY KEY ("id_token")
);

-- CreateIndex
CREATE UNIQUE INDEX "TokenRenovacion_hash_key" ON "TokenRenovacion"("hash");

-- CreateIndex
CREATE INDEX "TokenRenovacion_id_usuario_revocado_idx" ON "TokenRenovacion"("id_usuario", "revocado");

-- AddForeignKey
ALTER TABLE "TokenRenovacion" ADD CONSTRAINT "TokenRenovacion_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "Usuario"("id_usuario") ON DELETE CASCADE ON UPDATE CASCADE;
