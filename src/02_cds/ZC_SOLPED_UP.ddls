@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Modificación masiva solped - Archivo (proyección)'
@Metadata.allowExtensions: true
define root view entity ZC_SOLPED_UP
  provider contract transactional_query
  as projection on ZR_SOLPED_UP
{
  key UploadUuid,
      PurchaseRequisition,

      @Semantics.largeObject: { mimeType: 'MimeType',
                                fileName: 'FileName',
                                acceptableMimeTypes: [ 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ],
                                contentDispositionPreference: #ATTACHMENT }
      FileContent,
      @Semantics.mimeType: true
      MimeType,
      FileName,

      Status,
      StatusText,
      StatusCriticality,
      RunMode,
      RunModeText,
      TotalItems,
      OkItems,
      ErrorItems,
      ProcessedAt,

      LocalCreatedBy,
      LocalCreatedAt,
      LocalLastChangedBy,
      LocalLastChangedAt,
      LastChangedAt,

      _Log : redirected to composition child ZC_SOLPED_LOG
}
