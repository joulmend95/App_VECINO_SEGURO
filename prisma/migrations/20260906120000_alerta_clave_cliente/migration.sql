-- Clave de cliente para hacer seguro el reintento sin conexion.
--
-- El telefono genera un UUID ANTES de enviar la alerta y lo conserva en su cola
-- local. Si la peticion llega al servidor pero la respuesta se pierde por el
-- camino, el reintento trae la misma clave y el servidor devuelve la alerta ya
-- creada en lugar de crear otra. Sin esto, una mala conexion convierte una sola
-- emergencia en tres avisos a toda la comunidad.
--
-- Nullable: las alertas anteriores a esta migracion no la tienen, y un cliente
-- que no la envie sigue funcionando igual que antes.
ALTER TABLE "Alerta" ADD COLUMN "clave_cliente" TEXT;

-- El indice unico es lo que hace cumplir la idempotencia en la base de datos y
-- no solo en el codigo: aunque dos reintentos llegaran a la vez, uno de los dos
-- INSERT falla y no se puede crear la alerta duplicada.
--
-- En PostgreSQL un indice UNIQUE admite multiples NULL, asi que las alertas sin
-- clave (las viejas, o las de un cliente que no la envie) no chocan entre si.
CREATE UNIQUE INDEX "Alerta_clave_cliente_key" ON "Alerta"("clave_cliente");
