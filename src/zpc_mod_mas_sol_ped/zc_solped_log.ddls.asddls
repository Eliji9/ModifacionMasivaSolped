@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Modificación masiva solped - Log (proyección)'
@Metadata.allowExtensions: true
define view entity ZC_SOLPED_LOG
  as projection on ZR_SOLPED_LOG
{
  key LogUuid,
      UploadUuid,
      RowNo,
      PurchaseRequisition,
      PurchaseRequisitionItem,
      AcctAssgmtCatOld,
      AcctAssgmtCatNew,
      MasterFixedAsset,
      FixedAsset,
      CompanyCode,
      Step,
      StepText,
      MsgType,
      MsgTypeText,
      Criticality,
      MsgOrigin,
      MsgOriginText,
      MsgId,
      MsgNo,
      Message,
      LocalCreatedBy,
      LocalCreatedAt,
      LocalLastChangedAt,

      _Upload : redirected to parent ZC_SOLPED_UP
}
