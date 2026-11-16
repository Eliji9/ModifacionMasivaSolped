"! <p class="shorttext synchronized">Modificación masiva solped: imputación A + activo fijo</p>
"! Lee el Excel (XCO), valida la solped y sus posiciones con vistas CDS liberadas
"! y prueba el cambio con BAPI_PR_CHANGE en modo prueba (TESTRUN) a través del
"! wrapper Tier 2 ZIF_MM_PR_CHANGE_API (misma lógica que ME52N).
"! No graba ni hace COMMIT.
"! - Simular: BAPI en modo prueba (TESTRUN) y log con los mensajes de SAP.
"! - Procesar: SOLO validaciones propias (sin BAPI, para no dejar el documento en
"!   memoria de la BAPI). Devuelve en es_bapi_data / et_pending las posiciones
"!   válidas; el saver llama la BAPI real una vez y RAP hace el COMMIT.
CLASS zcl_solped_imput_proc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    TYPES ty_banfn TYPE c LENGTH 10.

    TYPES:
      BEGIN OF ty_log,
        row_no               TYPE i,
        purchase_requisition TYPE ty_banfn,
        item                 TYPE c LENGTH 5,
        acct_cat_old         TYPE c LENGTH 1,
        acct_cat_new         TYPE c LENGTH 1,
        master_fixed_asset   TYPE c LENGTH 12,
        fixed_asset          TYPE c LENGTH 4,
        company_code         TYPE c LENGTH 4,
        step                 TYPE c LENGTH 1,
        msg_type             TYPE c LENGTH 1,
        msg_origin           TYPE c LENGTH 1,
        msg_id               TYPE c LENGTH 20,
        msg_no               TYPE n LENGTH 3,
        message              TYPE c LENGTH 220,
      END OF ty_log,
      tt_log TYPE STANDARD TABLE OF ty_log WITH EMPTY KEY,

      BEGIN OF ty_summary,
        total  TYPE i,
        ok     TYPE i,
        errors TYPE i,
      END OF ty_summary.

    CONSTANTS:
      BEGIN OF c_step,
        read       TYPE c LENGTH 1 VALUE 'L',
        validation TYPE c LENGTH 1 VALUE 'V',
        change     TYPE c LENGTH 1 VALUE 'M',
      END OF c_step,
      BEGIN OF c_origin,
        own TYPE c LENGTH 1 VALUE 'Z',
        sap TYPE c LENGTH 1 VALUE 'S',
      END OF c_origin.

    "! Procesa el archivo completo
    "! @parameter iv_file    | Contenido del .xlsx
    "! @parameter iv_test    | X = solo validar (no modifica la solped)
    "! @parameter ev_banfn   | Solped leída del archivo
    "! @parameter et_log     | Log por fila / posición
    "! @parameter es_summary | Totales de posiciones
    "! @parameter es_bapi_data | Solo si iv_test = space: datos para BAPI_PR_CHANGE
    "! @parameter et_pending   | Solo si iv_test = space: una línea de log por posición
    "!                           enviada a la BAPI (mismo orden que PRACCOUNT)
    "!                           con las posiciones aprobadas en la prueba
    METHODS execute
      IMPORTING iv_file    TYPE xstring
                iv_test    TYPE abap_bool
      EXPORTING ev_banfn   TYPE ty_banfn
                et_log     TYPE tt_log
                es_summary TYPE ty_summary
                es_bapi_data TYPE zif_mm_pr_change_api=>ty_data
                et_pending   TYPE tt_log.

  PRIVATE SECTION.

    CONSTANTS:
      c_acct_cat_asset  TYPE c LENGTH 1 VALUE 'A',
      c_pr_type_pattern TYPE c LENGTH 4 VALUE 'ZUB*',
      "! Estado de tratamiento de la solped: liberación completada (workflow flexible)
      c_status_released TYPE c LENGTH 2 VALUE '05'.

    TYPES:
      ty_c1        TYPE c LENGTH 1,
      ty_item_no   TYPE n LENGTH 5,
      ty_asset     TYPE c LENGTH 12,
      ty_subnumber TYPE c LENGTH 4,
      ty_msgid     TYPE c LENGTH 20,
      ty_msgno     TYPE n LENGTH 3,

      BEGIN OF ty_row,
        a TYPE string,
        b TYPE string,
        c TYPE string,
      END OF ty_row,
      tt_row TYPE STANDARD TABLE OF ty_row WITH EMPTY KEY,

      BEGIN OF ty_input,
        row_no       TYPE i,
        item         TYPE ty_item_no,
        asset        TYPE ty_asset,
        subnumber    TYPE ty_subnumber,
        acct_cat_old TYPE ty_c1,
        company_code TYPE c LENGTH 4,
        quantity     TYPE i_purchaserequisitionitemapi01-RequestedQuantity,
      END OF ty_input,
      tt_input TYPE STANDARD TABLE OF ty_input WITH EMPTY KEY,

      BEGIN OF ty_item,
        purchaserequisitionitem   TYPE i_purchaserequisitionitemapi01-PurchaseRequisitionItem,
        purchaserequisitiontype   TYPE i_purchaserequisitionitemapi01-PurchaseRequisitionType,
        accountassignmentcategory TYPE i_purchaserequisitionitemapi01-AccountAssignmentCategory,
        companycode               TYPE i_purchaserequisitionitemapi01-CompanyCode,
        requestedquantity         TYPE i_purchaserequisitionitemapi01-RequestedQuantity,
        orderedquantity           TYPE i_purchaserequisitionitemapi01-OrderedQuantity,
        purchasingdocument        TYPE i_purchaserequisitionitemapi01-PurchasingDocument,
        processingstatus          TYPE i_purchaserequisitionitemapi01-ProcessingStatus,
        isdeleted                 TYPE i_purchaserequisitionitemapi01-IsDeleted,
        isclosed                  TYPE i_purchaserequisitionitemapi01-IsClosed,
      END OF ty_item,
      tt_item TYPE SORTED TABLE OF ty_item WITH UNIQUE KEY purchaserequisitionitem,

      tt_row_set  TYPE SORTED TABLE OF i WITH UNIQUE KEY table_line,
      tt_item_set TYPE SORTED TABLE OF ty_item_no WITH UNIQUE KEY table_line.

    DATA mv_banfn      TYPE ty_banfn.
    DATA mt_items      TYPE tt_item.
    DATA mt_log        TYPE tt_log.
    DATA mt_error_rows TYPE tt_row_set.
    DATA mv_total      TYPE i.
    DATA ms_bapi_data  TYPE zif_mm_pr_change_api=>ty_data.
    DATA mt_pending    TYPE tt_log.

    METHODS read_excel
      IMPORTING iv_file        TYPE xstring
      RETURNING VALUE(rt_rows) TYPE tt_row.

    METHODS parse
      IMPORTING it_rows         TYPE tt_row
      RETURNING VALUE(rt_input) TYPE tt_input.

    METHODS check_header
      IMPORTING it_input     TYPE tt_input
      RETURNING VALUE(rv_ok) TYPE abap_bool.

    METHODS check_items
      CHANGING ct_input TYPE tt_input.

    METHODS change_items
      IMPORTING it_input TYPE tt_input
                iv_test  TYPE abap_bool.

    METHODS normalize
      IMPORTING iv_value        TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS add_log
      IMPORTING is_input  TYPE ty_input OPTIONAL
                iv_row    TYPE i OPTIONAL
                iv_step   TYPE ty_c1
                iv_type   TYPE ty_c1
                iv_origin TYPE ty_c1 DEFAULT c_origin-own
                iv_msgid  TYPE ty_msgid OPTIONAL
                iv_msgno  TYPE ty_msgno OPTIONAL
                iv_text   TYPE csequence.

    "! Arma las estructuras de BAPI_PR_CHANGE para las posiciones indicadas
    METHODS build_bapi_data
      IMPORTING it_input       TYPE tt_input
      RETURNING VALUE(rs_data) TYPE zif_mm_pr_change_api=>ty_data.

    "! Pasa un mensaje BAPIRET2 al log
    METHODS add_bapi_message
      IMPORTING is_return TYPE zif_mm_pr_change_api=>ty_return
                is_input  TYPE ty_input OPTIONAL.

ENDCLASS.



CLASS zcl_solped_imput_proc IMPLEMENTATION.

  METHOD execute.
    DATA lt_rows TYPE tt_row.

    CLEAR: mv_banfn, mt_items, mt_log, mt_error_rows, mv_total, ms_bapi_data, mt_pending,
           ev_banfn, et_log, es_summary, es_bapi_data, et_pending.

    " 1. Lectura del Excel
    IF xstrlen( iv_file ) = 0.
      add_log( iv_row  = 0
               iv_step = c_step-read
               iv_type = 'E'
               iv_text = 'El archivo llegó vacío. Vuelva a subirlo, guarde y luego Simule o Procese' ).
    ELSE.
      TRY.
          lt_rows = read_excel( iv_file ).
        CATCH cx_root INTO DATA(lx_error).
          add_log( iv_row  = 0
                   iv_step = c_step-read
                   iv_type = 'E'
                   iv_text = |No se pudo leer el Excel ({ xstrlen( iv_file ) } bytes): { lx_error->get_text( ) }| ).
      ENDTRY.
    ENDIF.

    " 2. Interpretación de filas (solped + posiciones)
    DATA(lt_input) = parse( lt_rows ).

    IF mv_banfn IS INITIAL AND mt_log IS INITIAL.
      add_log( iv_row  = 0
               iv_step = c_step-read
               iv_type = 'E'
               iv_text = 'El archivo no tiene datos en la primera hoja (o no es un .xlsx válido)' ).
    ENDIF.

    " 3. Validaciones y modificación
    IF mv_banfn IS NOT INITIAL AND check_header( lt_input ) = abap_true.
      check_items( CHANGING ct_input = lt_input ).
      IF lt_input IS NOT INITIAL.
        change_items( it_input = lt_input
                      iv_test  = iv_test ).
      ENDIF.
    ENDIF.

    " 4. Resultado
    SORT mt_log STABLE BY row_no.
    ev_banfn          = mv_banfn.
    et_log            = mt_log.
    es_summary-total  = mv_total.
    es_summary-errors = lines( mt_error_rows ).
    es_summary-ok     = nmax( val1 = es_summary-total - es_summary-errors val2 = 0 ).
    es_bapi_data      = ms_bapi_data.
    et_pending        = mt_pending.
  ENDMETHOD.


  METHOD read_excel.
    DATA(lo_document) = xco_cp_xlsx=>document->for_file_content( iv_file )->read_access( ).
    DATA(lo_worksheet) = lo_document->get_workbook( )->worksheet->at_position( 1 ).
    IF lo_worksheet IS NOT BOUND OR lo_worksheet->exists( ) = abap_false.
      RETURN.
    ENDIF.

    " Columnas A..C desde la fila 1; el índice de la tabla = fila del Excel
    DATA(lo_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to(
                         )->from_column( xco_cp_xlsx=>coordinate->for_alphabetic_value( 'A' )
                         )->to_column( xco_cp_xlsx=>coordinate->for_alphabetic_value( 'C' )
                         )->from_row( xco_cp_xlsx=>coordinate->for_numeric_value( 1 )
                         )->get_pattern( ).

    lo_worksheet->select( lo_pattern
      )->row_stream(
      )->operation->write_to( REF #( rt_rows )
      )->set_value_transformation( xco_cp_xlsx_read_access=>value_transformation->string_value
      )->if_xco_xlsx_ra_operation~execute( ).
  ENDMETHOD.


  METHOD parse.
    LOOP AT it_rows INTO DATA(ls_row).
      DATA(lv_row) = sy-tabix.
      DATA(lv_a)   = normalize( ls_row-a ).
      DATA(lv_b)   = normalize( ls_row-b ).
      DATA(lv_c)   = normalize( ls_row-c ).

      IF lv_a IS INITIAL AND lv_b IS INITIAL AND lv_c IS INITIAL.
        CONTINUE.
      ENDIF.

      " ---- Primera fila con datos: número de solped -----------------------
      IF mv_banfn IS INITIAL.
        IF lv_a CO '0123456789' AND strlen( lv_a ) <= 10
           AND lv_b IS INITIAL AND lv_c IS INITIAL.
          mv_banfn = |{ CONV ty_banfn( lv_a ) ALPHA = IN }|.
        ELSE.
          add_log( iv_row  = lv_row
                   iv_step = c_step-read
                   iv_type = 'E'
                   iv_text = |Fila { lv_row }: la primera fila debe tener solo el número de solped en la columna A| ).
          RETURN.
        ENDIF.
        CONTINUE.
      ENDIF.

      " ---- Filas de posición ----------------------------------------------
      mv_total += 1.
      DATA(ls_input) = VALUE ty_input( row_no = lv_row ).
      DATA(lv_error) = ``.

      IF lv_a CO '0123456789' AND strlen( lv_a ) BETWEEN 1 AND 5.
        ls_input-item = lv_a.
      ENDIF.

      IF lv_b IS INITIAL AND lv_c IS INITIAL.
        lv_error = |Fila con solo columna A ("{ lv_a }"). Solo se admite una solped por archivo; | &&
                   |cada posición necesita columnas A (posición), B (A) y C (activo)|.
      ELSEIF ls_input-item IS INITIAL.
        lv_error = |Posición inválida "{ lv_a }"|.
      ELSEIF lv_b <> c_acct_cat_asset.
        lv_error = |Tipo de imputación "{ lv_b }" no válido; se espera "A"|.
      ELSEIF lv_c IS INITIAL.
        lv_error = `Activo fijo vacío`.
      ELSEIF matches( val = lv_c pcre = `^[0-9]+(\.[0-9]+)?E[+-]?[0-9]+$` ).
        lv_error = |Activo en notación científica ({ lv_c }). Formatee la columna C como texto|.
      ELSE.
        SPLIT lv_c AT '-' INTO DATA(lv_asset) DATA(lv_sub).
        IF strlen( lv_asset ) NOT BETWEEN 1 AND 12 OR strlen( lv_sub ) > 4.
          lv_error = |Activo fijo inválido "{ lv_c }"|.
        ELSE.
          ls_input-asset     = |{ CONV ty_asset( lv_asset ) ALPHA = IN }|.
          ls_input-subnumber = |{ CONV ty_subnumber( COND string( WHEN lv_sub IS INITIAL THEN `0` ELSE lv_sub ) ) ALPHA = IN }|.
          IF line_exists( rt_input[ item = ls_input-item ] ).
            lv_error = |La posición { CONV i( ls_input-item ) } está repetida en el archivo|.
          ENDIF.
        ENDIF.
      ENDIF.

      IF lv_error IS INITIAL.
        APPEND ls_input TO rt_input.
      ELSE.
        add_log( is_input = ls_input
                 iv_step  = c_step-read
                 iv_type  = 'E'
                 iv_text  = lv_error ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD check_header.
    " Datos de la solped (vista liberada para ABAP Cloud)
    SELECT PurchaseRequisitionItem, PurchaseRequisitionType, AccountAssignmentCategory, CompanyCode,
           RequestedQuantity, OrderedQuantity, PurchasingDocument, ProcessingStatus, IsDeleted, IsClosed
      FROM i_purchaserequisitionitemapi01
      WHERE PurchaseRequisition = @mv_banfn
      INTO CORRESPONDING FIELDS OF TABLE @mt_items.

    DATA(lv_error) = ``.

    IF mt_items IS INITIAL.
      lv_error = |La solped { mv_banfn ALPHA = OUT } no existe|.
    ELSE.
      DATA(ls_first) = mt_items[ 1 ].

      IF ls_first-purchaserequisitiontype NP c_pr_type_pattern.
        lv_error = |La solped { mv_banfn ALPHA = OUT } es de clase { ls_first-purchaserequisitiontype }; | &&
                   |solo se permiten solpeds de traslado { c_pr_type_pattern }|.

      ELSEIF line_exists( mt_items[ processingstatus = c_status_released ] ).
        lv_error = |La solped { mv_banfn ALPHA = OUT } está aprobada (workflow flexible); no se puede modificar|.

      ELSE.
        LOOP AT mt_items INTO DATA(ls_item)
             WHERE purchasingdocument IS NOT INITIAL OR orderedquantity > 0.
          lv_error = COND #(
            WHEN ls_item-purchasingdocument IS NOT INITIAL
              THEN |La solped { mv_banfn ALPHA = OUT } ya tiene la orden de compra { ls_item-purchasingdocument ALPHA = OUT } | &&
                   |(posición { CONV i( ls_item-purchaserequisitionitem ) })|
            ELSE |La solped { mv_banfn ALPHA = OUT } ya tiene cantidad pedida en la posición { CONV i( ls_item-purchaserequisitionitem ) }| ).
          EXIT.
        ENDLOOP.
      ENDIF.
    ENDIF.

    IF lv_error IS INITIAL.
      rv_ok = abap_true.
      RETURN.
    ENDIF.

    " Error de cabecera: no se toca ninguna posición
    add_log( iv_row  = 1
             iv_step = c_step-validation
             iv_type = 'E'
             iv_text = lv_error ).
    LOOP AT it_input INTO DATA(ls_input).
      add_log( is_input = ls_input
               iv_step  = c_step-validation
               iv_type  = 'E'
               iv_text  = 'Posición no procesada por error en la solped (ver fila 1)' ).
    ENDLOOP.
  ENDMETHOD.


  METHOD check_items.
    TYPES:
      BEGIN OF ty_asset_key,
        companycode      TYPE c LENGTH 4,
        masterfixedasset TYPE ty_asset,
        fixedasset       TYPE ty_subnumber,
      END OF ty_asset_key.
    DATA lt_assets TYPE SORTED TABLE OF ty_asset_key
                   WITH UNIQUE KEY companycode masterfixedasset fixedasset.
    DATA lt_valid  TYPE tt_input.

    " ---- Posición existe, no borrada, no cerrada ----------------------------
    LOOP AT ct_input INTO DATA(ls_input).
      READ TABLE mt_items INTO DATA(ls_item)
           WITH TABLE KEY purchaserequisitionitem = ls_input-item.
      IF sy-subrc <> 0.
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = 'E'
                 iv_text  = |La posición { CONV i( ls_input-item ) } no existe en la solped { mv_banfn ALPHA = OUT }| ).
        CONTINUE.
      ENDIF.

      ls_input-acct_cat_old = ls_item-accountassignmentcategory.
      ls_input-company_code = ls_item-companycode.
      ls_input-quantity     = ls_item-requestedquantity.

      IF ls_item-isdeleted IS NOT INITIAL.
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = 'E'
                 iv_text  = 'La posición está marcada para borrado' ).
        CONTINUE.
      ENDIF.

      IF ls_item-isclosed IS NOT INITIAL.
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = 'E'
                 iv_text  = 'La posición está cerrada' ).
        CONTINUE.
      ENDIF.

      APPEND ls_input TO lt_valid.
    ENDLOOP.

    " ---- Activo fijo existe en la sociedad de la posición (una sola lectura) --
    IF lt_valid IS NOT INITIAL.
      SELECT CompanyCode, MasterFixedAsset, FixedAsset
        FROM i_fixedasset
        FOR ALL ENTRIES IN @lt_valid
        WHERE CompanyCode      = @lt_valid-company_code
          AND MasterFixedAsset = @lt_valid-asset
          AND FixedAsset       = @lt_valid-subnumber
        INTO CORRESPONDING FIELDS OF TABLE @lt_assets.
    ENDIF.

    CLEAR ct_input.
    LOOP AT lt_valid INTO ls_input.
      IF NOT line_exists( lt_assets[ companycode      = ls_input-company_code
                                     masterfixedasset = ls_input-asset
                                     fixedasset       = ls_input-subnumber ] ).
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = 'E'
                 iv_text  = |El activo fijo { ls_input-asset ALPHA = OUT }-{ ls_input-subnumber ALPHA = OUT } | &&
                            |no existe en la sociedad { ls_input-company_code }; posición no modificada| ).
        CONTINUE.
      ENDIF.
      APPEND ls_input TO ct_input.
    ENDLOOP.
  ENDMETHOD.


  METHOD change_items.
    DATA lt_change TYPE tt_input.

    " ---- Imputación múltiple: no soportada (lectura, sin modificar) -------
    READ ENTITIES OF i_purchaserequisitiontp
      ENTITY PurchaseRequisitionItem BY \_PurchaseReqnAcctAssgmt
        FIELDS ( MasterFixedAsset ) WITH VALUE #( FOR ls_in IN it_input
                                                  ( PurchaseRequisition     = mv_banfn
                                                    PurchaseRequisitionItem = ls_in-item ) )
        RESULT DATA(lt_accts).

    LOOP AT it_input INTO DATA(ls_input).
      DATA(lv_lines) = REDUCE i( INIT n = 0
                                 FOR ls_a IN lt_accts
                                 WHERE ( PurchaseRequisitionItem = ls_input-item )
                                 NEXT n = n + 1 ).
      IF lv_lines > 1.
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = 'E'
                 iv_text  = |La posición tiene imputación múltiple ({ lv_lines } líneas); no soportado| ).
        CONTINUE.
      ENDIF.
      APPEND ls_input TO lt_change.
    ENDLOOP.

    IF lt_change IS INITIAL.
      RETURN.
    ENDIF.

    " ---- Procesar: sin prueba de BAPI. La BAPI deja el documento en memoria y
    "      una segunda llamada en la misma petición no grabaría nada. El saver
    "      llama la BAPI real una sola vez con estas posiciones.
    IF iv_test = abap_false.
      ms_bapi_data = build_bapi_data( lt_change ).
      LOOP AT lt_change INTO ls_input.
        APPEND VALUE #( row_no               = ls_input-row_no
                        purchase_requisition = mv_banfn
                        item                 = |{ CONV i( ls_input-item ) }|
                        acct_cat_old         = ls_input-acct_cat_old
                        acct_cat_new         = c_acct_cat_asset
                        master_fixed_asset   = |{ ls_input-asset ALPHA = OUT }|
                        fixed_asset          = |{ ls_input-subnumber ALPHA = OUT }|
                        company_code         = ls_input-company_code
                        step                 = c_step-change ) TO mt_pending.
      ENDLOOP.
      RETURN.
    ENDIF.

    " ---- Simular: BAPI_PR_CHANGE en modo prueba (sin grabar) ---------------
    DATA(lo_api) = zcl_mm_pr_change_api_fact=>create_instance( ).
    DATA(ls_data) = build_bapi_data( lt_change ).
    DATA(lt_return) = lo_api->change( EXPORTING iv_number  = mv_banfn
                                                iv_testrun = abap_true
                                      CHANGING  cs_data    = ls_data ).

    " Los mensajes de posición traen PARAMETER = PRITEM / PRACCOUNT y ROW =
    " fila de esa tabla; las tablas se arman en el mismo orden que lt_change.
    DATA(lv_general_error) = abap_false.
    " ME 664 (no se pudo modificar un campo) llega como 'I': se trata como error
    LOOP AT lt_return ASSIGNING FIELD-SYMBOL(<ls_664>) WHERE id = 'ME' AND number = '664'.
      <ls_664>-type = 'E'.
    ENDLOOP.

    LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EAW'.
      DATA(lv_row) = CONV i( ls_ret-row ).
      IF ( ls_ret-parameter CS 'PRITEM' OR ls_ret-parameter CS 'PRACCOUNT' )
         AND lv_row BETWEEN 1 AND lines( lt_change ).
        add_bapi_message( is_return = ls_ret
                          is_input  = lt_change[ lv_row ] ).
      ELSE.
        add_bapi_message( is_return = ls_ret ).
        IF ls_ret-type CA 'EA'.
          lv_general_error = abap_true.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " ---- Resultado por posición --------------------------------------------
    DATA lt_ok TYPE tt_input.
    LOOP AT lt_change INTO ls_input.
      IF line_exists( mt_error_rows[ table_line = ls_input-row_no ] ).
        CONTINUE.
      ENDIF.

      IF lv_general_error = abap_true.
        " SAP devolvió un error sin posición: no se puede saber cuál falla
        add_log( is_input = ls_input
                 iv_step  = c_step-validation
                 iv_type  = COND #( WHEN iv_test = abap_true THEN 'W' ELSE 'E' )
                 iv_text  = COND #( WHEN iv_test = abap_true
                                    THEN `Sin errores en la posición, pero SAP devolvió errores de la solped (ver fila 1)`
                                    ELSE `No se modificó: SAP devolvió errores de la solped (ver fila 1)` ) ).
        CONTINUE.
      ENDIF.

      APPEND ls_input TO lt_ok.
      add_log( is_input = ls_input
               iv_step  = COND #( WHEN iv_test = abap_true THEN c_step-validation ELSE c_step-change )
               iv_type  = 'S'
               iv_text  = COND #( WHEN iv_test = abap_true
                                  THEN |Validación SAP correcta: se cambiaría la imputación { ls_input-acct_cat_old } a A | &&
                                       |con el activo { ls_input-asset ALPHA = OUT }-{ ls_input-subnumber ALPHA = OUT }|
                                  ELSE |Imputación cambiada de { ls_input-acct_cat_old } a A y activo | &&
                                       |{ ls_input-asset ALPHA = OUT }-{ ls_input-subnumber ALPHA = OUT } asignado| ) ).
    ENDLOOP.

  ENDMETHOD.


  METHOD build_bapi_data.
    " Como en ME52N al cambiar a A: tipo de imputación A en la posición y, en la
    " línea de imputación 01, activo + subnúmero; se limpian centro de coste y
    " cuenta de mayor del tipo anterior (SAP deriva la cuenta de la clase del activo).
    LOOP AT it_input INTO DATA(ls_input).
      APPEND VALUE #( preq_item  = ls_input-item
                      acctasscat = c_acct_cat_asset ) TO rs_data-item.
      APPEND VALUE #( preq_item  = ls_input-item
                      preq_itemx = abap_true
                      acctasscat = abap_true ) TO rs_data-itemx.

      APPEND VALUE #( preq_item  = ls_input-item
                      serial_no  = '01'
                      quantity   = ls_input-quantity
                      asset_no   = ls_input-asset
                      sub_number = ls_input-subnumber
                      costcenter = space
                      gl_account = space ) TO rs_data-account.
      APPEND VALUE #( preq_item  = ls_input-item
                      serial_no  = '01'
                      preq_itemx = abap_true
                      serial_nox = abap_true
                      quantity   = abap_true
                      asset_no   = abap_true
                      sub_number = abap_true
                      costcenter = abap_true
                      gl_account = abap_true ) TO rs_data-accountx.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalize.
    rv_value = to_upper( condense( iv_value ) ).
    " Excel puede devolver enteros como "10.0"
    rv_value = replace( val = rv_value pcre = `\.0+$` with = `` ).
    " Quita caracteres invisibles (espacio duro, BOM, comillas, etc.)
    rv_value = replace( val = rv_value pcre = `[^0-9A-Z.+\-]` with = `` occ = 0 ).
  ENDMETHOD.


  METHOD add_log.
    DATA(lv_row) = COND i( WHEN is_input IS SUPPLIED AND is_input-row_no > 0
                           THEN is_input-row_no
                           ELSE iv_row ).

    APPEND VALUE #( row_no               = lv_row
                    purchase_requisition = mv_banfn
                    item                 = COND #( WHEN is_input-item IS NOT INITIAL
                                                   THEN |{ CONV i( is_input-item ) }| )
                    acct_cat_old         = is_input-acct_cat_old
                    acct_cat_new         = COND #( WHEN is_input-item IS NOT INITIAL THEN c_acct_cat_asset )
                    master_fixed_asset   = |{ is_input-asset ALPHA = OUT }|
                    fixed_asset          = |{ is_input-subnumber ALPHA = OUT }|
                    company_code         = is_input-company_code
                    step                 = iv_step
                    msg_type             = iv_type
                    msg_origin           = iv_origin
                    msg_id               = iv_msgid
                    msg_no               = iv_msgno
                    message              = iv_text ) TO mt_log.

    " Una posición cuenta como error si tiene al menos un mensaje E
    IF iv_type = 'E' AND is_input IS SUPPLIED AND is_input-row_no > 0.
      INSERT is_input-row_no INTO TABLE mt_error_rows.
    ENDIF.
  ENDMETHOD.


  METHOD add_bapi_message.
    DATA(lv_type) = COND ty_c1( WHEN is_return-type = 'A' THEN 'E' ELSE is_return-type ).
    DATA(lv_text) = COND string( WHEN is_return-message IS NOT INITIAL
                                 THEN is_return-message
                                 ELSE |{ is_return-id } { is_return-number }| ).

    IF is_input-row_no > 0.
      add_log( is_input  = is_input
               iv_step   = c_step-change
               iv_type   = lv_type
               iv_origin = c_origin-sap
               iv_msgid  = CONV #( is_return-id )
               iv_msgno  = CONV #( is_return-number )
               iv_text   = lv_text ).
    ELSE.
      add_log( iv_row    = 1
               iv_step   = c_step-change
               iv_type   = lv_type
               iv_origin = c_origin-sap
               iv_msgid  = CONV #( is_return-id )
               iv_msgno  = CONV #( is_return-number )
               iv_text   = lv_text ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
