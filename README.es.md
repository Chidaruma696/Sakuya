[🇬🇧 English](README.md)

<div align="center">

# 咲夜

**Sakuya** · <sub>*un punto de venta y trastienda que se dobla con Lisp*</sub>

*"El tiempo se detiene hasta que las cuentas cuadran."*

</div>

<br/>

Sakuya lleva un negocio pequeño desde un solo servidor: la caja, el inventario por sucursal, las compras a proveedores, los conteos y los traspasos entre sucursales. Es estricto de fábrica. Cada operación vive en una transacción, el dinero va en centavos enteros, los libros son de solo inserción, y lo que necesita a un supervisor lo espera o queda registrado para revisión.

Cada negocio trabaja distinto, y Sakuya está pensado para doblarse a eso. El núcleo es fijo; las reglas alrededor (quién puede vender a crédito, cuánta diferencia en la caja es demasiada, hasta dónde puede bajar un precio) se escribirán en un Lisp pequeño que vive dentro de la aplicación, como Emacs vive dentro de Emacs Lisp. Esa parte todavía se está construyendo.

Ruby on Rails, SQLite, Hotwire. La interfaz habla inglés, español y alemán.

<br/>

## Qué hace hoy

| Área | Qué tiene |
|---|---|
| Caja | Vender por código de barras, PLU o clave, pagos mixtos, ticket con su propio código, devoluciones solo con ticket, corte contado por billetes y monedas, retiros |
| Inventario | Existencias por sucursal y producto, kardex de solo inserción, entradas y ajustes a mano que pasan a revisión si se hacen sin permiso |
| Administración | Productos, códigos de barras, precios por sucursal, promociones, usuarios, roles, sucursales |
| Revisión | Lo que se hace sin el permiso se hace con motivo y espera a que un supervisor lo apruebe o se lo cargue a alguien |
| Compras | Proveedores, recepción de mercancía, facturas del proveedor, cuentas por pagar, pago desde la caja |
| Almacenes | Sucursales que solo guardan y traspasos entre sucursales |
| Conteos | Conteos totales o parciales; el conteo manda y el faltante se carga al responsable |

Compras, almacenes y conteos son módulos: cada negocio enciende lo que necesita.

<br/>

## Correrlo

```sh
bin/setup        # gemas, base de datos, semillas
bin/dev          # http://localhost:3000
```

La primera vez, con la base vacía, Sakuya pide el nombre del negocio, la matriz y el primer administrador, y entra con él. Las semillas solo crean los roles base. Tests: `bin/rails test`.

<br/>

## El tablero, en Lisp

El tablero de Inicio es un programa, y el primer lugar donde Sakuya se dobla. De fábrica se ve así:

```lisp
(dashboard
  (tile :sales)
  (tile :tickets)
  (tile :average-ticket)
  (panel :top-products))
```

Cambia el orden, quita lo que no miras o calcula tus propias cifras:

```lisp
(define margin (- (sales) (returns)))
(dashboard
  (tile "Margen" margin :money)
  (tile "Por día" (/ (sales) (days)) :money)
  (when (> (returns) 0) (tile :returns))
  (panel :top-products 5))
```

Se edita en Ajustes › Opciones avanzadas › Tablero en Lisp, con vista previa; no se guarda nada hasta que corre, cada versión se conserva, y si alguna vez una guardada falla, sale el tablero de fábrica.

<br/>

## Lo que viene

- **Las reglas en Lisp, en la caja.** El mismo Lisp pequeño. Una regla lee lo que necesita por funciones estrechas y responde con una decisión (`(allow)`, `(reject "motivo")`, `(to-review "motivo")`, un precio); el núcleo la aplica por sus caminos de siempre, así que ninguna regla puede saltarse el kardex ni editar un libro. Las reglas llevan versión, se prueban en seco contra datos reales antes de entrar en vigor, y una regla que falla cae al comportamiento de fábrica y queda en revisión. Los ganchos (cerrar una venta, el precio de un renglón, la diferencia del corte, recibir mercancía) son un contrato con versión.
- **Más estricto de fábrica, relajado con reglas.** Lo que necesita a un supervisor lo espera. El negocio que lo quiera más suelto lo dice en una regla.
- **Clientes y crédito, y pedidos**, como módulos propios.
- **Plugins en Lisp**, incluidas traducciones de la interfaz a otros idiomas.
- Impresión por ESC/POS, una caja que aguante que se caiga la red, PostgreSQL para muchas sucursales.

En `docs/decisiones.md` están las razones de cada decisión; en `docs/arquitectura.md`, el mapa de módulos.

<br/>

## Licencia

Apache 2.0.

Sakuya Izayoi y Touhou Project pertenecen a Team Shanghai Alice (ZUN). El nombre es un homenaje de fan, no oficial y sin afiliación, hecho según sus directrices para obras derivadas.
