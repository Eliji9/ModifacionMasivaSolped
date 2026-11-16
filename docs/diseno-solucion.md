# Diseño de solución – Modificación masiva de solpeds (imputación A + activo fijo)

## 1. Requerimiento

Modificar de forma masiva las posiciones de solicitudes de pedido de traslado (`ZUB*`, p. ej. `ZUBH`)
para:

1. Cambiar el tipo de imputación de la posición a **A – Activo fijo**.
2. Asignar el **activo fijo** en la pestaña *Imputación* de la posición (campos *Activo fijo* y *SNº*).

Condiciones:

- La solped no debe tener orden de compra creada.
- La solped no debe estar aprobada.
- La posición debe existir y el activo fijo también.
- Las validaciones y el resultado de la modificación se muestran en un log.

## 2. Alcance y restricciones

- Sistema: **S/4HANA Cloud Private Edition 2023**, desarrollo **ABAP Cloud (Tier 1)**.
- Aprobación de solpeds con **workflow flexible**.
- **Una solped por archivo**; el archivo puede ser grande por la cantidad de posiciones.
- Si una posición falla, **se modifican las demás**; el log muestra correctas y con error.
- App sencilla: el usuario sube el archivo, procesa y ve el log. No se necesita historial funcional.

## 3. Formato del archivo

Excel `.xlsx`, primera hoja:

| Fila | A | B | C |
|---|---|---|---|
| 1 | Nº de solped (ej. `40000802`) | | |
| 2..n | Posición (ej. `10`) | `A` | Activo fijo (ej. `140000000003`) o `activo-subnúmero` (ej. `140000000003-1`) |

- Subnúmero por defecto `0`.
- La columna C debe tener formato **Texto**: un activo en notación científica (`1,4E+11`) se rechaza.
- Se ignoran filas vacías y se toleran espacios, comillas y valores numéricos tipo `10.0`.

## 4. Opciones evaluadas

### Opción A – Reporte clásico con `BAPI_PR_CHANGE` (descartada)

Reporte con `GUI_UPLOAD`, lectura de `EBAN` / `EBKN` / `ANLA`, `BAPI_PR_CHANGE` y log en ALV.

- **Descartada:** no es Clean Core (API no liberada, acceso a tablas estándar, GUI y ALV).

### Opción B – App RAP síncrona (elegida)

1. El usuario crea una carga y sube el `.xlsx` (campo de objeto grande en RAP).
2. **Simular:** lee el Excel con XCO, valida y escribe el log. No modifica la solped.
3. **Procesar:** valida y modifica la solped con EML sobre el BO estándar `I_PurchaseRequisitionTP`.
4. La acción **no hace COMMIT**: RAP graba la solped y el log al final de la petición.
5. El log aparece en la misma pantalla al terminar.

- **Clean Core:** 100 % Tier 1 (solo APIs liberadas C1).
- **Limitación:** si SAP rechaza la solped completa en el momento de grabar, no se graba nada y
  Fiori muestra el mensaje estándar. El usuario corrige y vuelve a procesar.

### Opción C – App RAP + Background Processing Framework (en reserva)

Igual que B, pero *Procesar* registra una operación bgPF que graba todas las posiciones juntas y,
si SAP rechaza el grabado conjunto, reintenta **posición por posición** con `COMMIT ENTITIES`.

- **En reserva:** requiere configuración de bgRFC/bgPF (Basis), el log se ve al actualizar la
  pantalla y agrega una clase y un saver. Está en el historial del repo (commit `20d5304`).

## 5. Flujo de la opción B

```
Usuario ──► Crear carga ──► Subir .xlsx ──► Guardar
                                              │
                         ┌────────────────────┴────────────────────┐
                         ▼                                         ▼
                     Simular                                   Procesar
                         │                                         │
            ZCL_SOLPED_IMPUT_PROC (iv_test = X)       ZCL_SOLPED_IMPUT_PROC (iv_test = space)
            · Lee Excel (XCO_CP_XLSX)                 · Lee Excel y valida (igual que Simular)
            · Valida solped y posiciones              · MODIFY ENTITIES OF i_purchaserequisitiontp
                         │                                         │
                         └──────────────► Log + resumen ◄──────────┘
                                   (RAP graba al final de la petición)
```

## 6. Validaciones

| Nivel | Validación | Fuente | Si falla |
|---|---|---|---|
| Archivo | Primera fila solo con el nº de solped | Excel | No se procesa |
| Fila | Posición numérica, columna B = `A`, activo informado, sin notación científica, sin repetir | Excel | Se omite la posición |
| Solped | Existe | `I_PurchaseRequisitionItemAPI01` | No se modifica nada |
| Solped | Clase de documento `ZUB*` | `PurchaseRequisitionType` | No se modifica nada |
| Solped | No aprobada (workflow flexible) | `ProcessingStatus <> '05'` | No se modifica nada |
| Solped | Sin orden de compra ni cantidad pedida | `PurchasingDocument`, `OrderedQuantity` | No se modifica nada |
| Posición | Existe, no borrada, no cerrada | `IsDeleted`, `IsClosed` | Se omite la posición |
| Posición | Activo existe en la sociedad de la posición | `I_FixedAsset` | Se omite la posición |
| Posición | Una sola línea de imputación | `_PurchaseReqnAcctAssgmt` | Se omite la posición |

## 7. Modificación de la solped

Un `MODIFY ENTITIES OF i_purchaserequisitiontp` **por posición** (así cada mensaje de SAP queda asociado a su posición):

| Entidad | Operación | Campos |
|---|---|---|
| `PurchaseRequisitionItem` | `UPDATE` | `AccountAssignmentCategory = 'A'` |
| `PurchaseRequisitionItem` → `_PurchaseReqnAcctAssgmt` | `CREATE BY` (si la posición no tiene imputación) | `MasterFixedAsset`, `FixedAsset`, `Quantity` (cantidad total) |
| `PurReqnItmAccountAssignment` | `UPDATE` (si ya tiene línea de imputación) | `MasterFixedAsset`, `FixedAsset` |

- Tipo e imputación van en el **mismo LUW**, como exige el estándar al cambiar el tipo de imputación.
- La **cuenta de mayor no se envía**: SAP la deriva de la clase del activo.
- Si SAP rechaza una posición (FAILED o cualquier mensaje de error, p. ej. `ME045` cuenta de mayor no
  utilizable), la posición se deja como estaba: se restaura el activo anterior o se borra la línea de
  imputación creada, y se devuelve el tipo de imputación original. El **mensaje exacto de SAP** (texto,
  clase y número) va al log de esa posición.
- La autorización la valida el BO estándar (el EML se ejecuta sin `IN LOCAL MODE`).

## 8. Log

Tabla `ZTMM_SOLPED_LG`, hija de la carga. En la app se ve como sección **Log** de la carga.

| Columna en la lista | Detalle (Object Page) |
|---|---|
| Estado (semáforo), Fila, Posición, Imput. anterior, Imput. nueva, Activo fijo, Subnúm., Paso, Mensaje | Solped, Sociedad, Tipo de mensaje, Origen (propia / SAP), Clase y número de mensaje, Creado por, Creado el |

- Cada posición del archivo tiene al menos una línea: **Correcto** o **Error**.
- Pasos: *Lectura de archivo*, *Validación*, *Modificación*.
- Cada ejecución reemplaza el log anterior de la carga.
- La cabecera de la carga guarda el resumen: estado, modo, posiciones, correctas, con error.

## 9. Limitaciones conocidas

- Si SAP rechaza la solped completa al grabar, no se graba nada (ver opción C).
- No se soportan posiciones con **imputación múltiple**.
- No se valida si el activo está dado de baja (depende de los campos disponibles en `I_FixedAsset`).
- La tabla de cargas guarda el archivo; no hay borrado automático (se puede eliminar desde la app).
