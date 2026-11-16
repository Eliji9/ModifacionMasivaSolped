# ModificacionMasivaSolped – Imputación A y activo fijo en solpeds de traslado

App Fiori Elements V4 sobre RAP para **S/4HANA Cloud Private Edition 2023** (ABAP Cloud / Clean Core)
que modifica de forma masiva las posiciones de una solicitud de pedido de traslado (`ZUB*`):
cambia el tipo de imputación a **A (Activo fijo)** y asigna el **activo fijo** en la pestaña
*Imputación*, a partir de un archivo Excel, y muestra un log por posición.

- **Documentación técnica (Word):** [`docs/Documentacion_Modificacion_Masiva_Solped.docx`](docs/Documentacion_Modificacion_Masiva_Solped.docx)
- Diseño de la solución: [`docs/diseno-solucion.md`](docs/diseno-solucion.md)
- **Objetos y orden de creación:** [`src/README.md`](src/README.md)
- Archivo de carga de ejemplo: [`ejemplos/solped_40000230.xlsx`](ejemplos/solped_40000230.xlsx)

## Contexto

| Tema | Hoy | Con la app |
|---|---|---|
| Cambio de imputación | Manual en ME52N, posición por posición | Masivo desde un Excel |
| Activo fijo | Se digita en la pestaña *Imputación* de cada posición | Columna C del archivo |
| Validaciones | Las hace el usuario | Solped (clase, pedido, aprobación), posición y activo |
| Resultado | Sin registro | Log por posición: correctas y con error |

## Alcance

- Una solped por archivo; el archivo puede traer todas sus posiciones.
- Solo solpeds de traslado con clase de documento `ZUB*`.
- Por posición: tipo de imputación `A` + activo fijo / subnúmero. La cuenta de mayor la deriva SAP.
- Si una posición falla, las demás se modifican. Todas quedan en el log.
- Modo **Simular** (solo valida) y **Procesar** (valida y modifica).

## Restricciones

- 100 % Clean Core: sin BAPIs clásicas, sin acceso directo a tablas estándar, sin GUI ni ALV.
- No se modifican solpeds **aprobadas** (workflow flexible) ni solpeds con **orden de compra**.
- No se guarda historial funcional de cargas: la tabla de cargas es solo técnica (archivo + log).

## Opciones evaluadas

| Criterio | A · Reporte clásico + BAPI | B · App RAP síncrona | C · App RAP + bgPF |
|---|---|---|---|
| Clean Core | No (`BAPI_PR_CHANGE`, `GUI_UPLOAD`, ALV, EBAN) | Sí (Tier 1) | Sí (Tier 1) |
| Log | ALV | En la app, al terminar | En la app, al actualizar |
| Posición con error | Se omite | Se omite; las demás se modifican | Se omite; las demás se modifican |
| SAP rechaza el grabado completo | — | No se graba nada; mensaje en pantalla | Reintenta posición por posición |
| Configuración Basis | No | No | Sí (bgRFC / bgPF) |
| Complejidad | Baja | Baja | Media |

**Decisión:** **opción B**. La C queda en el historial del repo (commit `20d5304`) por si en pruebas
el rechazo del grabado completo resulta frecuente.

## Estado

- [x] Objetos creados y activados en DS4 (paquete `ZPC_MOD_MAS_SOL_PED`)
- [x] Nombres reales del BO estándar confirmados (entidad `PurReqnItmAccountAssignment`, asociación `_PurchaseReqnAcctAssgmt`)
- [ ] Service binding `ZUI_SOLPED_IMPUT_O4` publicado y probado con *Preview*
- [ ] Confirmar que `ProcessingStatus = '05'` es "aprobada" en el workflow flexible de DS4
- [ ] Prueba Simular / Procesar con la solped 40000802 (y una solped grande)
- [ ] Casos de error: activo inexistente, posición inexistente, solped aprobada, solped con pedido
- [x] App Fiori generada en BAS y desplegada en DS4 (BSP `ZMMMODSOLPED`, orden `DS4K908727`)
- [ ] Launchpad (inbound, catálogo, target mapping) y rol PFCG
- [ ] ATC con la variante Clean Core del cliente

## Estructura

```
src/zpc_mod_mas_sol_ped/   Objetos ABAP del paquete (copiar y pegar en ADT)
docs/                      Diseño de la solución
ejemplos/                  Archivos de carga de ejemplo
```
