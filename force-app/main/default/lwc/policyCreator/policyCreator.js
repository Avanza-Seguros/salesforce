import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPolicyIdByQuote from '@salesforce/apex/PolicyController.getPolicyIdByQuote';

export default class PolicyCreator extends NavigationMixin(LightningElement) {
    @track policyId;
    @track quoteId;
    @track opportunityId;
    @track loading = true;
    @track errorMsg = '';

    // Recibe los Ids por navegación (desde el botón "Póliza" de Crear Oportunidad).
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) { return; }
        this.quoteId = pageRef.state.c__quoteId;
        this.opportunityId = pageRef.state.c__opportunityId;
        this.loadPolicy();
    }

    async loadPolicy() {
        this.loading = true;
        this.errorMsg = '';
        this.policyId = null;
        try {
            const id = await getPolicyIdByQuote({
                quoteId: this.quoteId,
                opportunityId: this.opportunityId
            });
            if (id) {
                this.policyId = id;
            } else {
                this.errorMsg = 'No se encontró la póliza de esta oportunidad. '
                    + 'Verifica que el flujo la haya creado al pasar a etapa Póliza.';
            }
        } catch (e) {
            this.errorMsg = (e && e.body && e.body.message) || 'Error al cargar la póliza.';
        } finally {
            this.loading = false;
        }
    }

    get hasPolicy() {
        return !!this.policyId;
    }

    handleSuccess() {
        this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
    }
    handleError(event) {
        const msg = (event && event.detail && event.detail.message) || 'No se pudo guardar la póliza.';
        this.showToast('Error', msg, 'error');
    }

    // El análisis de PDF de Póliza se conectará cuando esté listo el Prompt Template.
    handleAnalizarPdf() {
        this.showToast(
            'Próximamente',
            'El análisis de PDF de Póliza se habilitará en el siguiente paso.',
            'info'
        );
    }

    handleReintentar() {
        this.loadPolicy();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}