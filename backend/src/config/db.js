// Pool de conexiones PostgreSQL (driver "pg").
//
// El codigo de la app escribe SQL con el estilo que ya tenia (placeholders "?", alias camelCase,
// identificadores entre `backticks`, CURDATE(), MONTH(), ...). La funcion `traducir` lo pasa a
// PostgreSQL y `query`/`transaction` devuelven los resultados con la misma forma de siempre:
//   - SELECT            -> array de filas
//   - INSERT/UPDATE/... -> { insertId, affectedRows, rows }
//   - conn.execute/query dentro de una transaccion -> [resultado]
// Las columnas "booleanas" son SMALLINT (0/1), los DECIMAL/BIGINT llegan como numero y las
// fechas como texto 'YYYY-MM-DD' / 'YYYY-MM-DD HH:MM:SS'.
import pg from 'pg';
import { config } from './env.js';

const { types } = pg;
types.setTypeParser(20, (v) => (v === null ? null : Number(v)));      // BIGINT / COUNT(*)
types.setTypeParser(1700, (v) => (v === null ? null : Number(v)));    // NUMERIC / DECIMAL
types.setTypeParser(1082, (v) => v);                                  // DATE -> 'YYYY-MM-DD'
types.setTypeParser(1114, (v) => (v === null ? null : v.slice(0, 19))); // TIMESTAMP -> 'YYYY-MM-DD HH:MM:SS'
types.setTypeParser(1184, (v) => (v === null ? null : v.slice(0, 19))); // TIMESTAMPTZ

const SCHEMA = config.db.schema;
if (!/^[a-z_][a-z0-9_]*$/.test(SCHEMA)) throw new Error(`DB_SCHEMA invalido: "${SCHEMA}"`);

const base = config.db.url
  ? { connectionString: config.db.url }
  : { host: config.db.host, port: config.db.port, user: config.db.user, password: config.db.password, database: config.db.database };

export const pool = new pg.Pool({
  ...base,
  ssl: config.db.ssl ? { rejectUnauthorized: false } : undefined,
  max: 10,
  // Cada conexion trabaja en el esquema del negocio.
  options: `-c search_path=${SCHEMA}`,
});

// Tablas sin columna "id" (para no pedir RETURNING id al insertar).
const SIN_ID = new Set(['producto_proveedor', 'reporte_conteo']);

/** Recorre el SQL fuera de los literales '...' aplicando `fn` a cada tramo de codigo. */
function fueraDeLiterales(sql, fn) {
  let out = '';
  let i = 0;
  while (i < sql.length) {
    const q = sql.indexOf("'", i);
    if (q === -1) { out += fn(sql.slice(i)); break; }
    out += fn(sql.slice(i, q));
    let j = q + 1;
    while (j < sql.length) {
      if (sql[j] === "'" && sql[j + 1] === "'") { j += 2; continue; }
      if (sql[j] === "'") break;
      j++;
    }
    out += sql.slice(q, j + 1);
    i = j + 1;
  }
  return out;
}

/** Pasa el SQL escrito al estilo MySQL a PostgreSQL. */
export function traducir(sqlOriginal) {
  let n = 0;
  let sql = fueraDeLiterales(sqlOriginal, (t) => t
    .replace(/`([^`]+)`/g, '"$1"')
    .replace(/\bCURDATE\(\)/gi, 'CURRENT_DATE')
    .replace(/\bDATEDIFF\(\s*([^,()]+?)\s*,\s*([^()]+?)\s*\)/gi, '(($1)::date - ($2)::date)')
    .replace(/\bDATE_ADD\(\s*([^,()]+?|CURRENT_DATE)\s*,\s*INTERVAL\s+(\S+)\s+DAY\s*\)/gi, '(($1)::date + ($2)::int)')
    .replace(/\bDATE_SUB\(\s*([^,()]+?|CURRENT_DATE)\s*,\s*INTERVAL\s+(\S+)\s+DAY\s*\)/gi, '(($1)::date - ($2)::int)')
    .replace(/\b(MONTH|YEAR|DAY)\(\s*([^()]+?)\s*\)/gi, (_m, f, x) => `EXTRACT(${f.toUpperCase()} FROM ${x})::int`)
    // Los alias camelCase (productoId, cantidadVendida...) se citan para que no pasen a minusculas.
    .replace(/(^|[^"\w.$])([a-z][a-z0-9]*[A-Z][A-Za-z0-9]*)\b(?!")/g, '$1"$2"')
    .replace(/\?/g, () => `$${++n}`));

  const insert = /^\s*INSERT\s+(IGNORE\s+)?INTO\s+"?(\w+)"?/i.exec(sql);
  if (insert) {
    if (insert[1]) sql = sql.replace(/INSERT\s+IGNORE\s+INTO/i, 'INSERT INTO') + ' ON CONFLICT DO NOTHING';
    if (!/\bRETURNING\b/i.test(sql)) sql += SIN_ID.has(insert[2]) ? '' : ' RETURNING id';
  }
  return sql;
}

// Los booleanos de JS van como 0/1 (las columnas son SMALLINT); undefined -> NULL.
const valores = (params) => (Array.isArray(params) ? params : params == null ? [] : [params])
  .map((v) => (v === undefined ? null : typeof v === 'boolean' ? (v ? 1 : 0) : v));

function adaptarError(err) {
  if (err && err.code === '23505') {
    err.code = 'ER_DUP_ENTRY';
    err.sqlMessage = err.detail || err.message;
  }
  return err;
}

function resultado(r) {
  if (r.command === 'SELECT' || (r.command !== 'INSERT' && r.command !== 'UPDATE' && r.command !== 'DELETE')) return r.rows;
  return { insertId: r.rows?.[0]?.id ?? null, affectedRows: r.rowCount, rows: r.rows };
}

async function ejecutar(cliente, sql, params) {
  try {
    return resultado(await cliente.query(traducir(sql), valores(params)));
  } catch (err) {
    throw adaptarError(err);
  }
}

/**
 * Ejecuta una consulta y devuelve las filas (o el resultado del INSERT/UPDATE/DELETE).
 * @param {string} sql
 * @param {array} [params]
 */
export function query(sql, params) {
  return ejecutar(pool, sql, params);
}

/**
 * Ejecuta una operacion dentro de una transaccion.
 * El callback recibe una conexion con execute()/query() que devuelven [resultado],
 * igual que antes. Si lanza, se hace rollback.
 */
export async function transaction(fn) {
  const cliente = await pool.connect();
  const conn = {
    execute: async (sql, params) => [await ejecutar(cliente, sql, params)],
    query: async (sql, params) => [await ejecutar(cliente, sql, params)],
    /** SQL nativo de PostgreSQL, sin traducir. */
    raw: (sql, params) => cliente.query(sql, params),
  };
  try {
    await cliente.query('BEGIN');
    const result = await fn(conn);
    await cliente.query('COMMIT');
    return result;
  } catch (err) {
    await cliente.query('ROLLBACK').catch(() => {});
    throw adaptarError(err);
  } finally {
    cliente.release();
  }
}

export async function testConnection() {
  const r = await pool.query('SELECT current_schema() AS esquema');
  if (r.rows[0].esquema !== SCHEMA) {
    throw new Error(`El esquema "${SCHEMA}" no existe en la base. Crealo con: npm run db:init`);
  }
}
