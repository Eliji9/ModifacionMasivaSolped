# Modificación masiva de solpeds – Imputación A + Activo fijo

App Fiori Elements V4 (RAP, ABAP Cloud, 100 % Clean Core) para **S/4HANA Cloud Private Edition 2023**.

El usuario sube un Excel con **una solped** y sus posiciones; la app cambia el tipo de imputación de cada
posición a **A (Activo fijo)** y asigna el **activo fijo / subnúmero** en la línea de imputación
(pestaña *Imputación* de ME52N). Muestra un log por posición.

## Formato del archivo (.xlsx, primera hoja)

| Fila | A | B | C |
|---|---|---|---|
| 1 | Nº de solped (ej. `40000802`) | | |
| 2..n | Posición (ej. `10`) | `A` | Activo fijo (ej. `140000000003`) o `activo-subnúmero` (ej. `140000000003-1`) |

- Una sola solped por archivo. Subnúmero por defecto `0`.
- Formatear la columna C como **Texto** (si Excel muestra `1,4E+11`, la fila se rechaza).

## Reglas

| Nivel | Validación | Resultado si falla |
|---|---|---|
| Solped | Existe | No se modifica nada |
| Solped | Clase de documento `ZUB*` | No se modifica nada |
| Solped | No aprobada (workflow flexible, `ProcessingStatus = '05'`) | No se modifica nada |
| Solped | Sin orden de compra ni cantidad pedida en ninguna posición | No se modifica nada |
| Posición | Fila válida (posición numérica, columna B = `A`, activo informado, sin repetir) | Se omite la posición |
| Posición | Existe en la solped, no borrada, no cerrada | Se omite la posición |
| Posición | Activo fijo existe en la sociedad de la posición (`I_FixedAsset`) | Se omite la posición |
| Posición | Una sola línea de imputación (no imputación múltiple) | Se omite la posición |

Las posiciones con error se informan en el log y **las demás se modifican**.

## Cómo modifica la solped (sin dumps por COMMIT)

**Simular** (síncrono): lee el archivo y valida. No modifica la solped. El log aparece al terminar.

**Procesar** (segundo plano con bgPF):

1. La acción `procesar` **no modifica ni hace COMMIT**: borra el log anterior y deja la carga *En proceso*.
2. El saver (`save_modified`) registra la operación bgPF `ZCL_SOLPED_IMPUT_BGPF` con `save_for_execution( )`
   (el framework RAP hace el commit de ese registro).
3. La operación bgPF corre **fuera** de la transacción RAP de la app; ahí sí se permite `COMMIT ENTITIES`:
   - Lee y valida el archivo. Las posiciones con error de validación se omiten.
   - **Intento 1:** un solo `MODIFY` de todas las posiciones válidas + `COMMIT ENTITIES`.
   - **Intento 2 (solo si SAP rechaza el grabado conjunto):** `ROLLBACK ENTITIES` y se graba **posición por posición**
     (un `MODIFY` + `COMMIT ENTITIES` por posición). Así una posición con error nunca impide grabar las demás.
   - Graba el log y el resumen (correctas / con error) y deja la carga *Procesada* o *Procesada con errores*.
4. El usuario actualiza la pantalla para ver el log.

En cada posición:
- `UPDATE` de `AccountAssignmentCategory = 'A'` en el ítem.
- Si ya tiene línea de imputación → `UPDATE` de `MasterFixedAsset` / `FixedAsset`; si no → `CREATE BY \_PurReqnAcctAssgmt`
  con activo, subnúmero y la cantidad total del ítem. La cuenta de mayor **no se envía**: SAP la deriva de la clase del activo.
- Si SAP rechaza la posición al modificar, se le devuelve su tipo de imputación original.

**Log:** todas las posiciones del archivo quedan en el log, con estado *Correcto* o *Error*, más los mensajes de SAP
(clase y número) cuando el estándar rechaza algo.

## Objetos

| Orden | Objeto | Tipo | Archivo |
|---|---|---|---|
| 1 | `ZTMM_SOLPED_UP` | Tabla (archivo + resumen) | `src/01_tablas/ZTMM_SOLPED_UP.tabl` |
| 2 | `ZTMM_SOLPED_LG` | Tabla (log) | `src/01_tablas/ZTMM_SOLPED_LG.tabl` |
| 3 | `ZR_SOLPED_LOG` | CDS view entity (hija) | `src/02_cds/ZR_SOLPED_LOG.ddls` |
| 4 | `ZR_SOLPED_UP` | CDS root view entity | `src/02_cds/ZR_SOLPED_UP.ddls` |
| 5 | `ZR_SOLPED_UP` | Behavior definition (managed, draft) | `src/03_comportamiento/ZR_SOLPED_UP.bdef` |
| 6 | `ZTMM_SOLPED_UP_D`, `ZTMM_SOLPED_LG_D` | Tablas draft | Generarlas con el *quick fix* (Ctrl+1) en la BDEF |
| 7 | `ZCL_SOLPED_IMPUT_PROC` | Clase (lectura, validaciones, EML) | `src/03_comportamiento/ZCL_SOLPED_IMPUT_PROC.clas.abap` |
| 7b | `ZCL_SOLPED_IMPUT_BGPF` | Clase operación bgPF | `src/03_comportamiento/ZCL_SOLPED_IMPUT_BGPF.clas.abap` |
| 8 | `ZBP_R_SOLPED_UP` | Behavior pool (handler + saver) | `...ZBP_R_SOLPED_UP.clas.abap` + pestaña *Local Types*: `...clas.locals_imp.abap` |
| 9 | `ZC_SOLPED_LOG`, `ZC_SOLPED_UP` | CDS proyección | `src/02_cds/ZC_*.ddls` |
| 10 | `ZC_SOLPED_LOG`, `ZC_SOLPED_UP` | Metadata extensions | `src/02_cds/ZC_*.ddlx` |
| 11 | `ZC_SOLPED_UP` | Behavior definition proyección | `src/03_comportamiento/ZC_SOLPED_UP.bdef` |
| 12 | `ZUI_SOLPED_IMPUT` | Service definition | `src/04_servicio/ZUI_SOLPED_IMPUT.srvd` |
| 13 | `ZUI_SOLPED_IMPUT_O4` | Service binding **OData V4 – UI** | Crear en ADT sobre la service definition y *Publish* |

Tip: crear `ZCL_SOLPED_IMPUT_PROC` y `ZCL_SOLPED_IMPUT_BGPF` antes del behavior pool. Crear `ZR_SOLPED_UP` y `ZR_SOLPED_LOG` juntas (se referencian entre sí) y activarlas a la vez.

## Verificar en ADT antes de activar (F2 / Ctrl+clic sobre el objeto estándar)

Los nombres siguientes se tomaron de la API estándar de solicitudes de pedido; confirmarlos en el sistema del cliente:

1. **BDEF `I_PurchaseRequisitionTP`**: alias de entidades `PurchaseRequisition`, `PurchaseRequisitionItem`,
   `PurReqnAcctAssgmt` y la asociación ítem → imputación `_PurReqnAcctAssgmt`.
2. Campos de imputación en `I_PurReqnAcctAssgmtTP`: `MasterFixedAsset`, `FixedAsset`, `Quantity`.
3. Campos de `I_PurchaseRequisitionItemAPI01`: `PurchaseRequisitionType`, `AccountAssignmentCategory`, `CompanyCode`,
   `RequestedQuantity`, `OrderedQuantity`, `PurchasingDocument`, `ProcessingStatus`, `IsDeleted`, `IsClosed`.
4. Campos de `I_FixedAsset`: `CompanyCode`, `MasterFixedAsset`, `FixedAsset`.
5. Dominio `BANPR` (estado de tratamiento): confirmar que **`05` = liberación completada** con workflow flexible.
6. **bgPF configurado** (Basis): bgRFC para el Background Processing Framework en `SBGRFCCONF`
   (destino inbound de bgPF y supervisor). Monitor de ejecuciones: `SBGRFCMON`.
7. Disponibilidad de la librería XCO `XCO_CP_XLSX` en el release (2023 la incluye para ABAP Cloud).

Si algún alias o campo difiere, solo hay que ajustarlo en `ZCL_SOLPED_IMPUT_PROC`.

## App Fiori

Generar en BAS una app **List Report / Object Page (OData V4)** sobre `ZUI_SOLPED_IMPUT_O4`, entidad `Upload`
(o usar *Preview* del service binding para probar).

Flujo: **Crear** → subir el .xlsx → **Guardar** → **Simular** (solo valida) o **Procesar** → actualizar → ver la sección **Log**.

Si una ejecución en segundo plano terminara con dump, la carga queda *En proceso*: revisar `SBGRFCMON` / `ST22` y crear una carga nueva.

## Pruebas sugeridas

1. Simular con la solped de prueba (sin modificar) y revisar el log.
2. Procesar y comprobar en ME53N: tipo de imputación A, activo y subnúmero en la pestaña *Imputación*, cuenta de mayor derivada.
3. Casos de error: activo inexistente, posición inexistente, solped aprobada, solped con pedido, columna C en notación científica.
4. Una posición que SAP rechace al grabar (p. ej. activo de otra clase no permitida) junto con posiciones correctas:
   las correctas deben quedar modificadas y el log debe mostrar el intento posición por posición.
5. Archivo grande (todas las posiciones de la solped) para medir el tiempo de proceso.
