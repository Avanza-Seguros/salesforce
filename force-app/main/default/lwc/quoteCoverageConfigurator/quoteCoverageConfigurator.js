import { LightningElement, api, wire, track } from 'lwc';
import getCoverages from '@salesforce/apex/QuoteCoverageController.getCoverages';
import saveCoverages from '@salesforce/apex/QuoteCoverageController.saveCoverages';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class QuoteCoverageConfigurator extends LightningElement {
    
    @api recordId; // Quote Id - ahora se espera del padre
    
    @track coverages = [];
    @track isLoading = true;
    @track hasChanges = false;
    @track originalCoverages = [];
    
    // Propiedades computadas
    get totalCount() {
        return this.coverages.length;
    }
    
    get selectedCount() {
        return this.coverages.filter(c => c.Is_Selected__c).length;
    }
    
    get totalPremium() {
        return this.coverages.reduce((sum, c) => {
            return c.Is_Selected__c ? sum + (c.Premium__c || 0) : sum;
        }, 0);
    }
    
    get formattedTotalPremium() {
        return this.formatCurrency(this.totalPremium);
    }
    
    get hasCoverages() {
        return this.coverages && this.coverages.length > 0;
    }
    
    get allSelected() {
        return this.hasCoverages && this.selectedCount === this.totalCount;
    }
    
    get noneSelected() {
        return this.selectedCount === 0;
    }
    
    @wire(getCoverages, { quoteId: '' })
    wiredCoverages({ error, data }) {
        console.log('Result from getCoverages:', JSON.stringify(data), JSON.stringify(error));
        if (data) {
            console.log('Coverages retrieved:', data);
            this.coverages = data.map(c => ({
                ...c,
                name: c.Name,
                originalSumInsured: c.Sum_Insured__c,
                originalDeductible: c.Deductible__c,
                originalSelected: c.Is_Selected__c,
                CalculatedPremium: this.calculatePremium(c)
            }));
            
            // Guardar copia original para detectar cambios
            this.originalCoverages = JSON.parse(JSON.stringify(this.coverages));
            this.isLoading = false;
            this.hasChanges = false;
            
        } else if (error) {
            console.error('Error loading coverages:', error);
            this.showToast('Error', 'No se pudieron cargar las coberturas', 'error');
            this.isLoading = false;
        }
    }
    
    handleCheckbox(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        
        this.updateCoverage(id, { Is_Selected__c: checked });
        
        // Si se deselecciona, resetear valores
        if (!checked) {
            this.updateCoverage(id, { 
                Sum_Insured__c: 0,
                Deductible__c: 0,
                Premium__c: 0
            });
        } else {
            // Recalcular prima cuando se selecciona
            const coverage = this.coverages.find(c => c.Id === id);
            if (coverage) {
                const newPremium = this.calculatePremium(coverage);
                this.updateCoverage(id, { Premium__c: newPremium });
            }
        }
    }
    
    handleInput(event) {
        const id = event.target.dataset.id;
        const field = event.target.name;
        let value = event.target.value;
        
        // Validaciones
        if (field === 'Sum_Insured__c') {
            value = Math.max(0, parseFloat(value) || 0);
        } else if (field === 'Deductible__c') {
            value = Math.min(100, Math.max(0, parseFloat(value) || 0));
        }
        
        this.updateCoverage(id, { [field]: value });
        
        // Recalcular prima si es necesario
        const coverage = this.coverages.find(c => c.Id === id);
        if (coverage && coverage.Is_Selected__c) {
            const newPremium = this.calculatePremium(coverage);
            if (newPremium !== coverage.Premium__c) {
                this.updateCoverage(id, { Premium__c: newPremium });
            }
        }
    }
    
    updateCoverage(id, updates) {
        this.coverages = this.coverages.map(c => 
            c.Id === id ? { ...c, ...updates } : c
        );
        this.detectChanges();
    }
    
    detectChanges() {
        if (!this.originalCoverages.length) return;
        
        const hasChanges = this.coverages.some((current, index) => {
            const original = this.originalCoverages[index];
            return current.Is_Selected__c !== original.Is_Selected__c ||
                   current.Sum_Insured__c !== original.Sum_Insured__c ||
                   current.Deductible__c !== original.Deductible__c;
        });
        
        this.hasChanges = hasChanges;
    }
    
    calculatePremium(coverage) {
        // Lógica mejorada de cálculo de prima
        // Basado en suma asegurada, deducible y tipo de cobertura
        const basePremium = coverage.BasePremium || 1000;
        const sumFactor = (coverage.Sum_Insured__c || 10000) / 10000;
        const deductibleFactor = 1 - ((coverage.Deductible__c || 0) / 100);
        
        let calculatedPremium = basePremium * sumFactor * deductibleFactor;
        
        // Aplicar descuentos según tipo de cobertura
        if (coverage.Type__c === 'Básica') {
            calculatedPremium *= 0.9;
        } else if (coverage.Type__c === 'Premium') {
            calculatedPremium *= 1.2;
        }
        
        return Math.round(calculatedPremium * 100) / 100;
    }
    
    selectAll() {
        this.coverages = this.coverages.map(c => ({
            ...c,
            Is_Selected__c: true,
            Premium__c: this.calculatePremium(c)
        }));
        this.detectChanges();
        this.showToast('Info', 'Todas las coberturas seleccionadas', 'info');
    }
    
    deselectAll() {
        this.coverages = this.coverages.map(c => ({
            ...c,
            Is_Selected__c: false,
            Sum_Insured__c: 0,
            Deductible__c: 0,
            Premium__c: 0
        }));
        this.detectChanges();
        this.showToast('Info', 'Todas las coberturas deseleccionadas', 'info');
    }
    
    async handleSave() {
        if (!this.hasChanges) {
            this.showToast('Info', 'No hay cambios para guardar', 'info');
            return;
        }
        
        this.isLoading = true;
        
        try {
            const coveragesToSave = this.coverages.map(c => ({
                Id: c.Id,
                Is_Selected__c: c.Is_Selected__c,
                Sum_Insured__c: c.Sum_Insured__c,
                Deductible__c: c.Deductible__c,
                Premium__c: c.Premium__c
            }));
            
            await saveCoverages({ coverages: coveragesToSave });
            
            // Actualizar copia original
            this.originalCoverages = JSON.parse(JSON.stringify(this.coverages));
            this.hasChanges = false;
            
            this.showToast('Éxito', 'Coberturas actualizadas correctamente', 'success');
            
            // Disparar evento para notificar al padre
            this.dispatchEvent(new CustomEvent('coveragessaved', {
                detail: { coverages: this.coverages }
            }));
            
        } catch (error) {
            console.error('Error saving coverages:', error);
            this.showToast('Error', 'Error al guardar las coberturas', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    handleRefresh() {
        this.isLoading = true;
        this.hasChanges = false;
        // Recargar datos
        return this.wiredCoverages.refresh();
    }
    
    showHelp() {
        this.showToast('Ayuda', 'Selecciona las coberturas deseadas y configura los valores de suma asegurada y deducible', 'info');
    }
    
    formatCurrency(value) {
        if (!value && value !== 0) return '$0.00';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 2
        }).format(value);
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
                mode: 'dismissible'
            })
        );
    }
}