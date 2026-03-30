import { LightningElement, track, wire } from 'lwc';
import getDashboardData from '@salesforce/apex/massEmailConsoleController.getDashboardData';
import runMassEmailFlow from '@salesforce/apex/massEmailConsoleController.runMassEmailFlow';
import getAvailableCases from '@salesforce/apex/massEmailConsoleController.getAvailableCases';

export default class MassEmailConsole extends LightningElement {

    // Variables de estado
    @track pending = 0;
    @track sentToday = 0;
    @track loading = false;
    @track status = '';
    @track isSuccess = false;
    @track isError = false;

    // Variables para selección de casos
    @track selectionMode = 'all'; // 'all' o 'manual'
    @track selectedCaseIds = [];
    @track selectedCases = [];
    @track caseOptions = [];
    @track showCaseSelector = false;

    // Opciones para el radio group
    selectionOptions = [
        { label: 'Todos los casos pendientes', value: 'all' },
        { label: 'Seleccionar casos específicos', value: 'manual' }
    ];

    connectedCallback() {
        this.refreshData();
        this.loadAvailableCases();
    }

    // Wire para cargar casos disponibles
    @wire(getAvailableCases)
    wiredCases({ error, data }) {
        if (data) {
            this.caseOptions = data.map(caso => ({
                label: `${caso.CaseNumber}: ${caso.Subject || 'Sin asunto'}`,
                value: caso.Id
            }));
        } else if (error) {
            console.error('Error loading cases:', error);
        }
    }

    get showSelectedCases() {
        return this.selectionMode === 'manual';
    }

    get isRunDisabled() {
        if (this.loading) return true;
        if (this.selectionMode === 'manual') {
            return this.selectedCaseIds.length === 0;
        }
        return false;
    }

    handleSelectionModeChange(event) {
        this.selectionMode = event.detail.value;
        this.showCaseSelector = this.selectionMode === 'manual';
        
        if (this.selectionMode === 'all') {
            this.selectedCaseIds = [];
            this.selectedCases = [];
        }
    }

    handleCaseSelection(event) {
        this.selectedCaseIds = event.detail.value;
        this.updateSelectedCases();
    }

    updateSelectedCases() {
        // Filtrar los casos seleccionados del listado completo
        this.selectedCases = this.caseOptions
            .filter(option => this.selectedCaseIds.includes(option.value))
            .map(option => ({
                Id: option.value,
                CaseNumber: option.label.split(':')[0],
                Subject: option.label.split(':')[1]?.trim() || 'Sin asunto'
            }));
    }

    removeCase(event) {
        const caseId = event.currentTarget.dataset.id;
        this.selectedCaseIds = this.selectedCaseIds.filter(id => id !== caseId);
        this.selectedCases = this.selectedCases.filter(caso => caso.Id !== caseId);
        
        // Actualizar combobox
        const combobox = this.template.querySelector('lightning-combobox');
        if (combobox) {
            combobox.value = this.selectedCaseIds;
        }
    }

    refreshData() {
        console.log('Refreshing data...');
        this.loading = true;
        this.status = '';
        this.isSuccess = false;
        this.isError = false;

        getDashboardData()
            .then(result => {
                if (result) {
                    console.log('Result:', result);
                    this.showSuccess('Datos actualizados correctamente.');
                } else {
                    this.showError('No se pudieron cargar los datos.');
                }
                this.pending = result.pending;
                this.sentToday = result.sentToday;
            })
            .catch(error => {
                console.error(error);
                this.showError('Error al cargar datos: ' + error.body?.message);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    loadAvailableCases() {
        console.log('loadAvailableCases');
        // Este método asegura que los casos se carguen si el wire no funciona
        getAvailableCases()
            .then(data => {
                if (data) {
                    console.log('Data:', data);
                    this.showSuccess('Casos disponibles cargados correctamente.');
                } else {
                    this.showError('No se pudieron cargar los casos disponibles.');
                }
                this.caseOptions = data.map(caso => ({
                    label: `${caso.CaseNumber}: ${caso.Subject || 'Sin asunto'}`,
                    value: caso.Id
                }));
            })
            .catch(error => {
                console.error('Error loading cases:', error);
            });
    }

    async handleRun() {
        console.log('handleRun');
        console.log('this.selectionMode', this.selectionMode);
        console.log('this.selectedCaseIds', this.selectedCaseIds);
        this.loading = true;
        this.status = '';
        this.isSuccess = false;
        this.isError = false;

        const params = {
            selectionMode: this.selectionMode,
            caseIds: this.selectionMode === 'manual' ? this.selectedCaseIds : null
        };
        console.log('Running with params:', JSON.stringify(params));
        await runMassEmailFlow({ params: JSON.stringify(params) })
            .then(result => {
                console.log('Result:', result);
                if (result === 'OK') {
                    this.showSuccess('El proceso ha sido lanzado correctamente. Revisa nuevamente en 1-2 minutos.');
                    
                    // Limpiar selección si fue manual
                    if (this.selectionMode === 'manual') {
                        this.selectedCaseIds = [];
                        this.selectedCases = [];
                        const combobox = this.template.querySelector('lightning-combobox');
                        if (combobox) {
                            combobox.value = [];
                        }
                    }
                } else {
                    this.showError(result);
                }
            })
            .catch(error => {
                this.showError('ERROR: ' + (error.body?.message || JSON.stringify(error)));
            })
            .finally(() => {
                this.loading = false;
                this.refreshData();
            });
    }

    showSuccess(message) {
        this.status = message;
        this.isSuccess = true;
        this.isError = false;
    }

    showError(message) {
        this.status = message;
        this.isSuccess = false;
        this.isError = true;
    }

    get casosSeleccionados() {
        return this.showSelectedCases && this.selectedCases.length > 0
    }
}