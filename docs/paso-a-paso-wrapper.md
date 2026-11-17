# Paso a paso – Wrapper Tier 2 de BAPI_PR_CHANGE

## Por qué

`I_PurchaseRequisitionTP` (EML) rechaza el cambio de imputación K/Y → A sin devolver
mensaje (FAILED `UNSPECIFIC`), aunque en ME52N el mismo cambio funciona.
`BAPI_PR_CHANGE` usa la misma lógica que ME52N y devuelve los mensajes reales en `RETURN`.
Como la BAPI no está liberada para ABAP Cloud, se encapsula en un **wrapper Tier 2**
(interfaz + fábrica liberadas C1, implementación no liberada).

## Cómo queda la app (sin bgPF, sin COMMIT propio)

| Acción | Qué hace |
|---|---|
| **Simular** | Validaciones propias + `BAPI_PR_CHANGE` en **modo prueba** (`TESTRUN = X`). El log muestra los mensajes reales de SAP por posición. No graba. |
| **Procesar** | La acción deja la carga *En proceso* y el saver registra una operación **bgPF** (`ZCL_SOLPED_IMPUT_BGPF`). En segundo plano: validaciones propias y, **por cada posición**, `BAPI_PR_CHANGE` + `BAPI_TRANSACTION_COMMIT` (o `ROLLBACK` si SAP la rechaza, incluido `ME 664`). Graba el log y el resumen. Actualizar la pantalla para ver el resultado. |

La BAPI no puede grabar dentro de la transacción RAP (COMMIT y AUTHORITY-CHECK prohibidos),
por eso Procesar corre en segundo plano con bgPF. **Basis debe tener configurado bgPF**
(`SBGRFCCONF`); monitor `SBGRFCMON`.

## Paquetes

| Paquete | Superpaquete | Versión de lenguaje | Contenido |
|---|---|---|---|
| `ZPC_MOD_MAS_SOL_PED` | `ZMM` | ABAP for Cloud Development | App RAP (existente) |
| `ZPC_MOD_MAS_SOL_PED_T2` | `ZMM` | **Standard ABAP** | Wrapper de `BAPI_PR_CHANGE` |

## Objetos nuevos y modificados

| # | Objeto | Tipo | Paquete | Archivo | Acción |
|---|---|---|---|---|---|
| 1 | `ZIF_MM_PR_CHANGE_API` | Interfaz (liberar C1) | T2 | `src/zpc_mod_mas_sol_ped_t2/zif_mm_pr_change_api.intf.abap` | Nuevo |
| 2 | `ZCL_MM_PR_CHANGE_API` | Clase implementación (no liberar) | T2 | `src/zpc_mod_mas_sol_ped_t2/zcl_mm_pr_change_api.clas.abap` | Nuevo |
| 3 | `ZCL_MM_PR_CHANGE_API_FACT` | Clase fábrica (liberar C1) | T2 | `src/zpc_mod_mas_sol_ped_t2/zcl_mm_pr_change_api_fact.clas.abap` | Nuevo |
| 4 | `ZCL_SOLPED_IMPUT_PROC` | Clase | T1 | `src/zpc_mod_mas_sol_ped/zcl_solped_imput_proc.clas.abap` | Modificado |
| 5 | `ZR_SOLPED_UP` | Behavior definition | T1 | `src/zpc_mod_mas_sol_ped/zr_solped_up.bdef.asbdef` | Modificado (`with additional save`) |
| 6 | `ZBP_R_SOLPED_UP` | Behavior pool (Local Types) | T1 | `src/zpc_mod_mas_sol_ped/zbp_r_solped_up.clas.locals_imp.abap` | Modificado (Procesar → En proceso; saver bgPF) |
| 7 | `ZCL_SOLPED_IMPUT_BGPF` | Clase operación bgPF | T1 | `src/zpc_mod_mas_sol_ped/zcl_solped_imput_bgpf.clas.abap` | Nuevo |
| 8 | `ZR_SOLPED_UP` | CDS | T1 | `src/zpc_mod_mas_sol_ped/zr_solped_up.ddls.asddls` | Modificado (estado R = En proceso) |

## Paso a paso

### 1. Paquete Tier 2

ADT → *New → ABAP Package*: `ZPC_MOD_MAS_SOL_PED_T2`, superpaquete `ZMM`, componente `MM`,
**ABAP Language Version: Standard ABAP**, misma capa de transporte.

### 2. Interfaz `ZIF_MM_PR_CHANGE_API`

Nueva interfaz en el paquete T2, pegar el archivo y activar. Si algún tipo no existe en el
release (p. ej. una estructura `BAPI_SRV_*`), comparar con la firma de `BAPI_PR_CHANGE` en
SE37 y quitar ese tipo de la interfaz y su parámetro en la clase del paso 3.

### 3. Clase `ZCL_MM_PR_CHANGE_API`

Nueva clase en el paquete T2, pegar y activar. **No se libera.**

### 4. Clase `ZCL_MM_PR_CHANGE_API_FACT`

Nueva clase en el paquete T2, pegar y activar.

### 5. Liberar con contrato C1

`ZIF_MM_PR_CHANGE_API` y `ZCL_MM_PR_CHANGE_API_FACT`: **Properties → API State →
Use in Cloud Development (C1) → Add Release Contract → Released**, orden de transporte, *Finish*.

### 6. Objetos de la app (paquete `ZPC_MOD_MAS_SOL_PED`), en este orden

1. **`ZCL_SOLPED_IMPUT_PROC`**: reemplazar completa y activar.
2. **Behavior definition `ZR_SOLPED_UP`**: primera línea
   `managed with additional save implementation in class zbp_r_solped_up unique;` y activar.
3. **`ZBP_R_SOLPED_UP`**: reemplazar la pestaña *Local Types* completa y activar.

### 7. Prueba

1. Crear carga → subir el `.xlsx` → **Guardar**.
2. **Simular**: el log muestra los mensajes reales de SAP por posición.
3. **Procesar**: el log muestra *Correcto* / *Error* por posición. Revisar en ME53N las correctas.

### 8. Transporte a calidad

Liberar las órdenes de ambos paquetes (la liberación C1 viaja con el objeto).

## Consideraciones

- Los métodos `commit` y `rollback` del wrapper **no se usan en la app** (dentro de RAP no se
  permiten); se dejan en la interfaz para otros usos fuera de RAP.
- Los mensajes de la prueba se asignan a la posición por `RETURN-PARAMETER`
  (`PRITEM` / `PRACCOUNT`) y `RETURN-ROW`. Si SAP devuelve un error sin posición, no se
  modifica ninguna posición y el mensaje queda en la fila 1.
- Caso excepcional: si la llamada real en el saver devolviera un error que la prueba no
  detectó, no se graba la solped, el mensaje sale en pantalla y se agrega al log.
- La línea de imputación se envía como en ME52N: `ASSET_NO`, `SUB_NUMBER`, `QUANTITY` y
  `COSTCENTER` / `GL_ACCOUNT` vacíos (SAP deriva la cuenta de la clase del activo).
