# Numeración de objetos para AutoCAD / AutoCAD Object Numbering

Herramienta AutoLISP para numerar automáticamente objetos en AutoCAD mediante etiquetas consecutivas.

**Comando:** `NOBJ`

Ejemplo:

`0001 → 0002 → 0003 → 0004 → ...`

El proyecto está pensado principalmente para trabajos de arquitectura, ingeniería, cuantificación y documentación de planos.

---

# Español (MX)

## Funciones principales

- Numeración consecutiva automática.
- Formato mínimo de **4 dígitos**:
  - `0001`
  - `0002`
  - `0125`
  - `9999`
  - `10000`
- Selección individual de objetos.
- Selección múltiple mediante ventana.
- Compatible con selección Window y Crossing.
- Recuadro automático alrededor de cada número.
- Ancho del recuadro adaptable al contenido.
- Utiliza el **Layer actual** de AutoCAD.
- Grosor de línea del recuadro: 0,30 mm.
- Una sola operación de **UNDO / Ctrl+Z** elimina toda la numeración generada en una ejecución.

---

## Ubicación de la numeración

El usuario puede elegir:

- `C` = Centro
- `A` = Arriba
- `D` = Derecha
- `I` = Izquierda
- `AB` = Abajo

La opción predeterminada es:

**Arriba**

---

## Orden de numeración

La numeración puede ordenarse mediante:

- `IzqDer` = Izquierda → Derecha
- `DerIzq` = Derecha → Izquierda
- `ArrAba` = Arriba → Abajo
- `AbaArr` = Abajo → Arriba
- `Seleccion` = Orden de selección

La opción predeterminada es:

**IzqDer**

---

## Escala automática

La versión actual está diseñada para dibujos realizados en **metros** dentro de Model Space.

La escala predeterminada es:

**1:100**

El tamaño de la etiqueta se calcula automáticamente según la escala.

Ejemplos:

| Escala | Altura del recuadro |
|---|---:|
| 1:50 | 0.05 m |
| 1:75 | 0.075 m |
| 1:100 | 0.10 m |
| 1:150 | 0.15 m |
| 1:200 | 0.20 m |

También se pueden utilizar otras escalas escribiendo directamente el denominador.

Ejemplo:

`175` = escala `1:175`

---

## Proporciones automáticas

A escala **1:100**:

- Recuadro: `0.10 m`
- Texto: `0.06 m`
- Separación: `0.025 m`

Las proporciones utilizadas son:

- Texto = **60 %** de la altura del recuadro.
- Separación = **25 %** de la altura del recuadro.
- Margen horizontal = **15 %** por cada lado.

Tanto la altura del recuadro como la separación pueden modificarse manualmente durante la ejecución del comando.

---

## Tratamiento especial de líneas

Las entidades `LINE` tienen un comportamiento especial.

### Líneas inclinadas

El texto y el recuadro:

- mantienen la misma inclinación de la línea;
- permanecen paralelos al elemento;
- se colocan usando el punto medio real de la línea;
- mantienen la separación configurada.

La orientación del texto se ajusta para conservar una lectura correcta.

### Líneas verticales

En líneas verticales o casi verticales:

- la etiqueta permanece centrada respecto al punto medio;
- texto y recuadro permanecen paralelos a la línea;
- `I` coloca la etiqueta al lado izquierdo;
- `D` coloca la etiqueta al lado derecho;
- `C` coloca la etiqueta sobre el centro;
- `A` y `AB` utilizan posiciones laterales para evitar mandar la etiqueta a los extremos de la línea.

---

## Instalación

1. Descarga `Numeracion_de_objetos.lsp`.
2. Abre AutoCAD.
3. Escribe:

`APPLOAD`

4. Selecciona `Numeracion_de_objetos.lsp`.
5. Presiona **Load / Cargar**.
6. Cierra APPLOAD.
7. Escribe:

`NOBJ`

---

## Uso básico

Al ejecutar `NOBJ` aparecerán opciones similares a:

```text
Numero inicial <1>:

Escala de impresion 1:<100>:

Altura del recuadro <0.10>:

Separacion respecto al objeto <0.025>:

Ubicacion
[Centro/Arriba/Derecha/Izquierda/Abajo] <Arriba>:

Orden
[Seleccion/IzqDer/DerIzq/ArrAba/AbaArr] <IzqDer>:

Seleccione los objetos a numerar:
```

Presionar **Enter** acepta el valor predeterminado.

---

## Pruebas realizadas

La versión actual fue probada visualmente en AutoCAD con:

- Círculos.
- Líneas horizontales.
- Líneas verticales.
- Líneas inclinadas.
- Centro.
- Arriba.
- Abajo.
- Derecha.
- Izquierda.
- Numeración consecutiva.
- Rotación de etiquetas en entidades LINE.
- Separación automática.
- `Ctrl + Z / UNDO` de una ejecución completa.

---

## Versión actual

**v1.5**

Primera versión preparada para publicación pública.

---

## Limitaciones actuales

- El cálculo automático de escala está pensado para dibujos realizados en **metros**.
- Esta versión trabaja principalmente en **Model Space**.
- No detecta automáticamente si el dibujo está realizado en metros o milímetros.
- Otros tipos de objetos utilizan principalmente su bounding box para determinar la posición de la etiqueta.

---

## Licencia

Este proyecto se distribuye bajo la **MIT License**.

Puede utilizarse, modificarse y distribuirse respetando los términos de dicha licencia.

---

# 🇺🇸 English

## AutoCAD Object Numbering

AutoLISP productivity tool for automatic sequential numbering of AutoCAD objects.

**Command:** `NOBJ`

Main features:

- Automatic sequential numbering.
- Minimum four-digit format.
- Individual and multiple selection.
- Window and Crossing selection.
- Automatic adaptive label frame.
- Current AutoCAD layer.
- Automatic print-scale-based sizing.
- Manual label size and spacing options.
- Center / Top / Right / Left / Bottom placement.
- Multiple numbering order options.
- Special handling for AutoCAD `LINE` entities.
- Line labels rotate to remain parallel to the selected line.
- Single-step Undo for each NOBJ execution.

### Default configuration

- Scale: `1:100`
- Label frame height: `0.10 m`
- Text height: `60%`
- Automatic spacing: `25%`
- Horizontal margin: `15%`
- Default position: `Top`
- Default numbering order: `Left to Right`

### Installation

1. Download `Numeracion_de_objetos.lsp`.
2. Open AutoCAD.
3. Run `APPLOAD`.
4. Load the LISP file.
5. Type `NOBJ`.

---

## Project status

**Version 1.5**

Initial public release.

Suggestions, testing, bug reports and contributions are welcome.
