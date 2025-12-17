// cobranzaPolizas/cobranzaPolizas.js
import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPolizas from '@salesforce/apex/CobranzaPolizaController.getPolizas';
import getResumenPolizas from '@salesforce/apex/CobranzaPolizaController.getResumenPolizas';

export default class CobranzaPolizas extends LightningElement {
    @track polizas = [];
    @track polizasFiltradas = [];
    @track fechaDesde = '';
    @track fechaHasta = '';
    @track filtroEstado = '';
    @track mostrarModal = false;
    @track polizaSeleccionadaId = '';
    @track resumen;
    
    // KPIs
    totalPolizas = 0;
    polizasVigentes = 0;
    polizasCanceladas = 0;
    polizasTraspasadas = 0;

    // Opciones para combobox
    opcionesEstado = [
        { label: 'Todas', value: '' },
        { label: 'Vigente', value: 'Vigente' },
        { label: 'Pagada', value: 'Pagada' },
        { label: 'Pendiente', value: 'Pendiente' },
        { label: 'Cancelada', value: 'Cancelada' }
    ];

    // Wire services
    @wire(getPolizas)
    wiredPolizas({ error, data }) {
        if (data) {
            console.log('Wired Polizas:', JSON.stringify(data));
            this.polizas = data;
            this.actualizarKPIs();
        } else if (error) {
            console.log('Error Wired Polizas:', JSON.stringify(error));
            this.mostrarError('Error al cargar pólizas');
        }
    }

    @wire(getResumenPolizas)
    wiredResumen({ error, data }) {
        if (data) {
            console.log('Wired Resumen:', JSON.stringify(data));
            this.resumen = data;
            this.actualizarKPIs();
        }else if (error) {
            console.log('Error Wired Resumen:', JSON.stringify(error));
            this.mostrarError('Error al cargar pólizas');
        }
    }

    // Handlers de filtros
    handleFechaDesdeChange(event) {
        this.fechaDesde = event.target.value;
    }

    handleFechaHastaChange(event) {
        this.fechaHasta = event.target.value;
    }

    handleEstadoChange(event) {
        this.filtroEstado = event.detail.value;
    }

    aplicarFiltros() {
        let filtered = [...this.polizas];

        // Filtro por fecha
        if (this.fechaDesde) {
            filtered = filtered.filter(poliza => 
                new Date(poliza.FechaVencimiento) >= new Date(this.fechaDesde)
            );
        }

        if (this.fechaHasta) {
            filtered = filtered.filter(poliza => 
                new Date(poliza.FechaVencimiento) <= new Date(this.fechaHasta)
            );
        }

        // Filtro por estado
        if (this.filtroEstado) {
            filtered = filtered.filter(poliza => 
                poliza.Estado === this.filtroEstado
            );
        }

        this.polizasFiltradas = filtered;
    }

    limpiarFiltros() {
        this.fechaDesde = '';
        this.fechaHasta = '';
        this.filtroEstado = '';
        this.polizasFiltradas = [...this.polizas];
    }

    // Getters computados para las tabs
    get polizasPagadas() {
        return this.polizasFiltradas.filter(poliza => poliza.Estado === 'Pagada');
    }

    get polizasPorPagar() {
        return this.polizasFiltradas.filter(poliza => poliza.Estado === 'Pendiente');
    }

    get polizasVigentesLista() {
        return this.polizasFiltradas.filter(poliza => poliza.Estado === 'Vigente');
    }

    get polizasCanceladasLista() {
        return this.polizasFiltradas.filter(poliza => poliza.Estado === 'Cancelada');
    }

    handleTabActive(event) {
        // Lógica adicional cuando se cambia de tab
    }

    handleActualizarDatos() {
        // Refrescar datos
        this.refreshApex(this.wiredPolizas);
        this.refreshApex(this.wiredResumen);
    }

    mostrarError(mensaje) {
        const event = new ShowToastEvent({
            title: 'Error',
            message: mensaje,
            variant: 'error'
        });
        this.dispatchEvent(event);
    }

    actualizarKPIs() {
        this.totalPolizas = this.resumen.totalPolizas;
        this.polizasVigentes = this.resumen.Vigor;
        this.polizasAnuladas = this.resumen.Anulada;
        this.polizasCanceladas = this.resumen.Cancelada;
        this.polizasTraspasadas = this.resumen.Traspaso;
        // Lógica para actualizar KPIs basado en datos locales
    }
}