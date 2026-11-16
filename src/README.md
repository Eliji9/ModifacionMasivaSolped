# Objetos – Modificación masiva de solpeds (opción B)

Código fuente para crear en ADT (copiar y pegar). No es un repositorio abapGit:
las tablas draft, el behavior pool y el service binding se generan con los asistentes de ADT.

## Paquete

| Paquete | Superpaquete | Versión de lenguaje | Componente de aplicación | Contenido |
|---|---|---|---|---|
| `ZPC_MOD_MAS_SOL_PED` | `ZMM` | ABAP for Cloud Development | `MM` | Todos los objetos de la app |

## Objetos

| # | Objeto | Tipo | Paquete | Archivo |
|---|---|---|---|---|
| 1 | `ZTMM_SOLPED_UP` | Tabla de BD (archivo + resumen) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/ztmm_solped_up.tabl.ddls` |
| 2 | `ZTMM_SOLPED_LG` | Tabla de BD (log) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/ztmm_solped_lg.tabl.ddls` |
| 3 | `ZCL_SOLPED_IMPUT_PROC` | Clase (lectura Excel, validaciones, EML) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zcl_solped_imput_proc.clas.abap` |
| 4 | `ZR_SOLPED_LOG` | CDS view entity (hija) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zr_solped_log.ddls.asddls` |
| 5 | `ZR_SOLPED_UP` | CDS root view entity | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zr_solped_up.ddls.asddls` |
| 6 | `ZR_SOLPED_UP` | Behavior definition (managed, draft) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zr_solped_up.bdef.asbdef` |
| 7 | `ZTMM_SOLPED_UP_D` | Tabla draft | `ZPC_MOD_MAS_SOL_PED` | — (generada, paso 6) |
| 8 | `ZTMM_SOLPED_LG_D` | Tabla draft | `ZPC_MOD_MAS_SOL_PED` | — (generada, paso 6) |
| 9 | `ZBP_R_SOLPED_UP` | Behavior pool | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zbp_r_solped_up.clas.abap` + `zbp_r_solped_up.clas.locals_imp.abap` |
| 10 | `ZC_SOLPED_LOG` | CDS proyección (hija) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zc_solped_log.ddls.asddls` |
| 11 | `ZC_SOLPED_UP` | CDS proyección (raíz) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zc_solped_up.ddls.asddls` |
| 12 | `ZC_SOLPED_LOG` | Metadata extension | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zc_solped_log.ddlx.asddlxs` |
| 13 | `ZC_SOLPED_UP` | Metadata extension | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zc_solped_up.ddlx.asddlxs` |
| 14 | `ZC_SOLPED_UP` | Behavior definition (proyección) | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zc_solped_up.bdef.asbdef` |
| 15 | `ZUI_SOLPED_IMPUT` | Service definition | `ZPC_MOD_MAS_SOL_PED` | `zpc_mod_mas_sol_ped/zui_solped_imput.srvd.srvdsrv` |
| 16 | `ZUI_SOLPED_IMPUT_O4` | Service binding (OData V4 – UI) | `ZPC_MOD_MAS_SOL_PED` | — (asistente, paso 13) |

## Orden de creación

1. **Paquete** `ZPC_MOD_MAS_SOL_PED` (superpaquete `ZMM`, *ABAP for Cloud Development*).
2. **Tablas** `ZTMM_SOLPED_UP` y `ZTMM_SOLPED_LG`: nueva tabla de BD y pegar el DDL.
3. **Clase `ZCL_SOLPED_IMPUT_PROC`**: solo depende de objetos estándar. Al activarla se confirman los
   nombres del BO `I_PurchaseRequisitionTP` (ver *Puntos a validar*).
4. **CDS `ZR_SOLPED_LOG` y `ZR_SOLPED_UP`**: crear las dos y **activarlas juntas** (se referencian entre sí).
5. **Behavior definition `ZR_SOLPED_UP`**: clic derecho sobre la CDS `ZR_SOLPED_UP` →
   *New Behavior Definition* (*Managed*), pegar el contenido y guardar **sin activar**.
6. **Tablas draft**: en la BDEF, cursor sobre `ztmm_solped_up_d` → **Ctrl+1** →
   *Create draft table* → activar. Repetir con `ztmm_solped_lg_d`.
7. **Behavior pool**: en la BDEF, cursor sobre `zbp_r_solped_up` → **Ctrl+1** →
   *Create behavior implementation class*. Activar la BDEF.
8. **`ZBP_R_SOLPED_UP`**: pegar `zbp_r_solped_up.clas.locals_imp.abap` en la pestaña *Local Types* y activar.
9. **CDS proyección `ZC_SOLPED_LOG` y `ZC_SOLPED_UP`**: crearlas y activarlas juntas.
10. **Metadata extensions** `ZC_SOLPED_LOG` y `ZC_SOLPED_UP`.
11. **Behavior definition de proyección `ZC_SOLPED_UP`**: clic derecho sobre la CDS `ZC_SOLPED_UP` →
    *New Behavior Definition*.
12. **Service definition `ZUI_SOLPED_IMPUT`**: clic derecho sobre la CDS `ZC_SOLPED_UP` →
    *New Service Definition*; agregar `ZC_SOLPED_LOG` y los alias `Upload` / `Log`.
13. **Service binding `ZUI_SOLPED_IMPUT_O4`**: clic derecho sobre `ZUI_SOLPED_IMPUT` →
    *New Service Binding*, tipo *OData V4 – UI* → **Publish**.
14. **Preview** desde el binding (entidad `Upload`) y luego app List Report / Object Page en BAS.
15. **ATC** con la variante Clean Core del cliente antes de transportar.

Si se cambian campos de las CDS `ZR_`, regenerar la tabla draft correspondiente (Ctrl+1 sobre su nombre
en la BDEF); si no, la activación falla.

## Puntos a validar al activar

| Punto | Dónde | Qué revisar | Estado |
|---|---|---|---|
| Asociación ítem → imputación | `ZCL_SOLPED_IMPUT_PROC` | `_PurchaseReqnAcctAssgmt` | Confirmado en DS4 |
| Entidad de imputación | `ZCL_SOLPED_IMPUT_PROC` (`TYPE TABLE FOR UPDATE`, `ENTITY`, `ls_failed-` / `ls_reported-`) | `PurReqnItmAccountAssignment` / `purreqnitmaccountassignment` | Confirmado en DS4 |
| `SORT ... STABLE` | `ZCL_SOLPED_IMPUT_PROC->execute` | `SORT mt_log STABLE BY row_no.` | Corregido |
| Tipo `RESPONSE FOR REPORTED EARLY` | `ZBP_R_SOLPED_UP` (`run`) | No se acepta como parámetro: el mensaje se arma en cada acción | Corregido |
| Campos de imputación | `I_PurReqnAcctAssgmtTP` | `MasterFixedAsset`, `FixedAsset`, `Quantity` | Activado sin error |
| Campos de la posición | `I_PurchaseRequisitionItemAPI01` | `PurchaseRequisitionType`, `CompanyCode`, `PurchasingDocument`, `OrderedQuantity`, `ProcessingStatus`, `IsDeleted`, `IsClosed` | Activado sin error |
| Estado "aprobada" | `ZCL_SOLPED_IMPUT_PROC` (`c_status_released = '05'`) | Dominio `BANPR`: `05` = liberación completada con workflow flexible | Pendiente en pruebas |
| API liberadas (C1) | Properties → *API State* | `I_PurchaseRequisitionTP`, `I_PurchaseRequisitionItemAPI01`, `I_FixedAsset`, `XCO_CP_XLSX` | Pendiente ATC |
| Cuenta de mayor | ME53N tras procesar | Derivada de la clase del activo (en gris en la pestaña *Imputación*) | Pendiente en pruebas |
| Columna C del Excel | Archivo de carga | Formato texto; con `1,4E+11` la fila se rechaza | Pendiente en pruebas |
