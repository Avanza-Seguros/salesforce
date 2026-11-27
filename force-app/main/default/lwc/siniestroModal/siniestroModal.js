// siniestroModal/siniestroModal.js
// Ventana de Nuevo siniestro desde la póliza: la pestaña Siniestros y los renglones de Asegurados, Vehículos y
// Ubicaciones abren c-nuevo-siniestro con la póliza fija y, desde un renglón, lo afectado ya elegido. Regresa
// { claimId, abrir } (abrir = ir al siniestro); con la X regresa undefined.
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { NavigationMixin } from 'lightning/navigation';

export default class SiniestroModal extends LightningModal {
    @api policyId;
    @api participanteId;
    @api bienId;
    enModal = true;
    creadoId = null;

    handleCreado(e) { this.creadoId = e.detail.claimId; }
    handleCerrar(e) { this.close({ claimId: e.detail.claimId || this.creadoId, abrir: !!e.detail.abrir }); }
}

/**
 * Abre la ventana de Nuevo siniestro y, si se pide, navega al siniestro registrado.
 * @param host componente con NavigationMixin que abre la ventana.
 * @param datos { policyId, participanteId, bienId }.
 * @return el resultado de la ventana ({ claimId, abrir } o undefined).
 */
export async function abrirNuevoSiniestro(host, datos) {
    const r = await SiniestroModal.open({ size: 'large', label: 'Nuevo siniestro', description: 'Registro de un siniestro de la póliza', ...datos });
    if (r && r.abrir && r.claimId && host && host[NavigationMixin.Navigate]) {
        host[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: r.claimId, objectApiName: 'Claim', actionName: 'view' } });
    }
    return r;
}
