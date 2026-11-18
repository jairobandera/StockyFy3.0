-- ============================================================
--  Stockify - Script completo importable (PostgreSQL)
--  Generado por: npm run db:export
--
--  Como importar:
--   * IDE/cliente (HeidiSQL, DBeaver, pgAdmin): conectate a la base y ejecutá este archivo.
--   * Consola:  psql -U postgres -d stockify -f stockify_import.sql
--
--  Crea el esquema "stockify", todas las tablas y datos de ejemplo.
--  Usuarios de prueba (contrasenia = "12345"): superadmin / admin / empleado
-- ============================================================

CREATE SCHEMA IF NOT EXISTS "stockify";
SET search_path TO "stockify";

-- Stockify - Esquema de base de datos (PostgreSQL)
-- Se ejecuta dentro del esquema del negocio (search_path = DB_SCHEMA).
-- Las columnas "booleanas" son SMALLINT (0/1) y las claves foraneas son DEFERRABLE
-- (la restauracion de un respaldo las valida al final de la transaccion).


DROP TABLE IF EXISTS codigo_activacion CASCADE;
DROP TABLE IF EXISTS import_perfil CASCADE;
DROP TABLE IF EXISTS descuento_codigo CASCADE;
DROP TABLE IF EXISTS promocion_producto CASCADE;
DROP TABLE IF EXISTS promocion CASCADE;
DROP TABLE IF EXISTS envio_correo_detalle CASCADE;
DROP TABLE IF EXISTS envio_correo CASCADE;
DROP TABLE IF EXISTS contacto_correo CASCADE;
DROP TABLE IF EXISTS cotizacion CASCADE;
DROP TABLE IF EXISTS cliente_movimiento CASCADE;
DROP TABLE IF EXISTS venta_detalle CASCADE;
DROP TABLE IF EXISTS venta CASCADE;
DROP TABLE IF EXISTS turno_usuario CASCADE;
DROP TABLE IF EXISTS turno CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS sucursal_pin CASCADE;
DROP TABLE IF EXISTS reporte_conteo CASCADE;
DROP TABLE IF EXISTS producto_proveedor CASCADE;
DROP TABLE IF EXISTS conteo_usuario CASCADE;
DROP TABLE IF EXISTS conteo_producto CASCADE;
DROP TABLE IF EXISTS sucursal_proveedor CASCADE;
DROP TABLE IF EXISTS lote CASCADE;
DROP TABLE IF EXISTS codigo_barra CASCADE;
DROP TABLE IF EXISTS conteo CASCADE;
DROP TABLE IF EXISTS reporte CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TABLE IF EXISTS proveedor CASCADE;
DROP TABLE IF EXISTS usuario CASCADE;
DROP TABLE IF EXISTS sucursal CASCADE;
DROP TABLE IF EXISTS empresa CASCADE;


-- EMPRESA
CREATE TABLE empresa (
  id        BIGSERIAL PRIMARY KEY,
  nombre    VARCHAR(255),
  rut       VARCHAR(255),
  direccion VARCHAR(255),
  telefono  VARCHAR(255),
  -- Suscripcion: prueba de 7 dias desde fecha_alta; luego hay que activar con una clave.
  fecha_alta            TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,  -- inicio de la prueba
  suscripcion_hasta     DATE,                                        -- pagada hasta (NULL = solo prueba)
  suscripcion_ilimitada SMALLINT NOT NULL DEFAULT 0,              -- no vence nunca (lo fija el superadmin)
  activo    SMALLINT NOT NULL DEFAULT 1
);

-- CODIGO_ACTIVACION (claves de suscripcion por empresa)
-- El superadmin genera una clave para una empresa con una duracion (dias). El admin de
-- esa empresa la ingresa y extiende `empresa.suscripcion_hasta`. Clave de un solo uso.
CREATE TABLE codigo_activacion (
  id               BIGSERIAL PRIMARY KEY,
  codigo           VARCHAR(40) NOT NULL,
  empresa_id       BIGINT NOT NULL,
  dias             INT NOT NULL,
  usado            SMALLINT NOT NULL DEFAULT 0,
  usado_fecha      TIMESTAMP(0),
  fecha_generacion TIMESTAMP(0) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  activo           SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT uk_codigo_activacion UNIQUE (codigo),
  CONSTRAINT fk_codact_empresa FOREIGN KEY (empresa_id) REFERENCES empresa(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- COTIZACION (cambio de moneda por empresa)
-- Cotizaciones manuales que carga el administrador, COMPARTIDAS por todas las
-- sucursales de la empresa. `compra`/`venta` se expresan en PESOS URUGUAYOS por 1
-- unidad de la moneda (ej. USD compra 40.0 = $40 por dolar). moneda: USD | ARS | EUR.
-- Para cobrar una venta en otra moneda se usa `compra`; si una moneda no esta cargada,
-- la app cae a la cotizacion en vivo de una API.
CREATE TABLE cotizacion (
  id          BIGSERIAL PRIMARY KEY,
  empresa_id  BIGINT NOT NULL,
  moneda      VARCHAR(3) NOT NULL,            -- USD | ARS | EUR
  compra      DOUBLE PRECISION NOT NULL DEFAULT 0,
  venta       DOUBLE PRECISION NOT NULL DEFAULT 0,
  actualizado TIMESTAMP(0),
  CONSTRAINT uk_cotizacion_empresa_moneda UNIQUE (empresa_id, moneda),
  CONSTRAINT fk_cotizacion_empresa FOREIGN KEY (empresa_id) REFERENCES empresa(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- IMPORT_PERFIL (perfiles de mapeo de columnas de Excel)
-- Guarda, por empresa y tipo de import (categorias/productos/stock/contactos/...), un
-- mapeo nombrado {columna -> campo} para no re-mapear cada vez un export sin encabezado.
CREATE TABLE import_perfil (
  id         BIGSERIAL PRIMARY KEY,
  empresa_id BIGINT NOT NULL,
  tipo       VARCHAR(30) NOT NULL,
  nombre     VARCHAR(100) NOT NULL,
  mapeo      TEXT,                 -- JSON: { mapeo, filaInicio, filtro }
  activo     SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_importperfil_empresa FOREIGN KEY (empresa_id) REFERENCES empresa(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_importperfil ON import_perfil (empresa_id, tipo, activo);

-- SUCURSAL
CREATE TABLE sucursal (
  id         BIGSERIAL PRIMARY KEY,
  nombre     VARCHAR(255),
  direccion  VARCHAR(255),
  telefono   VARCHAR(255),
  empresa_id BIGINT,
  activo     SMALLINT NOT NULL DEFAULT 1,
  -- Habilita el apartado de Lotes para los administradores de esta sucursal.
  -- Si esta en 0, el menu queda deshabilitado y la API de lotes rechaza la sucursal.
  usa_lotes  SMALLINT NOT NULL DEFAULT 1,
  -- Paquetes contratados por la sucursal (los configura el superadmin):
  --   usa_stock:       control de stock (conteos + estadisticas de conteo).
  --   usa_facturacion: facturacion (punto de venta + ventas + clientes).
  -- Una empresa puede tener una sucursal con el paquete completo y otra con uno solo.
  usa_stock       SMALLINT NOT NULL DEFAULT 1,
  usa_facturacion SMALLINT NOT NULL DEFAULT 0,
  -- Habilita la pagina publica de consulta de precios (kiosko) para que el cliente
  -- escanee un codigo y vea nombre/imagen/precio. Requiere el paquete de facturacion.
  usa_consulta_precio SMALLINT NOT NULL DEFAULT 0,
  -- Paquete "Solo envio de correos": automatiza el envio del estado de cuenta de la
  -- quincena por email, cargando los datos desde Excel (sin usar la facturacion de la app).
  usa_envio_correos SMALLINT NOT NULL DEFAULT 0,
  -- Limite de credito por defecto para las cuentas de cliente NUEVAS de la sucursal
  -- (lo fija el administrador). 0 = sin limite. Al crear un cliente se copia a
  -- cliente.limite_credito, que el admin puede editar despues por cliente.
  limite_credito_default DOUBLE PRECISION NOT NULL DEFAULT 0,
  -- Credenciales de correo (SMTP) propias de la sucursal, para enviar el estado de
  -- cuenta de la quincena desde SU casilla. Las carga el superadministrador en el
  -- formulario de sucursal. smtp_pass NUNCA se devuelve en un GET. Si estan vacias,
  -- el envio usa la config global del .env (si existe).
  smtp_user   VARCHAR(255),
  smtp_pass   VARCHAR(255),
  smtp_host   VARCHAR(255) DEFAULT 'smtp.gmail.com',
  smtp_port   INT DEFAULT 465,
  smtp_secure SMALLINT NOT NULL DEFAULT 1,
  smtp_from   VARCHAR(255),
  CONSTRAINT fk_sucursal_empresa FOREIGN KEY (empresa_id) REFERENCES empresa(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- SUCURSAL_PIN (PINes de anulacion)
-- Hasta 3 PINes activos por sucursal (el maximo se controla en el servicio). El cajero
-- ingresa cualquiera de ellos para anular una venta. El valor del PIN nunca se devuelve
-- en un GET: solo la etiqueta y si esta configurado. Los administra el administrador.
CREATE TABLE sucursal_pin (
  id          BIGSERIAL PRIMARY KEY,
  sucursal_id BIGINT NOT NULL,
  pin         VARCHAR(20) NOT NULL,
  etiqueta    VARCHAR(100),
  activo      SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_sucursalpin_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_sucursalpin_sucursal ON sucursal_pin (sucursal_id, activo);

-- USUARIO
CREATE TABLE usuario (
  id             BIGSERIAL PRIMARY KEY,
  nombre         VARCHAR(255),
  apellido       VARCHAR(255),
  nombre_usuario VARCHAR(255),
  contrasenia    VARCHAR(255),
  rol            VARCHAR(30),
  sucursal_id    BIGINT,
  -- Permite participar en conteos de otras sucursales de su misma empresa.
  cuenta_en_cualquier_sucursal SMALLINT NOT NULL DEFAULT 0,
  activo         SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_usuario_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CATEGORIA
CREATE TABLE categoria (
  id                BIGSERIAL PRIMARY KEY,
  nombre            VARCHAR(255),
  descripcion       VARCHAR(255),
  codigo_categoria  VARCHAR(255),
  sucursal_id       BIGINT,
  activo            SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_categoria_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- PROVEEDOR
CREATE TABLE proveedor (
  id              BIGSERIAL PRIMARY KEY,
  rut             VARCHAR(255) NOT NULL UNIQUE,
  nombre          VARCHAR(255) NOT NULL,
  direccion       VARCHAR(255),
  telefono        VARCHAR(255),
  nombre_vendedor VARCHAR(255),
  activo          SMALLINT NOT NULL DEFAULT 1
);

-- PRODUCTO
CREATE TABLE producto (
  id              BIGSERIAL PRIMARY KEY,
  codigo_producto VARCHAR(255) NOT NULL,
  imagen          TEXT,
  nombre          VARCHAR(255) NOT NULL,
  detalle         VARCHAR(255),
  precio          DOUBLE PRECISION NOT NULL,
  -- DECIMAL para admitir stock con decimales (ej. combustible en litros).
  cantidad_stock  NUMERIC(14,3) NOT NULL,
  activo          SMALLINT NOT NULL DEFAULT 1,
  sucursal_id     BIGINT NOT NULL,
  categoria_id    BIGINT NOT NULL,
  -- El codigo de producto es unico dentro de la sucursal, no entre sucursales.
  CONSTRAINT uk_producto_codigo_sucursal UNIQUE (codigo_producto, sucursal_id),
  CONSTRAINT fk_producto_sucursal  FOREIGN KEY (sucursal_id)  REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_producto_categoria FOREIGN KEY (categoria_id) REFERENCES categoria(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CODIGO_BARRA
CREATE TABLE codigo_barra (
  id          BIGSERIAL PRIMARY KEY,
  codigo      VARCHAR(255) NOT NULL,
  producto_id BIGINT NOT NULL,
  -- Desnormalizado desde producto: un UNIQUE no puede abarcar una columna de
  -- otra tabla y el mismo EAN debe poder existir una vez por sucursal.
  -- Lo mantiene sincronizado syncCodigosBarra() en producto.service.js.
  sucursal_id BIGINT NOT NULL,
  -- Baja logica: un codigo nunca se borra. Las importaciones solo suman; solo la
  -- accion explicita del usuario desactiva uno (y deja de escanear, pero queda).
  activo      SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT uk_codigobarra_sucursal UNIQUE (codigo, sucursal_id),
  CONSTRAINT fk_codigobarra_producto FOREIGN KEY (producto_id) REFERENCES producto(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_codigobarra_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- LOTE
CREATE TABLE lote (
  id                BIGSERIAL PRIMARY KEY,
  numero_lote       VARCHAR(255) NOT NULL,
  fecha_ingreso     DATE NOT NULL,
  fecha_vencimiento DATE,
  cantidad_stock    NUMERIC(14,3) NOT NULL,
  activo            SMALLINT NOT NULL DEFAULT 1,
  -- Indica si este lote sumo su cantidad al stock del producto (mercaderia nueva).
  -- Si es 0 el lote solo etiqueta stock que ya estaba contado (por ejemplo el del Excel).
  afecta_stock      SMALLINT NOT NULL DEFAULT 0,
  producto_id       BIGINT NOT NULL,
  -- El numero de lote lo asigna el proveedor: se repite entre productos, no dentro del mismo.
  CONSTRAINT uk_lote_numero_producto UNIQUE (numero_lote, producto_id),
  CONSTRAINT fk_lote_producto FOREIGN KEY (producto_id) REFERENCES producto(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_lote_vencimiento ON lote (fecha_vencimiento);

-- PRODUCTO_PROVEEDOR (N:M)
CREATE TABLE producto_proveedor (
  producto_id  BIGINT NOT NULL,
  proveedor_id BIGINT NOT NULL,
  PRIMARY KEY (producto_id, proveedor_id),
  CONSTRAINT fk_pp_producto  FOREIGN KEY (producto_id)  REFERENCES producto(id)  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_pp_proveedor FOREIGN KEY (proveedor_id) REFERENCES proveedor(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE
);

-- SUCURSAL_PROVEEDOR
CREATE TABLE sucursal_proveedor (
  id           BIGSERIAL PRIMARY KEY,
  sucursal_id  BIGINT NOT NULL,
  proveedor_id BIGINT NOT NULL,
  CONSTRAINT fk_sp_sucursal  FOREIGN KEY (sucursal_id)  REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_sp_proveedor FOREIGN KEY (proveedor_id) REFERENCES proveedor(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CONTEO
CREATE TABLE conteo (
  id                BIGSERIAL PRIMARY KEY,
  fecha_hora        TIMESTAMP(0),
  conteo_finalizado SMALLINT NOT NULL DEFAULT 0,
  usuario_id        BIGINT,
  -- Sucursal en la que se cuenta. La elige el admin al crear el conteo (por defecto
  -- la suya) y de ella salen las categorias, los productos y el catalogo de escaneo.
  sucursal_id       BIGINT,
  activo            SMALLINT NOT NULL DEFAULT 1,
  tipo_conteo       VARCHAR(20) NOT NULL DEFAULT 'LIBRE',
  CONSTRAINT fk_conteo_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_conteo_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_conteo_sucursal ON conteo (sucursal_id, activo);

-- CONTEO_PRODUCTO (renglones del conteo)
CREATE TABLE conteo_producto (
  id                SERIAL PRIMARY KEY,
  precio_actual     DOUBLE PRECISION NOT NULL DEFAULT 0,
  cantidad_esperada NUMERIC(14,3),
  cantidad_contada  NUMERIC(14,3),
  conteo_id         BIGINT,
  producto_id       BIGINT,
  usuario_id        BIGINT,
  activo            SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_cp_conteo   FOREIGN KEY (conteo_id)   REFERENCES conteo(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_cp_producto FOREIGN KEY (producto_id) REFERENCES producto(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_cp_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CONTEO_USUARIO (participantes)
CREATE TABLE conteo_usuario (
  id         BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL,
  conteo_id  BIGINT NOT NULL,
  CONSTRAINT uq_conteo_usuario UNIQUE (conteo_id, usuario_id),
  CONSTRAINT fk_cu_usuario FOREIGN KEY (usuario_id) REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_cu_conteo  FOREIGN KEY (conteo_id)  REFERENCES conteo(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- REPORTE
CREATE TABLE reporte (
  id                    BIGSERIAL PRIMARY KEY,
  fecha_generacion      DATE,
  total_faltante        DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_sobrante        DOUBLE PRECISION NOT NULL DEFAULT 0,
  diferencia_monetaria  DOUBLE PRECISION NOT NULL DEFAULT 0,
  activo                SMALLINT NOT NULL DEFAULT 1
);

-- REPORTE_CONTEO (N:M)
CREATE TABLE reporte_conteo (
  reporte_id BIGINT NOT NULL,
  conteo_id  BIGINT NOT NULL,
  PRIMARY KEY (reporte_id, conteo_id),
  CONSTRAINT fk_rc_reporte FOREIGN KEY (reporte_id) REFERENCES reporte(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_rc_conteo  FOREIGN KEY (conteo_id)  REFERENCES conteo(id)  ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE
);

-- FACTURACION
-- CLIENTE
-- Scoped por sucursal. El RUT es opcional (el consumidor final no crea cliente)
-- y es unico dentro de la sucursal cuando esta presente.
CREATE TABLE cliente (
  id              BIGSERIAL PRIMARY KEY,
  rut             VARCHAR(50),
  razon_social    VARCHAR(255),
  nombre_fantasia VARCHAR(255),
  direccion       VARCHAR(255),
  telefono        VARCHAR(255),
  email           VARCHAR(255),
  -- Tipo de documento (preparado para la factura electronica de Uruguay).
  tipo_documento  VARCHAR(20) NOT NULL DEFAULT 'RUT',
  -- Limite de credito del cliente (0 = sin limite). Se copia de
  -- sucursal.limite_credito_default al crearlo; el admin lo edita por cliente.
  limite_credito  DOUBLE PRECISION NOT NULL DEFAULT 0,
  sucursal_id     BIGINT NOT NULL,
  activo          SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT uk_cliente_rut_sucursal UNIQUE (rut, sucursal_id),
  CONSTRAINT fk_cliente_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- TURNO (caja)
-- Un turno agrupa las ventas de una jornada de caja. Es UNO por sucursal a la vez:
-- mientras hay un turno ABIERTO, los cajeros que entran se suman a el (turno_usuario).
-- numero: 1=manana, 2=tarde, 3=noche, 4=otro. El responsable es el cajero que se
-- marco como tal al abrir o sumarse (puede no haber responsable todavia). El cierre
-- lo hace el responsable o un administrador y genera el reporte de arqueo.
CREATE TABLE turno (
  id                     BIGSERIAL PRIMARY KEY,
  sucursal_id            BIGINT NOT NULL,
  numero                 SMALLINT NOT NULL,                       -- 1..4
  estado                 VARCHAR(20) NOT NULL DEFAULT 'ABIERTO', -- ABIERTO | CERRADO
  fecha_apertura         TIMESTAMP(0),
  fecha_cierre           TIMESTAMP(0),
  usuario_apertura_id    BIGINT,                                 -- quien abrio el turno
  usuario_responsable_id BIGINT,                                 -- cajero responsable (NULL si nadie se marco)
  usuario_cierre_id      BIGINT,                                 -- quien lo cerro
  observaciones_cierre   VARCHAR(500),
  activo                 SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_turno_sucursal    FOREIGN KEY (sucursal_id)            REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_turno_apertura    FOREIGN KEY (usuario_apertura_id)    REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_turno_responsable FOREIGN KEY (usuario_responsable_id) REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_turno_cierre      FOREIGN KEY (usuario_cierre_id)      REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_turno_sucursal_estado ON turno (sucursal_id, estado);

-- TURNO_USUARIO (cajeros que trabajan el turno)
-- Varios cajeros pueden trabajar el mismo turno. Un cajero se une una sola vez.
CREATE TABLE turno_usuario (
  id             BIGSERIAL PRIMARY KEY,
  turno_id       BIGINT NOT NULL,
  usuario_id     BIGINT NOT NULL,
  es_responsable SMALLINT NOT NULL DEFAULT 0,
  fecha_union    TIMESTAMP(0),
  CONSTRAINT uk_turno_usuario UNIQUE (turno_id, usuario_id),
  CONSTRAINT fk_tu_turno   FOREIGN KEY (turno_id)   REFERENCES turno(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_tu_usuario FOREIGN KEY (usuario_id) REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- VENTA
-- Registro interno de la venta. Las columnas cfe_* quedan preparadas para la
-- factura electronica de Uruguay (DGI/CFE): hoy la venta nace con estado INTERNO.
CREATE TABLE venta (
  id                   BIGSERIAL PRIMARY KEY,
  fecha_hora           TIMESTAMP(0),
  sucursal_id          BIGINT NOT NULL,
  turno_id             BIGINT,              -- turno de caja al que pertenece la venta
  usuario_id           BIGINT,              -- cajero que emitio la venta
  cliente_id           BIGINT,              -- NULL = consumidor final
  consumidor_final     SMALLINT NOT NULL DEFAULT 1,
  subtotal             DOUBLE PRECISION NOT NULL DEFAULT 0,
  descuento            DOUBLE PRECISION NOT NULL DEFAULT 0,          -- monto del descuento aplicado (codigo)
  descuento_codigo_id  BIGINT,                            -- codigo de descuento usado (si hubo)
  descuento_codigo     VARCHAR(60),                       -- snapshot del codigo
  descuento_tipo       VARCHAR(20),                       -- PORCENTAJE | MONTO (snapshot)
  descuento_valor      NUMERIC(14,3),                     -- valor del codigo (snapshot)
  total                DOUBLE PRECISION NOT NULL DEFAULT 0,
  forma_pago           VARCHAR(20) NOT NULL DEFAULT 'CONTADO', -- CONTADO | CREDITO
  -- Moneda de cobro. El total "oficial" (subtotal/total) SIEMPRE esta en UYU; cuando
  -- se cobra en otra moneda se guardan aca la moneda, la cotizacion (UYU por 1 unidad)
  -- y el total convertido. moneda_pago = UYU y cotizacion = 1 para la venta normal.
  moneda_pago          VARCHAR(3) NOT NULL DEFAULT 'UYU',       -- UYU | USD | ARS | EUR
  cotizacion           DOUBLE PRECISION NOT NULL DEFAULT 1,                -- UYU por 1 unidad de moneda_pago
  total_moneda         DOUBLE PRECISION NOT NULL DEFAULT 0,                -- total en moneda_pago
  -- Efectivo recibido y vuelto, en moneda_pago (para ventas al contado). NULL si no aplica.
  efectivo_recibido    DOUBLE PRECISION,
  vuelto               DOUBLE PRECISION,
  -- Comentario opcional que el cajero agrega a pedido del cliente (sale en la boleta/correo).
  comentario           VARCHAR(500),
  estado               VARCHAR(20) NOT NULL DEFAULT 'EMITIDA', -- EMITIDA | ANULADA
  motivo_anulacion     VARCHAR(500),
  fecha_anulacion      TIMESTAMP(0),
  usuario_anulacion_id BIGINT,
  activo               SMALLINT NOT NULL DEFAULT 1,
  -- Factura electronica (DGI/CFE Uruguay) - preparado, hoy sin uso
  cfe_tipo             VARCHAR(20),         -- E_TICKET | E_FACTURA
  cfe_serie            VARCHAR(10),
  cfe_numero           BIGINT,
  cfe_estado           VARCHAR(20) NOT NULL DEFAULT 'INTERNO', -- INTERNO|PENDIENTE|AUTORIZADO|RECHAZADO
  cfe_uuid             VARCHAR(100),
  cfe_cae              VARCHAR(100),
  cfe_qr_url           VARCHAR(500),
  cfe_hash             VARCHAR(255),
  CONSTRAINT fk_venta_turno    FOREIGN KEY (turno_id)    REFERENCES turno(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_venta_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_venta_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_venta_cliente  FOREIGN KEY (cliente_id)  REFERENCES cliente(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_venta_usuario_anulacion FOREIGN KEY (usuario_anulacion_id) REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_venta_sucursal_estado ON venta (sucursal_id, estado);
CREATE INDEX idx_venta_turno ON venta (turno_id);
CREATE INDEX idx_venta_fecha ON venta (fecha_hora);

-- VENTA_DETALLE (renglones)
-- Guarda snapshot de codigo/nombre/precio: si despues editan el producto, el
-- historial de la venta no cambia.
CREATE TABLE venta_detalle (
  id              BIGSERIAL PRIMARY KEY,
  venta_id        BIGINT NOT NULL,
  producto_id     BIGINT,
  codigo_producto VARCHAR(255),
  nombre          VARCHAR(255),
  precio_unitario DOUBLE PRECISION NOT NULL DEFAULT 0,
  cantidad        INT NOT NULL DEFAULT 0,
  subtotal        DOUBLE PRECISION NOT NULL DEFAULT 0,
  CONSTRAINT fk_vd_venta    FOREIGN KEY (venta_id)    REFERENCES venta(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_vd_producto FOREIGN KEY (producto_id) REFERENCES producto(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- PROMOCIONES (precio especial por lista de productos)
-- Cualquier sucursal con facturacion. Mientras la promo esta vigente, cada producto de su
-- lista se vende a `precio`. Vigencia por fecha (hasta NULL = sin fin / baja manual).
CREATE TABLE promocion (
  id          BIGSERIAL PRIMARY KEY,
  sucursal_id BIGINT NOT NULL,
  nombre      VARCHAR(255) NOT NULL,
  precio      NUMERIC(14,3) NOT NULL,
  fecha_desde DATE,
  fecha_hasta DATE,
  activo      SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT fk_promocion_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_promocion_sucursal ON promocion (sucursal_id, activo);

CREATE TABLE promocion_producto (
  id           BIGSERIAL PRIMARY KEY,
  promocion_id BIGINT NOT NULL,
  producto_id  BIGINT NOT NULL,
  CONSTRAINT uk_promoprod UNIQUE (promocion_id, producto_id),
  CONSTRAINT fk_promoprod_promo    FOREIGN KEY (promocion_id) REFERENCES promocion(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_promoprod_producto FOREIGN KEY (producto_id)  REFERENCES producto(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CODIGOS DE DESCUENTO (un solo uso, aplicados en el POS)
CREATE TABLE descuento_codigo (
  id             BIGSERIAL PRIMARY KEY,
  sucursal_id    BIGINT NOT NULL,
  codigo         VARCHAR(60) NOT NULL,
  tipo           VARCHAR(20) NOT NULL,          -- PORCENTAJE | MONTO
  valor          NUMERIC(14,3) NOT NULL,
  fecha_desde    DATE,
  fecha_hasta    DATE,                          -- vencimiento (NULL = sin vencimiento)
  usado          SMALLINT NOT NULL DEFAULT 0,
  usado_venta_id BIGINT,
  usado_fecha    TIMESTAMP(0),
  activo         SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT uk_descuento_sucursal_codigo UNIQUE (sucursal_id, codigo),
  CONSTRAINT fk_descuento_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_descuento_venta    FOREIGN KEY (usado_venta_id) REFERENCES venta(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- CLIENTE_MOVIMIENTO (cuenta corriente)
-- Mayor de la cuenta corriente del cliente. El saldo (lo que debe) es
-- SUMA(cargos) - SUMA(pagos). Tipos:
--  CARGO_VENTA -> una venta a credito (referencia la venta)
--  CARGO_MORA  -> cargo por mora que aplica el administrador (fijo o %)
--  PAGO        -> abono del cliente (total o parcial)
-- monto siempre positivo; el signo lo da el tipo (CARGO_* suma, PAGO resta).
CREATE TABLE cliente_movimiento (
  id          BIGSERIAL PRIMARY KEY,
  cliente_id  BIGINT NOT NULL,
  tipo        VARCHAR(20) NOT NULL,       -- CARGO_VENTA | CARGO_MORA | PAGO
  monto       DOUBLE PRECISION NOT NULL DEFAULT 0,
  fecha       TIMESTAMP(0),
  venta_id    BIGINT,                     -- solo para CARGO_VENTA
  descripcion VARCHAR(255),
  usuario_id  BIGINT,                     -- quien lo registro
  CONSTRAINT fk_climov_cliente FOREIGN KEY (cliente_id) REFERENCES cliente(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_climov_venta   FOREIGN KEY (venta_id)   REFERENCES venta(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_climov_usuario FOREIGN KEY (usuario_id) REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_climov_cliente ON cliente_movimiento (cliente_id);

-- CONTACTO_CORREO (paquete "Solo envio de correos")
-- Lista de contactos reutilizable, por sucursal, para el envio del estado de cuenta.
-- Se carga/actualiza desde Excel (merge por `clave`). No tiene relacion con `cliente`.
-- `clave` (RUT/documento) y `cuenta` (N° de cuenta) se guardan normalizadas (ver claveCodigo);
-- el estado de cuenta cruza por cualquiera de las dos.
CREATE TABLE contacto_correo (
  id          BIGSERIAL PRIMARY KEY,
  sucursal_id BIGINT NOT NULL,
  clave       VARCHAR(100) NOT NULL,
  cuenta      VARCHAR(100),           -- N° de cuenta corriente (cruza el estado de cuenta; aparte del RUT)
  nombre      VARCHAR(255),
  email       VARCHAR(255),
  direccion   VARCHAR(255),
  activo      SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT uk_contacto_sucursal_clave UNIQUE (sucursal_id, clave),
  CONSTRAINT fk_contacto_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE
);

-- ENVIO_CORREO (historial de envios de quincena)
CREATE TABLE envio_correo (
  id            BIGSERIAL PRIMARY KEY,
  sucursal_id   BIGINT NOT NULL,
  fecha         TIMESTAMP(0),
  usuario_id    BIGINT,
  asunto        VARCHAR(255),
  periodo_desde DATE,
  periodo_hasta DATE,
  total         INT NOT NULL DEFAULT 0,
  enviados      INT NOT NULL DEFAULT 0,
  fallidos      INT NOT NULL DEFAULT 0,
  sin_contacto  INT NOT NULL DEFAULT 0,
  CONSTRAINT fk_envio_sucursal FOREIGN KEY (sucursal_id) REFERENCES sucursal(id) DEFERRABLE INITIALLY IMMEDIATE,
  CONSTRAINT fk_envio_usuario  FOREIGN KEY (usuario_id)  REFERENCES usuario(id) DEFERRABLE INITIALLY IMMEDIATE
);
CREATE INDEX idx_envio_sucursal ON envio_correo (sucursal_id, fecha);

-- ENVIO_CORREO_DETALLE (destinatarios de cada envio)
CREATE TABLE envio_correo_detalle (
  id       BIGSERIAL PRIMARY KEY,
  envio_id BIGINT NOT NULL,
  clave    VARCHAR(100),
  nombre   VARCHAR(255),
  email    VARCHAR(255),
  monto    DOUBLE PRECISION NOT NULL DEFAULT 0,
  estado   VARCHAR(20),                 -- ENVIADO | FALLIDO | SIN_CONTACTO
  error    VARCHAR(255),
  CONSTRAINT fk_enviodet_envio FOREIGN KEY (envio_id) REFERENCES envio_correo(id) ON DELETE CASCADE DEFERRABLE INITIALLY IMMEDIATE
);

-- ============================================================
--  Datos de ejemplo (usuarios de prueba, contrasenia = "12345")
-- ============================================================

INSERT INTO empresa (id, nombre, rut, direccion, telefono) VALUES
  (1, 'Distribuidora Demo S.A.', '210000000012', 'Av. Siempre Viva 742', '099111222');

-- Centro: paquete COMPLETO (stock + facturacion) y limite de credito por defecto 5000.
-- Pocitos: solo control de stock y sin Lotes, para mostrar las opciones del superadmin.
INSERT INTO sucursal (id, nombre, direccion, telefono, empresa_id, usa_lotes, usa_stock, usa_facturacion, usa_consulta_precio, usa_envio_correos, limite_credito_default) VALUES
  (1, 'Sucursal Centro',  'Calle 18 de Julio 1234', '099333444', 1, 1, 1, 1, 1, 1, 5000),
  (2, 'Sucursal Pocitos', 'Av. Brasil 2500',        '099555666', 1, 0, 1, 0, 0, 0, 0);

-- Contactos de ejemplo para el apartado "Envio de correos" (Sucursal Centro).
INSERT INTO contacto_correo (sucursal_id, clave, nombre, email) VALUES
  (1, '216000000013', 'Comercio del Este S.R.L.', 'ventas@eleste.com'),
  (1, 'CLI-002', 'Juan Perez', 'juan.perez@example.com');

-- PINes de anulacion de la Sucursal Centro (hasta 3). El cajero ingresa uno para anular.
INSERT INTO sucursal_pin (id, sucursal_id, pin, etiqueta) VALUES
  (1, 1, '1234', 'Supervisor'),
  (2, 1, '9999', 'Encargado');

-- Cotizaciones de ejemplo (compra/venta en pesos uruguayos por 1 unidad), por empresa.
INSERT INTO cotizacion (empresa_id, moneda, compra, venta, actualizado) VALUES
  (1, 'USD', 40, 41, NOW()),
  (1, 'ARS', 0.03, 0.035, NOW()),
  (1, 'EUR', 44, 46, NOW());

-- cuenta_en_cualquier_sucursal: "empleado2" puede contar en las dos sucursales.
-- "cajero" opera el punto de venta de la Sucursal Centro (paquete con facturacion).
INSERT INTO usuario (id, nombre, apellido, nombre_usuario, contrasenia, rol, sucursal_id, cuenta_en_cualquier_sucursal) VALUES
  (1, 'Sofia',  'Perez',     'superadmin', '$2a$10$KSxinx.l6r3egWBX6P3trePFB4sBioy6MKk9qc2652iWAJIAdqnai', 'SUPERADMINISTRADOR', 1, 0),
  (2, 'Martin', 'Gomez',     'admin',      '$2a$10$KSxinx.l6r3egWBX6P3trePFB4sBioy6MKk9qc2652iWAJIAdqnai', 'ADMINISTRADOR',      1, 0),
  (3, 'Lucia',  'Fernandez', 'empleado',   '$2a$10$KSxinx.l6r3egWBX6P3trePFB4sBioy6MKk9qc2652iWAJIAdqnai', 'EMPLEADO',           1, 0),
  (4, 'Diego',  'Rodriguez', 'empleado2',  '$2a$10$KSxinx.l6r3egWBX6P3trePFB4sBioy6MKk9qc2652iWAJIAdqnai', 'EMPLEADO',           1, 1),
  (5, 'Carla',  'Lopez',     'cajero',     '$2a$10$KSxinx.l6r3egWBX6P3trePFB4sBioy6MKk9qc2652iWAJIAdqnai', 'CAJERO',             1, 0);

-- Cliente de ejemplo (Sucursal Centro) para probar la facturacion con RUT y credito.
INSERT INTO cliente (id, rut, razon_social, nombre_fantasia, direccion, telefono, email, tipo_documento, limite_credito, sucursal_id) VALUES
  (1, '210000000019', 'Comercio del Este S.R.L.', 'El Este', 'Av. Italia 3000', '099777888', 'ventas@eleste.com', 'RUT', 5000, 1);

INSERT INTO categoria (id, nombre, descripcion, codigo_categoria, sucursal_id) VALUES
  (1, 'Bebidas', 'Bebidas y refrescos', 'BEB', 1),
  (2, 'Almacen', 'Productos de almacen', 'ALM', 1),
  (3, 'Bebidas', 'Bebidas y refrescos', 'BEB', 2);

INSERT INTO proveedor (id, rut, nombre, direccion, telefono, nombre_vendedor) VALUES
  (1, '215000000018', 'Proveedor Central', 'Ruta 8 km 20', '098000111', 'Juan Vendedor');

INSERT INTO producto (id, codigo_producto, nombre, detalle, precio, cantidad_stock, sucursal_id, categoria_id) VALUES
  (1, 'P001', 'Agua mineral 500ml',  'Botella 500ml', 32.5, 120, 1, 1),
  (2, 'P002', 'Refresco cola 1.5L',  'Botella 1.5L',  89.0, 60,  1, 1),
  (3, 'P003', 'Arroz 1kg',           'Paquete 1kg',   54.0, 80,  1, 2),
  (4, 'P004', 'Fideos 500g',         'Paquete 500g',  41.0, 95,  1, 2),
  -- Los mismos P001 y P002, tambien en Sucursal Pocitos con stock propio: el codigo
  -- de producto y el de barra son unicos POR SUCURSAL, no entre sucursales.
  (5, 'P001', 'Agua mineral 500ml',  'Botella 500ml', 32.5, 40,  2, 3),
  (6, 'P002', 'Refresco cola 1.5L',  'Botella 1.5L',  89.0, 18,  2, 3);

-- Un producto puede tener varios codigos: al mismo articulo le cambian el EAN y
-- conviven el viejo y el nuevo (producto 1). Todos escanean.
INSERT INTO codigo_barra (codigo, producto_id, sucursal_id) VALUES
  ('7791234500011', 1, 1),
  ('7791234599998', 1, 1),
  ('7791234599999', 1, 1),
  ('7791234500028', 2, 1),
  ('7791234500035', 3, 1),
  ('7791234500042', 4, 1),
  ('7791234500011', 5, 2),
  ('7791234500028', 6, 2);

INSERT INTO producto_proveedor (producto_id, proveedor_id) VALUES
  (1, 1), (2, 1), (3, 1), (4, 1);

-- Lotes de ejemplo: fechas relativas a hoy para que siempre haya un caso de cada
-- color del semaforo. El producto 3 queda con un descuadre a proposito (sus lotes
-- suman 100 contra un stock de 80). afecta_stock = 0 significa que el lote solo
-- etiqueta stock que ya estaba contado.
INSERT INTO lote (numero_lote, fecha_ingreso, fecha_vencimiento, cantidad_stock, activo, afecta_stock, producto_id) VALUES
  ('L-1001', CURRENT_DATE - 30, CURRENT_DATE - 5,   60,  1, 0, 1),
  ('L-1002', CURRENT_DATE - 30, CURRENT_DATE + 5,   40,  1, 0, 1),
  ('L-2001', CURRENT_DATE - 30, CURRENT_DATE + 20,  20,  1, 0, 2),
  ('L-2002', CURRENT_DATE - 30, NULL,               25,  1, 0, 2),
  ('L-3001', CURRENT_DATE - 30, CURRENT_DATE + 180, 100, 1, 0, 3),
  ('L-4001', CURRENT_DATE - 30, CURRENT_DATE + 60,  15,  1, 1, 4);

-- Las filas de arriba traen el id puesto a mano: se adelantan las secuencias.
SELECT setval(pg_get_serial_sequence('empresa', 'id'),      (SELECT MAX(id) FROM empresa));
SELECT setval(pg_get_serial_sequence('sucursal', 'id'),     (SELECT MAX(id) FROM sucursal));
SELECT setval(pg_get_serial_sequence('sucursal_pin', 'id'), (SELECT MAX(id) FROM sucursal_pin));
SELECT setval(pg_get_serial_sequence('usuario', 'id'),      (SELECT MAX(id) FROM usuario));
SELECT setval(pg_get_serial_sequence('cliente', 'id'),      (SELECT MAX(id) FROM cliente));
SELECT setval(pg_get_serial_sequence('categoria', 'id'),    (SELECT MAX(id) FROM categoria));
SELECT setval(pg_get_serial_sequence('proveedor', 'id'),    (SELECT MAX(id) FROM proveedor));
SELECT setval(pg_get_serial_sequence('producto', 'id'),     (SELECT MAX(id) FROM producto));
