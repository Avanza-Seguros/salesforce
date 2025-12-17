import { LightningElement, track } from 'lwc';
// Verifica que el import sea EXACTAMENTE igual al nombre de la clase
import buildRelaciones from '@salesforce/apex/GenerarRelacionPolizaController.buildRelaciones';

export default class GenerarRelacionPoliza extends LightningElement {
    @track polizaIds = '';
    @track resultado;
    @track error;
    @track isLoading = false;
    @track relacionesCreadas = [];

    handlePolizaIdsChange(event) {
        this.polizaIds = event.target.value;
    }

    handleGenerarRelaciones() {
        if (!this.polizaIds || this.polizaIds.trim() === '') {
            this.showToast('Error', 'Por favor ingresa al menos un ID de póliza', 'error');
            return;
        }

        this.isLoading = true;
        this.error = undefined;
        this.resultado = undefined;

        // Convertir a array y limpiar los IDs
        const idsArray = this.polizaIds.split(',')
            .map(id => id.trim())
            .filter(id => id !== '' && id.length >= 15); // Filtro básico para IDs

        console.log('IDs a procesar:', idsArray); // Para debug

        buildRelaciones({ polizaIds: idsArray })
            .then(result => {
                this.relacionesCreadas = result;
                this.resultado = `Se crearon ${result.length} relaciones de póliza exitosamente`;
                this.isLoading = false;
                this.showToast('Éxito', `Se generaron ${result.length} relaciones correctamente`, 'success');
                this.polizaIds = '';
            })
            .catch(error => {
                this.error = error;
                this.isLoading = false;
                console.error('Error completo:', error);
                this.showToast('Error', 'Error al generar las relaciones: ' + this.getErrorMessage(error), 'error');
            });
    }

    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        }
        return error.message || 'Error desconocido';
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    get hasRelacionesCreadas() {
        return this.relacionesCreadas && this.relacionesCreadas.length > 0;
    }

    get relacionesColumns() { 
        this.isLoading || !this.polizaIds;
    }
}