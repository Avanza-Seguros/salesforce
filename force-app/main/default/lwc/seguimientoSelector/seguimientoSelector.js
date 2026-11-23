// seguimientoSelector/seguimientoSelector.js
// Seguimiento de un movimiento (registro) o de toda una solicitud: con un clic se elige otro estado (Solicitado, En
// proceso o Concluido; la solicitud que el cliente envió desde el sitio también se puede Rechazar, con el motivo que él
// ve). Se usa en c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones, solo en Salesforce.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import cambiarSeguimiento from '@salesforce/apex/MovimientosColectivoController.cambiarSeguimiento';
import rechazarSolicitud from '@salesforce/apex/MovimientosColectivoController.rechazarSolicitud';

const CLASES = { Solicitado: 'solicitado', 'En proceso': 'proceso', Concluido: 'concluido', Rechazada: 'rechazada' };

export default class SeguimientoSelector extends LightningElement {
    @api valor;
    @api policyId;
    @api folio;
    // Con movimiento cambia solo ese registro; sin él, toda la solicitud.
    @api movimientoId;
    // Caso de la solicitud del sitio (permite Rechazada).
    @api casoId;
    // Una solicitud sin movimientos no se concluye: se rechaza.
    @api sinMovimientos = false;
    guardando = false;

    get clase() { return `seg seg-${CLASES[this.valor] || 'proceso'}`; }
    get opciones() {
        const l = ['Solicitado', 'En proceso'];
        if (!this.sinMovimientos) { l.push('Concluido'); }
        if (this.casoId) { l.push('Rechazada'); }
        if (this.valor && !l.includes(this.valor)) { l.push(this.valor); }
        return l.map((x) => ({ valor: x, elegida: x === this.valor }));
    }
    regresar() {
        const s = this.template.querySelector('select');
        if (s) { s.value = this.valor; }
    }
    async handleCambio(e) {
        const nuevo = e.target.value;
        if (!nuevo || nuevo === this.valor) { return; }
        this.guardando = true;
        try {
            if (nuevo === 'Rechazada') {
                const motivo = await LightningPrompt.open({ message: 'Motivo del rechazo (lo ve el cliente). Los movimientos ya registrados no se borran.',
                    label: 'Rechazar solicitud', theme: 'warning' });
                if (motivo === null) { this.regresar(); return; }
                await rechazarSolicitud({ casoId: this.casoId, motivo });
            } else {
                if (!this.movimientoId && !this.sinMovimientos && (nuevo === 'Concluido' || this.valor === 'Concluido')) {
                    const ok = await LightningConfirm.open({
                        message: nuevo === 'Concluido' ? 'Se concluyen todos los movimientos abiertos de la solicitud. ¿Continuar?'
                            : `Los movimientos de la solicitud se reabren (se quita su fecha de cierre) y quedan ${nuevo}. ¿Continuar?`,
                        variant: 'header', label: 'Cambiar seguimiento', theme: 'warning' });
                    if (!ok) { this.regresar(); return; }
                }
                await cambiarSeguimiento({ policyId: this.policyId, folio: this.folio || null, movimientoId: this.movimientoId || null, valor: nuevo });
            }
            this.dispatchEvent(new ShowToastEvent({ title: 'Seguimiento', message: `Quedó ${nuevo}.`, variant: 'success' }));
            this.dispatchEvent(new CustomEvent('cambio'));
        } catch (err) {
            this.regresar();
            this.dispatchEvent(new ShowToastEvent({ title: 'Seguimiento', variant: 'error',
                message: (err && err.body && err.body.message) || 'No se pudo cambiar el seguimiento.' }));
        } finally {
            this.guardando = false;
        }
    }
}
