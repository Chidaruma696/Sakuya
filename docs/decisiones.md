# Decisiones

Por qué Sakuya es como es. Lo más nuevo, arriba.

## El cierre de caja ya pregunta a una regla (3 oct 2026)

El segundo gancho, y el primero que decide algo: al cerrar el corte, la regla lee el conteo en pesos (`(difference)`, `(expected)`, `(limit)`, `(authorized)`…) y contesta `(allow)`, `(to-review "motivo")` o `(reject "motivo")`. La de fábrica usa el tope de Ajustes › Caja. Un rechazo frena a la cajera, pero no a quien tiene `caja.diferencia`: para esa persona cuenta como revisión. No me convence del todo, pero una regla mal escrita no puede dejar una caja sin poder cerrarse a las once de la noche. Si la regla truena decide la de fábrica y el fallo se anota en la revisión del corte. Todavía no hay editor: la regla solo se guarda desde la consola; el editor llega junto al del tablero.

## El primer gancho es el tablero (30 sept 2026)

El tablero de Inicio es el primer programa en Lisp: solo lee, así que es el lugar sin riesgo para estrenar el lenguaje antes de meterlo en la caja. El programa termina en `(dashboard …)` con `(tile …)` y `(panel …)`; las cifras de fábrica (`:sales`, `:tickets`…) también se leen como funciones para calcular las propias, y el dinero llega en pesos con decimales exactos. Si el programa guardado truena, Inicio enseña el de fábrica y un aviso a quien puede arreglarlo; nunca una página rota. Se edita en Ajustes › Opciones avanzadas, el lugar de todo lo que se programa en Lisp, con vista previa y sin guardar hasta que corre, y cada versión se asienta en `reglas` (solo inserción). Permiso nuevo: `reglas.editar`.

## Las reglas del negocio se escriben en Lisp (30 sept 2026)

Cada negocio quiere algo distinto en los mismos puntos: uno vende a crédito y otro jamás, uno aguanta cien pesos de diferencia en la caja y otro ni uno, uno deja bajar el precio a la mitad y otro nunca. Meter cada variante como un ajuste más acaba en una pantalla de mil casillas; programarla a mano para cada cliente acaba en mil ramas. La salida es la de Emacs o AutoCAD: un núcleo fijo y un lenguaje dentro para lo que cambia.

Cómo va a ser:

- **Un Lisp pequeño escrito en Ruby, dentro de la app.** No es Common Lisp ni Scheme completos: lector, `eval`, `define`, `lambda`, `let`, `if`, `cond`, listas y mapas. El dinero es `BigDecimal`, nunca flotante.
- **La regla propone, el núcleo dispone.** Una regla lee por funciones estrechas (`(stock product branch)`, `(total sale)`…) y devuelve una decisión: `(allow)`, `(reject "motivo")`, `(to-review "motivo")` o un valor (un precio). El núcleo la aplica por sus caminos de siempre. Ninguna regla escribe en la base, así que ninguna puede saltarse `Inventario.mover!` ni editar un libro.
- **Sandbox por construcción.** Solo existen las funciones que Sakuya registra: no hay archivos, ni red, ni procesos. Cada regla corre con un contador de pasos y un límite de recursión, porque va dentro de la transacción de una venta y un bucle infinito no puede congelar la caja. Si una regla truena, se aplica lo de fábrica y el fallo cae en Revisión.
- **Ganchos con contrato y versión.** Cada punto donde el núcleo pregunta (cerrar una venta, el precio de un renglón, la diferencia del corte, recibir mercancía) dice qué recibe y qué puede devolver, y lleva versión. Es lo que evita el problema de Odoo: personalizas, actualizas y todo se rompe.
- **Las reglas son datos.** Viven en una tabla de solo inserción con quién cambió qué y cuándo; volver atrás es asentar la versión anterior. Se editan en la app con revisión de sintaxis y con permiso propio, se prueban en seco contra una venta real dentro de una transacción que se deshace, y se exportan como un archivo por negocio.
- **Todo en inglés.** Las funciones del Lisp se llaman en inglés (`allow`, `reject`), como Emacs; lo que cambia de idioma es la interfaz, no el lenguaje de las reglas.
- **Después:** un REPL de solo lectura en el navegador para preguntarle cosas a los datos en vivo, y plugins en Lisp de la comunidad, incluidas traducciones de la interfaz a más idiomas.

Por qué un Lisp propio y no Ruby: Ruby ajeno no se puede ejecutar seguro desde que Ruby 3 quitó `$SAFE`; un evaluador propio solo sabe hacer lo que le das. Y por qué no Common Lisp de verdad como servicio aparte: dos runtimes, un salto de red en cada regla y las reglas lejos de la transacción.

## Más estricto de fábrica (30 sept 2026)

Lo que necesita a un supervisor, de fábrica, lo espera: la regla general no es "se hace con motivo y se revisa después", es "se frena". El negocio que lo quiera más suelto lo relaja con una regla. Los roles de fábrica ya van con lo justo: la caja vende, abre, retira y ve el inventario; devolver dinero es de supervisor y recibir mercancía es de almacén. Frenar y reportar: lo irregular no pasa y el intento queda en Revisión a nombre de quien lo hizo, para que nada se pierda aunque no haya pasado. Desde el 3 oct 2026 así va el cierre de caja: fuera del tope, la cajera no cierra ni con motivo y su intento queda reportado; cierra quien tiene `caja.diferencia`, con motivo, y también queda por revisar. TODO: los retiros, los precios abajo del catálogo y los ajustes de inventario todavía van con la autorización diferida (se hace con motivo y se revisa después); pasan a frenar cuando les toque su gancho.

## Sakuya arranca solo con lo genérico (30 sept 2026)

Lo que le sirve a cualquier negocio: caja, inventario, administración, ajustes, revisión, compras, almacenes y conteos. Pedidos y clientes con crédito llegan después como módulos propios; el crédito, prohibido de fábrica y permitido por regla. El esquema arranca en una sola migración.

## Decisiones de base

- **Rails y SQLite.** Un POS que no cobra el primer día no sirve; Rails con Hotwire da pantallas rápido. SQLite en modo IMMEDIATE aguanta una tienda; PostgreSQL entra cuando haya varias sucursales pegando a la vez.
- **Una sola puerta al inventario y libros de solo inserción.** Corregir es asentar, nunca editar.
- **Folios por sucursal, con el prefijo que elija el negocio**, o una sola numeración corrida. El contador va por documento, no por letra.
- **El primer administrador se crea desde la pantalla**, no desde las semillas; mientras no hay usuarios, todo lleva a `/instalar`.
- **Un solo esquema y módulos que se apagan.** El giro que se elige al arrancar solo es un preset.
- **El ticket se diseña viendo el ticket.**
- **Compras sin costo en inventario**: el precio de compra solo vive en la factura.
- **Contar la gaveta por billetes y monedas**, con un tope de diferencia.
- **Tres idiomas, inglés por defecto.** Los modelos y las claves siguen en español.
- **Apache 2.0.** Que se use, se cambie y hasta se venda.
