"! <p class="shorttext synchronized">Wrapper Tier 2: BAPI_PR_CHANGE (modificar solicitud de pedido)</p>
"! Interfaz liberada (contrato C1 - Use in Cloud Development) para consumir
"! BAPI_PR_CHANGE desde ABAP Cloud. Expone TODAS las estructuras de la BAPI,
"! aunque la aplicación de modificación masiva solo use algunas.
"! Instancia: ZCL_MM_PR_CHANGE_API_FACT=>CREATE_INSTANCE( ).
INTERFACE zif_mm_pr_change_api
  PUBLIC.

  " ---------------------------------------------------------------------
  " Tipos simples
  " ---------------------------------------------------------------------
  TYPES:
    ty_number  TYPE banfn,
    ty_testrun TYPE bapiflag-bapiflag,

  " ---------------------------------------------------------------------
  " Estructuras de cabecera
  " ---------------------------------------------------------------------
    ty_header    TYPE bapimereqheader,
    ty_headerx   TYPE bapimereqheaderx,
    ty_headerexp TYPE bapimereqheader,
    ty_return    TYPE bapiret2,

  " ---------------------------------------------------------------------
  " Tablas (parámetros TABLES de BAPI_PR_CHANGE)
  " ---------------------------------------------------------------------
    tt_return                 TYPE STANDARD TABLE OF bapiret2                  WITH EMPTY KEY,
    tt_item                   TYPE STANDARD TABLE OF bapimereqitemimp          WITH EMPTY KEY,
    tt_itemx                  TYPE STANDARD TABLE OF bapimereqitemx            WITH EMPTY KEY,
    tt_itemexp                TYPE STANDARD TABLE OF bapimereqitem             WITH EMPTY KEY,
    tt_itemsource             TYPE STANDARD TABLE OF bapimereqsource           WITH EMPTY KEY,
    tt_account                TYPE STANDARD TABLE OF bapimereqaccount          WITH EMPTY KEY,
    tt_accountproitsegment    TYPE STANDARD TABLE OF bapimereqaccountprofitseg WITH EMPTY KEY,
    tt_accountx               TYPE STANDARD TABLE OF bapimereqaccountx         WITH EMPTY KEY,
    tt_addrdelivery           TYPE STANDARD TABLE OF bapimerqaddrdelivery      WITH EMPTY KEY,
    tt_itemtext               TYPE STANDARD TABLE OF bapimereqitemtext         WITH EMPTY KEY,
    tt_headertext             TYPE STANDARD TABLE OF bapimereqheadtext         WITH EMPTY KEY,
    tt_extensionin            TYPE STANDARD TABLE OF bapiparex                 WITH EMPTY KEY,
    tt_extensionout           TYPE STANDARD TABLE OF bapiparex                 WITH EMPTY KEY,
    tt_version                TYPE STANDARD TABLE OF bapimereqdcm              WITH EMPTY KEY,
    tt_versionx               TYPE STANDARD TABLE OF bapimereqdcmx             WITH EMPTY KEY,
    tt_allversions            TYPE STANDARD TABLE OF bapimedcm_allversions     WITH EMPTY KEY,
    tt_components             TYPE STANDARD TABLE OF bapimereqcomponent        WITH EMPTY KEY,
    tt_componentsx            TYPE STANDARD TABLE OF bapimereqcomponentx       WITH EMPTY KEY,
    tt_serviceoutline         TYPE STANDARD TABLE OF bapi_srv_outline          WITH EMPTY KEY,
    tt_serviceoutlinex        TYPE STANDARD TABLE OF bapi_srv_outlinex         WITH EMPTY KEY,
    tt_servicelines           TYPE STANDARD TABLE OF bapi_srv_service_line     WITH EMPTY KEY,
    tt_servicelinesx          TYPE STANDARD TABLE OF bapi_srv_service_linex    WITH EMPTY KEY,
    tt_servicelimit           TYPE STANDARD TABLE OF bapi_srv_limit_data       WITH EMPTY KEY,
    tt_servicelimitx          TYPE STANDARD TABLE OF bapi_srv_limit_datax      WITH EMPTY KEY,
    tt_servicecontractlimits  TYPE STANDARD TABLE OF bapi_srv_contract_limits  WITH EMPTY KEY,
    tt_servicecontractlimitsx TYPE STANDARD TABLE OF bapi_srv_contract_limitsx WITH EMPTY KEY,
    tt_serviceaccount         TYPE STANDARD TABLE OF bapi_srv_acc_data         WITH EMPTY KEY,
    tt_serviceaccountx        TYPE STANDARD TABLE OF bapi_srv_acc_datax        WITH EMPTY KEY,
    tt_servicelongtexts       TYPE STANDARD TABLE OF bapi_srv_longtexts        WITH EMPTY KEY,
    tt_serialnumber           TYPE STANDARD TABLE OF bapimereqserialno         WITH EMPTY KEY,
    tt_serialnumberx          TYPE STANDARD TABLE OF bapimereqserialnox        WITH EMPTY KEY.

  "! Todos los datos de entrada / salida de BAPI_PR_CHANGE en una estructura
  TYPES:
    BEGIN OF ty_data,
      " Entrada
      header                 TYPE ty_header,
      headerx                TYPE ty_headerx,
      " Salida
      header_exp             TYPE ty_headerexp,
      " Tablas (entrada y/o salida)
      item                   TYPE tt_item,
      itemx                  TYPE tt_itemx,
      itemexp                TYPE tt_itemexp,
      itemsource             TYPE tt_itemsource,
      account                TYPE tt_account,
      accountproitsegment    TYPE tt_accountproitsegment,
      accountx               TYPE tt_accountx,
      addrdelivery           TYPE tt_addrdelivery,
      itemtext               TYPE tt_itemtext,
      headertext             TYPE tt_headertext,
      extensionin            TYPE tt_extensionin,
      extensionout           TYPE tt_extensionout,
      version                TYPE tt_version,
      versionx               TYPE tt_versionx,
      allversions            TYPE tt_allversions,
      components             TYPE tt_components,
      componentsx            TYPE tt_componentsx,
      serviceoutline         TYPE tt_serviceoutline,
      serviceoutlinex        TYPE tt_serviceoutlinex,
      servicelines           TYPE tt_servicelines,
      servicelinesx          TYPE tt_servicelinesx,
      servicelimit           TYPE tt_servicelimit,
      servicelimitx          TYPE tt_servicelimitx,
      servicecontractlimits  TYPE tt_servicecontractlimits,
      servicecontractlimitsx TYPE tt_servicecontractlimitsx,
      serviceaccount         TYPE tt_serviceaccount,
      serviceaccountx        TYPE tt_serviceaccountx,
      servicelongtexts       TYPE tt_servicelongtexts,
      serialnumber           TYPE tt_serialnumber,
      serialnumberx          TYPE tt_serialnumberx,
    END OF ty_data.

  "! Llama a BAPI_PR_CHANGE. No hace COMMIT ni ROLLBACK.
  "! @parameter iv_number  | Número de solicitud de pedido
  "! @parameter iv_testrun | X = solo validar (no graba)
  "! @parameter cs_data    | Estructuras de la BAPI (entrada y salida)
  "! @parameter rt_return  | Mensajes (BAPIRET2)
  METHODS change
    IMPORTING iv_number         TYPE ty_number
              iv_testrun        TYPE ty_testrun OPTIONAL
    CHANGING  cs_data           TYPE ty_data
    RETURNING VALUE(rt_return)  TYPE tt_return.

  "! BAPI_TRANSACTION_COMMIT con WAIT = X.
  "! Solo se puede llamar fuera de una transacción RAP (p. ej. operación bgPF).
  METHODS commit
    RETURNING VALUE(rs_return) TYPE ty_return.

  "! BAPI_TRANSACTION_ROLLBACK.
  "! Solo se puede llamar fuera de una transacción RAP (p. ej. operación bgPF).
  METHODS rollback
    RETURNING VALUE(rs_return) TYPE ty_return.

ENDINTERFACE.
