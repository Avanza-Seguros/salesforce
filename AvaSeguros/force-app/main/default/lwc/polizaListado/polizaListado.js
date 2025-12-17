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
    @track sortedBy = 'Name';
    @track sortedDirection = 'asc';
    defaultSortDirection = 'asc';

    get columns() {
        return [
            {
                label: 'Póliza',
                fieldName: 'Name',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: 'slds-text-color_default slds-text-title_caps'
                }
            },
            {
                label: 'Aseguradora',
                fieldName: 'Aseguradora__c',
                type: 'text',
                sortable: true
            },
            {
                label: 'Asegurado',
                fieldName: 'Asegurado_r.Name',
                type: 'text',
                sortable: true
            },
            {
                label: 'Ramo',
                fieldName: 'Ramo__c',
                type: 'text',
                sortable: true
            },
            {
                label: 'Forma de pago',
                fieldName: 'ClienteNombre',
                type: 'text',
                sortable: true
            },
            {
                label: 'Fecha Vencimiento',
                fieldName: 'ClienteNombre',
                type: 'text',
                sortable: true
            },
            {
                label: 'Cliente',
                fieldName: 'ClienteNombre',
                type: 'text',
                sortable: true
            },
            {
                label: 'Fecha de pago',
                fieldName: 'ClienteNombre',
                type: 'date',
                sortable: true
            },
            {
                label: 'Pago en MXN',
                fieldName: 'Estatus__c',
                type: 'text',
                sortable: true,
                cellAttributes: {
                    class: { 
                        fieldName: 'estadoClase' 
                    }
                }
            },
            {
                label: 'Pago en MXN',
                fieldName: 'PrimaTotal',
                type: 'currency',
                sortable: true,
                typeAttributes: {
                    currencyCode: 'MXN'
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