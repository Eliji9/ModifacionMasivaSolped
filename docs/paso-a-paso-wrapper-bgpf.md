# Paso a paso – Wrapper Tier 2 de BAPI_PR_CHANGE + Procesar en segundo plano

## Por qué

`I_PurchaseRequisitionTP` (EML) rechaza el cambio de imputación K/Y → A sin devolver
mensaje (FAILED `UNSPECIFIC`), aunque en ME52N el mismo cambio funciona.
`BAPI_PR_CHANGE` usa la misma lógica que ME52N y devuelve los mensajes reales en `RETURN`.
Como la BAPI no está liberada para ABAP Cloud, se encapsula en un **wrapper Tier 2**
(interfaz + fábrica liberadas C1, implementación no liberada).

## Cómo queda la app

| Acción | Qué hace | Dónde corre |
|---|---|---|
| **Simular** | Validaciones propias + `BAPI_PR_CHANGE` con `TESTRUN = X` (todas las posiciones, sin grabar). El log muestra los mensajes reales de SAP | Síncrona, en la acción RAP |
| **Procesar** | Deja la carga *En proceso*. En segundo plano (bgPF), por cada posición: `BAPI_PR_CHANGE` → si hay error `ROLLBACK`, si no `COMMIT`. Una posición rechazada no afecta a las demás | bgPF (`ZCL_SOLPED_IMPUT_BGPF`) |

Después de **Procesar**, actualizar la pantalla para ver el log.

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
| 4 | `ZCL_SOLPED_IMPUT_PROC` | Clase | T1 | `src/zpc_mod_mas_sol_ped/zcl_solped_imput_proc.clas.abap` | Modificado (usa el wrapper; sin EML de modificación; sin diagnóstico) |
| 5 | `ZCL_SOLPED_IMPUT_BGPF` | Clase operación bgPF | T1 | `src/zpc_mod_mas_sol_ped/zcl_solped_imput_bgpf.clas.abap` | Nuevo |
| 6 | `ZR_SOLPED_UP` | Behavior definition | T1 | `src/zpc_mod_mas_sol_ped/zr_solped_up.bdef.asbdef` | Modificado (`with additional save`) |
| 7 | `ZBP_R_SOLPED_UP` | Behavior pool (Local Types) | T1 | `src/zpc_mod_mas_sol_ped/zbp_r_solped_up.clas.locals_imp.abap` | Modificado (Procesar → *En proceso*; saver bgPF) |
| 8 | `ZR_SOLPED_UP` | CDS | T1 | `src/zpc_mod_mas_sol_ped/zr_solped_up.ddls.asddls` | Modificado (estado `R` = En proceso) |

## Paso a paso

### 1. Basis: bgPF

Confirmar con Basis que el Background Processing Framework está configurado en DS4 y QS4
(transacción `SBGRFCCONF`: destino inbound de bgPF y supervisor). Monitor: `SBGRFCMON`.

### 2. Paquete Tier 2

ADT → *New → ABAP Package*:
- Nombre `ZPC_MOD_MAS_SOL_PED_T2`, superpaquete `ZMM`, componente `MM`.
- **ABAP Language Version: Standard ABAP**.
- Misma capa de transporte y orden de los demás objetos.

### 3. Interfaz `ZIF_MM_PR_CHANGE_API`

1. Nueva interfaz en `ZPC_MOD_MAS_SOL_PED_T2` y pegar el archivo.
2. Activar. **Si algún tipo no existe en el release** (p. ej. una estructura de servicios
   `BAPI_SRV_*`), revisar la firma de `BAPI_PR_CHANGE` en SE37 y quitar ese tipo de la
   interfaz y su parámetro en la clase del paso 4.

### 4. Clase `ZCL_MM_PR_CHANGE_API`

Nueva clase en `ZPC_MOD_MAS_SOL_PED_T2`, pegar y activar. **No se libera.**

### 5. Clase `ZCL_MM_PR_CHANGE_API_FACT`

Nueva clase en `ZPC_MOD_MAS_SOL_PED_T2`, pegar y activar.

### 6. Liberar con contrato C1

Para **`ZIF_MM_PR_CHANGE_API`** y **`ZCL_MM_PR_CHANGE_API_FACT`**:
1. Abrir el objeto → pestaña **Properties** → **API State**.
2. **Use in Cloud Development (C1)** → *Add Release Contract* → Release State **Released**
   → marcar **Use in Cloud Development** → *Next* → orden de transporte → *Finish*.

`ZCL_MM_PR_CHANGE_API` se queda sin liberar.

### 7. Objetos de la app (paquete `ZPC_MOD_MAS_SOL_PED`), en este orden

1. **CDS `ZR_SOLPED_UP`**: pegar y activar (estado *En proceso*).
2. **Clase `ZCL_SOLPED_IMPUT_PROC`**: reemplazar completa y activar. Quita el diagnóstico
   `GET PERMISSIONS` y el `MODIFY ENTITIES` sobre `I_PurchaseRequisitionTP`.
3. **Clase `ZCL_SOLPED_IMPUT_BGPF`** (nueva): crear y activar.
4. **Behavior definition `ZR_SOLPED_UP`**: cambiar la primera línea a
   `managed with additional save implementation in class zbp_r_solped_up unique;` y activar.
5. **Behavior pool `ZBP_R_SOLPED_UP`**: reemplazar la pestaña *Local Types* completa y activar
   (incluye la clase saver `lsc_zr_solped_up`).

### 8. Prueba en DS4 / QS4

1. Crear carga → subir el `.xlsx` → **Guardar**.
2. **Simular**: el log debe mostrar los mensajes reales de SAP por posición (igual que ME52N).
3. **Procesar**: mensaje *En proceso*. Esperar unos segundos y **actualizar**.
4. El log debe mostrar cada posición *Correcto* o *Error* con el mensaje de SAP, y en ME53N
   las correctas con tipo A, activo, subnúmero y cuenta derivada.
5. Si la carga se queda *En proceso*: revisar `SBGRFCMON` y `ST22`.

### 9. Transporte a calidad

- Liberar las órdenes de ambos paquetes (T1 y T2). La liberación C1 viaja con el objeto.
- Basis: bgPF configurado también en QS4.

## Consideraciones

- **Simular** llama a la BAPI en modo prueba dentro de la acción RAP (sin COMMIT). Si en algún
  sistema esto da un dump de transacción RAP, pasar Simular también a bgPF.
- Los mensajes de la prueba se asignan a la posición por `RETURN-PARAMETER`
  (`PRITEM` / `PRACCOUNT`) y `RETURN-ROW`. Los mensajes sin posición van a la fila 1.
- En **Procesar** cada posición se graba por separado, así que todos los mensajes de una
  llamada pertenecen a esa posición.
- La línea de imputación se envía como en ME52N: `ASSET_NO`, `SUB_NUMBER`, `QUANTITY` y
  `COSTCENTER` / `GL_ACCOUNT` vacíos (SAP deriva la cuenta de la clase del activo).
