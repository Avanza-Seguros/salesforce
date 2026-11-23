// solicitudesPortal/solicitudesPortal.js
// Solicitudes de movimientos que el cliente envió desde el sitio (casos «Solicitud de movimientos») que nadie ha atendido
// (Solicitado). «Atender» pasa el caso a En proceso y la solicitud ya no vuelve a salir aquí. Se usa en
// c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones:
// «Excel para la aseguradora» descarga el Excel de los movimientos de la solicitud (lo arma el componente que lo
// contiene); «Capturar movimientos» hace que los que se registren lleven el folio; «Rechazar» concluye el caso con el motivo (el cliente lo ve en el sitio); los movimientos ya registrados no se borran.
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import atenderSolicitud from '@salesforce/apex/EndosoPoliza.atenderSolicitud';
import rechazarSolicitud from '@salesforce/apex/EndosoPoliza.rechazarSolicitud';

export default class SolicitudesPortal extends LightningElement {
    @api solicitudes = [];
    @api atendiendo;
    @api puedeEditar = false;
    rechazando = null;
    motivo = '';
    enviando = false;

    get pendientes() {
        return (this.solicitudes || []).filter((s) => s.portal && s.seguimiento === 'Solicitado').map((s) => {
            const lineas = String(s.descripcion || '').split('\n').filter((l) => /^\d+\./.test(l));
            const activa = s.folio === this.atendiendo;
            return {
                ...s,
                activa,
                clase: `solicitud${activa ? ' solicitud-activa' : ''}`,
                fechaTxt: s.fecha ? new Intl.DateTimeFormat('es-MX', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(s.fecha)) : '',
                ligaCaso: '/' + s.casoId,
                lineas: lineas.map((l, i) => ({ key: i, texto: l })),
                docs: (s.documentos || []).map((d) => ({ ...d, liga: `/lightning/r/ContentDocument/${d.id}/view` })),
                rechazando: this.rechazando === s.casoId,
                avisoRechazo: s.total > 0
                    ? (s.total === 1 ? 'El movimiento ya registrado no se borra' : `Los ${s.total} movimientos ya registrados no se borran`)
                        + ': si no proceden, dalos de baja o corrígelos aparte.'
                    : '',
                conMovimientos: s.total > 0,
                resumenTxt: s.total > 0 ? `${s.total} ${s.total === 1 ? 'movimiento registrado' : 'movimientos registrados'}`
                    + (s.abiertos ? ` · ${s.abiertos} ${s.abiertos === 1 ? 'pendiente' : 'pendientes'} de cerrar con la aseguradora` : '')
                    : (this.puedeEditar ? 'Sin movimientos registrados: captúralos con «Capturar movimientos» o recházala'
                        // Póliza de un solo vehículo (o sin permiso de edición): no se capturan aquí.
                        : 'Sin movimientos registrados: esta póliza no admite capturarlos aquí; envía el archivo del cliente a la aseguradora o recházala'),
                textoAtender: activa ? 'Terminar captura' : 'Capturar movimientos'
            };
        });
    }
    get hayPendientes() { return this.pendientes.length > 0; }
    get titulo() {
        return `Solicitudes del sitio por atender (${this.pendientes.length})`;
    }

    handleAtender(e) {
        const folio = e.currentTarget.dataset.folio;
        this.dispatchEvent(new CustomEvent('atender', { detail: { folio: folio === this.atendiendo ? null : folio } }));
    }
    // Pasa el caso a En proceso: la solicitud sale del aviso y no vuelve a aparecer.
    async handleAtenderCaso(e) {
        const casoId = e.currentTarget.dataset.id;
        this.enviando = true;
        try {
            await atenderSolicitud({ casoId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Solicitud en proceso',
                message: 'El cliente la verá En proceso en el sitio.', variant: 'success' }));
            this.dispatchEvent(new CustomEvent('cambio'));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Solicitud', variant: 'error',
                message: (err && err.body && err.body.message) || 'No se pudo atender la solicitud.' }));
        } finally {
            this.enviando = false;
        }
    }
    handleExcel(e) {
        this.dispatchEvent(new CustomEvent('excel', { detail: { folio: e.currentTarget.dataset.folio } }));
    }
    handleRechazar(e) { this.rechazando = e.currentTarget.dataset.id; this.motivo = ''; }
    handleCancelar() { this.rechazando = null; }
    handleMotivo(e) { this.motivo = e.detail.value; }
    async handleConfirmar() {
        const campo = this.template.querySelector('lightning-textarea');
        if (!this.motivo || !this.motivo.trim()) { campo.reportValidity(); return; }
        this.enviando = true;
        try {
            await rechazarSolicitud({ casoId: this.rechazando, motivo: this.motivo });
            this.dispatchEvent(new ShowToastEvent({ title: 'Solicitud rechazada', message: 'El cliente verá el motivo en el sitio.', variant: 'success' }));
            this.rechazando = null;
            this.dispatchEvent(new CustomEvent('cambio'));
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Solicitud', variant: 'error',
                message: (err && err.body && err.body.message) || 'No se pudo rechazar la solicitud.' }));
        } finally {
            this.enviando = false;
        }
    }
}
