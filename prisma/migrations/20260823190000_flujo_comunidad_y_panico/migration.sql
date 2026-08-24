-- CreateEnum
CREATE TYPE "RolUsuario" AS ENUM ('VECINO', 'ADMIN');

-- CreateEnum
CREATE TYPE "EstadoSolicitud" AS ENUM ('PENDIENTE', 'APROBADA', 'RECHAZADA');

-- CreateEnum
CREATE TYPE "EstadoAlerta" AS ENUM ('ACTIVA', 'RESUELTA', 'CANCELADA');

-- DropForeignKey
ALTER TABLE "Notificacion" DROP CONSTRAINT "Notificacion_id_alerta_fkey";

-- DropForeignKey
ALTER TABLE "Notificacion" DROP CONSTRAINT "Notificacion_id_usuario_receptor_fkey";

-- DropForeignKey
ALTER TABLE "Usuario" DROP CONSTRAINT "Usuario_id_comunidad_fkey";

-- AlterTable
ALTER TABLE "Alerta" ADD COLUMN     "descripcion" TEXT,
ADD COLUMN     "es_panico" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "latitud" DOUBLE PRECISION,
ADD COLUMN     "longitud" DOUBLE PRECISION;

-- Conversión de "Alerta.estado" de TEXT a enum PRESERVANDO LOS DATOS.
-- Prisma generaba DROP COLUMN + ADD COLUMN, que habría borrado el estado de
-- las 15 alertas existentes. El USING convierte fila por fila.
ALTER TABLE "Alerta" ALTER COLUMN "estado" DROP DEFAULT;
ALTER TABLE "Alerta" ALTER COLUMN "estado" TYPE "EstadoAlerta"
  USING (
    CASE upper(trim("estado"))
      WHEN 'RESUELTA'  THEN 'RESUELTA'
      WHEN 'CANCELADA' THEN 'CANCELADA'
      ELSE 'ACTIVA'
    END
  )::"EstadoAlerta";
ALTER TABLE "Alerta" ALTER COLUMN "estado" SET DEFAULT 'ACTIVA';

-- AlterTable
ALTER TABLE "Comunidad" ADD COLUMN     "id_admin" INTEGER;

-- AlterTable
ALTER TABLE "Notificacion" ADD COLUMN     "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "leida_en" TIMESTAMP(3);

-- AlterTable
-- `id_comunidad` pasa a ser NULL: es lo que permite existir como usuario
-- registrado antes de pertenecer a ninguna comunidad.
ALTER TABLE "Usuario" ALTER COLUMN "id_comunidad" DROP NOT NULL;

-- Conversión de "Usuario.rol" de TEXT a enum PRESERVANDO LOS DATOS.
-- Los valores existentes venían capitalizados ("Vecino"); se normalizan.
ALTER TABLE "Usuario" ALTER COLUMN "rol" DROP DEFAULT;
ALTER TABLE "Usuario" ALTER COLUMN "rol" TYPE "RolUsuario"
  USING (
    CASE upper(trim("rol"))
      WHEN 'ADMIN' THEN 'ADMIN'
      ELSE 'VECINO'
    END
  )::"RolUsuario";
ALTER TABLE "Usuario" ALTER COLUMN "rol" SET DEFAULT 'VECINO';

-- CreateTable
CREATE TABLE "SolicitudMembresia" (
    "id_solicitud" SERIAL NOT NULL,
    "estado" "EstadoSolicitud" NOT NULL DEFAULT 'PENDIENTE',
    "id_usuario" INTEGER NOT NULL,
    "id_comunidad" INTEGER NOT NULL,
    "fecha_solicitud" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_resuelta" TIMESTAMP(3),

    CONSTRAINT "SolicitudMembresia_pkey" PRIMARY KEY ("id_solicitud")
);

-- CreateTable
CREATE TABLE "Dispositivo" (
    "id_dispositivo" SERIAL NOT NULL,
    "token_push" TEXT NOT NULL,
    "plataforma" TEXT NOT NULL,
    "actualizado_en" TIMESTAMP(3) NOT NULL,
    "id_usuario" INTEGER NOT NULL,

    CONSTRAINT "Dispositivo_pkey" PRIMARY KEY ("id_dispositivo")
);

-- CreateIndex
CREATE INDEX "SolicitudMembresia_id_comunidad_estado_idx" ON "SolicitudMembresia"("id_comunidad", "estado");

-- CreateIndex
CREATE UNIQUE INDEX "SolicitudMembresia_id_usuario_id_comunidad_key" ON "SolicitudMembresia"("id_usuario", "id_comunidad");

-- CreateIndex
CREATE UNIQUE INDEX "Dispositivo_token_push_key" ON "Dispositivo"("token_push");

-- CreateIndex
CREATE INDEX "Dispositivo_id_usuario_idx" ON "Dispositivo"("id_usuario");

-- CreateIndex
CREATE INDEX "Alerta_id_usuario_fecha_hora_idx" ON "Alerta"("id_usuario", "fecha_hora");

-- CreateIndex
CREATE INDEX "Notificacion_id_usuario_receptor_leida_en_idx" ON "Notificacion"("id_usuario_receptor", "leida_en");

-- CreateIndex
CREATE INDEX "Usuario_id_comunidad_idx" ON "Usuario"("id_comunidad");

-- AddForeignKey
ALTER TABLE "Comunidad" ADD CONSTRAINT "Comunidad_id_admin_fkey" FOREIGN KEY ("id_admin") REFERENCES "Usuario"("id_usuario") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Usuario" ADD CONSTRAINT "Usuario_id_comunidad_fkey" FOREIGN KEY ("id_comunidad") REFERENCES "Comunidad"("id_comunidad") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMembresia" ADD CONSTRAINT "SolicitudMembresia_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "Usuario"("id_usuario") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SolicitudMembresia" ADD CONSTRAINT "SolicitudMembresia_id_comunidad_fkey" FOREIGN KEY ("id_comunidad") REFERENCES "Comunidad"("id_comunidad") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Dispositivo" ADD CONSTRAINT "Dispositivo_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "Usuario"("id_usuario") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notificacion" ADD CONSTRAINT "Notificacion_id_alerta_fkey" FOREIGN KEY ("id_alerta") REFERENCES "Alerta"("id_alerta") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notificacion" ADD CONSTRAINT "Notificacion_id_usuario_receptor_fkey" FOREIGN KEY ("id_usuario_receptor") REFERENCES "Usuario"("id_usuario") ON DELETE CASCADE ON UPDATE CASCADE;


-- ============================================================================
-- MIGRACION DE DATOS
-- ============================================================================
-- Las comunidades creadas antes de este cambio no tienen administrador. Sin
-- uno, nadie podria aprobar solicitudes de ingreso y quedarian bloqueadas.
-- Se designa como administrador al miembro mas antiguo de cada comunidad.
UPDATE "Comunidad" c
SET "id_admin" = (
  SELECT u."id_usuario"
  FROM "Usuario" u
  WHERE u."id_comunidad" = c."id_comunidad"
  ORDER BY u."id_usuario" ASC
  LIMIT 1
)
WHERE c."id_admin" IS NULL;

-- El designado pasa a tener rol ADMIN de forma coherente.
UPDATE "Usuario" u
SET "rol" = 'ADMIN'
WHERE EXISTS (
  SELECT 1 FROM "Comunidad" c WHERE c."id_admin" = u."id_usuario"
);
