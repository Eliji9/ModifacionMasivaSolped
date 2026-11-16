"! <p class="shorttext synchronized">bgPF: procesa la carga de modificación masiva de solped</p>
"! Operación no controlada (uncontrolled) del Background Processing Framework.
"! Corre fuera de la transacción RAP de la app, por eso aquí SÍ se permite
"! COMMIT ENTITIES / COMMIT WORK sin dumps.
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

    METHODS save_result
      IMPORTING iv_banfn   TYPE zcl_solped_imput_proc=>ty_banfn
                it_log     TYPE zcl_solped_imput_proc=>tt_log
                is_summary TYPE zcl_solped_imput_proc=>ty_summary.

ENDCLASS.



CLASS zcl_solped_imput_bgpf IMPLEMENTATION.

  METHOD constructor.
    mv_upload_uuid = iv_upload_uuid.
  ENDMETHOD.


  METHOD if_bgmc_op_single_tx_uncontr~execute.
    SELECT SINGLE file_content
      FROM ztmm_solped_up
      WHERE upload_uuid = @mv_upload_uuid
      INTO @DATA(lv_file).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Lee, valida y modifica la solped (COMMIT ENTITIES dentro: todo junto o
    " posición por posición si SAP rechaza el grabado conjunto)
    NEW zcl_solped_imput_proc( )->execute( EXPORTING iv_file    = lv_file
                                                     iv_test    = abap_false
                                           IMPORTING ev_banfn   = DATA(lv_banfn)
                                                     et_log     = DATA(lt_log)
                                                     es_summary = DATA(ls_summary) ).

    save_result( iv_banfn   = lv_banfn
                 it_log     = lt_log
                 is_summary = ls_summary ).
  ENDMETHOD.


  METHOD save_result.
    DATA lv_now    TYPE timestampl.
    DATA lt_db_log TYPE STANDARD TABLE OF ztmm_solped_lg WITH EMPTY KEY.

    GET TIME STAMP FIELD lv_now.
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    LOOP AT it_log INTO DATA(ls_log).
      TRY.
          DATA(lv_log_uuid) = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
          CONTINUE.
      ENDTRY.

      APPEND VALUE #( log_uuid              = lv_log_uuid
                      upload_uuid           = mv_upload_uuid
                      row_no                = ls_log-row_no
                      purchase_requisition  = ls_log-purchase_requisition
                      item                  = ls_log-item
                      acct_cat_old          = ls_log-acct_cat_old
                      acct_cat_new          = ls_log-acct_cat_new
                      master_fixed_asset    = ls_log-master_fixed_asset
                      fixed_asset           = ls_log-fixed_asset
                      company_code          = ls_log-company_code
                      step                  = ls_log-step
                      msg_type              = ls_log-msg_type
                      msg_origin            = ls_log-msg_origin
                      msg_id                = ls_log-msg_id
                      msg_no                = ls_log-msg_no
                      message               = ls_log-message
                      local_created_by      = lv_user
                      local_created_at      = lv_now
                      local_last_changed_at = lv_now ) TO lt_db_log.
    ENDLOOP.

    " P = Procesada, E = Procesada con errores
    DATA lv_status TYPE c LENGTH 1.
    lv_status = COND #( WHEN line_exists( it_log[ msg_type = 'E' ] ) THEN 'E'
                        ELSE 'P' ).

    " Tablas propias de la app: el log anterior ya lo borró la acción Procesar
    DELETE FROM ztmm_solped_lg WHERE upload_uuid = @mv_upload_uuid.
    INSERT ztmm_solped_lg FROM TABLE @lt_db_log.

    UPDATE ztmm_solped_up
      SET purchase_requisition  = @iv_banfn,
          status                = @lv_status,
          total_items           = @is_summary-total,
          ok_items              = @is_summary-ok,
          error_items           = @is_summary-errors,
          processed_at          = @lv_now,
          local_last_changed_by = @lv_user,
          local_last_changed_at = @lv_now,
          last_changed_at       = @lv_now
      WHERE upload_uuid = @mv_upload_uuid.

    COMMIT WORK.
  ENDMETHOD.

ENDCLASS.
