import { LightningElement, track, wire } from 'lwc';
import getProducts from '@salesforce/apex/ProductCoverageManagerController.getProducts';
import getCoverages from '@salesforce/apex/ProductCoverageManagerController.getCoverages';
import getAssignedCoveragesForMultipleProducts from '@salesforce/apex/ProductCoverageManagerController.getAssignedCoveragesForMultipleProducts';
import saveAssignmentsForMultipleProducts from '@salesforce/apex/ProductCoverageManagerController.saveAssignmentsForMultipleProducts';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ProductCoverageManager extends LightningElement {
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
    
    @wire(getProducts)
    wiredProducts({ data, error }) {
        if (data) {
            this.products = data.map(p => ({
                Id: p.Id,
                Name: p.Name,
                selected: false
            }));
            this.filteredProducts = [...this.products];
            console.log('Productos cargados:', this.products.length);
            this.checkLoadingComplete();
        } else if (error) {
            console.error('Error cargando productos:', error);
            this.checkLoadingComplete();
        }
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
        if (this.products !== undefined && this.coverages !== undefined) {
            this.isLoading = false;
        }
    }
    
    handleProductSearch(event) {
        this.productSearchTerm = event.target.value.toLowerCase();
        this.filterProducts();
    }
    
    filterProducts() {
        if (!this.productSearchTerm) {
            this.filteredProducts = [...this.products];
        } else {
            this.filteredProducts = this.products.filter(product => 
                product.Name.toLowerCase().includes(this.productSearchTerm)
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
        this.coverageSearchTerm = event.target.value.toLowerCase();
        this.filterCoverages();
    }
    
    filterCoverages() {
        if (!this.coverageSearchTerm) {
            this.filteredCoverages = [...this.coverages];
        } else {
            this.filteredCoverages = this.coverages.filter(coverage => 
                coverage.Name.toLowerCase().includes(this.coverageSearchTerm)
            );
        }
        
        this.filteredCoverages = this.filteredCoverages.map(c => ({
            ...c,
            assigned: this.assignedCoverageMap.has(c.Id)
        }));
    }
    
    handleAssignedSearch(event) {
        this.assignedSearchTerm = event.target.value.toLowerCase();
        this.filterAssignedCoverages();
    }
    
    filterAssignedCoverages() {
        if (!this.assignedSearchTerm) {
            this.filteredAssignedCoverages = [...this.assignedCoverages];
        } else {
            this.filteredAssignedCoverages = this.assignedCoverages.filter(coverage => 
                coverage.Name.toLowerCase().includes(this.assignedSearchTerm)
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
            productIds: this.selectedProductIds,
            coverageIds: coverageIds
        })
        .then(() => {
            // Actualizar el estado original
            this.originalAssignedCoverageMap.clear();
            for (let [key, value] of this.assignedCoverageMap) {
                this.originalAssignedCoverageMap.set(key, { ...value });
            }
            
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Éxito',
                    message: `Se han guardado ${coverageIds.length} coberturas para ${this.selectedProductsCount} producto(s)`,
                    variant: 'success'
                })
            );
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