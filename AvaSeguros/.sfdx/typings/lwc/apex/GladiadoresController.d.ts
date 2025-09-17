declare module "@salesforce/apex/GladiadoresController.getSolicitudes" {
  export default function getSolicitudes(param: {IdGladiador: any}): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.getAllGladiadores" {
  export default function getAllGladiadores(): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.getDiasEspeciales" {
  export default function getDiasEspeciales(): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.getAuthenticate" {
  export default function getAuthenticate(param: {name: any, password: any}): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.createSolicitudVacaciones" {
  export default function createSolicitudVacaciones(param: {fechaSolicitud: any, idGladiadior: any, fechaDesde: any, fechaHasta: any, tipoPermiso: any, motivoAusencia: any, motivoAusenciaDescription: any, Establecerhora: any, HoraRegresoSolicitada: any, HoraSalidaSolicitada: any, MotivoInexcusable: any}): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.updateSolicitudVacaciones" {
  export default function updateSolicitudVacaciones(param: {idSolicitud: any, idGladiadior: any}): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.deleteSolicitudVacaciones" {
  export default function deleteSolicitudVacaciones(param: {idSolicitud: any, idGladiadior: any}): Promise<any>;
}
declare module "@salesforce/apex/GladiadoresController.UpdateFile" {
  export default function UpdateFile(param: {IdFile: any, IdRecord: any}): Promise<any>;
}
