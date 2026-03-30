// polizaListado/polizaListado.js
import { LightningElement, api, track } from 'lwc';

const ACTIONS = [
    { label: 'Ver Detalles', name: 'ver_detalles' },
    { label: 'Registrar Pago', name: 'registrar_pago' },
    { label: 'Cancelar Póliza', name: 'cancelar_poliza' }
];

export default class PolizaListado extends LightningElement {
    @api polizas = [];
    @api estadoFiltro = 'todas';
    
    @track cargando = false;
    @track sortedBy = 'Nombre';
    @track sortedDirection = 'asc';
    defaultSortDirection = 'asc';

    get columns() {
        return [
            {
                label: 'Número Póliza',
                fieldName: 'Nombre',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: 'slds-text-color_default slds-text-title_caps'
                }
            },
            {
                label: 'Cliente',
                fieldName: 'ClienteNombre',
                type: 'text',
                sortable: true
            },
            {
                label: 'Estado',
                fieldName: 'Estado',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: { 
                        fieldName: 'estadoClase' 
                    }
                }
            },
            {
                label: 'Prima Total',
                fieldName: 'PrimaTotal',
                type: 'currency',
                sortable: true,
                typeAttributes: {
                    currencyCode: 'USD'
                }
            },
            {
                label: 'Fecha Vencimiento',
                fieldName: 'FechaVencimiento',
                type: 'date',
                sortable: true
            },
            {
                label: 'Saldo Pendiente',
                fieldName: 'SaldoPendiente',
                type: 'currency',
                sortable: true,
                typeAttributes: {
                    currencyCode: 'USD'
                }
            },
            {
                type: 'action',
                typeAttributes: { rowActions: ACTIONS }
            }
        ];
    }

    get tituloListado() {
        const titulos = {
            'todas': 'Todas las Pólizas',
            'pagadas': 'Pólizas Pagadas',
            'pendientes': 'Pólizas por Pagar',
            'vigentes': 'Pólizas en Vigor',
            'canceladas': 'Pólizas Canceladas'
        };
        return titulos[this.estadoFiltro] || 'Pólizas';
    }

    get totalRegistros() {
        return this.polizas.length;
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        
        switch (action.name) {
            case 'ver_detalles':
                this.mostrarDetalles(row.Id);
                break;
            case 'registrar_pago':
                this.registrarPago(row.Id);
                break;
            case 'cancelar_poliza':
                this.cancelarPoliza(row.Id);
                break;
        }
    }

    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortedDirection = event.detail.sortDirection;
        this.sortData(this.sortedBy, this.sortedDirection);
    }

    sortData(field, direction) {
        // Lógica de ordenamiento
        const reverse = direction === 'asc' ? 1 : -1;
        this.polizas.sort((a, b) => {
            const valueA = a[field] || '';
            const valueB = b[field] || '';
            return reverse * ((valueA > valueB) - (valueB > valueA));
        });
    }

    mostrarDetalles(polizaId) {
        this.dispatchEvent(new CustomEvent('mostrardetalles', {
            detail: { polizaId }
        }));
    }

    registrarPago(polizaId) {
        this.dispatchEvent(new CustomEvent('registrarpago', {
            detail: { polizaId }
        }));
    }

    cancelarPoliza(polizaId) {
        this.dispatchEvent(new CustomEvent('cancelarpoliza', {
            detail: { polizaId }
        }));
    }

    exportarDatos() {
        // Lógica para exportar datos
    }
}