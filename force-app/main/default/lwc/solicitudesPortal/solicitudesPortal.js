// solicitudesPortal/solicitudesPortal.js
// Solicitudes de movimientos que el cliente envió desde el sitio (casos «Solicitud de movimientos») que siguen en
// trámite: sus movimientos ya quedaron registrados con el folio (En proceso) o, si no se pudieron registrar solos, están
// por atender (Recibida). Se usa en c-movimientos-colectivo, c-movimientos-flotilla y c-movimientos-ubicaciones:
// «Excel para la aseguradora» descarga el Excel de los movimientos de la solicitud (lo arma el componente que lo
// contiene); «Agregar movimientos» hace que los que se registren lleven el folio; «Rechazar» (solo si aún no tiene
// movimientos) concluye el caso con el motivo (el cliente lo ve en el sitio).
import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import rechazarSolicitud from '@salesforce/apex/EndosoPoliza.rechazarSolicitud';

export default class SolicitudesPortal extends LightningElement {
    @api solicitudes = [];
    @api atendiendo;
    @api puedeEditar = false;
    rechazando = null;
    motivo = '';
    enviando = false;

    get pendientes() {
        return (this.solicitudes || []).filter((s) => s.portal && (s.pendiente || s.estadoPortal === 'En proceso' || s.folio === this.atendiendo)).map((s) => {
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
                conMovimientos: s.total > 0,
                resumenTxt: s.total > 0 ? `${s.total} ${s.total === 1 ? 'movimiento registrado' : 'movimientos registrados'}`
                    + (s.abiertos ? ` · ${s.abiertos} sin cerrar` : '') : 'Sin movimientos registrados: atiéndela o recházala',
                textoAtender: activa ? 'Dejar de atender' : (s.total > 0 ? 'Agregar movimientos' : 'Atender'),
                varianteAtender: activa ? 'neutral' : (s.total > 0 ? 'neutral' : 'brand')
            };
        });
    }
    get hayPendientes() { return this.pendientes.length > 0; }
    get titulo() {
        return `Solicitudes del sitio en trámite (${this.pendientes.length})`;
    }

    handleAtender(e) {
        const folio = e.currentTarget.dataset.folio;
        this.dispatchEvent(new CustomEvent('atender', { detail: { folio: folio === this.atendiendo ? null : folio } }));
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
