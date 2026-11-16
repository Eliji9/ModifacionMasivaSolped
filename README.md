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

## Cómo modifica la solped (sin COMMIT propio)

- `ZCL_SOLPED_IMPUT_PROC` hace **un solo** `MODIFY ENTITIES OF i_purchaserequisitiontp` con todas las posiciones válidas:
  - `UPDATE` de `AccountAssignmentCategory = 'A'` en el ítem.
  - Si la posición ya tiene línea de imputación → `UPDATE` de `MasterFixedAsset` / `FixedAsset`.
  - Si no tiene → `CREATE BY \_PurchaseReqnAcctAssgmt` con activo, subnúmero y la cantidad total del ítem.
  - La cuenta de mayor **no se envía**: SAP la deriva de la clase del activo.
- Si el estándar rechaza una posición en el `MODIFY`, se le devuelve su tipo de imputación original para que no
  bloquee el grabado de las demás, y el mensaje de SAP va al log.
- La acción RAP **no hace COMMIT**: el framework graba la solped y el log al final de la petición OData.
- Si el estándar rechazara la solped completa **al grabar** (checks del *save*), no se guarda nada y Fiori
  muestra los mensajes de SAP en el popup (el log de esa ejecución tampoco queda guardado).

## Objetos

| Orden | Objeto | Tipo | Archivo |
|---|---|---|---|
| 1 | `ZTMM_SOLPED_UP` | Tabla (archivo + resumen) | `src/01_tablas/ZTMM_SOLPED_UP.tabl` |
| 2 | `ZTMM_SOLPED_LG` | Tabla (log) | `src/01_tablas/ZTMM_SOLPED_LG.tabl` |
| 3 | `ZR_SOLPED_LOG` | CDS view entity (hija) | `src/02_cds/ZR_SOLPED_LOG.ddls` |
| 4 | `ZR_SOLPED_UP` | CDS root view entity | `src/02_cds/ZR_SOLPED_UP.ddls` |
| 5 | `ZR_SOLPED_UP` | Behavior definition (managed, draft) | `src/03_comportamiento/ZR_SOLPED_UP.bdef` |
| 6 | `ZTMM_SOLPED_UP_D`, `ZTMM_SOLPED_LG_D` | Tablas draft | Generarlas con el *quick fix* (Ctrl+1) en la BDEF |
| 7 | `ZCL_SOLPED_IMPUT_PROC` | Clase (lógica) | `src/03_comportamiento/ZCL_SOLPED_IMPUT_PROC.clas.abap` |
| 8 | `ZBP_R_SOLPED_UP` | Behavior pool | `...ZBP_R_SOLPED_UP.clas.abap` + pestaña *Local Types*: `...clas.locals_imp.abap` |
| 9 | `ZC_SOLPED_LOG`, `ZC_SOLPED_UP` | CDS proyección | `src/02_cds/ZC_*.ddls` |
| 10 | `ZC_SOLPED_LOG`, `ZC_SOLPED_UP` | Metadata extensions | `src/02_cds/ZC_*.ddlx` |
| 11 | `ZC_SOLPED_UP` | Behavior definition proyección | `src/03_comportamiento/ZC_SOLPED_UP.bdef` |
| 12 | `ZUI_SOLPED_IMPUT` | Service definition | `src/04_servicio/ZUI_SOLPED_IMPUT.srvd` |
| 13 | `ZUI_SOLPED_IMPUT_O4` | Service binding **OData V4 – UI** | Crear en ADT sobre la service definition y *Publish* |

Tip: crear `ZR_SOLPED_UP` y `ZR_SOLPED_LOG` juntas (se referencian entre sí) y activarlas a la vez.

## Verificar en ADT antes de activar (F2 / Ctrl+clic sobre el objeto estándar)

Los nombres siguientes se tomaron de la API estándar de solicitudes de pedido; confirmarlos en el sistema del cliente:

1. **BDEF `I_PurchaseRequisitionTP`**: alias de entidades `PurchaseRequisition`, `PurchaseRequisitionItem`,
   `PurchaseReqnAcctAssgmt` y la asociación ítem → imputación `_PurchaseReqnAcctAssgmt`.
2. Campos de imputación en `I_PurchaseReqnAcctAssgmtTP`: `MasterFixedAsset`, `FixedAsset`, `Quantity`.
3. Campos de `I_PurchaseRequisitionItemAPI01`: `PurchaseRequisitionType`, `AccountAssignmentCategory`, `CompanyCode`,
   `RequestedQuantity`, `OrderedQuantity`, `PurchasingDocument`, `ProcessingStatus`, `IsDeleted`, `IsClosed`.
4. Campos de `I_FixedAsset`: `CompanyCode`, `MasterFixedAsset`, `FixedAsset`.
5. Dominio `BANPR` (estado de tratamiento): confirmar que **`05` = liberación completada** con workflow flexible.
6. Disponibilidad de la librería XCO `XCO_CP_XLSX` en el release (2023 la incluye para ABAP Cloud).

Si algún alias o campo difiere, solo hay que ajustarlo en `ZCL_SOLPED_IMPUT_PROC`.

## App Fiori

Generar en BAS una app **List Report / Object Page (OData V4)** sobre `ZUI_SOLPED_IMPUT_O4`, entidad `Upload`
(o usar *Preview* del service binding para probar).

Flujo: **Crear** → subir el .xlsx → **Guardar** → **Simular** (solo valida) o **Procesar** → ver la sección **Log**.

## Pruebas sugeridas

1. Simular con la solped de prueba (sin modificar) y revisar el log.
2. Procesar y comprobar en ME53N: tipo de imputación A, activo y subnúmero en la pestaña *Imputación*, cuenta de mayor derivada.
3. Casos de error: activo inexistente, posición inexistente, solped aprobada, solped con pedido, columna C en notación científica.
4. Archivo grande (todas las posiciones de la solped) para medir el tiempo de respuesta.
