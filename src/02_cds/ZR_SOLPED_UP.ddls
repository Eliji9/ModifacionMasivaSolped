@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Modificación masiva solped - Archivo'
define root view entity ZR_SOLPED_UP
  as select from ztmm_solped_up
  composition [0..*] of ZR_SOLPED_LOG as _Log
{
  key upload_uuid           as UploadUuid,
      purchase_requisition  as PurchaseRequisition,

      @Semantics.largeObject: { mimeType: 'MimeType',
                                fileName: 'FileName',
                                acceptableMimeTypes: [ 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' ],
                                contentDispositionPreference: #ATTACHMENT }
      file_content          as FileContent,
      @Semantics.mimeType: true
      mime_type             as MimeType,
      file_name             as FileName,

      // N = Nueva, S = Simulada, R = En proceso, P = Procesada, E = Procesada con errores
      status                as Status,
      cast( case status
              when 'E' then 'Procesada con errores'
              when 'N' then 'Nueva'
              when 'S' then 'Simulada'
              when 'R' then 'En proceso'
              when 'P' then 'Procesada'
              else ''
            end as abap.char( 25 ) )               as StatusText,
      cast( case status
              when 'E' then 1
              when 'S' then 2
              when 'R' then 2
              when 'P' then 3
              else 0
            end as abap.int1 )                      as StatusCriticality,

      // S = Simulación, R = Real
      run_mode              as RunMode,
      cast( case run_mode
              when 'S' then 'Simulación'
              when 'R' then 'Real'
              else ''
            end as abap.char( 10 ) )               as RunModeText,

      total_items           as TotalItems,
      ok_items              as OkItems,
      error_items           as ErrorItems,
      processed_at          as ProcessedAt,

      @Semantics.user.createdBy: true
      local_created_by      as LocalCreatedBy,
      @Semantics.systemDateTime.createdAt: true
      local_created_at      as LocalCreatedAt,
      @Semantics.user.localInstanceLastChangedBy: true
      local_last_changed_by as LocalLastChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      local_last_changed_at as LocalLastChangedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at       as LastChangedAt,

      _Log
}
