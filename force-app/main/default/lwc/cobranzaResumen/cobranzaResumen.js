import { LightningElement, track } from 'lwc';
import getResumenCobranza from '@salesforce/apex/CobranzaController.getResumenCobranza';

export default class CobranzaResumen extends LightningElement {
    @track resumen = {};
    @track error;
    @track fechaInicio;
    @track fechaFin;
    @track frecuencia = 'Todas';
    @track cargando = false;

    frecuencias = [
        { label: 'Todas', value: 'Todas' },
        { label: 'Mensual', value: 'Mensual' },
        { label: 'Bimestral', value: 'Bimestral' },
        { label: 'Trimestral', value: 'Trimestral' },
        { label: 'Semestral', value: 'Semestral' },
        { label: 'Anual', value: 'Anual' }
    ];

    connectedCallback() {
        console.log('CobranzaResumen connectedCallback called');
        // Establecer fechas por defecto (mes actual)
        const hoy = new Date();
        this.fechaInicio = new Date(hoy.getFullYear(), hoy.getMonth(), 1).toISOString().split('T')[0];
        this.fechaFin = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0).toISOString().split('T')[0];
        
        this.cargarDatos();
    }

    handleFechaInicio(event) {
        this.fechaInicio = event.target.value;
    }

    handleFechaFin(event) {
        this.fechaFin = event.target.value;
    }

    handleFrecuencia(event) {
        this.frecuencia = event.detail.value;
    }

    cargarDatos() {
        this.cargando = true;
        this.error = null;
        console.log('Cargando datos con filtros:');
        console.log('Fecha Inicio:', this.fechaInicio);
        console.log('Fecha Fin:', this.fechaFin);
        console.log('Frecuencia:', this.frecuencia);
        getResumenCobranza({
            fechaInicio: this.fechaInicio || null,
            fechaFin: this.fechaFin || null,
            frecuencia: this.frecuencia === 'Todas' ? null : this.frecuencia
        })
        .then(result => {
            this.resumen = result || {};
            console.log('Datos cargados:', JSON.stringify(this.resumen));
        })
        .catch(error => {
            console.error('Error:', error);
            this.error = error;
        })
        .finally(() => {
            this.cargando = false;
        });
    }

    get totalPolizas() {
        return this.resumen.totalPolizas || 0;
    }

    get montoTotal() {
        return this.resumen.montoTotal || 0;
    }

    get montoTotalFormateado() {
        return this.formatCurrency(this.montoTotal);
    }

    get porcentajeCorrientes() {
        return this.calcularPorcentaje(this.resumen.corrientes || 0);
    }

    get porcentajePorVencer() {
        return this.calcularPorcentaje(this.resumen.porVencer || 0);
    }

    get porcentajeVencidas() {
        return this.calcularPorcentaje(this.resumen.vencidas || 0);
    }

    calcularPorcentaje(valor) {
        const total = this.totalPolizas;
        return total > 0 ? Math.round((valor / total) * 100) : 0;
    }

    formatCurrency(value) {
        if (!value) return '$0.00';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN'
        }).format(value);
    }
}