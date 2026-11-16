*"* Implementación del comportamiento de ZR_SOLPED_UP
*"* (pestaña "Local Types" del behavior pool ZBP_R_SOLPED_UP)

"! Buffer de la transacción: posiciones aprobadas por SAP en Procesar, que el
"! saver graba con BAPI_PR_CHANGE (RAP hace el COMMIT).
CLASS lcl_buffer DEFINITION FINAL.
  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_pending,
        upload_uuid TYPE sysuuid_x16,
        banfn       TYPE zcl_solped_imput_proc=>ty_banfn,
        data        TYPE zif_mm_pr_change_api=>ty_data,
        log         TYPE zcl_solped_imput_proc=>tt_log,
        own_errors  TYPE i,
      END OF ty_pending,
      tt_pending TYPE STANDARD TABLE OF ty_pending WITH EMPTY KEY.
    CLASS-DATA mt_pending TYPE tt_pending.
ENDCLASS.

CLASS lcl_buffer IMPLEMENTATION.
ENDCLASS.


CLASS lhc_upload DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF c_status,
        new         TYPE c LENGTH 1 VALUE 'N',
        simulated   TYPE c LENGTH 1 VALUE 'S',
        processed   TYPE c LENGTH 1 VALUE 'P',
        with_errors TYPE c LENGTH 1 VALUE 'E',
      END OF c_status,
      BEGIN OF c_mode,
        test TYPE c LENGTH 1 VALUE 'S',
        real TYPE c LENGTH 1 VALUE 'R',
      END OF c_mode.

    TYPES tt_upload_keys TYPE TABLE FOR READ IMPORT zr_solped_up\\Upload.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Upload RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Upload RESULT result.

    METHODS setInitialStatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Upload~setInitialStatus.

    METHODS validateFile FOR VALIDATE ON SAVE
      IMPORTING keys FOR Upload~validateFile.

    METHODS simular FOR MODIFY
      IMPORTING keys FOR ACTION Upload~simular RESULT result.

    METHODS procesar FOR MODIFY
      IMPORTING keys FOR ACTION Upload~procesar RESULT result.

    "! Simular / Procesar: lee, valida y prueba la BAPI (TESTRUN); deja resumen y log
    METHODS run
      IMPORTING it_keys TYPE tt_upload_keys
                iv_test TYPE abap_bool.

    "! Borra el log de la ejecución anterior
    METHODS delete_old_log
      IMPORTING it_keys TYPE tt_upload_keys.

ENDCLASS.


CLASS lhc_upload IMPLEMENTATION.

  METHOD get_global_authorizations.
    " La autorización de modificar la solped la valida BAPI_PR_CHANGE
    " (mismas autorizaciones que ME52N).
    result = VALUE #( %create          = if_abap_behv=>auth-allowed
                      %update          = if_abap_behv=>auth-allowed
                      %delete          = if_abap_behv=>auth-allowed
                      %action-simular  = if_abap_behv=>auth-allowed
                      %action-procesar = if_abap_behv=>auth-allowed
                      %action-Edit     = if_abap_behv=>auth-allowed ).
  ENDMETHOD.


  METHOD get_instance_features.
    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        FIELDS ( Status FileName ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload)
      FAILED failed.

    " Simular / Procesar solo con archivo cargado y mientras no se haya
    " procesado completo sin errores.
    " Procesar solo sobre la instancia activa (no sobre el borrador).
    result = VALUE #( FOR ls_upload IN lt_upload
                      ( %tky             = ls_upload-%tky
                        %action-simular  = COND #( WHEN ls_upload-FileName IS INITIAL
                                                     OR ls_upload-Status = c_status-processed
                                                   THEN if_abap_behv=>fc-o-disabled
                                                   ELSE if_abap_behv=>fc-o-enabled )
                        %action-procesar = COND #( WHEN ls_upload-FileName IS INITIAL
                                                     OR ls_upload-Status = c_status-processed
                                                     OR ls_upload-%is_draft = if_abap_behv=>mk-on
                                                   THEN if_abap_behv=>fc-o-disabled
                                                   ELSE if_abap_behv=>fc-o-enabled ) ) ).
  ENDMETHOD.


  METHOD setInitialStatus.
    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        FIELDS ( Status ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload).

    DELETE lt_upload WHERE Status IS NOT INITIAL.
    CHECK lt_upload IS NOT INITIAL.

    MODIFY ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        UPDATE FIELDS ( Status )
        WITH VALUE #( FOR ls_upload IN lt_upload
                      ( %tky   = ls_upload-%tky
                        Status = c_status-new ) ).
  ENDMETHOD.


  METHOD validateFile.
    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        FIELDS ( FileName ) WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload).

    LOOP AT lt_upload INTO DATA(ls_upload).
      APPEND VALUE #( %tky        = ls_upload-%tky
                      %state_area = 'VALIDATE_FILE' ) TO reported-upload.

      DATA(lv_text) = COND string(
        WHEN ls_upload-FileName IS INITIAL
          THEN `Suba el archivo Excel (.xlsx) con la solped y sus posiciones`
        WHEN to_upper( ls_upload-FileName ) NP '*.XLSX'
          THEN `El archivo debe ser de tipo .xlsx` ).

      IF lv_text IS NOT INITIAL.
        APPEND VALUE #( %tky = ls_upload-%tky ) TO failed-upload.
        APPEND VALUE #( %tky                 = ls_upload-%tky
                        %state_area          = 'VALIDATE_FILE'
                        %msg                 = new_message_with_text(
                                                 severity = if_abap_behv_message=>severity-error
                                                 text     = lv_text )
                        %element-FileContent = if_abap_behv=>mk-on ) TO reported-upload.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD simular.
    run( it_keys = CORRESPONDING #( keys )
         iv_test = abap_true ).

    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload).

    " Mensaje resumen para el usuario
    LOOP AT lt_upload INTO DATA(ls_msg).
      APPEND VALUE #( %tky = ls_msg-%tky
                      %msg = new_message_with_text(
                               " Information (no warning): un warning hace que Fiori pida
                               " confirmación y vuelva a ejecutar la acción
                               severity = COND #( WHEN ls_msg-ErrorItems > 0 OR ls_msg-TotalItems = 0
                                                  THEN if_abap_behv_message=>severity-information
                                                  ELSE if_abap_behv_message=>severity-success )
                               " Máximo 50 caracteres: el texto se corta en el popup
                               text     = |Simulación { CONV string( ls_msg-PurchaseRequisition ) ALPHA = OUT }: | &&
                                          |{ ls_msg-OkItems } OK, { ls_msg-ErrorItems } con error. Ver log| ) )
        TO reported-upload.
    ENDLOOP.

    result = VALUE #( FOR ls_upload IN lt_upload
                      ( %tky   = ls_upload-%tky
                        %param = ls_upload ) ).
  ENDMETHOD.


  METHOD procesar.
    " Validaciones propias y deja en lcl_buffer las posiciones válidas. El saver
    " (save_modified) llama BAPI_PR_CHANGE una sola vez, escribe el resultado por
    " posición en el log y RAP hace el COMMIT.
    run( it_keys = CORRESPONDING #( keys )
         iv_test = abap_false ).

    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload).

    " Mensaje resumen para el usuario (máx. 50 caracteres, severidad informativa)
    LOOP AT lt_upload INTO DATA(ls_msg).
      APPEND VALUE #( %tky = ls_msg-%tky
                      %msg = new_message_with_text(
                               severity = COND #( WHEN ls_msg-ErrorItems > 0 OR ls_msg-TotalItems = 0
                                                  THEN if_abap_behv_message=>severity-information
                                                  ELSE if_abap_behv_message=>severity-success )
                               text     = |Solped { CONV string( ls_msg-PurchaseRequisition ) ALPHA = OUT } procesada. Ver log| ) )
        TO reported-upload.
    ENDLOOP.

    result = VALUE #( FOR ls_upload IN lt_upload
                      ( %tky   = ls_upload-%tky
                        %param = ls_upload ) ).
  ENDMETHOD.


  METHOD delete_old_log.
    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload BY \_Log
        FIELDS ( LogUuid ) WITH CORRESPONDING #( it_keys )
        RESULT DATA(lt_old_log).

    IF lt_old_log IS NOT INITIAL.
      MODIFY ENTITIES OF zr_solped_up IN LOCAL MODE
        ENTITY Log
          DELETE FROM VALUE #( FOR ls_old IN lt_old_log ( %tky = ls_old-%tky ) ).
    ENDIF.
  ENDMETHOD.


  METHOD run.
    DATA lv_now    TYPE timestampl.
    DATA lv_status TYPE c LENGTH 1.

    GET TIME STAMP FIELD lv_now.

    " Cada ejecución reemplaza el log anterior
    delete_old_log( it_keys ).

    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        FIELDS ( FileContent FileName ) WITH CORRESPONDING #( it_keys )
        RESULT DATA(lt_upload).

    LOOP AT lt_upload INTO DATA(ls_upload).

      " Lectura del Excel, validaciones y prueba con BAPI_PR_CHANGE (TESTRUN)
      DATA(lo_processor) = NEW zcl_solped_imput_proc( ).
      lo_processor->execute( EXPORTING iv_file    = ls_upload-FileContent
                                       iv_test    = iv_test
                             IMPORTING ev_banfn   = DATA(lv_banfn)
                                       et_log     = DATA(lt_log)
                                       es_summary = DATA(ls_summary)
                                       es_bapi_data = DATA(ls_bapi_data)
                                       et_pending   = DATA(lt_pending) ).

      " Procesar: posiciones aprobadas para grabar en el saver
      IF iv_test = abap_false AND ls_bapi_data-item IS NOT INITIAL.
        DELETE lcl_buffer=>mt_pending WHERE upload_uuid = ls_upload-UploadUuid.
        APPEND VALUE #( upload_uuid = ls_upload-UploadUuid
                        banfn       = lv_banfn
                        data        = ls_bapi_data
                        log         = lt_pending
                        own_errors  = ls_summary-errors ) TO lcl_buffer=>mt_pending.
      ENDIF.

      DATA(lv_has_error) = xsdbool( line_exists( lt_log[ msg_type = 'E' ] ) ).

      lv_status = COND #( WHEN iv_test = abap_true    THEN c_status-simulated
                          WHEN lv_has_error = abap_true THEN c_status-with_errors
                          ELSE c_status-processed ).

      MODIFY ENTITIES OF zr_solped_up IN LOCAL MODE
        ENTITY Upload
          UPDATE FIELDS ( PurchaseRequisition Status RunMode TotalItems OkItems ErrorItems ProcessedAt )
          WITH VALUE #( ( %tky                = ls_upload-%tky
                          PurchaseRequisition = lv_banfn
                          Status              = lv_status
                          RunMode             = COND #( WHEN iv_test = abap_true THEN c_mode-test ELSE c_mode-real )
                          TotalItems          = ls_summary-total
                          OkItems             = ls_summary-ok
                          ErrorItems          = ls_summary-errors
                          ProcessedAt         = lv_now ) )
          CREATE BY \_Log
          FIELDS ( RowNo PurchaseRequisition PurchaseRequisitionItem AcctAssgmtCatOld AcctAssgmtCatNew
                   MasterFixedAsset FixedAsset CompanyCode Step MsgType MsgOrigin MsgId MsgNo Message )
          WITH VALUE #( ( %tky    = ls_upload-%tky
                          %target = VALUE #( FOR ls_log IN lt_log INDEX INTO lv_index
                                             ( %cid                    = |LOG{ lv_index }|
                                               %is_draft               = ls_upload-%is_draft
                                               RowNo                   = ls_log-row_no
                                               PurchaseRequisition     = ls_log-purchase_requisition
                                               PurchaseRequisitionItem = ls_log-item
                                               AcctAssgmtCatOld        = ls_log-acct_cat_old
                                               AcctAssgmtCatNew        = ls_log-acct_cat_new
                                               MasterFixedAsset        = ls_log-master_fixed_asset
                                               FixedAsset              = ls_log-fixed_asset
                                               CompanyCode             = ls_log-company_code
                                               Step                    = ls_log-step
                                               MsgType                 = ls_log-msg_type
                                               MsgOrigin               = ls_log-msg_origin
                                               MsgId                   = ls_log-msg_id
                                               MsgNo                   = ls_log-msg_no
                                               Message                 = ls_log-message ) ) ) ).


    ENDLOOP.
  ENDMETHOD.

ENDCLASS.


"! Saver: graba con BAPI_PR_CHANGE las posiciones aprobadas en Procesar.
"! La BAPI deja el cambio en la tarea de actualización y el COMMIT lo hace RAP
"! (no se llama BAPI_TRANSACTION_COMMIT ni COMMIT WORK).
CLASS lsc_zr_solped_up DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
    METHODS cleanup_finalize REDEFINITION.

ENDCLASS.


CLASS lsc_zr_solped_up IMPLEMENTATION.

  METHOD save_modified.
    DATA lv_now     TYPE timestampl.
    DATA lt_db_log  TYPE STANDARD TABLE OF ztmm_solped_lg WITH EMPTY KEY.

    GET TIME STAMP FIELD lv_now.
    DATA(lv_user) = cl_abap_context_info=>get_user_technical_name( ).

    LOOP AT lcl_buffer=>mt_pending INTO DATA(ls_pending).
      CLEAR lt_db_log.
      DATA(ls_data) = ls_pending-data.

      " Llamada real (una sola vez). La BAPI deja el cambio en la tarea de
      " actualización y RAP hace el COMMIT.
      DATA(lt_return) = zcl_mm_pr_change_api_fact=>create_instance( )->change(
                          EXPORTING iv_number  = ls_pending-banfn
                                    iv_testrun = abap_false
                          CHANGING  cs_data    = ls_data ).

      " ME 664 (no se pudo modificar un campo, p. ej. KNTTP) llega como 'I'
      LOOP AT lt_return ASSIGNING FIELD-SYMBOL(<ls_ret>) WHERE id = 'ME' AND number = '664'.
        <ls_ret>-type = 'E'.
      ENDLOOP.

      " Errores de cabecera: SAP no graba la solped
      DATA(lv_header_error) = abap_false.
      LOOP AT lt_return INTO DATA(ls_ret) WHERE type CA 'EA'
           AND NOT ( parameter CS 'PRITEM' OR parameter CS 'PRACCOUNT' ).
        lv_header_error = abap_true.
        APPEND VALUE #( row_no = 1 msg_type = 'E' msg_origin = 'S'
                        msg_id = ls_ret-id msg_no = ls_ret-number
                        message = ls_ret-message ) TO lt_db_log.
      ENDLOOP.

      " Resultado por posición (PRITEM / PRACCOUNT, ROW = orden de envío)
      DATA(lv_ok)  = 0.
      DATA(lv_err) = ls_pending-own_errors.
      LOOP AT ls_pending-log INTO DATA(ls_line).
        DATA(lv_index) = sy-tabix.
        DATA(lv_item_error) = lv_header_error.

        LOOP AT lt_return INTO ls_ret
             WHERE ( parameter CS 'PRITEM' OR parameter CS 'PRACCOUNT' )
               AND row = lv_index
               AND type CA 'EAW'.
          IF ls_ret-type CA 'EA'.
            lv_item_error = abap_true.
          ENDIF.
          DATA(ls_msg_line) = ls_line.
          ls_msg_line-msg_type   = COND #( WHEN ls_ret-type = 'A' THEN 'E' ELSE ls_ret-type ).
          ls_msg_line-msg_origin = 'S'.
          ls_msg_line-msg_id     = ls_ret-id.
          ls_msg_line-msg_no     = ls_ret-number.
          ls_msg_line-message    = ls_ret-message.
          APPEND CORRESPONDING #( ls_msg_line ) TO lt_db_log.
        ENDLOOP.

        ls_line-msg_origin = 'Z'.
        IF lv_item_error = abap_true.
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

      " Claves y datos administrativos del log
      LOOP AT lt_db_log ASSIGNING FIELD-SYMBOL(<ls_db>).
        TRY.
            <ls_db>-log_uuid = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
        ENDTRY.
        <ls_db>-upload_uuid           = ls_pending-upload_uuid.
        <ls_db>-purchase_requisition  = ls_pending-banfn.
        <ls_db>-step                  = 'M'.
        <ls_db>-local_created_by      = lv_user.
        <ls_db>-local_created_at      = lv_now.
        <ls_db>-local_last_changed_at = lv_now.
      ENDLOOP.
      INSERT ztmm_solped_lg FROM TABLE @lt_db_log.

      " Resumen final de la carga
      DATA lv_status TYPE c LENGTH 1.
      lv_status = COND #( WHEN lv_err > 0 THEN 'E' ELSE 'P' ).
      UPDATE ztmm_solped_up
        SET ok_items    = @lv_ok,
            error_items = @lv_err,
            status      = @lv_status
        WHERE upload_uuid = @ls_pending-upload_uuid.
    ENDLOOP.

    CLEAR lcl_buffer=>mt_pending.
  ENDMETHOD.


  METHOD cleanup_finalize.
    CLEAR lcl_buffer=>mt_pending.
  ENDMETHOD.

ENDCLASS.
