// folioAseguradora/folioAseguradora.js
// Folio que dio la aseguradora a un movimiento (toda la solicitud): se escribe y se guarda al salir del campo o con Enter
// (Esc lo regresa). Se usa en c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones, solo en Salesforce.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import guardarFolioAseguradora from '@salesforce/apex/MovimientosColectivoController.guardarFolioAseguradora';

export default class FolioAseguradora extends LightningElement {
    @api valor;
    @api policyId;
    @api folio;
    guardando = false;

    get texto() { return this.valor || ''; }
    handleTecla(e) {
        if (e.key === 'Enter') { e.target.blur(); }
        if (e.key === 'Escape') { e.target.value = this.texto; e.target.blur(); }
    }
    async handleCambio(e) {
        const campo = e.target;
        const nuevo = campo.value.trim();
        if (this.guardando) { return; }
        if (nuevo === this.texto) { campo.value = nuevo; return; }
        this.guardando = true;
        try {
            await guardarFolioAseguradora({ policyId: this.policyId, folio: this.folio, valor: nuevo });
            this.dispatchEvent(new ShowToastEvent({ title: 'Folio Aseguradora', variant: 'success',
                message: nuevo ? `Se guardó ${nuevo}.` : 'Se quitó el folio.' }));
            this.dispatchEvent(new CustomEvent('cambio'));
        } catch (err) {
            campo.value = this.texto;
            this.dispatchEvent(new ShowToastEvent({ title: 'Folio Aseguradora', variant: 'error',
                message: (err && err.body && err.body.message) || 'No se pudo guardar el folio.' }));
        } finally {
            this.guardando = false;
        }
    }
}
