# Arquitectura de primer nivel

Sakuya es un solo sistema y una sola base de datos, partido en **módulos**. Un módulo es un conjunto aparte: sus tablas, sus reglas, sus permisos y su pestaña en la cinta. Se enciende o se apaga por negocio (el giro elegido al arrancar es solo un preset; después manda Ajustes › Módulos). Apagado, desaparece de la cinta, de los roles y de sus pantallas; sus datos se quedan y no se apaga con trabajo abierto. Nada nuevo se mete "dentro" de un módulo que ya existía: si es otra cosa, es otro módulo.

## Núcleo (siempre encendido)

| Conjunto | Qué es | Tablas propias | Permisos | Pestaña |
|---|---|---|---|---|
| **Caja** | Vender, ticket, gaveta, cortes, retiros, devoluciones. | ventas, venta_lineas, pagos, cortes, retiros, devoluciones | `caja.*` | Caja |
| **Inventario** | Existencias por sucursal y producto, kardex, entradas y ajustes a mano. Es la única puerta para mover existencias (`Inventario.mover!`). | existencias, movimientos | `inventario.*` | Inventario |
| **Administración** | Catálogos y gente: productos, códigos, promociones, precios por sucursal, usuarios, roles, sucursales. | productos, codigos_barras, promociones, precios_sucursal, usuarios, roles, sucursales | `admin.*` | Admin |
| **Ajustes** | Preferencias de cada persona (idioma, tema, densidad, letra) y del negocio (ticket, moneda, folios, caja, compras, módulos). Admin da de alta, Ajustes configura. | ajustes | `admin.usuarios` para lo del sistema | Inicio › Ajustes |
| **Revisión** | La bandeja de autorización diferida: lo que necesitaba a un supervisor y pasó con motivo. | revisiones, cargos | `revisiones.*` | Inicio |

## Módulos

| Módulo | Qué es | Tablas propias | Permisos | Pestaña |
|---|---|---|---|---|
| **Compras** | Proveedores, recepción de mercancía (entrada con proveedor y remisión), factura del proveedor con renglones, cuentas por pagar, pago desde la gaveta. Sin costo en inventario. | proveedores, recepciones, recepcion_lineas, facturas_proveedor, factura_proveedor_lineas, movimientos_proveedor, pagos_proveedor | `compras.*` | Compras |
| **Almacenes** | Sucursales tipo *almacén* (solo guardan: sin caja ni conteos) y traspasos entre sucursales. | traspasos, traspaso_lineas (y el tipo `almacen` en sucursales) | `almacenes.*` | Almacenes |
| **Conteos** | Conteos físicos: se escanean las piezas y se teclea lo que va en fracciones; el faltante se carga al responsable. | conteos, conteo_lineas | `conteos.*` | Conteos |

## Reglas transversales

- **Una sola puerta al inventario**: todo pasa por `Inventario.mover!`, que escribe el movimiento y la existencia en la misma transacción. Ningún módulo toca `existencias` directo.
- **Libros solo-inserción** para lo que es dinero o deuda (deuda con proveedores, kardex): el saldo es la suma; nada se edita ni se borra; corregir es asentar.
- **Folios por sucursal** con prefijo por documento (B venta, C corte, RC recepción, TG traspaso, K conteo…), únicos por sucursal.
- **Idempotencia** en lo que captura el navegador y podría reenviarse (venta, recepción, traspaso): una clave, y la misma clave devuelve el mismo documento.
- **Autorización diferida**: quien tiene el permiso lo hace a su nombre; quien no, lo hace con motivo y cae en Revisión. TODO: en Sakuya esto se vuelve más estricto de fábrica (ver `decisiones.md`).
- **Tipos de sucursal**: matriz (de donde sale todo), tienda (vende), almacén (solo guarda). Las reglas se derivan del tipo, nunca de una bandera aparte.
- **i18n completa** (inglés por defecto, español, alemán): todo texto visible pasa por `t(...)`, incluidos avisos, errores y JS. En los tests falta una traducción = falla.

## Reglas en Lisp (en construcción)

El núcleo pregunta en puntos fijos (**ganchos**) y una regla escrita en el Lisp de Sakuya contesta. La regla propone, el núcleo dispone: la regla lee por funciones estrechas y devuelve una decisión; nunca escribe en la base. Detalle en `decisiones.md`.

## Cómo se agrega un módulo

1. Clave en `Modulo::OPCIONALES` (y en `DEPENDE` si cuelga de otro, en `ALGUNO` si le basta con uno de varios, en `GIROS` donde arranque encendido, en `comprobar_apagable!` si puede tener trabajo abierto).
2. Sus permisos con prefijo propio en `Permiso` y el prefijo en `Modulo::PERMISOS`; el rol supervisor suele llevar `prefijo.*`.
3. `Ajuste::DEFAULTS["modulos.<clave>"] = "1"`.
4. Sus controladores con `pestana :<clave>` y `modulo :<clave>`; su pestaña en `RibbonHelper::PESTANAS`.
5. Textos `modulos.<clave>.{nombre,que}`, `cinta.pestanas.<clave>`, permisos, en es/en/de.
6. Tests: el flujo, y que apagado desaparece de la cinta y sus pantallas responden 404.
