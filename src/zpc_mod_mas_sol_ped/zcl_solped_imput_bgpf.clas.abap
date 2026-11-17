"! <p class="shorttext synchronized">bgPF: Procesar modificación masiva de solped</p>
"! Operación no controlada del Background Processing Framework. Corre FUERA de la
"! transacción RAP de la app, por eso aquí se permiten BAPI_PR_CHANGE con
"! BAPI_TRANSACTION_COMMIT / ROLLBACK (vía wrapper Tier 2) y COMMIT WORK.
"! Primero graba todas las posiciones en una sola llamada (como en SE37); si SAP
"! rechaza, reintenta posición por posición para que las demás sí se graben.
CLASS zcl_solped_imput_bgpf DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_bgmc_op_single_tx_uncontr.

    METHODS constructor
      IMPORTING iv_upload_uuid TYPE sysuuid_x16.

  PRIVATE SECTION.
    DATA mv_upload_uuid TYPE sysuuid_x16.

ENDCLASS.



CLASS zcl_solped_imput_bgpf IMPLEMENTATION.

  METHOD constructor.
    mv_upload_uuid = iv_upload_uuid.
  ENDMETHOD.


  METHOD if_bgmc_op_single_tx_uncontr~execute.
    DATA lt_db_log TYPE STANDARD TABLE OF ztmm_solped_lg WITH EMPTY KEY.
    DATA lv_now    TYPE timestampl.
    DATA lv_status TYPE c LENGTH 1.

    SELECT SINGLE file_content
      FROM ztmm_solped_up
      WHERE upload_uuid = @mv_upload_uuid
      INTO @DATA(lv_file).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " 1. Lectura del Excel y validaciones propias (sin BAPI)
    NEW zcl_solped_imput_proc( )->execute( EXPORTING iv_file      = lv_file
                                                     iv_test      = abap_false
                                           IMPORTING ev_banfn     = DATA(lv_banfn)
                                                     et_log       = DATA(lt_log)
                                                     es_summary   = DATA(ls_summary)
                                                     es_bapi_data = DATA(ls_all)
                                                     et_pending   = DATA(lt_pending) ).

    " Errores de validación propia
    LOOP AT lt_log INTO DATA(ls_own).
      APPEND CORRESPONDING #( ls_own ) TO lt_db_log.
    ENDLOOP.

    " 2. BAPI_PR_CHANGE
    "    2a. Una sola llamada con TODAS las posiciones + COMMIT (igual que la prueba
    "        exitosa en SE37: BAPI_PR_CHANGE -> BAPI_TRANSACTION_COMMIT).
    "    2b. Solo si 2a falla: ROLLBACK y posición por posición, para que una
    "        posición rechazada no impida modificar las demás.
    DATA(lo_api) = zcl_mm_pr_change_api_fact=>create_instance( ).
    DATA(lv_ok)  = 0.
    DATA(lv_err) = ls_summary-errors.

    IF lt_pending IS NOT INITIAL.
      DATA(ls_data_all) = VALUE zif_mm_pr_change_api=>ty_data(
        item     = ls_all-item
        itemx    = ls_all-itemx
        account  = ls_all-account
        accountx = ls_all-accountx ).

      DATA(lt_return_all) = lo_api->change( EXPORTING iv_number  = lv_banfn
                                                      iv_testrun = abap_false
                                            CHANGING  cs_data    = ls_data_all ).

      " ME 664 llega como 'I' pero significa que la BAPI NO aplicó el cambio
      LOOP AT lt_return_all ASSIGNING FIELD-SYMBOL(<ls_664_all>) WHERE id = 'ME' AND number = '664'.
        <ls_664_all>-type = 'E'.
      ENDLOOP.

      DATA(lv_all_ok) = xsdbool( NOT line_exists( lt_return_all[ type = 'E' ] )
                             AND NOT line_exists( lt_return_all[ type = 'A' ] ) ).

      IF lv_all_ok = abap_true.
        DATA(ls_commit_all) = lo_api->commit( ).
        IF ls_commit_all-type CA 'EA'.
          lv_all_ok = abap_false.
        ENDIF.
      ELSE.
        lo_api->rollback( ).
      ENDIF.
    ENDIF.

    IF lv_all_ok = abap_true.
      " 2a correcto: todas las posiciones quedan OK; advertencias de SAP (presupuesto, etc.)
      LOOP AT lt_pending INTO DATA(ls_line_ok).
        DATA(lv_idx_ok) = sy-tabix.
        LOOP AT lt_return_all INTO DATA(ls_ret_all) WHERE type = 'W'.
          " Mensaje ligado a una fila -> esa posición; mensaje general -> primera posición
          IF ( ls_ret_all-row > 0 AND ls_ret_all-row <> lv_idx_ok )
          OR ( ls_ret_all-row = 0 AND lv_idx_ok > 1 ).
            CONTINUE.
          ENDIF.
          DATA(ls_msg_ok) = ls_line_ok.
          ls_msg_ok-msg_type   = 'W'.
          ls_msg_ok-msg_origin = 'S'.
          ls_msg_ok-msg_id     = ls_ret_all-id.
          ls_msg_ok-msg_no     = ls_ret_all-number.
          ls_msg_ok-message    = ls_ret_all-message.
          APPEND CORRESPONDING #( ls_msg_ok ) TO lt_db_log.
        ENDLOOP.
        lv_ok += 1.
        ls_line_ok-msg_origin = 'Z'.
        ls_line_ok-msg_type   = 'S'.
        ls_line_ok-message    = |Imputación cambiada de { ls_line_ok-acct_cat_old } a A y activo | &&
                                |{ ls_line_ok-master_fixed_asset }-{ ls_line_ok-fixed_asset } asignado|.
        APPEND CORRESPONDING #( ls_line_ok ) TO lt_db_log.
      ENDLOOP.

    ELSE.
      " 2b. Posición por posición, con COMMIT o ROLLBACK
      LOOP AT lt_pending INTO DATA(ls_line).
        DATA(lv_index) = sy-tabix.
        DATA(lv_item)  = ls_all-item[ lv_index ]-preq_item.

        " Datos de BAPI solo de esta posición
        DATA(ls_data) = VALUE zif_mm_pr_change_api=>ty_data(
          item     = VALUE #( FOR i  IN ls_all-item     WHERE ( preq_item = lv_item ) ( i ) )
          itemx    = VALUE #( FOR ix IN ls_all-itemx    WHERE ( preq_item = lv_item ) ( ix ) )
          account  = VALUE #( FOR a  IN ls_all-account  WHERE ( preq_item = lv_item ) ( a ) )
          accountx = VALUE #( FOR ax IN ls_all-accountx WHERE ( preq_item = lv_item ) ( ax ) ) ).

        DATA(lt_return) = lo_api->change( EXPORTING iv_number  = lv_banfn
                                                    iv_testrun = abap_false
                                          CHANGING  cs_data    = ls_data ).

        " ME 664 llega como 'I' pero la BAPI NO aplicó el cambio: es error
        LOOP AT lt_return ASSIGNING FIELD-SYMBOL(<ls_664>) WHERE id = 'ME' AND number = '664'.
          <ls_664>-type = 'E'.
        ENDLOOP.

        DATA(lv_error) = xsdbool( line_exists( lt_return[ type = 'E' ] ) OR line_exists( lt_return[ type = 'A' ] ) ).

        IF lv_error = abap_true.
          lo_api->rollback( ).
        ELSE.
          DATA(ls_commit) = lo_api->commit( ).
          IF ls_commit-type CA 'EA'.
            lv_error = abap_true.
            APPEND ls_commit TO lt_return.
          ENDIF.
        ENDIF.

        " Mensajes de SAP de la posición (errores y advertencias)
        LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EAW'.
          DATA(ls_msg) = ls_line.
          ls_msg-msg_type   = COND #( WHEN ls_ret-type = 'A' THEN 'E' ELSE ls_ret-type ).
          ls_msg-msg_origin = 'S'.
          ls_msg-msg_id     = ls_ret-id.
          ls_msg-msg_no     = ls_ret-number.
          ls_msg-message    = ls_ret-message.
          APPEND CORRESPONDING #( ls_msg ) TO lt_db_log.
        ENDLOOP.

        " Resultado de la posición
        ls_line-msg_origin = 'Z'.
        IF lv_error = abap_true.
          lv_err += 1.
          ls_line-msg_type = 'E'.
          ls_line-message  = 'No se modificó la posición (ver mensaje de SAP)'.
        ELSE.
          lv_ok += 1.
          ls_line-msg_type = 'S'.
          ls_line-message  = |Imputación cambiada de { ls_line-acct_cat_old } a A y activo | &&
                             |{ ls_line-master_fixed_asset }-{ ls_line-fixed_asset } asignado|.
        ENDIF.
        APPEND CORRESPONDING #( ls_line ) TO lt_db_log.
      ENDLOOP.
    ENDIF.

    " 3. Log y resumen de la carga
    GET TIME STAMP FIELD lv_now.
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    LOOP AT lt_db_log ASSIGNING FIELD-SYMBOL(<ls_db>).
      TRY.
          <ls_db>-log_uuid = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
      ENDTRY.
      <ls_db>-upload_uuid           = mv_upload_uuid.
      <ls_db>-purchase_requisition  = lv_banfn.
      <ls_db>-local_created_by      = lv_user.
      <ls_db>-local_created_at      = lv_now.
      <ls_db>-local_last_changed_at = lv_now.
    ENDLOOP.

    lv_status = COND #( WHEN lv_err > 0 THEN 'E' ELSE 'P' ).

    DELETE FROM ztmm_solped_lg WHERE upload_uuid = @mv_upload_uuid.
    INSERT ztmm_solped_lg FROM TABLE @lt_db_log.
    UPDATE ztmm_solped_up
      SET purchase_requisition  = @lv_banfn,
          status                = @lv_status,
          total_items           = @ls_summary-total,
          ok_items              = @lv_ok,
          error_items           = @lv_err,
          processed_at          = @lv_now,
          local_last_changed_by = @lv_user,
          local_last_changed_at = @lv_now,
          last_changed_at       = @lv_now
      WHERE upload_uuid = @mv_upload_uuid.

    COMMIT WORK.
  ENDMETHOD.

ENDCLASS.
