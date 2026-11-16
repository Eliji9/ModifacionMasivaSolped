"! <p class="shorttext synchronized">Wrapper Tier 2: fábrica de ZIF_MM_PR_CHANGE_API</p>
"! Clase liberada (contrato C1 - Use in Cloud Development).
"! Es el único punto de entrada desde ABAP Cloud al wrapper de BAPI_PR_CHANGE.
CLASS zcl_mm_pr_change_api_fact DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.
    CLASS-METHODS create_instance
      RETURNING VALUE(ro_instance) TYPE REF TO zif_mm_pr_change_api.

ENDCLASS.



CLASS zcl_mm_pr_change_api_fact IMPLEMENTATION.

  METHOD create_instance.
    ro_instance = NEW zcl_mm_pr_change_api( ).
  ENDMETHOD.

ENDCLASS.
