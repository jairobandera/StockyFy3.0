// Prepara la base de un negocio al arrancar (lo usa el despliegue en el servidor).
// Si el esquema ya tiene tablas no hace nada. Si esta vacio:
//   - SEED_DEMO=1: carga los datos de ejemplo (scripts/init-db.js) y, si vienen,
//                  pone BOOT_SUPERADMIN_PASSWORD al superadmin y BOOT_EMPRESA como nombre.
//   - si no:       crea las tablas y solo la empresa (BOOT_EMPRESA), la "Casa central",
//                  el superadmin (BOOT_SUPERADMIN_PASSWORD) y el admin (BOOT_ADMIN_USER / BOOT_ADMIN_PASSWORD).
// Uso: node scripts/bootstrap.js && node server.js
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { config } from '../src/config/env.js';
import { pool, transaction } from '../src/config/db.js';
import { hashPassword } from '../src/core/password.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const e = process.env;
const esquema = config.db.schema;

async function esperarBase() {
  for (let i = 0; i < 30; i++) {
    try { await pool.query('SELECT 1'); return; } catch (err) {
      console.log('[bootstrap] esperando la base...', err.code || err.message);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  throw new Error('no se pudo conectar a la base');
}

async function main() {
  await esperarBase();
  await pool.query(`CREATE SCHEMA IF NOT EXISTS "${esquema}"`);
  const { rows } = await pool.query(
    "SELECT COUNT(*)::int AS n FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'usuario'",
    [esquema]
  );
  if (rows[0].n > 0) {
    console.log(`[bootstrap] el esquema "${esquema}" ya esta preparado`);
    return;
  }

  if (e.SEED_DEMO === '1') {
    console.log('[bootstrap] preparando la base con datos de demo');
    execFileSync(process.execPath, [path.join(__dirname, 'init-db.js')], { stdio: 'inherit' });
    if (e.BOOT_SUPERADMIN_PASSWORD) {
      await pool.query("UPDATE usuario SET contrasenia = $1 WHERE rol = 'SUPERADMINISTRADOR'", [await hashPassword(e.BOOT_SUPERADMIN_PASSWORD)]);
    }
    if (e.BOOT_EMPRESA) await pool.query('UPDATE empresa SET nombre = $1 WHERE id = (SELECT MIN(id) FROM empresa)', [e.BOOT_EMPRESA]);
    return;
  }

  if (!e.BOOT_ADMIN_USER || !e.BOOT_ADMIN_PASSWORD || !e.BOOT_SUPERADMIN_PASSWORD) {
    throw new Error('Faltan BOOT_ADMIN_USER, BOOT_ADMIN_PASSWORD o BOOT_SUPERADMIN_PASSWORD');
  }
  console.log('[bootstrap] creando las tablas del negocio');
  await pool.query(fs.readFileSync(path.join(__dirname, '..', 'sql', 'schema.sql'), 'utf8'));
  await transaction(async (conn) => {
    const [emp] = await conn.query('INSERT INTO empresa (nombre, suscripcion_ilimitada) VALUES (?, 1)', [e.BOOT_EMPRESA || 'Mi empresa']);
    const [suc] = await conn.query(
      'INSERT INTO sucursal (nombre, empresa_id, usa_stock, usa_facturacion) VALUES (?, ?, 1, 1)',
      ['Casa central', emp.insertId]
    );
    await conn.query(
      'INSERT INTO usuario (nombre, apellido, nombre_usuario, contrasenia, rol, sucursal_id) VALUES (?,?,?,?,?,?), (?,?,?,?,?,?)',
      ['Soporte', 'Kairos', 'superadmin', await hashPassword(e.BOOT_SUPERADMIN_PASSWORD), 'SUPERADMINISTRADOR', suc.insertId,
        'Administrador', '', e.BOOT_ADMIN_USER, await hashPassword(e.BOOT_ADMIN_PASSWORD), 'ADMINISTRADOR', suc.insertId]
    );
  });
  console.log('[bootstrap] negocio listo');
}

main()
  .then(() => pool.end())
  .catch(async (err) => {
    console.error('[bootstrap] error:', err.message);
    await pool.end().catch(() => {});
    process.exit(1);
  });
