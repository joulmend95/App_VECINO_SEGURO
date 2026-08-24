-- CreateTable
CREATE TABLE "Comunidad" (
    "id_comunidad" SERIAL NOT NULL,
    "codigo_unico" TEXT NOT NULL,
    "nombre_comunidad" TEXT NOT NULL,
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Comunidad_pkey" PRIMARY KEY ("id_comunidad")
);

-- CreateTable
CREATE TABLE "Usuario" (
    "id_usuario" SERIAL NOT NULL,
    "nombre" TEXT NOT NULL,
    "telefono" TEXT NOT NULL,
    "password" TEXT NOT NULL,
    "rol" TEXT NOT NULL DEFAULT 'Vecino',
    "id_comunidad" INTEGER NOT NULL,

    CONSTRAINT "Usuario_pkey" PRIMARY KEY ("id_usuario")
);

-- CreateTable
CREATE TABLE "Alerta" (
    "id_alerta" SERIAL NOT NULL,
    "tipo_alerta" TEXT NOT NULL,
    "fecha_hora" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "estado" TEXT NOT NULL DEFAULT 'Activa',
    "id_usuario" INTEGER NOT NULL,

    CONSTRAINT "Alerta_pkey" PRIMARY KEY ("id_alerta")
);

-- CreateTable
CREATE TABLE "Notificacion" (
    "id_notificacion" SERIAL NOT NULL,
    "estado_entrega" TEXT NOT NULL DEFAULT 'Enviada',
    "id_alerta" INTEGER NOT NULL,
    "id_usuario_receptor" INTEGER NOT NULL,

    CONSTRAINT "Notificacion_pkey" PRIMARY KEY ("id_notificacion")
);

-- CreateIndex
CREATE UNIQUE INDEX "Comunidad_codigo_unico_key" ON "Comunidad"("codigo_unico");

-- CreateIndex
CREATE UNIQUE INDEX "Usuario_telefono_key" ON "Usuario"("telefono");

-- AddForeignKey
ALTER TABLE "Usuario" ADD CONSTRAINT "Usuario_id_comunidad_fkey" FOREIGN KEY ("id_comunidad") REFERENCES "Comunidad"("id_comunidad") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Alerta" ADD CONSTRAINT "Alerta_id_usuario_fkey" FOREIGN KEY ("id_usuario") REFERENCES "Usuario"("id_usuario") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notificacion" ADD CONSTRAINT "Notificacion_id_alerta_fkey" FOREIGN KEY ("id_alerta") REFERENCES "Alerta"("id_alerta") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Notificacion" ADD CONSTRAINT "Notificacion_id_usuario_receptor_fkey" FOREIGN KEY ("id_usuario_receptor") REFERENCES "Usuario"("id_usuario") ON DELETE RESTRICT ON UPDATE CASCADE;

