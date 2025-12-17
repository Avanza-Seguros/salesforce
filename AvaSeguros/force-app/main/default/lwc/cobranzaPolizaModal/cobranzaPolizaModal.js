import LightningModal from 'lightning/modal';
import { api } from 'lwc';

export default class CobranzaPolizaModal extends LightningModal {
    @api pagoData;
    @api showDetallesModal = false;

    get titulo() {
        return this.pagoData?.titulo || 'Detalles del Pago';
    }

    get pagos() {
        return this.pagoData?.pagos || [];
    }

    get pago() {
        return this.pagoData?.pago || {};
    }

    get poliza() {
        return this.pagoData?.poliza || {};
    }

    // Opciones para el modal
    get modalOptions() {
        console.log('modalOptions called');
        return {
            label: 'Detalles de Póliza y Cobranza',
            size: 'large'
        };
    }

    handleClose() {
        this.showDetallesModal = true;
        this.close();
    }

    // Prevenir que el evento se propague cuando se hace click en el modal
    handleDialogClick(event) {
        event.stopPropagation();
    }

    // Cerrar al hacer click fuera del modal
    handleOverlayClick() {
        this.handleClose();
    }

    // Métodos de formato
    formatCurrency(value) {
        if (!value) return '$0.00';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN'
        }).format(value);
    }

    formatDate(dateString) {
        if (!dateString) return 'N/A';
        try {
            const date = new Date(dateString);
            return date.toLocaleDateString('es-MX');
        } catch (error) {
            return 'Fecha inválida';
        }
    }

    get diasVencimientoHoy() {
        if(this.pago.Estatus_pago__c === 'Pendiente' || this.pago.Estatus_pago__c === 'Vencido') {
            const hoy = new Date();
            const proximoPago = new Date(this.pago.Proximo_Pago__c);
            const aplicacionPago = new Date(this.pago.Fecha_de_Aplicaci_n_del_pago__c);
            const dias = this.diferenciaDias(proximoPago, hoy) || this.diferenciaDias(aplicacionPago, hoy);
            return dias;
        }else {
            return 0;
        }
    }

    diferenciaDias(fecha1, fecha2) {
        // Convertir a milisegundos
        const unDia = 1000 * 60 * 60 * 24; // milisegundos en un día
        
        // Obtener diferencia en milisegundos
        const diferenciaMs = Math.abs(fecha2 - fecha1);
        
        // Convertir a días
        return Math.floor(diferenciaMs / unDia);
    }

    get diasVencimientoClass() {
        const dias = this.diasVencimientoHoy;
        if (!dias) return 'dias-normal';
        if (dias > 0) return 'dias-vencido';
        if (dias >= -7) return 'dias-por-vencer';
        return 'dias-normal';
    }

    getDiasVencimientoClass(dias) {
        if (!dias) return 'dias-normal';
        if (dias > 0) return 'dias-vencido';
        if (dias >= -7) return 'dias-por-vencer';
        return 'dias-normal';
    }

    getEstadoPolizaClass(estatus) {
        if (!estatus) return '';
        return estatus.toLowerCase().replace(/\s+/g, '-');
    }

    // Computed properties para la UI
    get tienePagos() {
        return this.pagos && this.pagos.length > 0;
    }

    get pagosRecientes() {
        return this.tienePagos ? this.pagos.slice(0, 5) : []; // Mostrar solo los 5 más recientes
    }

    get totalPagado() {
        if (!this.tienePagos) return 0;
        return this.pagos
            .filter(pago => pago.Pagado__c)
            .reduce((total, pago) => total + (pago.Pago_en_MXN__c || 0), 0);
    }

    get proximosPagos() {
        if (!this.tienePagos) return [];
        const hoy = new Date();
        return this.pagos.filter(pago => 
            pago.Proximo_Pago__c > hoy
        );
    }

    get proximoPago() {
        return this.formatCurrency(this.pago.Pago_en_MXN__c);
    }

    get fechaProximoPago() {
        return this.formatDate(this.pago.Proximo_Pago__c);
    }
}