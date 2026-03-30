import { LightningElement, api } from 'lwc';
import obtenerPagosDePoliza from '@salesforce/apex/PolizaDashboardController.obtenerPagosDePoliza';
import actualizarComentariosPago from '@salesforce/apex/PolizaDashboardController.actualizarComentariosPago';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CobranzaPolizaPagosModal extends LightningElement {
    @api numeroPoliza;
    @api open = false;

    pagos = [];
    loading = false;

    draftValues = [];

    columns = [
        { label: 'Recibo', fieldName: 'name' },
        {
            label: 'Fecha Pago',
            fieldName: 'fechaPago',
            type: 'date-local',
            typeAttributes: {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            }
        },
        {
            label: 'Fecha Vencimiento',
            fieldName: 'fechaVencimiento',
            type: 'date-local',
            typeAttributes: {
                day: '2-digit',
                month: '2-digit',
                year: 'numeric'
            }
        },
        { label: 'Moneda', fieldName: 'moneda', type: 'text' },
        { label: 'Monto', fieldName: 'monto', type: 'currency' },
        { label: 'Monto MXN', fieldName: 'montoMXN', type: 'currency' },
        { label: 'Estado Pago', fieldName: 'estatusPago' },
        { label: 'Forma de Pago', fieldName: 'formaPago' },
        { label: 'Canal de Cobro', fieldName: 'canalCobro' },
        { label: 'Modo de Pago', fieldName: 'modoPago' },
        { label: 'Comentarios', fieldName: 'comentarios', wrapText: true , editable: true}

    ];

    @api
    cargar(numero) {
        this.numeroPoliza = numero;
        this.open = true;
        this.consultarPagos();
    }

    consultarPagos() {
        this.loading = true;

        obtenerPagosDePoliza({ numeroPoliza: this.numeroPoliza })
            .then(res => {
                this.pagos = res; this.draftValues = [];
            })
            .finally(() => this.loading = false);
    }

    close() {
        this.open = false;
        this.pagos = [];
        this.draftValues = [];
    }

    handleSave(event) {
        const comentariosMap = {};

        event.detail.draftValues.forEach(d => {
            comentariosMap[d.id] = d.comentarios;
        });

        this.loading = true;

        actualizarComentariosPago({ comentariosPorPago: comentariosMap })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Éxito',
                        message: 'Comentarios actualizados',
                        variant: 'success'
                    })
                );

                return this.consultarPagos();
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: error.body?.message || 'Error al guardar',
                        variant: 'error'
                    })
                );
            })
            .finally(() => {
                this.loading = false;
            });
    }

}