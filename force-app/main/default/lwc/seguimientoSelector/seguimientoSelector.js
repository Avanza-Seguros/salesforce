// seguimientoSelector/seguimientoSelector.js
// Seguimiento de un movimiento (registro) o de toda una solicitud: con un clic se elige otro estado (Solicitado, En
// proceso o Concluido; un registro también se puede Rechazar, con el motivo que ve el cliente; toda la solicitud no). Se
// usa en c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones, solo en Salesforce.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import LightningPrompt from 'lightning/prompt';
import cambiarSeguimiento from '@salesforce/apex/MovimientosColectivoController.cambiarSeguimiento';

const CLASES = { Solicitado: 'solicitado', 'En proceso': 'proceso', Concluido: 'concluido', Rechazado: 'rechazada', Rechazada: 'rechazada' };

export default class SeguimientoSelector extends LightningElement {
    @api valor;
    @api policyId;
    @api folio;
    // Con movimiento cambia solo ese registro; sin él, toda la solicitud.
    @api movimientoId;
    // Solicitud que aún no tiene movimientos: al concluirla se concluye su caso.
    @api sinMovimientos = false;
    // Correos por enviar a los asegurados de la solicitud (o del registro): al concluir se abre su envío (evento «concluir»).
    @api correosPendientes = 0;
    guardando = false;

    get clase() { return `seg seg-${CLASES[this.valor] || 'proceso'}`; }
    get opciones() {
        const l = ['Solicitado', 'En proceso', 'Concluido'];
        if (this.movimientoId) { l.push('Rechazado'); }
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
        if (nuevo === 'Concluido' && this.correosPendientes > 0) {
            this.regresar();
            this.dispatchEvent(new CustomEvent('concluir', { detail: { folio: this.folio, movimientoId: this.movimientoId } }));
            return;
        }
        this.guardando = true;
        try {
            let motivo = null;
            if (nuevo === 'Rechazado') {
                motivo = await LightningPrompt.open({ message: 'Motivo del rechazo (lo ve el cliente). El movimiento ya registrado no se borra.',
                    label: 'Rechazar registro', theme: 'warning' });
                if (motivo === null) { this.regresar(); return; }
            } else {
                if (!this.movimientoId && !this.sinMovimientos && (nuevo === 'Concluido' || this.valor === 'Concluido')) {
                    const ok = await LightningConfirm.open({
                        message: nuevo === 'Concluido' ? 'Se concluyen todos los movimientos abiertos de la solicitud y se le envía al cliente el correo con el resumen. ¿Continuar?'
                            : `Los movimientos de la solicitud se reabren (se quita su fecha de cierre) y quedan ${nuevo}. ¿Continuar?`,
                        variant: 'header', label: 'Cambiar seguimiento', theme: 'warning' });
                    if (!ok) { this.regresar(); return; }
                }
            }
            const aviso = await cambiarSeguimiento({ policyId: this.policyId, folio: this.folio || null, movimientoId: this.movimientoId || null, valor: nuevo, motivo });
            this.dispatchEvent(new ShowToastEvent({ title: 'Seguimiento', message: `Quedó ${nuevo}.${aviso ? ' ' + aviso : ''}`, variant: 'success' }));
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
