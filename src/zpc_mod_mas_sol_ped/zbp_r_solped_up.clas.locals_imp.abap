*"* Implementación del comportamiento de ZR_SOLPED_UP
*"* (pestaña "Local Types" del behavior pool ZBP_R_SOLPED_UP)

CLASS lhc_upload DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF c_status,
        new         TYPE c LENGTH 1 VALUE 'N',
        simulated   TYPE c LENGTH 1 VALUE 'S',
        running     TYPE c LENGTH 1 VALUE 'R',
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
                                                     OR ls_upload-Status = c_status-running
                                                   THEN if_abap_behv=>fc-o-disabled
                                                   ELSE if_abap_behv=>fc-o-enabled )
                        %action-procesar = COND #( WHEN ls_upload-FileName IS INITIAL
                                                     OR ls_upload-Status = c_status-processed
                                                     OR ls_upload-Status = c_status-running
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
    " La acción no modifica la solped: borra el log anterior y deja la carga
    " "En proceso". El saver registra la operación bgPF ZCL_SOLPED_IMPUT_BGPF,
    " que llama BAPI_PR_CHANGE con COMMIT por posición y graba el log.
    delete_old_log( CORRESPONDING #( keys ) ).

    MODIFY ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        UPDATE FIELDS ( Status RunMode TotalItems OkItems ErrorItems )
        WITH VALUE #( FOR ls_key IN keys
                      ( %tky       = ls_key-%tky
                        Status     = c_status-running
                        RunMode    = c_mode-real
                        TotalItems = 0
                        OkItems    = 0
                        ErrorItems = 0 ) ).

    LOOP AT keys INTO DATA(ls_key_msg).
      " Máx. 50 caracteres, severidad informativa
      APPEND VALUE #( %tky = ls_key_msg-%tky
                      %msg = new_message_with_text(
                               severity = if_abap_behv_message=>severity-information
                               text     = `En proceso. Actualice en unos segundos` ) )
        TO reported-upload.
    ENDLOOP.

    READ ENTITIES OF zr_solped_up IN LOCAL MODE
      ENTITY Upload
        ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lt_upload).

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
                                       es_summary = DATA(ls_summary) ).

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


"! Saver: registra el procesamiento en segundo plano (bgPF) al grabar.
"! save_for_execution debe llamarse en la fase de grabado, nunca en la acción.
CLASS lsc_zr_solped_up DEFINITION INHERITING FROM cl_abap_behavior_saver.

  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.

ENDCLASS.


CLASS lsc_zr_solped_up IMPLEMENTATION.

  METHOD save_modified.
    LOOP AT update-upload INTO DATA(ls_upload)
         WHERE %control-Status = if_abap_behv=>mk-on
           AND Status          = 'R'.
      TRY.
          DATA(lo_process) = cl_bgmc_process_factory=>get_default( )->create( ).
          lo_process->set_name( 'Modificación masiva solped' ).
          lo_process->set_operation_tx_uncontrolled( NEW zcl_solped_imput_bgpf( ls_upload-UploadUuid ) ).
          lo_process->save_for_execution( ).
        CATCH cx_bgmc INTO DATA(lx_bgmc).
          APPEND VALUE #( UploadUuid = ls_upload-UploadUuid
                          %msg       = new_message_with_text(
                                         severity = if_abap_behv_message=>severity-error
                                         text     = |No se pudo iniciar el proceso: { lx_bgmc->get_text( ) }| ) )
            TO reported-upload.
      ENDTRY.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
