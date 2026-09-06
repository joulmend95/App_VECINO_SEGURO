import { Request, Response, NextFunction } from 'express';

/**
 * Validación de entrada sin dependencias externas.
 *
 * Antes los controladores solo comprobaban que los campos "existieran". Se
 * aceptaba un teléfono de una letra o una contraseña de un carácter, y el error
 * aparecía más tarde como un fallo de base de datos o, peor, no aparecía.
 */

export interface ReglaCampo {
    campo: string;
    etiqueta: string;
    tipo?: 'texto' | 'telefono' | 'password' | 'codigo';
    obligatorio?: boolean;
    min?: number;
    max?: number;
}

export interface ErrorCampo {
    campo: string;
    mensaje: string;
}

/** Teléfono ecuatoriano/internacional: 7 a 15 dígitos, con + opcional. */
const RE_TELEFONO = /^\+?[0-9]{7,15}$/;

/** Código de comunidad: letras, números y guiones. */
const RE_CODIGO = /^[A-Za-z0-9-]{4,20}$/;

export function validar(reglas: ReglaCampo[]) {
    return (req: Request, res: Response, next: NextFunction): void => {
        const errores: ErrorCampo[] = [];

        for (const regla of reglas) {
            const bruto = req.body?.[regla.campo];
            const obligatorio = regla.obligatorio !== false;

            if (bruto === undefined || bruto === null || String(bruto).trim() === '') {
                if (obligatorio) {
                    errores.push({ campo: regla.campo, mensaje: `${regla.etiqueta} es obligatorio.` });
                }
                continue;
            }

            const valor = String(bruto).trim();

            switch (regla.tipo) {
                case 'telefono':
                    if (!RE_TELEFONO.test(valor)) {
                        errores.push({
                            campo: regla.campo,
                            mensaje: `${regla.etiqueta} debe tener entre 7 y 15 dígitos.`,
                        });
                    }
                    break;

                case 'password':
                    // No se aplica `trim` a la contraseña: los espacios son
                    // caracteres válidos y recortarlos cambiaría la credencial.
                    if (String(bruto).length < (regla.min ?? 8)) {
                        errores.push({
                            campo: regla.campo,
                            mensaje: `${regla.etiqueta} debe tener al menos ${regla.min ?? 8} caracteres.`,
                        });
                    }
                    break;

                case 'codigo':
                    if (!RE_CODIGO.test(valor)) {
                        errores.push({
                            campo: regla.campo,
                            mensaje: `${regla.etiqueta} debe tener entre 4 y 20 caracteres (letras, números o guiones).`,
                        });
                    }
                    break;

                default:
                    if (regla.min && valor.length < regla.min) {
                        errores.push({
                            campo: regla.campo,
                            mensaje: `${regla.etiqueta} debe tener al menos ${regla.min} caracteres.`,
                        });
                    }
                    if (regla.max && valor.length > regla.max) {
                        errores.push({
                            campo: regla.campo,
                            mensaje: `${regla.etiqueta} no puede superar ${regla.max} caracteres.`,
                        });
                    }
            }
        }

        if (errores.length > 0) {
            // 422 y no 400: la petición está bien formada —JSON válido, ruta
            // correcta—, lo que falla es el CONTENIDO de los campos. Esa es
            // exactamente la semántica de "Unprocessable Content" (RFC 9110
            // §15.5.21), y permite al cliente distinguir sin ambigüedad un
            // error que debe pintar campo por campo de un 400 de negocio.
            //
            // Los 400 que devuelven los controladores se conservan: ahí el
            // dato es sintácticamente correcto pero la operación no procede
            // (un :id no numérico, una contraseña actual que no coincide).
            res.status(422).json({ mensaje: 'Revisa los datos ingresados.', errores });
            return;
        }

        next();
    };
}
