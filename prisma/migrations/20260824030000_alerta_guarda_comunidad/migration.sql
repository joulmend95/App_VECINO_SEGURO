-- Alerta guarda su propia comunidad.
--
-- Antes se deducia de `usuario.id_comunidad`. Eso hacia que las alertas de un
-- vecino desaparecieran del muro en cuanto saliera de la comunidad o fuera
-- expulsado, borrando historial que pertenece a la comunidad, no a la persona.
ALTER TABLE "Alerta" ADD COLUMN "id_comunidad" INTEGER;

-- Relleno de las alertas existentes con la comunidad actual de su autor.
UPDATE "Alerta" a
SET "id_comunidad" = u."id_comunidad"
FROM "Usuario" u
WHERE u."id_usuario" = a."id_usuario"
  AND a."id_comunidad" IS NULL;

CREATE INDEX "Alerta_id_comunidad_fecha_hora_idx" ON "Alerta"("id_comunidad", "fecha_hora");
