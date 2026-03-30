import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboardDataCobranza from '@salesforce/apex/PolizaDashboardController.getDashboardDataCobranza';
import getPolizasVencidas from '@salesforce/apex/PolizaDashboardController.getPolizasVencidas';

export default class PolizaDashboard extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track polizas = [];
    @track polizasVencidas = [];
    @track selectedPeriodo = 'mensual';
    @track totalPendiente = 0;
    @track totalPolizas = 0;
    @track totalSumaAsegurada = 0;
    @track resumenEstatus = [];
    @track currentPage = 1;
    @track pageSize = 10;
    @track sortBy = 'Fecha_Proximo_Pago__c';
    @track sortDirection = 'asc';
    @track errorMessage = '';
    @track fechaInicio = '';
    @track fechaFin = '';
    @track showVencidas = false;

    periodos = [
        { label: 'Este Mes', value: 'mensual' },
        { label: 'Este Bimestre', value: 'bimestral' },
        { label: 'Este Semestre', value: 'semestral' }
    ];

    connectedCallback() {
        console.log('🚀 Iniciando Dashboard de Cobranza');
        this.cargarDatosCobranza();
        this.cargarPolizasVencidas();
    }

    async cargarDatosCobranza() {
        console.log(`🔄 Cargando datos de cobranza para período: ${this.selectedPeriodo}`);
        try {
            this.isLoading = true;
            const data = await getDashboardDataCobranza({ periodo: this.selectedPeriodo });
            
            console.log('✅ Datos de cobranza recibidos:', data);
            
            this.polizas = data.polizas || [];
            this.totalPendiente = data.totalPendiente || 0;
            this.totalPolizas = data.totalPolizas || 0;
            this.totalSumaAsegurada = data.totalSumaAsegurada || 0;
            this.resumenEstatus = data.resumenEstatus || [];
            this.fechaInicio = this.formatDateForDisplay(data.fechaInicio);
            this.fechaFin = this.formatDateForDisplay(data.fechaFin);
            this.errorMessage = '';

            console.log('✅ Datos de cobranza procesados:', this.totalPolizas + ' pólizas');

        } catch (error) {
            console.error('❌ Error al cargar datos de cobranza:', error);
            this.errorMessage = 'Error al cargar datos de cobranza: ' + (error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }

    async cargarPolizasVencidas() {
        try {
            this.polizasVencidas = await getPolizasVencidas();
            console.log('✅ Pólizas vencidas cargadas:', this.polizasVencidas.length);
        } catch (error) {
            console.error('❌ Error al cargar pólizas vencidas:', error);
        }
    }

    handlePeriodoChange(event) {
        console.log('🔄 Cambiando período de cobranza a:', event.detail.value);
        this.selectedPeriodo = event.detail.value;
        this.currentPage = 1;
        this.showVencidas = false;
        this.cargarDatosCobranza();
    }

    toggleVencidas() {
        this.showVencidas = !this.showVencidas;
        this.currentPage = 1;
    }

    // Métodos de utilidad
    formatCurrency(amount) {
        if (amount == null || isNaN(amount)) return '$0.00';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 2
        }).format(amount);
    }

    formatDate(dateString) {
        if (!dateString) return 'N/A';
        try {
            const date = new Date(dateString);
            return date.toLocaleDateString('es-MX');
        } catch (error) {
            return 'N/A';
        }
    }

    formatDateForDisplay(dateValue) {
        if (!dateValue) return 'N/A';
        try {
            const date = new Date(dateValue);
            return date.toLocaleDateString('es-MX', {
                year: 'numeric',
                month: 'long',
                day: 'numeric'
            });
        } catch (error) {
            return 'N/A';
        }
    }

    calcularDiasVencimiento(fechaPago) {
        if (!fechaPago) return 0;
        try {
            const hoy = new Date();
            const fechaPagoDate = new Date(fechaPago);
            const diffTime = hoy - fechaPagoDate;
            const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
            return diffDays > 0 ? diffDays : 0;
        } catch (error) {
            return 0;
        }
    }

    getEstatusBadgeClass(estatus) {
        if (!estatus) return 'estado-default';
        
        const estatusLower = estatus.toLowerCase();
        if (estatusLower.includes('activa') || estatusLower.includes('vigor')) {
            return 'estado-activa';
        } else if (estatusLower.includes('vencida')) {
            return 'estado-vencida';
        } else if (estatusLower.includes('pagada')) {
            return 'estado-pagada';
        } else if (estatusLower.includes('pendiente')) {
            return 'estado-pendiente';
        } else {
            return 'estado-default';
        }
    }

    // Getters computados para cobranza
    get polizasPaginadas() {
        const polizasParaMostrar = this.showVencidas ? this.polizasVencidas : this.polizas;
        
        let sortedPolizas = [...polizasParaMostrar];
        
        // Procesar polizas para agregar campos calculados
        sortedPolizas = sortedPolizas.map(poliza => ({
            ...poliza,
            diasVencimiento: this.calcularDiasVencimiento(poliza.Fecha_Proximo_Pago__c),
            montoFormatted: this.formatCurrency(poliza.Monto_Proximo_Pago__c),
            fechaPagoFormatted: this.formatDate(poliza.Fecha_Proximo_Pago__c),
            estatusClass: this.getEstatusBadgeClass(poliza.Estatus__c)
        }));
        
        // Ordenar
        sortedPolizas.sort((a, b) => {
            let valueA = a[this.sortBy];
            let valueB = b[this.sortBy];
            
            if (valueA === null || valueA === undefined) valueA = '';
            if (valueB === null || valueB === undefined) valueB = '';
            
            if (typeof valueA === 'string') {
                valueA = valueA.toLowerCase();
                valueB = valueB.toLowerCase();
            }
            
            if (valueA < valueB) {
                return this.sortDirection === 'asc' ? -1 : 1;
            }
            if (valueA > valueB) {
                return this.sortDirection === 'asc' ? 1 : -1;
            }
            return 0;
        });

        const start = (this.currentPage - 1) * this.pageSize;
        const end = start + this.pageSize;
        return sortedPolizas.slice(start, end);
    }

    get totalPages() {
        const polizasParaMostrar = this.showVencidas ? this.polizasVencidas : this.polizas;
        return Math.ceil(polizasParaMostrar.length / this.pageSize);
    }

    get hasPreviousPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get formattedTotalPendiente() {
        return this.formatCurrency(this.totalPendiente);
    }

    get formattedSumaAsegurada() {
        return this.formatCurrency(this.totalSumaAsegurada);
    }

    get periodoDisplay() {
        const periodoMap = {
            'mensual': 'Este Mes',
            'bimestral': 'Este Bimestre', 
            'semestral': 'Este Semestre'
        };
        return periodoMap[this.selectedPeriodo] || 'Este Mes';
    }

    get tienePolizasVencidas() {
        return this.polizasVencidas && this.polizasVencidas.length > 0;
    }

    get cantidadPolizasVencidas() {
        return this.polizasVencidas ? this.polizasVencidas.length : 0;
    }

    get totalVencido() {
        if (!this.polizasVencidas) return 0;
        return this.polizasVencidas.reduce((total, poliza) => {
            return total + (poliza.Monto_Proximo_Pago__c || 0);
        }, 0);
    }

    get formattedTotalVencido() {
        return this.formatCurrency(this.totalVencido);
    }

    get mostrarPolizasDelPeriodo() {
        return !this.showVencidas && this.polizas.length > 0;
    }

    get mostrarPolizasVencidas() {
        return this.showVencidas && this.polizasVencidas.length > 0;
    }

    get noHayDatos() {
        return !this.isLoading && 
               ((!this.showVencidas && this.polizas.length === 0) || 
                (this.showVencidas && this.polizasVencidas.length === 0));
    }

    // Métodos de UI
    previousPage() {
        if (this.hasPreviousPage) {
            this.currentPage--;
        }
    }

    nextPage() {
        if (this.hasNextPage) {
            this.currentPage++;
        }
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortBy === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortBy = field;
            this.sortDirection = 'asc';
        }
    }

    navigateToRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    objectApiName: 'Polizas__c',
                    actionName: 'view'
                }
            });
        }
    }

    get resumenEstatusConClase() {
        if (!this.resumenEstatus) return [];
        
        return this.resumenEstatus.map(item => {
            let claseBadge = 'estatus-badge ';
            
            if (!item.estatus) {
                claseBadge += 'estado-default';
            } else {
                const estatusLower = item.estatus.toLowerCase();
                if (estatusLower.includes('activa') || estatusLower.includes('vigor')) {
                    claseBadge += 'estado-activa';
                } else if (estatusLower.includes('vencida')) {
                    claseBadge += 'estado-vencida';
                } else if (estatusLower.includes('pagada')) {
                    claseBadge += 'estado-pagada';
                } else if (estatusLower.includes('pendiente')) {
                    claseBadge += 'estado-pendiente';
                } else {
                    claseBadge += 'estado-default';
                }
            }
            
            return {
                ...item,
                claseBadge: claseBadge
            };
        });
    }

    get classDiasVencimiento() {
        return this.calcularDiasVencimiento > 0 ? 'estado-vencida' : 'estado-pendiente';
    }

    get labelDiasVencimiento() {
        return this.showVencidas ? 'Ver Pólizas del Período' : 'Ver Pólizas Vencidas';
    }

    get resumenEstatusSize(){
        return this.resumenEstatus.length > 0;
    }
}