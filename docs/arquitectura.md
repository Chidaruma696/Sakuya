# Arquitectura de primer nivel

Sakuya es un solo sistema y una sola base de datos, partido en **módulos**. Un módulo es un conjunto aparte: sus tablas, sus reglas, sus permisos y su pestaña en la cinta. Se enciende o se apaga por negocio (el giro elegido al arrancar es solo un preset; después manda Ajustes › Módulos). Apagado, desaparece de la cinta, de los roles y de sus pantallas; sus datos se quedan y no se apaga con trabajo abierto. Nada nuevo se mete "dentro" de un módulo que ya existía: si es otra cosa, es otro módulo.

## Núcleo (siempre encendido)

| Conjunto | Qué es | Tablas propias | Permisos | Pestaña |
|---|---|---|---|---|
| **Caja** | Vender, ticket (navegador o térmica ESC/POS por red o cable, según la sucursal), gaveta, cortes, retiros, devoluciones; sin conexión vende con el catálogo del equipo y encola (`sin_conexion.js`, service worker). | ventas, venta_lineas, pagos, cortes, retiros, devoluciones | `caja.*` | Caja |
| **Inventario** | Existencias por sucursal y producto, kardex, entradas y ajustes a mano. Es la única puerta para mover existencias (`Inventario.mover!`). | existencias, movimientos | `inventario.*` | Inventario |
| **Administración** | Catálogos y gente: productos, códigos, promociones, precios por sucursal, usuarios, roles, sucursales. | productos, codigos_barras, promociones, precios_sucursal, usuarios, roles, sucursales | `admin.*` | Admin |
| **Ajustes** | Preferencias de cada persona (idioma, tema, densidad, letra) y del negocio (ticket, moneda, folios, caja, compras, módulos). Admin da de alta, Ajustes configura. En sus opciones avanzadas vive todo lo que se programa en Lisp. | ajustes | `admin.usuarios` para lo del sistema; `reglas.editar` para lo avanzado | Inicio › Ajustes |
| **Revisión** | Lo que una regla frenó (el intento, marcado como frenado) y lo que pasó con permiso pero hay que mirar; el supervisor aprueba u observa y puede cargarlo. | revisiones, cargos | `revisiones.*` | Inicio |

## Módulos

| Módulo | Qué es | Tablas propias | Permisos | Pestaña |
|---|---|---|---|---|
| **Compras** | Proveedores, recepción de mercancía (entrada con proveedor y remisión), factura del proveedor con renglones, cuentas por pagar, pago desde la gaveta. Sin costo en inventario. | proveedores, recepciones, recepcion_lineas, facturas_proveedor, factura_proveedor_lineas, movimientos_proveedor, pagos_proveedor | `compras.*` | Compras |
| **Almacenes** | Sucursales tipo *almacén* (solo guardan: sin caja ni conteos), traspasos entre sucursales y reabasto por mínimos y máximos (arma el traspaso). | traspasos, traspaso_lineas, minimos (y el tipo `almacen` en sucursales) | `almacenes.*` | Almacenes |
| **Conteos** | Conteos físicos: se escanean las piezas y se teclea lo que va en fracciones; el faltante se carga al responsable. | conteos, conteo_lineas | `conteos.*` | Conteos |
| **Clientes** (apagado de fábrica) | Clientes, venta a cuenta (forma de pago «A cuenta»), cuenta del cliente con antigüedad, abonos que entran a la caja, pedidos que apartan existencias y se cobran en la caja. | clientes, movimientos_credito, abonos, pedidos, pedido_lineas | `clientes.*` | Clientes |

## Reglas transversales

- **Una sola puerta al inventario**: todo pasa por `Inventario.mover!`, que escribe el movimiento y la existencia en la misma transacción. Ningún módulo toca `existencias` directo.
- **Libros solo-inserción** para lo que es dinero o deuda (deuda con proveedores, cuenta de clientes, abonos, kardex) y para lo que deja rastro (reglas y sus versiones, bitácora del REPL): el saldo es la suma; nada se edita ni se borra; corregir es asentar.
- **Folios por sucursal** con prefijo por documento (B venta, C corte, D devolución, RC recepción, TG traspaso, K conteo, AB abono, P pedido), únicos por sucursal.
- **Idempotencia** en lo que captura el navegador y podría reenviarse (venta, recepción, traspaso): una clave, y la misma clave devuelve el mismo documento.
- **Frenar y reportar**: en cada punto delicado una regla decide; lo irregular, de fábrica, no pasa y el intento queda en Revisión a nombre de quien lo hizo. Quien tiene el permiso nunca se queda atorado: para esa persona, frenar es pasar y quedar por revisar.
- **Lo apartado**: un pedido abierto aparta existencias; vender y traspasar lo respetan (`Apartado.comprobar!`), mermas y ajustes no.
- **Dos bases**: SQLite de fábrica, PostgreSQL con `DATABASE_URL`; nada de SQL propio de una sola, y la CI prueba las dos.
- **Tipos de sucursal**: matriz (de donde sale todo), tienda (vende), almacén (solo guarda). Las reglas se derivan del tipo, nunca de una bandera aparte.
- **i18n completa** (inglés por defecto, español, alemán): todo texto visible pasa por `t(...)`, incluidos avisos, errores y JS. En los tests falta una traducción = falla. Un plugin puede traer otro idioma o cambiar textos (backend propio en cadena, delante de los YAML).

## Reglas en Lisp

El núcleo pregunta en puntos fijos (**ganchos**) y una regla escrita en el Lisp de Sakuya (`lib/lisp*.rb`) contesta. La regla propone, el núcleo dispone: lee por funciones estrechas y devuelve una decisión; nunca escribe en la base. Detalle en `decisiones.md`.

| Gancho | Módulo | Pregunta | De fábrica |
|---|---|---|---|
| tablero | `Tablero` | qué cifras y listas salen en Inicio | las de siempre |
| precio | `ReglaPrecio` | cada renglón que se cobra | abajo de lo que toca, frena |
| venta | `ReglaVenta` | la venta entera antes de cobrar | deja pasar |
| credito | `ReglaCredito` | lo que va a cuenta de un cliente | frena (no se fía) |
| corte | `ReglaCorte` | la diferencia al cerrar | fuera del tope, frena |
| retiro | `ReglaRetiro` | sacar efectivo de la gaveta | sin permiso, frena |
| movimiento | `ReglaMovimiento` | entradas sueltas, ajustes y mermas | sin permiso, frena |
| recepcion | `ReglaRecepcion` | mercancía que llega del proveedor | deja pasar |
| factura | `ReglaFactura` | facturar más de lo recibido | con candado, frena |

Lo común de los que deciden está en `Gancho`; cada uno lleva su `VERSION` de contrato y cada regla guarda la suya (`Regla::CONTRATOS`). Todo se edita en Ajustes › Opciones avanzadas (un editor común en `ReglasController`, con prueba en seco contra datos reales), se exporta e importa en un `.lisp` (`ArchivoReglas`), y ahí mismo viven el REPL de solo lectura (`Repl`, con bitácora) y los plugins (`Plugin`: funciones con prefijo, informes y traducciones; lo de fábrica corre sin ellos).

## Cómo se agrega un módulo

1. Clave en `Modulo::OPCIONALES` (y en `DEPENDE` si cuelga de otro, en `ALGUNO` si le basta con uno de varios, en `GIROS` donde arranque encendido, en `comprobar_apagable!` si puede tener trabajo abierto).
2. Sus permisos con prefijo propio en `Permiso` y el prefijo en `Modulo::PERMISOS`; el rol supervisor suele llevar `prefijo.*`.
3. `Ajuste::DEFAULTS["modulos.<clave>"] = "1"` (o `"0"` si arranca apagado, como clientes).
4. Sus controladores con `pestana :<clave>` y `modulo :<clave>`; su pestaña en `RibbonHelper::PESTANAS`.
5. Textos `modulos.<clave>.{nombre,que}`, `cinta.pestanas.<clave>`, permisos, en es/en/de.
6. Tests: el flujo, y que apagado desaparece de la cinta y sus pantallas responden 404.
