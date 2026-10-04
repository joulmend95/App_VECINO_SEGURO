import NodeCache from 'node-cache';
import { ES_SERVERLESS } from './entorno';

/**
 * Caché en memoria que se desactiva sola en serverless.
 *
 * En un servidor único la invalidación explícita la mantiene coherente: quien
 * cambia el dato borra la entrada y la siguiente lectura va a la base de datos.
 * En serverless cada instancia tendría su propia copia y la invalidación solo
 * llegaría a una de ellas; las demás seguirían sirviendo el dato viejo hasta
 * que caducara. En la práctica: un vecino recién aprobado seguiría bloqueado, o
 * una alerta de emergencia no aparecería en el muro de sus vecinos.
 *
 * Por eso allí se consulta siempre la base de datos. Además, el temporizador
 * de limpieza de NodeCache no tiene sentido en una función que se congela
 * entre peticiones.
 */
export class CacheLocal {
    private readonly cache: NodeCache | null;

    constructor(opciones: NodeCache.Options) {
        this.cache = ES_SERVERLESS ? null : new NodeCache(opciones);
    }

    get<T>(clave: string): T | undefined {
        return this.cache?.get<T>(clave);
    }

    set<T>(clave: string, valor: T): void {
        this.cache?.set(clave, valor);
    }

    del(clave: string): void {
        this.cache?.del(clave);
    }
}
