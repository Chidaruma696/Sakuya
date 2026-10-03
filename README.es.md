[🇬🇧 English](README.md)

<div align="center">
  <br/>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/logo/sakuya-logo-w.png">
  <img src="docs/logo/sakuya-logo-b.png" width="140" alt="Sakuya">
</picture>

# Sakuya

**咲 · Punto de venta y trastienda para negocios pequeños que se dobla con Lisp: la caja, el inventario por sucursal, las compras, los almacenes y los conteos, con las reglas alrededor escritas en un Lisp pequeño que vive dentro de la aplicación. Ruby on Rails.**

<br/>

![Rails 8.1](https://img.shields.io/badge/rails-8.1-cc0000?style=for-the-badge&logo=rubyonrails&logoColor=white)
![Ruby 3.4](https://img.shields.io/badge/ruby-3.4-cc342d?style=for-the-badge&logo=ruby&logoColor=white)
![SQLite](https://img.shields.io/badge/sqlite-un%20servidor-003b57?style=for-the-badge&logo=sqlite&logoColor=white)
![Lisp](https://img.shields.io/badge/reglas-lisp-4659a8?style=for-the-badge)
![Licencia Apache 2.0](https://img.shields.io/badge/licencia-Apache_2.0-1c2139?style=for-the-badge)

<br/>

*Dinero en centavos enteros · libros de solo inserción · una transacción por operación · estricto de fábrica, relajado con reglas*

</div>

---

> [!NOTE]
> Sakuya lleva un negocio pequeño desde **un solo servidor**, para la matriz y sus sucursales. El núcleo es fijo; lo que cada negocio hace distinto (quién vende a crédito, cuánta diferencia en la caja es demasiada, hasta dónde puede bajar un precio) está pensado para vivir en reglas escritas en Lisp, como Emacs vive dentro de Emacs Lisp. El tablero de Inicio y las reglas de la caja, el inventario y las compras ya funcionan.

> [!IMPORTANT]
> **Sakuya es software experimental en su primera fase.** Puede tener errores y bastantes cosas van a cambiar entre versiones. Si quieres probarlo en tu negocio, adelante: hazlo con calma, respalda la base de datos a menudo y conserva tu sistema actual hasta que se gane tu confianza. Se comparte tal cual, sin garantía (como dice la [licencia Apache 2.0](LICENSE)), y no puedo hacerme responsable de lo que pase por su uso ni de los errores que tenga. Si encuentras uno, abrir un [issue](https://github.com/Chidaruma696/Sakuya/issues) ayuda mucho.

<br/>

## 🏪 Qué es

Un sistema, una base de datos y **módulos que se encienden o se apagan según el negocio**. La caja, el inventario, la administración, los ajustes y la revisión siempre están; lo demás se cambia en Ajustes. La primera vez, con la base vacía, pide el nombre del negocio, la matriz, el giro y el primer administrador, y entra con él.

| Giro | Módulos que arrancan encendidos |
|---|---|
| **Una tienda** | caja, inventario, compras y conteos. |
| **Varias sucursales** | lo de una tienda más almacenes y traspasos entre sucursales. |
| **Todo encendido** | todos los módulos. |

| Área | Qué hace | Regla que impone |
|---|---|---|
| **Caja** | Vender por código de barras, PLU o clave, pagos mixtos, ticket con su propio código, corte contado por billetes y monedas, retiros. | Devoluciones solo con ticket. La caja se cierra contando el dinero. |
| **Inventario** | Existencias por sucursal y producto, entradas y ajustes a mano. | El kardex es de solo inserción. Un ajuste sin permiso se frena y queda reportado. |
| **Administración** | Productos, códigos de barras, precios por sucursal, promociones, usuarios, roles, sucursales. | Administración es el catálogo; Ajustes es cómo trabaja el negocio. Son pantallas distintas. |
| **Revisión** | Lo que una regla frenó y lo que pasó con permiso pero hay que mirar. | Nada irregular se pierde: un supervisor lo aprueba u observa, y puede cargárselo a alguien. |
| **Compras** *(módulo)* | Proveedores, recepción de mercancía, facturas del proveedor, cuentas por pagar, pago desde la caja. | Solo la factura crea deuda. El dinero sale de la caja por un único camino. |
| **Almacenes** *(módulo)* | Sucursales que solo guardan y traspasos entre sucursales. | Un almacén no tiene caja. Un traspaso sale y entra en una sola transacción. |
| **Conteos** *(módulo)* | Conteos totales o parciales, escaneando piezas por su código; lo que va por kilo, litro o metro se teclea. | El conteo manda, y el faltante se carga al responsable. |
| **Clientes** *(módulo, apagado de fábrica)* | Clientes, venta a cuenta, abonos en la caja, estado de cuenta y pedidos que se cobran en la caja. | De fábrica no se fía a nadie: el crédito lo decide una regla en Lisp. |

Roles de fábrica: administrador, cajero (vender, abrir caja, retiros, ver inventario), almacenista y supervisor. La interfaz habla inglés, español y alemán.

<br/>

## 🔪 El tablero, en Lisp

El tablero de Inicio es un programa, y el primer lugar donde Sakuya se dobla. De fábrica es esto:

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

Se edita en **Ajustes › Opciones avanzadas › Tablero en Lisp**, con una vista previa que se puede llenar con cifras de prueba. No se guarda nada hasta que corre, se conservan todas las versiones, y si alguna guardada llega a romperse, aparece el tablero de fábrica.

<br/>

## ⚖️ Las reglas que deciden

Cada punto delicado le pregunta a una regla antes de hacer nada: el precio de cada renglón, la venta entera antes de cobrarla, el cierre del corte, los retiros, las entradas, ajustes y mermas, lo que llega del proveedor y su factura. La regla contesta `(allow)`, `(to-review "motivo")` o `(reject "motivo")`:

```lisp
; Precio: rebajas chicas pasan, medianas se revisan, la cátsup nunca baja
(cond ((= (discount) 0) (allow))
      ((= (product) "CATS") (reject "La cátsup no se rebaja"))
      ((<= (discount) 5) (allow))
      (else (to-review "Rebaja mediana")))
```

De fábrica, todo lo irregular **se frena y se reporta**: no pasa y el intento queda en Revisión a nombre de quien lo hizo. Quien tiene el permiso nunca se queda atorado; para esa persona, frenar es pasar y quedar por revisar. Cada regla se prueba en su editor contra lo de verdad (el corte abierto, una venta ya cobrada, una factura registrada), guarda la versión del contrato de su gancho y todas viajan juntas en un archivo `.lisp` para respaldarlas o llevarlas a otro negocio. Y para preguntarle cosas a los datos en vivo hay un REPL de solo lectura: `(sort-by-desc :balance (customers))`.

El Lisp es propio de Sakuya, escrito en Ruby (`lib/lisp*.rb`): un lector, un evaluador con límite de pasos y de profundidad, decimales para el dinero y funciones con nombre en inglés. Un programa solo puede llamar lo que la aplicación le da; no toca archivos, ni la red, ni la base de datos directamente.

<br/>

## 🧭 Diseño

- **La regla propone, el núcleo dispone.** Una regla responde con una decisión (`(allow)`, `(reject "motivo")`, `(to-review "motivo")`) y el núcleo la aplica por sus caminos de siempre, así que ninguna regla puede saltarse el kardex ni editar un libro.
- **Estricto de fábrica.** Lo que necesita a un supervisor lo espera. El negocio que lo quiera más suelto lo dice en una regla, y esa regla lleva versión y se prueba en seco contra datos reales antes de entrar en vigor.
- **Los ganchos son un contrato.** Cerrar una venta, el precio de un renglón, la diferencia del corte, recibir mercancía: cada gancho lleva versión, para que actualizar Sakuya no rompa las reglas de un negocio.
- **Una transacción por operación, dinero en centavos enteros, libros a los que solo se añade.** Cancelar compensa; nada se edita en su sitio.

En `docs/decisiones.md` están las razones de cada decisión; en `docs/arquitectura.md`, el mapa de módulos.

<br/>

## 🗺️ Hoja de ruta

- **Pedidos de sucursal a la matriz** con mínimos y máximos, y que un pedido de cliente pueda apartar existencias.
- **Plugins en Lisp**, incluidas traducciones de la interfaz a otros idiomas.
- Impresión por ESC/POS, una caja que aguante que se caiga la red, PostgreSQL para muchas sucursales.

<br/>

## 🚀 Correrlo

```sh
bin/setup        # gemas, base de datos, semillas
bin/dev          # http://localhost:3000
```

Las semillas solo crean los roles base; lo demás sale del primer arranque. Tests (124 hoy): `bin/rails test`.

<br/>

## 📚 Créditos y nombres

Sakuya Izayoi y Touhou Project pertenecen a Team Shanghai Alice (ZUN). El nombre y los dos cuchillos cruzados del logo son un homenaje de fan, no oficial y sin afiliación, hecho según sus directrices para obras derivadas.

<br/>

## 📄 Licencia

Apache 2.0. Ver [LICENSE](LICENSE) y [NOTICE](NOTICE).
