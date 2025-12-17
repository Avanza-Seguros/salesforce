declare module "@salesforce/apex/CobranzaController.getUltimosPagosPoliza" {
  export default function getUltimosPagosPoliza(param: {fechaInicio: any, fechaFin: any}): Promise<any>;
}
declare module "@salesforce/apex/CobranzaController.getUltimosPagosPolizaEficiente" {
  export default function getUltimosPagosPolizaEficiente(param: {fechaInicio: any, fechaFin: any}): Promise<any>;
}
declare module "@salesforce/apex/CobranzaController.getEstadisticasPorMesYEstatusConFechas" {
  export default function getEstadisticasPorMesYEstatusConFechas(param: {fechaInicio: any, fechaFin: any}): Promise<any>;
}
declare module "@salesforce/apex/CobranzaController.getEstadisticasPorMesYEstatus" {
  export default function getEstadisticasPorMesYEstatus(): Promise<any>;
}
declare module "@salesforce/apex/CobranzaController.getPoliza" {
  export default function getPoliza(param: {idPol: any}): Promise<any>;
}
declare module "@salesforce/apex/CobranzaController.getPagosPol" {
  export default function getPagosPol(param: {pagoPol: any}): Promise<any>;
}
