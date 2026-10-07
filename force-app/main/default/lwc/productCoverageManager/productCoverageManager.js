import { LightningElement, track, wire } from 'lwc';
import getAseguradoras from '@salesforce/apex/ProductCoverageManagerController.getAseguradoras';
import getProducts from '@salesforce/apex/ProductCoverageManagerController.getProducts';
import getCoverages from '@salesforce/apex/ProductCoverageManagerController.getCoverages';
import getAssignedCoveragesForMultipleProducts from '@salesforce/apex/ProductCoverageManagerController.getAssignedCoveragesForMultipleProducts';
import saveAssignmentsForMultipleProducts from '@salesforce/apex/ProductCoverageManagerController.saveAssignmentsForMultipleProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ProductCoverageManager extends LightningElement {
    // Paso 1: aseguradora. Solo se muestran sus productos.
    @track aseguradoras = [];
    selectedAseguradoraId = '';
    @track products = [];
    @track coverages = [];
    @track assignedCoverages = [];
    @track filteredProducts = [];
    @track filteredCoverages = [];
    @track filteredAssignedCoverages = [];
    @track selectedProductIds = [];
    @track assignedCoverageMap = new Map(); // coverageId -> { assigned: true, productCount: number }
    @track originalAssignedCoverageMap = new Map();
    isLoading = true;
    isSaving = false;
    productSearchTerm = '';
    coverageSearchTerm = '';
    assignedSearchTerm = '';
    
    connectedCallback() {
        this.loadAseguradoras();
    }

    // Carga las aseguradoras con el número de productos activos de cada una.
    loadAseguradoras() {
        getAseguradoras()
            .then(data => {
                this.aseguradoras = data || [];
            })
            .catch(error => {
                this.showError('Error cargando aseguradoras', error);
            });
    }

    get aseguradoraOptions() {
        return this.aseguradoras.map(a => ({
            label: `${a.Name} (${a.productos} producto${a.productos === 1 ? '' : 's'})`,
            value: a.Id
        }));
    }

    get hasAseguradora() {
        return !!this.selectedAseguradoraId;
    }

    get selectedAseguradoraName() {
        const a = this.aseguradoras.find(x => x.Id === this.selectedAseguradoraId);
        return a ? a.Name : '';
    }

    // Al elegir la aseguradora se cargan SOLO sus productos y se reinicia la selección.
    handleAseguradoraChange(event) {
        this.selectedAseguradoraId = event.detail.value;
        this.selectedProductIds = [];
        this.productSearchTerm = '';
        this.products = [];
        this.filteredProducts = [];
        this.assignedCoverageMap.clear();
        this.originalAssignedCoverageMap.clear();
        this.updateCoveragesAssignment();
        this.updateAssignedCoveragesList();
        if (!this.selectedAseguradoraId) { return; }
        this.isLoading = true;
        getProducts({ aseguradoraId: this.selectedAseguradoraId })
            .then(data => {
                this.products = (data || []).map(p => ({
                    Id: p.Id,
                    Name: p.Name,
                    Family: p.Family,
                    label: p.Family ? `${p.Name} · ${p.Family}` : p.Name,
                    selected: false
                }));
                this.filteredProducts = [...this.products];
            })
            .catch(error => {
                this.showError('Error cargando productos', error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showError(titulo, error) {
        this.dispatchEvent(new ShowToastEvent({
            title: titulo,
            message: (error && error.body && error.body.message) || (error && error.message) || 'Error desconocido',
            variant: 'error'
        }));
    }

    @wire(getCoverages)
    wiredCoverages({ data, error }) {
        if (data) {
            this.coverages = data.map(c => ({
                Id: c.Id,
                Name: c.Name,
                assigned: false
            }));
            this.filteredCoverages = [...this.coverages];
            console.log('Coberturas cargadas:', this.coverages.length);
            this.checkLoadingComplete();
        } else if (error) {
            console.error('Error cargando coberturas:', error);
            this.checkLoadingComplete();
        }
    }
    
    checkLoadingComplete() {
        if (this.coverages !== undefined) {
            this.isLoading = false;
        }
    }
    
    handleProductSearch(event) {
        this.productSearchTerm = event.target.value || '';
        this.filterProducts();
    }
    
    filterProducts() {
        if (!this.productSearchTerm) {
            this.filteredProducts = [...this.products];
        } else {
            this.filteredProducts = this.products.filter(product => 
                (product.label || product.Name).toLowerCase().includes(this.productSearchTerm.toLowerCase())
            );
        }
    }
    
    handleProductCheckbox(event) {
        const productId = event.target.dataset.id;
        const isChecked = event.target.checked;
        
        if (isChecked) {
            if (!this.selectedProductIds.includes(productId)) {
                this.selectedProductIds = [...this.selectedProductIds, productId];
            }
        } else {
            this.selectedProductIds = this.selectedProductIds.filter(id => id !== productId);
        }
        
        // Actualizar estado de selección en el objeto product
        this.products = this.products.map(p => ({
            ...p,
            selected: this.selectedProductIds.includes(p.Id)
        }));
        
        this.filterProducts();
        this.loadAssignedCoveragesForSelection();
    }
    
    handleSelectAllProducts() {
        this.selectedProductIds = this.products.map(p => p.Id);
        this.products = this.products.map(p => ({
            ...p,
            selected: true
        }));
        this.filterProducts();
        this.loadAssignedCoveragesForSelection();
    }
    
    handleClearAllProducts() {
        this.selectedProductIds = [];
        this.products = this.products.map(p => ({
            ...p,
            selected: false
        }));
        this.filterProducts();
        this.loadAssignedCoveragesForSelection();
    }
    
    loadAssignedCoveragesForSelection() {
        if (this.selectedProductIds.length === 0) {
            this.assignedCoverageMap.clear();
            this.originalAssignedCoverageMap.clear();
            this.updateCoveragesAssignment();
            this.updateAssignedCoveragesList();
            return;
        }
        
        this.isLoading = true;
        
        getAssignedCoveragesForMultipleProducts({ productIds: this.selectedProductIds })
            .then(result => {
                // result es un mapa: { coverageId: productCount }
                this.assignedCoverageMap.clear();
                for (let key in result) {
                    this.assignedCoverageMap.set(key, {
                        assigned: true,
                        productCount: result[key]
                    });
                }
                
                // Guardar copia original para detectar cambios
                this.originalAssignedCoverageMap.clear();
                for (let [key, value] of this.assignedCoverageMap) {
                    this.originalAssignedCoverageMap.set(key, { ...value });
                }
                
                console.log('Coberturas asignadas cargadas:', this.assignedCoverageMap.size);
                this.updateCoveragesAssignment();
                this.updateAssignedCoveragesList();
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error cargando coberturas asignadas:', error);
                this.assignedCoverageMap.clear();
                this.originalAssignedCoverageMap.clear();
                this.updateCoveragesAssignment();
                this.updateAssignedCoveragesList();
                this.isLoading = false;
            });
    }
    
    handleCoverageCheckbox(event) {
        const coverageId = event.target.dataset.id;
        const isChecked = event.target.checked;
        
        if (isChecked) {
            if (!this.assignedCoverageMap.has(coverageId)) {
                this.assignedCoverageMap.set(coverageId, {
                    assigned: true,
                    productCount: 1
                });
            }
        } else {
            this.assignedCoverageMap.delete(coverageId);
        }
        
        this.updateCoveragesAssignment();
        this.updateAssignedCoveragesList();
    }
    
    updateAssignedCoveragesList() {
        // Convertir el mapa a lista para mostrar
        this.assignedCoverages = Array.from(this.assignedCoverageMap.entries()).map(([id, data]) => ({
            Id: id,
            Name: this.getCoverageName(id),
            productCount: data.productCount,
            assigned: data.assigned
        }));
        
        this.filterAssignedCoverages();
    }
    
    getCoverageName(coverageId) {
        const coverage = this.coverages.find(c => c.Id === coverageId);
        return coverage ? coverage.Name : 'Desconocido';
    }
    
    handleCoverageSearch(event) {
        this.coverageSearchTerm = event.target.value || '';
        this.filterCoverages();
    }
    
    filterCoverages() {
        if (!this.coverageSearchTerm) {
            this.filteredCoverages = [...this.coverages];
        } else {
            this.filteredCoverages = this.coverages.filter(coverage => 
                coverage.Name.toLowerCase().includes(this.coverageSearchTerm.toLowerCase())
            );
        }
        
        this.filteredCoverages = this.filteredCoverages.map(c => ({
            ...c,
            assigned: this.assignedCoverageMap.has(c.Id)
        }));
    }
    
    handleAssignedSearch(event) {
        this.assignedSearchTerm = event.target.value || '';
        this.filterAssignedCoverages();
    }
    
    filterAssignedCoverages() {
        if (!this.assignedSearchTerm) {
            this.filteredAssignedCoverages = [...this.assignedCoverages];
        } else {
            this.filteredAssignedCoverages = this.assignedCoverages.filter(coverage => 
                coverage.Name.toLowerCase().includes(this.assignedSearchTerm.toLowerCase())
            );
        }
    }
    
    updateCoveragesAssignment() {
        this.coverages = this.coverages.map(c => ({
            ...c,
            assigned: this.assignedCoverageMap.has(c.Id)
        }));
        
        this.filterCoverages();
    }
    
    // Selección rápida de coberturas
    handleSelectAllCoverages() {
        this.coverages.forEach(c => {
            if (!this.assignedCoverageMap.has(c.Id)) {
                this.assignedCoverageMap.set(c.Id, {
                    assigned: true,
                    productCount: 1
                });
            }
        });
        this.updateCoveragesAssignment();
        this.updateAssignedCoveragesList();
    }
    
    handleClearAllCoverages() {
        this.assignedCoverageMap.clear();
        this.updateCoveragesAssignment();
        this.updateAssignedCoveragesList();
    }
    
    handleSelectFilteredCoverages() {
        this.filteredCoverages.forEach(c => {
            if (!this.assignedCoverageMap.has(c.Id)) {
                this.assignedCoverageMap.set(c.Id, {
                    assigned: true,
                    productCount: 1
                });
            }
        });
        this.updateCoveragesAssignment();
        this.updateAssignedCoveragesList();
    }
    
    // Guardar cambios
    handleSave() {
        if (!this.hasChanges) return;
        
        this.isSaving = true;
        
        const coverageIds = Array.from(this.assignedCoverageMap.keys());
        
        saveAssignmentsForMultipleProducts({
            aseguradoraId: this.selectedAseguradoraId,
            productIds: this.selectedProductIds,
            coverageIds: coverageIds
        })
        .then((res) => {
            const r = res || {};
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Coberturas guardadas',
                    message: `${this.selectedAseguradoraName}: ${coverageIds.length} cobertura(s) en ${this.selectedProductsCount} producto(s). `
                        + `Agregadas: ${r.agregadas || 0} · Quitadas: ${r.quitadas || 0}.`,
                    variant: 'success'
                })
            );
            // Vuelve a leer lo que quedó guardado en ProductCoverage.
            this.loadAssignedCoveragesForSelection();
        })
        .catch(error => {
            console.error('Error guardando:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Error al guardar las coberturas: ' + (error.body?.message || error.message),
                    variant: 'error'
                })
            );
        })
        .finally(() => {
            this.isSaving = false;
        });
    }
    
    // Getters
    get hasProducts() {
        return this.products && this.products.length > 0;
    }
    
    get hasCoverages() {
        return this.coverages && this.coverages.length > 0;
    }
    
    get hasAssignedCoverages() {
        return this.assignedCoverages && this.assignedCoverages.length > 0;
    }
    
    get hasSelectedProducts() {
        return this.selectedProductIds.length > 0;
    }
    
    get noAssignedFound() {
        return this.filteredAssignedCoverages.length === 0 && this.assignedSearchTerm !== '';
    }
    
    get productCount() {
        return this.products.length;
    }
    
    get coverageCount() {
        return this.coverages.length;
    }
    
    get assignedCount() {
        return this.assignedCoverages.length;
    }
    
    get selectedProductsCount() {
        return this.selectedProductIds.length;
    }
    
    get selectedProductsList() {
        return this.products.filter(p => this.selectedProductIds.includes(p.Id));
    }
    
    get hasChanges() {
        if (this.selectedProductIds.length === 0) return false;
        
        if (this.assignedCoverageMap.size !== this.originalAssignedCoverageMap.size) {
            return true;
        }
        
        for (let [key, value] of this.assignedCoverageMap) {
            if (!this.originalAssignedCoverageMap.has(key)) {
                return true;
            }
        }
        
        return false;
    }
    
    get saveButtonTitle() {
        if (this.selectedProductsCount === 0) return 'Selecciona al menos un producto';
        if (!this.hasChanges) return 'No hay cambios para guardar';
        return 'Guardar cambios de coberturas';
    }

    get disabledSaveButton() {
        return !this.hasChanges || this.selectedProductsCount === 0;
    }
}