@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Modificación masiva solped - Log'
define view entity ZR_SOLPED_LOG
  as select from ztmm_solped_lg
  association to parent ZR_SOLPED_UP as _Upload on $projection.UploadUuid = _Upload.UploadUuid
{
  key log_uuid              as LogUuid,
      upload_uuid           as UploadUuid,
      row_no                as RowNo,
      purchase_requisition  as PurchaseRequisition,
      item                  as PurchaseRequisitionItem,
      acct_cat_old          as AcctAssgmtCatOld,
      acct_cat_new          as AcctAssgmtCatNew,
      master_fixed_asset    as MasterFixedAsset,
      fixed_asset           as FixedAsset,
      company_code          as CompanyCode,

      // L = Lectura de archivo, V = Validación, M = Modificación
      step                  as Step,
      cast( case step
              when 'L' then 'Lectura de archivo'
              when 'V' then 'Validación'
              when 'M' then 'Modificación'
              else ''
            end as abap.char( 20 ) )               as StepText,

      msg_type              as MsgType,
      cast( case msg_type
              when 'W' then 'Advertencia'
              when 'E' then 'Error'
              when 'A' then 'Error'
              when 'S' then 'Correcto'
              else 'Información'
            end as abap.char( 12 ) )               as MsgTypeText,
      cast( case msg_type
              when 'E' then 1
              when 'A' then 1
              when 'W' then 2
              when 'S' then 3
              else 0
            end as abap.int1 )                      as Criticality,

      // Z = Validación propia, S = Mensaje estándar SAP
      msg_origin            as MsgOrigin,
      cast( case msg_origin
              when 'Z' then 'Validación propia'
              when 'S' then 'SAP estándar'
              else ''
            end as abap.char( 20 ) )               as MsgOriginText,
      msg_id                as MsgId,
      msg_no                as MsgNo,
      message               as Message,

      @Semantics.user.createdBy: true
      local_created_by      as LocalCreatedBy,
      @Semantics.systemDateTime.createdAt: true
      local_created_at      as LocalCreatedAt,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,

      _Upload
}
