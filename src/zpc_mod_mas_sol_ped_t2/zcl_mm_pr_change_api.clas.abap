"! <p class="shorttext synchronized">Wrapper Tier 2: implementación de BAPI_PR_CHANGE</p>
"! Implementación NO liberada. Se instancia solo a través de
"! ZCL_MM_PR_CHANGE_API_FACT (liberada C1).
CLASS zcl_mm_pr_change_api DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zif_mm_pr_change_api.

ENDCLASS.



CLASS zcl_mm_pr_change_api IMPLEMENTATION.

  METHOD zif_mm_pr_change_api~change.
    CLEAR rt_return.

    CALL FUNCTION 'BAPI_PR_CHANGE'
      EXPORTING
        number                 = iv_number
        prheader               = cs_data-header
        prheaderx              = cs_data-headerx
        testrun                = iv_testrun
      IMPORTING
        prheaderexp            = cs_data-header_exp
      TABLES
        return                 = rt_return
        pritem                 = cs_data-item
        pritemx                = cs_data-itemx
        pritemexp              = cs_data-itemexp
        pritemsource           = cs_data-itemsource
        praccount              = cs_data-account
        praccountproitsegment  = cs_data-accountproitsegment
        praccountx             = cs_data-accountx
        praddrdelivery         = cs_data-addrdelivery
        pritemtext             = cs_data-itemtext
        prheadertext           = cs_data-headertext
        extensionin            = cs_data-extensionin
        extensionout           = cs_data-extensionout
        prversion              = cs_data-version
        prversionx             = cs_data-versionx
        allversions            = cs_data-allversions
        prcomponents           = cs_data-components
        prcomponentsx          = cs_data-componentsx
        serviceoutline         = cs_data-serviceoutline
        serviceoutlinex        = cs_data-serviceoutlinex
        servicelines           = cs_data-servicelines
        servicelinesx          = cs_data-servicelinesx
        servicelimit           = cs_data-servicelimit
        servicelimitx          = cs_data-servicelimitx
        servicecontractlimits  = cs_data-servicecontractlimits
        servicecontractlimitsx = cs_data-servicecontractlimitsx
        serviceaccount         = cs_data-serviceaccount
        serviceaccountx        = cs_data-serviceaccountx
        servicelongtexts       = cs_data-servicelongtexts
        serialnumber           = cs_data-serialnumber
        serialnumberx          = cs_data-serialnumberx.
  ENDMETHOD.


  METHOD zif_mm_pr_change_api~commit.
    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait   = abap_true
      IMPORTING
        return = rs_return.
  ENDMETHOD.


  METHOD zif_mm_pr_change_api~rollback.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'
      IMPORTING
        return = rs_return.
  ENDMETHOD.

ENDCLASS.
