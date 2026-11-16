"! <p class="shorttext synchronized">Modificación masiva solped: imputación A + activo fijo</p>
"! Lee el Excel (XCO), valida la solped y sus posiciones con vistas CDS liberadas
"! y modifica la solped con EML sobre el BO estándar I_PurchaseRequisitionTP.
"! No hace COMMIT: se llama desde una acción RAP y el framework graba al final.
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
    METHODS execute
      IMPORTING iv_file    TYPE xstring
                iv_test    TYPE abap_bool
      EXPORTING ev_banfn   TYPE ty_banfn
                et_log     TYPE tt_log
                es_summary TYPE ty_summary.

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

    METHODS add_sap_message
      IMPORTING io_msg   TYPE REF TO if_abap_behv_message
                is_input TYPE ty_input OPTIONAL.

ENDCLASS.



CLASS zcl_solped_imput_proc IMPLEMENTATION.

  METHOD execute.
    DATA lt_rows TYPE tt_row.

    CLEAR: mv_banfn, mt_items, mt_log, mt_error_rows, mv_total,
           ev_banfn, et_log, es_summary.

    " 1. Lectura del Excel
    TRY.
        lt_rows = read_excel( iv_file ).
      CATCH cx_root INTO DATA(lx_error).
        add_log( iv_row  = 0
                 iv_step = c_step-read
                 iv_type = 'E'
                 iv_text = |No se pudo leer el archivo Excel: { lx_error->get_text( ) }| ).
    ENDTRY.

    " 2. Interpretación de filas (solped + posiciones)
    DATA(lt_input) = parse( lt_rows ).

    IF mv_banfn IS INITIAL AND mt_log IS INITIAL.
      add_log( iv_row  = 0
               iv_step = c_step-read
               iv_type = 'E'
               iv_text = 'El archivo no contiene datos' ).
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
  ENDMETHOD.


  METHOD read_excel.
    DATA(lo_document) = xco_cp_xlsx=>document->for_file_content( iv_file )->read_access( ).
    DATA(lo_worksheet) = lo_document->get_workbook( )->worksheet->at_position( 1 ).

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
    DATA lt_change   TYPE tt_input.
    DATA lt_failed   TYPE tt_item_set.
    DATA lv_item     TYPE ty_item_no.
    DATA lt_upd_item TYPE TABLE FOR UPDATE i_purchaserequisitiontp\\PurchaseRequisitionItem.
    DATA lt_cba_acct TYPE TABLE FOR CREATE i_purchaserequisitiontp\\PurchaseRequisitionItem\_PurchaseReqnAcctAssgmt.
    DATA lt_upd_acct TYPE TABLE FOR UPDATE i_purchaserequisitiontp\\PurReqnItmAccountAssignment.
    DATA lt_revert   TYPE TABLE FOR UPDATE i_purchaserequisitiontp\\PurchaseRequisitionItem.

    " ---- Simulación: solo validaciones ------------------------------------
    IF iv_test = abap_true.
      LOOP AT it_input INTO DATA(ls_test).
        add_log( is_input = ls_test
                 iv_step  = c_step-validation
                 iv_type  = 'S'
                 iv_text  = |Validación correcta: se cambiaría la imputación { ls_test-acct_cat_old } a A | &&
                            |con el activo { ls_test-asset ALPHA = OUT }-{ ls_test-subnumber ALPHA = OUT }| ).
      ENDLOOP.
      RETURN.
    ENDIF.

    " ---- 1. Imputaciones actuales de las posiciones -----------------------
    READ ENTITIES OF i_purchaserequisitiontp
      ENTITY PurchaseRequisitionItem BY \_PurchaseReqnAcctAssgmt
        ALL FIELDS WITH VALUE #( FOR ls_in IN it_input
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

    " ---- 2. Tipo de imputación A + activo en la línea de imputación -------
    LOOP AT lt_change INTO ls_input.
      APPEND VALUE #( PurchaseRequisition       = mv_banfn
                      PurchaseRequisitionItem   = ls_input-item
                      AccountAssignmentCategory = c_acct_cat_asset ) TO lt_upd_item.

      READ TABLE lt_accts INTO DATA(ls_acct)
           WITH KEY PurchaseRequisitionItem = ls_input-item.
      IF sy-subrc = 0.
        " La posición ya tiene línea de imputación: se actualiza
        APPEND VALUE #( %tky             = ls_acct-%tky
                        MasterFixedAsset = ls_input-asset
                        FixedAsset       = ls_input-subnumber ) TO lt_upd_acct.
      ELSE.
        " Sin línea de imputación: se crea la línea 01 por toda la cantidad
        APPEND VALUE #( PurchaseRequisition     = mv_banfn
                        PurchaseRequisitionItem = ls_input-item
                        %target = VALUE #( ( %cid             = |ACC{ ls_input-item }|
                                             MasterFixedAsset = ls_input-asset
                                             FixedAsset       = ls_input-subnumber
                                             Quantity         = ls_input-quantity ) ) ) TO lt_cba_acct.
      ENDIF.
    ENDLOOP.

    " Mismo MODIFY: el estándar exige cambiar tipo e imputación en el mismo LUW
    MODIFY ENTITIES OF i_purchaserequisitiontp
      ENTITY PurchaseRequisitionItem
        UPDATE FIELDS ( AccountAssignmentCategory ) WITH lt_upd_item
        CREATE BY \_PurchaseReqnAcctAssgmt
          FIELDS ( MasterFixedAsset FixedAsset Quantity ) WITH lt_cba_acct
      ENTITY PurReqnItmAccountAssignment
        UPDATE FIELDS ( MasterFixedAsset FixedAsset ) WITH lt_upd_acct
      FAILED DATA(ls_failed)
      REPORTED DATA(ls_reported).

    " ---- 3. Posiciones rechazadas por el BO estándar ----------------------
    LOOP AT ls_failed-purchaserequisitionitem INTO DATA(ls_failed_item).
      INSERT CONV ty_item_no( ls_failed_item-PurchaseRequisitionItem ) INTO TABLE lt_failed.
    ENDLOOP.
    LOOP AT ls_failed-purreqnitmaccountassignment INTO DATA(ls_failed_acct).
      lv_item = COND #( WHEN ls_failed_acct-%cid IS NOT INITIAL
                        THEN substring( val = ls_failed_acct-%cid off = 3 )
                        ELSE ls_failed_acct-PurchaseRequisitionItem ).
      INSERT lv_item INTO TABLE lt_failed.
    ENDLOOP.

    " Si falló la imputación, se devuelve el tipo de imputación original para
    " que esa posición no quede en A sin activo (y no bloquee el grabado).
    IF lt_failed IS NOT INITIAL.
      LOOP AT lt_failed INTO DATA(lv_failed).
        READ TABLE lt_change INTO DATA(ls_failed_input) WITH KEY item = lv_failed.
        IF sy-subrc = 0.
          APPEND VALUE #( PurchaseRequisition       = mv_banfn
                          PurchaseRequisitionItem   = lv_failed
                          AccountAssignmentCategory = ls_failed_input-acct_cat_old ) TO lt_revert.
        ENDIF.
      ENDLOOP.

      IF lt_revert IS NOT INITIAL.
        MODIFY ENTITIES OF i_purchaserequisitiontp
          ENTITY PurchaseRequisitionItem
            UPDATE FIELDS ( AccountAssignmentCategory ) WITH lt_revert.
      ENDIF.
    ENDIF.

    " ---- 4. Mensajes del estándar al log -----------------------------------
    LOOP AT ls_reported-purchaserequisition INTO DATA(ls_rep_header).
      add_sap_message( io_msg = ls_rep_header-%msg ).
    ENDLOOP.

    LOOP AT ls_reported-purchaserequisitionitem INTO DATA(ls_rep_item).
      add_sap_message( io_msg   = ls_rep_item-%msg
                       is_input = VALUE #( lt_change[ item = ls_rep_item-PurchaseRequisitionItem ] OPTIONAL ) ).
    ENDLOOP.

    LOOP AT ls_reported-purreqnitmaccountassignment INTO DATA(ls_rep_acct).
      lv_item = COND #( WHEN ls_rep_acct-%cid IS NOT INITIAL
                        THEN substring( val = ls_rep_acct-%cid off = 3 )
                        ELSE ls_rep_acct-PurchaseRequisitionItem ).
      add_sap_message( io_msg   = ls_rep_acct-%msg
                       is_input = VALUE #( lt_change[ item = lv_item ] OPTIONAL ) ).
    ENDLOOP.

    " ---- 5. Resultado por posición -----------------------------------------
    LOOP AT lt_change INTO ls_input.
      IF line_exists( lt_failed[ table_line = ls_input-item ] ).
        IF NOT line_exists( mt_error_rows[ table_line = ls_input-row_no ] ).
          add_log( is_input = ls_input
                   iv_step  = c_step-change
                   iv_type  = 'E'
                   iv_text  = 'SAP rechazó el cambio de la posición; no se modificó' ).
        ENDIF.
        CONTINUE.
      ENDIF.

      IF line_exists( mt_error_rows[ table_line = ls_input-row_no ] ).
        CONTINUE.
      ENDIF.

      add_log( is_input = ls_input
               iv_step  = c_step-change
               iv_type  = 'S'
               iv_text  = |Imputación cambiada de { ls_input-acct_cat_old } a A y activo | &&
                          |{ ls_input-asset ALPHA = OUT }-{ ls_input-subnumber ALPHA = OUT } asignado| ).
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


  METHOD add_sap_message.
    DATA lv_msgid TYPE ty_msgid.
    DATA lv_msgno TYPE ty_msgno.

    CHECK io_msg IS BOUND.

    DATA(lv_type) = SWITCH ty_c1( io_msg->m_severity
                      WHEN if_abap_behv_message=>severity-error   THEN 'E'
                      WHEN if_abap_behv_message=>severity-warning THEN 'W'
                      WHEN if_abap_behv_message=>severity-success THEN 'S'
                      ELSE 'I' ).

    " Solo errores y advertencias del estándar
    CHECK lv_type CA 'EW'.

    IF io_msg IS INSTANCE OF if_t100_message.
      DATA(ls_t100) = CAST if_t100_message( io_msg )->t100key.
      lv_msgid = ls_t100-msgid.
      lv_msgno = ls_t100-msgno.
    ENDIF.

    IF is_input-row_no > 0.
      add_log( is_input = is_input
               iv_step   = c_step-change
               iv_type   = lv_type
               iv_origin = c_origin-sap
               iv_msgid  = lv_msgid
               iv_msgno  = lv_msgno
               iv_text   = io_msg->if_message~get_text( ) ).
    ELSE.
      add_log( iv_row    = 1
               iv_step   = c_step-change
               iv_type   = lv_type
               iv_origin = c_origin-sap
               iv_msgid  = lv_msgid
               iv_msgno  = lv_msgno
               iv_text   = io_msg->if_message~get_text( ) ).
    ENDIF.
  ENDMETHOD.

ENDCLASS.
