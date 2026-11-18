// Respaldo/restauracion de TODA la base de datos (admin/superadmin). El respaldo es un
// JSON autocontenido con todas las tablas y sus filas; la restauracion reemplaza los
// datos actuales por los del respaldo dentro de una transaccion (todo o nada).
// No depende de pg_dump ni de ningun binario externo: usa el propio pool.
import { Router } from '../../core/router.js';
import { query, transaction } from '../../config/db.js';
import { sendJson } from '../../core/http.js';
import { badRequest, forbidden } from '../../core/httpError.js';

const ROLES_OK = ['ADMINISTRADOR', 'SUPERADMINISTRADOR'];
const NOMBRE_IDENT = /^[A-Za-z0-9_]+$/; // tablas/columnas: solo alfanumerico + guion bajo
const VERSION = 1;
const LOTE = 200; // filas por INSERT

function assertRol(ctx) {
  if (!ROLES_OK.includes(ctx.user?.rol)) {
    throw forbidden('Solo un administrador puede respaldar o restaurar la base de datos.');
  }
}

// Tablas del esquema de este negocio.
async function listarTablas() {
  const rows = await query(
    `SELECT table_name AS t FROM information_schema.tables
      WHERE table_schema = current_schema() AND table_type = 'BASE TABLE' ORDER BY table_name`
  );
  return rows.map((r) => r.t).filter((t) => NOMBRE_IDENT.test(t));
}

export const respaldoService = {
  /** Exporta todas las tablas a un objeto JSON. */
  async exportar() {
    const tablas = await listarTablas();
    const dump = {};
    for (const t of tablas) dump[t] = await query(`SELECT * FROM \`${t}\``);
    return { app: 'stockify', version: VERSION, fecha: new Date().toISOString(), tablas: dump };
  },

  /** Reemplaza TODOS los datos por los del respaldo (transaccional). */
  async importar(data) {
    if (!data || typeof data !== 'object' || !data.tablas || typeof data.tablas !== 'object') {
      throw badRequest('El archivo de respaldo no es válido.');
    }
    const existentes = new Set(await listarTablas());
    // Solo tablas conocidas de la base actual (evita inyeccion por nombre y tablas ajenas).
    const entradas = Object.entries(data.tablas).filter(([t]) => NOMBRE_IDENT.test(t) && existentes.has(t));
    if (!entradas.length) throw badRequest('El respaldo no contiene tablas reconocidas de esta base.');

    let filas = 0;
    await transaction(async (conn) => {
      // Las claves foraneas son DEFERRABLE: se validan al final de la transaccion, asi
      // el orden en que se cargan las tablas no importa.
      await conn.raw('SET CONSTRAINTS ALL DEFERRED');
      {
        await conn.raw(`TRUNCATE ${entradas.map(([t]) => `"${t}"`).join(', ')} CASCADE`);
        for (const [tabla, rows] of entradas) {
          if (!Array.isArray(rows) || !rows.length) continue;
          const cols = Object.keys(rows[0]);
          if (!cols.length || !cols.every((c) => NOMBRE_IDENT.test(c))) {
            throw badRequest(`El respaldo tiene columnas inválidas en la tabla ${tabla}.`);
          }
          const colList = cols.map((c) => `\`${c}\``).join(',');
          const tupla = `(${cols.map(() => '?').join(',')})`;
          for (let i = 0; i < rows.length; i += LOTE) {
            const chunk = rows.slice(i, i + LOTE);
            const sql = `INSERT INTO \`${tabla}\` (${colList}) VALUES ${chunk.map(() => tupla).join(',')}`;
            const params = [];
            for (const f of chunk) for (const c of cols) params.push(f[c] === undefined ? null : f[c]);
            await conn.query(sql, params);
            filas += chunk.length;
          }
        }
        // Los ids vienen del respaldo: se adelantan las secuencias para que los nuevos no choquen.
        for (const [tabla] of entradas) {
          const { rows: conSecuencia } = await conn.raw(
            `SELECT 1 FROM information_schema.columns
              WHERE table_schema = current_schema() AND table_name = $1
                AND column_name = 'id' AND column_default LIKE 'nextval%'`,
            [tabla]
          );
          if (!conSecuencia.length) continue;
          await conn.raw(
            `SELECT setval(pg_get_serial_sequence($1, 'id')::regclass,
                           GREATEST((SELECT COALESCE(MAX(id), 0) FROM "${tabla}"), 1),
                           (SELECT COUNT(*) > 0 FROM "${tabla}"))`,
            [`"${tabla}"`]
          );
        }
      }
    });
    return { ok: true, tablas: entradas.length, filas };
  },
};

export const respaldoRoutes = new Router();

respaldoRoutes.get('/', async (ctx, res) => {
  assertRol(ctx);
  sendJson(res, 200, await respaldoService.exportar());
});

respaldoRoutes.post('/restaurar', async (ctx, res) => {
  assertRol(ctx);
  sendJson(res, 200, await respaldoService.importar(ctx.body));
});
