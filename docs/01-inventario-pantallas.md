# Paso 1 — Inventario de Pantallas derivado de la API

> Método: cada endpoint expuesto por la API de *Vecino Seguro* representa una capacidad
> del sistema. Una pantalla existe solo si hay al menos un endpoint que la alimente
> (lectura) o que ella dispare (escritura). Los endpoints se agrupan por recurso y por
> el momento del recorrido del usuario en que se consumen.

---

## 1. Endpoints reales de la API

Fuente: `src/app.ts`, `src/routes/*.ts`, `src/controllers/*.ts`

| # | Método | Ruta | Auth | Entrada | Salida | Estados de error |
|---|--------|------|------|---------|--------|------------------|
| E1 | `GET`  | `/` | No | — | `{ mensaje }` | — |
| E2 | `POST` | `/api/comunidades` | No | `{ codigo, nombre }` | `201 { mensaje, comunidad }` | `400` campos faltantes · `500` interno |
| E3 | `POST` | `/api/usuarios/registro` | No | `{ nombre, telefono, password, codigoComunidad }` | `201 { mensaje, usuario }` | `400` campos faltantes / comunidad inexistente |
| E4 | `POST` | `/api/usuarios/token-prueba` | No | `{ id_usuario, id_comunidad }` | `200 { token, ... }` | `500` interno |
| E5 | `POST` | `/api/alertas/emitir` | **Sí** (Bearer JWT) | `{ tipo_alerta }` | `202 { mensaje, alerta }` | `400` sin tipo_alerta · `401` sin token · `403` token inválido/expirado |
| E6 | `GET`  | `/api/alertas/comunidad` | **Sí** (Bearer JWT) | `?id_comunidad` (opcional, se prefiere el del JWT) | `200 { fuente, data[] }` | `401` sin token · `403` token inválido/expirado · `400` interno |

### Forma del recurso `Alerta` (E6)

Derivada de `src/services/alerta.service.ts` + `prisma/schema.prisma`:

```json
{
  "fuente": "BASE_DE_DATOS_POSTGRESQL",
  "data": [
    {
      "id_alerta": 12,
      "tipo_alerta": "Sospechoso",
      "fecha_hora": "2026-08-23T18:04:11.000Z",
      "estado": "Activa",
      "id_usuario": 1,
      "usuario": { "id_usuario": 1, "nombre": "Jorge", "telefono": "1234567890" }
    }
  ]
}
```

Notas relevantes para la UI:
- La lista viene **paginada a 20** y ordenada por `fecha_hora` descendente.
- Solo devuelve alertas con `estado: "Activa"` → la UI no necesita filtro de estado.
- El campo `fuente` indica caché vs. base de datos; es un dato de diagnóstico, no de negocio.
- `data` puede venir como arreglo **vacío** → la pantalla debe resolver el estado *vacío*.

---

## 2. Inventario de pantallas

| ID | Pantalla | Endpoints que consume | Rol en el recorrido | Prioridad |
|----|----------|----------------------|---------------------|-----------|
| **P1** | Crear Comunidad | E2 | Alta inicial del administrador de la urbanización | Media |
| **P2** | Registro de Vecino | E3 | Alta del usuario final con `codigoComunidad` | Alta |
| **P3** | Ingreso / Sesión | E4 | Obtiene el JWT que habilita P4 y P5 | Alta |
| **P4** | **Muro de Alertas de la Comunidad** | E6 | Pantalla principal: lista de alertas activas | **Crítica** |
| **P5** | Emitir Alerta | E5 | Acción de pánico; al confirmar vuelve a P4 y refresca | **Crítica** |
| **P6** | Diagnóstico de Conexión | E1 | Pantalla técnica de soporte (ya existente) | Baja |

### Justificación del recorte

- **P1 y P2 no se fusionan**: responden a actores distintos (administrador vs. vecino) y a
  endpoints sin dependencia entre sí. Fusionarlas obligaría a mezclar dos contratos de datos.
- **P3 existe aunque el endpoint sea "token-prueba"**: es el único emisor de JWT, y sin JWT
  E5 y E6 responden `401`. La pantalla es obligatoria aunque el backend aún no valide password.
- **P5 no se fusiona con P4**: E5 devuelve `202 Accepted` (proceso asíncrono) mientras E6
  devuelve `200` con datos. Son dos ciclos de vida distintos; mezclarlos dentro de una sola
  pantalla haría ambiguo qué estado de carga se está mostrando.
- **P6 se conserva** porque E1 existe y sirve para verificar el `baseUrl` en el emulador.

---

## 3. Pantalla seleccionada para el ensamblaje del taller

**P4 — Muro de Alertas de la Comunidad** (`GET /api/alertas/comunidad`).

Se elige porque es la única pantalla del inventario que ejercita de forma natural los
**tres estados obligatorios** del requisito 6, todos derivados del mismo endpoint:

| Estado | Origen real en la API |
|--------|----------------------|
| **Cargando** | Latencia de la petición HTTP (caché ≈3 ms vs. PostgreSQL, notoriamente distinto) |
| **Vacío** | `200` con `data: []` — comunidad sin alertas activas |
| **Error** | `401` sin token · `403` token expirado · fallo de red con el emulador |

---

## 4. Trazabilidad endpoint → pantalla

```
E1  /                            ──▶ P6 Diagnóstico
E2  POST /api/comunidades        ──▶ P1 Crear Comunidad
E3  POST /api/usuarios/registro  ──▶ P2 Registro de Vecino
E4  POST /api/usuarios/token-... ──▶ P3 Ingreso
E5  POST /api/alertas/emitir     ──▶ P5 Emitir Alerta
E6  GET  /api/alertas/comunidad  ──▶ P4 Muro de Alertas  ◀── pantalla ensamblada
```

Cobertura: **6/6 endpoints mapeados**, sin pantallas huérfanas ni endpoints sin consumidor.
