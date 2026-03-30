import { LightningElement, api } from 'lwc';

export default class CobranzaPolizaModalConfirmacion extends LightningElement {
    @api confirmData;
    showModal = true;

    get titulo() {
        return this.confirmData?.titulo || 'Confirmar Acción';
    }

    get mensaje() {
        return this.confirmData?.mensaje || '¿Estás seguro de realizar esta acción?';
    }

    get accion() {
        return this.confirmData?.accion || '';
    }

    // Confirmar acción
    handleConfirm() {
        this.showModal = false;
        this.dispatchEvent(new CustomEvent('close', {
            detail: {
                success: true,
                tipo: 'confirmacion',
                confirmado: true,
                accion: this.accion,
                pagoIds: this.confirmData?.pagoIds || []
            }
        }));
    }

    // Cancelar acción
    handleCancel() {
        this.showModal = false;
        this.dispatchEvent(new CustomEvent('close', {
            detail: {
                success: true,
                tipo: 'confirmacion',
                confirmado: false
            }
        }));
    }

    handleDialogClick(event) {
        event.stopPropagation();
    }

    handleOverlayClick() {
        this.handleCancel();
    }
}