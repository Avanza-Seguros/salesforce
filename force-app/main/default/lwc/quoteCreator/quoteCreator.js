import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import QUOTE_OBJECT from '@salesforce/schema/Quote';
import STATUS_FIELD from '@salesforce/schema/Quote.Status';

import getQuotes from '@salesforce/apex/QuoteCreatorController.getQuotes';
import getQuoteById from '@salesforce/apex/QuoteCreatorController.getQuoteById';
import saveQuote from '@salesforce/apex/QuoteCreatorController.saveQuote';
import deleteQuote from '@salesforce/apex/QuoteCreatorController.deleteQuote';
import getCoveragesByQuoteId from '@salesforce/apex/QuoteCreatorController.getCoveragesByQuoteId';
import getCoveragesByProduct from '@salesforce/apex/QuoteCreatorController.getCoveragesByProduct';
import saveCoverages from '@salesforce/apex/QuoteCreatorController.saveCoverages';
import searchOpportunities from '@salesforce/apex/QuoteCreatorController.searchOpportunities';
import searchAseguradoras from '@salesforce/apex/QuoteCreatorController.searchAseguradoras';
import getProducts from '@salesforce/apex/QuoteCreatorController.getProducts';

// ============================================================
// CONSTANTES
// ============================================================
const VIEW_MODES = {
    LIST: 'list',
    CREATE: 'create',
    EDIT: 'edit'
};

// Etiquetas amigables para el estado (API value → label en español)
const STATUS_LABELS = {
    Draft: 'Borrador',
    Sent: 'Enviada',
    Accepted: 'Aceptada',
    Rejected: 'Rechazada',
    Expired: 'Expirada'
};

// Iconos por estado
const STATUS_ICONS = {
    Draft: 'utility:draft',
    Sent: 'utility:send',
    Accepted: 'utility:check',
    Rejected: 'utility:close',
    Expired: 'utility:clock'
};

const PAGE_SIZE = 12;

export default class QuoteCreator extends NavigationMixin(LightningElement) {
    /**
     * Si el componente se invoca desde una RecordPage de Opportunity,
     * recordId trae el Id de esa oportunidad y la preseleccionamos.
     */
    @api recordId;

    // ===== Estado de UI =====
    @track viewMode = VIEW_MODES.LIST;
    @track isLoading = false;
    @track isSaving = false;
    @track isLoadingCoverages = false;
    @track searchTerm = '';
    @track statusFilter = '';
    @track currentPage = 1;

    // ===== Datos =====
    @track quotes = [];
    @track quote = this.getDefaultQuote();
    @track coverages = [];

    // ===== Catálogo de productos disponibles para el ramo seleccionado =====
    @track availableProducts = [];
    @track isLoadingProducts = false;

    // ===== Lookups =====
    @track showOpportunityDropdown = false;
    @track opportunityResults = [];
    @track showAseguradoraDropdown = false;
    @track aseguradoraResults = [];
    @track aseguradoraSearchTerm = '';

    // ===== Wires =====
    objectInfo = { data: null, error: null };
    @track statusPicklistValues = [];

    // Timers debounce
    _opportunitySearchTimer = null;
    _aseguradoraSearchTimer = null;
    _searchTimer = null;

    // Navegación entrante (desde otro componente)
    _pendingNavigation = null;
    _connectedReady = false;

    // ============================================================
    // NAVEGACIÓN ENTRANTE (lee state c__opportunityId / c__quoteId)
    // ============================================================
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) return;
        const oppId    = pageRef.state.c__opportunityId;
        const oppName  = pageRef.state.c__opportunityName;
        const oppRamo  = pageRef.state.c__opportunityRamo;
        const quoteId  = pageRef.state.c__quoteId;
        if (oppId || quoteId) {
            this._pendingNavigation = { oppId, oppName, oppRamo, quoteId };
            if (this._connectedReady) this.processPendingNavigation();
        }
    }

    // ============================================================
    // WIRES (sólo Status — Ramo y Aseguradora se cargan vía Apex)
    // ============================================================
    @wire(getObjectInfo, { objectApiName: QUOTE_OBJECT })
    wiredObjectInfo(result) {
        this.objectInfo = result;
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: STATUS_FIELD })
    wiredStatusPicklistValues({ data }) {
        if (data) {
            this.statusPicklistValues = data.values.map(item => ({
                label: STATUS_LABELS[item.value] || item.label,
                value: item.value
            }));
        }
    }

    // ============================================================
    // OPCIONES DE COMBOBOX
    // ============================================================
    get statusOptions() { return this.statusPicklistValues; }

    get statusFilterOptions() {
        return [{ label: 'Todos los estados', value: '' }, ...this.statusPicklistValues];
    }

    // ============================================================
    // GETTERS DE VISTA
    // ============================================================
    get pageTitle() {
        if (this.viewMode === VIEW_MODES.LIST) return 'Cotizaciones';
        return this.isEditMode ? 'Editar Cotización' : 'Nueva Cotización';
    }

    get showListView() { return this.viewMode === VIEW_MODES.LIST; }
    get isEditMode()   { return this.viewMode === VIEW_MODES.EDIT; }
    get saveButtonLabel() {
        if (this.isSaving) return 'Guardando...';
        return this.isEditMode ? 'Actualizar' : 'Crear';
    }
    get saveIcon() { return this.isSaving ? 'utility:spinner' : 'utility:save'; }

    // ============================================================
    // LISTA: FILTROS / PAGINACIÓN / TOTALES
    // ============================================================
    get filteredQuotes() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        const status = this.statusFilter;
        return (this.quotes || []).filter(q => {
            if (status && q.Status !== status) return false;
            if (term) {
                const aseguradoraName = q.Aseguradora__r?.Name || '';
                const ramoName = q.Ramo__c || '';
                const match =
                    (q.Name || '').toLowerCase().includes(term) ||
                    (q.OpportunityName || q.Opportunity?.Name || '').toLowerCase().includes(term) ||
                    (q.Status || '').toLowerCase().includes(term) ||
                    aseguradoraName.toLowerCase().includes(term) ||
                    ramoName.toLowerCase().includes(term);
                if (!match) return false;
            }
            return true;
        });
    }

    get quotesCount() { return this.filteredQuotes.length; }
    get hasQuotes()   { return this.filteredQuotes.length > 0; }

    get totalPremium() {
        return this.filteredQuotes.reduce((sum, q) => sum + (parseFloat(q.TotalPrice ?? q.TotalPremium) || 0), 0);
    }
    get totalPremiumFormatted() { return this.formatCurrency(this.totalPremium); }

    // ===== Paginación =====
    get totalPages() { return Math.max(1, Math.ceil(this.quotesCount / PAGE_SIZE)); }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return this.currentPage >= this.totalPages; }
    get pageInfoLabel() { return `Página ${this.currentPage} de ${this.totalPages}`; }

    /** Lista ya formateada y paginada que va al render. */
    get processedQuotes() {
        const today = new Date();
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredQuotes.slice(start, start + PAGE_SIZE).map(q => {
            const aseguradoraName = q.Aseguradora__r?.Name || q.AseguradoraName || '—';
            const ramoName = q.Ramo__c || '—';
            const oppName  = q.OpportunityName || q.Opportunity?.Name || '—';
            const totalPrice = q.TotalPrice ?? q.TotalPremium ?? 0;
            const expDate = this.parseSafeDate(q.ExpirationDate);
            const isExpired = expDate && expDate < today && q.Status !== 'Accepted';

            return {
                ...q,
                AseguradoraLabel: aseguradoraName,
                RamoLabel: ramoName,
                OpportunityLabel: oppName,
                StatusLabel: STATUS_LABELS[q.Status] || q.Status || 'Sin estado',
                TotalPremiumFormatted: this.formatCurrency(totalPrice),
                EffectiveDateFormatted: this.formatDate(q.EffectiveDate),
                ExpirationDateFormatted: this.formatDate(q.ExpirationDate),
                CreatedDateFormatted: this.formatDate(q.CreatedDate),
                statusIcon: STATUS_ICONS[q.Status] || 'utility:info',
                statusBadgeClass: this.getStatusBadgeClass(q.Status, isExpired),
                ramoIcon: this.getRamoIcon(ramoName),
                ramoStyle: `background: ${this.getRamoColor(ramoName)}; color: #fff;`,
                headerStyle: `background: linear-gradient(135deg, ${this.getCompanyColor(aseguradoraName)} 0%, ${this.adjustBrightness(this.getCompanyColor(aseguradoraName), -20)} 100%);`,
                isExpired,
                CoveragesCount: q.CoveragesCount || 0
            };
        });
    }

    // ============================================================
    // GETTERS DE COBERTURAS
    // ============================================================
    get hasCoverages()  { return this.coverages && this.coverages.length > 0; }
    get coveragesCount() { return this.coverages.length; }
    get totalCoveragesPremium() {
        return this.coverages.reduce((sum, c) => sum + (parseFloat(c.Premium__c) || 0), 0);
    }
    get totalCoveragesPremiumFormatted() { return this.formatCurrency(this.totalCoveragesPremium); }

    /**
     * Devuelve las coberturas con los valores YA formateados como moneda.
     * Esto es obligatorio porque LWC no permite llamar a métodos en plantillas.
     */
    get displayCoverages() {
        return this.coverages.map(c => ({
            ...c,
            uniqueKey: c.uniqueKey || c.Id || c.localKey,
            ProductName: c.ProductName || c.Product__r?.Name || '',
            PremiumFormatted: this.formatCurrency(c.Premium__c),
            CalculatedPremiumFormatted: this.formatCurrency(c.CalculatedPremium),
            SumInsuredFormatted: this.formatCurrency(c.Sum_Insured__c)
        }));
    }

    // ============================================================
    // LOOKUPS: getters auxiliares
    // ============================================================
    get hasOpportunityResults() { return this.opportunityResults && this.opportunityResults.length > 0; }
    get hasAseguradoraResults() { return this.aseguradoraResults && this.aseguradoraResults.length > 0; }

    // ============================================================
    // CICLO DE VIDA
    // ============================================================
    async connectedCallback() {
        // Los ramos vienen del picklist de Quote.Ramo__c (cargados por wire)
        await this.loadQuotes();
        this._connectedReady = true;

        // 1) Si vengo desde otro componente (state c__opportunityId / c__quoteId)
        if (this._pendingNavigation) {
            await this.processPendingNavigation();
            return;
        }

        // 2) Si vengo desde una Opportunity Record Page (recordId estándar)
        if (this.recordId && String(this.recordId).startsWith('006')) {
            this.handleCreateNew();
            this.quote = { ...this.quote, OpportunityId: this.recordId };
            try {
                const opps = await searchOpportunities({ searchTerm: this.recordId });
                const opp = (opps || []).find(o => o.Id === this.recordId);
                if (opp) this.quote.OpportunityName = opp.Name;
            } catch (e) { /* ignore */ }
        }
    }

    /**
     * Aplica los parámetros que llegan por URL desde otro componente.
     * - Si trae quoteId  → abre la cotización en modo edición.
     * - Si trae oppId    → abre modo creación con la oportunidad preseleccionada.
     */
    async processPendingNavigation() {
        const nav = this._pendingNavigation;
        this._pendingNavigation = null;
        if (!nav) return;

        if (nav.quoteId) {
            try {
                await this.loadQuoteData(nav.quoteId);
                this.viewMode = VIEW_MODES.EDIT;
            } catch (e) {
                this.showToast('Error', 'No se pudo cargar la cotización', 'error');
            }
            return;
        }

        if (nav.oppId) {
            this.handleCreateNew();
            this.quote = {
                ...this.quote,
                OpportunityId: nav.oppId,
                OpportunityName: nav.oppName || '',
                Ramo__c: nav.oppRamo || ''
            };
            if (nav.oppRamo) await this.loadProductsByRamo(nav.oppRamo);
        }
    }

    // ============================================================
    // CARGA DE DATOS
    // ============================================================
    async loadQuotes() {
        this.isLoading = true;
        try {
            this.quotes = (await getQuotes()) || [];
        } catch (error) {
            this.showToast('Error', 'No se pudieron cargar las cotizaciones', 'error');
            this.quotes = [];
        } finally {
            this.isLoading = false;
        }
    }

    async loadQuoteData(quoteId) {
        this.isLoading = true;
        try {
            const data = await getQuoteById({ quoteId });
            if (!data) return;
            // El Ramo siempre viene de la Oportunidad (Opportunity.Ramo__c).
            const ramoFromOpp = data.Opportunity?.Ramo__c || data.Ramo__c || '';
            this.quote = {
                ...this.getDefaultQuote(),
                ...data,
                Ramo__c: ramoFromOpp,
                AseguradoraName: data.Aseguradora__r?.Name || data.AseguradoraName || '',
                OpportunityName: data.OpportunityName || data.Opportunity?.Name || ''
            };
            // Modo edición: las coberturas se cargan por Quote Id
            if (this.quote.Id) {
                await this.loadCoveragesByQuoteId(this.quote.Id);
            }
            // Precargar productos del ramo (por si el usuario cambia el producto)
            if (ramoFromOpp) {
                await this.loadProductsByRamo(ramoFromOpp);
            }
        } catch (error) {
            this.showToast('Error', 'No se pudo cargar la cotización', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Carga las coberturas asociadas a una cotización existente
     * (Quote_Coverage__c WHERE Quote__c = :quoteId).
     */
    async loadCoveragesByQuoteId(quoteId) {
        if (!quoteId) { this.coverages = []; return; }
        this.isLoadingCoverages = true;
        try {
            const list = (await getCoveragesByQuoteId({ quoteId })) || [];
            this.coverages = list.map(c => this.normalizeCoverage(c));
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error(':::QuoteCreator::: Error coberturas (por quote):', JSON.stringify(error));
            this.showToast('Error', 'No se pudieron cargar las coberturas', 'error');
            this.coverages = [];
        } finally {
            this.isLoadingCoverages = false;
        }
    }

    /** Normaliza un registro Quote_Coverage__c al formato que espera la UI. */
    normalizeCoverage(cov) {
        const displayName = cov.Coverage_Name__c || cov.Name || 'Cobertura';
        const description = cov.Coverage_Code__c || '';
        const productName = cov.Product__r?.Name || cov.ProductName || '';
        return {
            ...cov,
            Name: displayName,
            Description__c: description,
            ProductName: productName,
            IsSelected: cov.Is_Selected__c || cov.Is_Included__c || false,
            CalculatedPremium: cov.Premium__c || 0,
            uniqueKey: cov.Id || cov.localKey || `cov-${Math.random().toString(36).substr(2, 9)}`
        };
    }

    // ============================================================
    // COBERTURAS
    // ============================================================
    handleCoverageInput(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        let value = event.target.value;

        if (field === 'Sum_Insured__c') value = Math.max(0, parseFloat(value) || 0);
        else if (field === 'Deductible__c') value = Math.min(100, Math.max(0, parseFloat(value) || 0));
        else if (field === 'Coinsurance__c') value = Math.min(100, Math.max(0, parseFloat(value) || 0));

        this.coverages = this.coverages.map(cov => {
            if (cov.uniqueKey !== key) return cov;
            const updated = { ...cov, [field]: value };
            updated.CalculatedPremium = this.calculatePremium(updated);
            if (updated.IsSelected) updated.Premium__c = updated.CalculatedPremium;
            return updated;
        });
        this.updateQuoteTotalPremium();
    }

    calculatePremium(coverage) {
        const basePremium = coverage.BasePremium__c || 1000;
        const sumInsured  = coverage.Sum_Insured__c || 10000;
        const deductible  = coverage.Deductible__c || 0;
        const sumFactor = sumInsured / 10000;
        const deductibleFactor = 1 - (deductible / 100);
        let calculated = basePremium * sumFactor * deductibleFactor;
        if (coverage.Type__c === 'Básica')  calculated *= 0.9;
        if (coverage.Type__c === 'Premium') calculated *= 1.2;
        return Math.round(calculated * 100) / 100;
    }

    updateQuoteTotalPremium() {
        const total = this.coverages.reduce((s, c) => s + (parseFloat(c.Premium__c) || 0), 0);
        this.quote = { ...this.quote, TotalPrice: total, TotalPremium: total };
    }

    // ============================================================
    // HANDLERS DE FORM
    // ============================================================
    handleInputChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.value;
        if (field === 'TotalPrice' || field === 'TotalPremium') value = parseFloat(value) || 0;
        this.quote = { ...this.quote, [field]: value };
    }

    handleComboboxChange(event) {
        const field = event.target.dataset.field;
        this.quote = { ...this.quote, [field]: event.detail.value };
    }


    /**
     * Trae los productos disponibles para el ramo elegido.
     * Llama al Apex QuoteCreatorController.getProducts(ramo).
     */
    async loadProductsByRamo(ramo) {
        if (!ramo) { this.availableProducts = []; return; }
        this.isLoadingProducts = true;
        // eslint-disable-next-line no-console
        console.log(':::QuoteCreator::: Solicitando productos para ramo:', ramo);
        try {
            this.availableProducts = (await getProducts({ ramo })) || [];
            // eslint-disable-next-line no-console
            console.log(':::QuoteCreator::: Productos recibidos:',
                JSON.stringify(this.availableProducts));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(':::QuoteCreator::: Error productos:', JSON.stringify(e));
            this.availableProducts = [];
            this.showToast('Error', 'No se pudieron cargar los productos', 'error');
        } finally {
            this.isLoadingProducts = false;
        }
    }

    /** Opciones del combobox de productos para la sección Información Básica. */
    get productOptions() {
        return (this.availableProducts || []).map(p => ({
            label: p.Name, value: p.Id
        }));
    }

    /** Sin ramo no hay productos cargados → combobox bloqueado. */
    get isProductSelectorDisabled() {
        return !this.quote.Ramo__c || this.isLoadingProducts;
    }

    /**
     * Cuando el usuario selecciona un Producto en el form principal,
     * cargamos las coberturas que ese producto trae configuradas.
     * Las coberturas no se pueden agregar ni quitar; solo se editan los
     * montos, deducibles y coaseguros.
     */
    async handleProductChange(event) {
        const productId = event.detail.value;
        const product = this.availableProducts.find(p => p.Id === productId) || null;
        this.quote = {
            ...this.quote,
            Product__c: productId,
            ProductName: product?.Name || ''
        };
        if (!productId) {
            this.coverages = [];
            return;
        }
        await this.loadCoveragesByProduct(productId);
    }

    /**
     * Trae las coberturas plantilla configuradas para un Producto.
     * En modo creación se usa para inicializar la lista; en edición ya
     * vienen del Quote (loadCoveragesByQuoteId) y este flujo se usa sólo
     * si el usuario cambia el producto.
     */
    async loadCoveragesByProduct(productId) {
        if (!productId) { this.coverages = []; return; }
        this.isLoadingCoverages = true;
        try {
            const list = (await getCoveragesByProduct({ productId })) || [];
            this.coverages = list.map(c => this.normalizeCoverage({
                ...c,
                Id: null,                       // todavía no existe en la BD
                Quote__c: this.quote.Id || null,
                Product__c: productId,
                Is_Selected__c: c.Is_Selected__c !== false,
                Is_Included__c: c.Is_Included__c !== false
            }));
            this.updateQuoteTotalPremium();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(':::QuoteCreator::: Error coberturas (por producto):', JSON.stringify(e));
            this.showToast('Error', 'No se pudieron cargar las coberturas del producto', 'error');
            this.coverages = [];
        } finally {
            this.isLoadingCoverages = false;
        }
    }

    handleSearchChange(event) {
        const value = event.target.value;
        clearTimeout(this._searchTimer);
        this._searchTimer = setTimeout(() => {
            this.searchTerm = value || '';
            this.currentPage = 1;
        }, 250);
    }

    handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value || '';
        this.currentPage = 1;
    }

    handlePrevPage() { if (this.currentPage > 1) this.currentPage -= 1; }
    handleNextPage() { if (this.currentPage < this.totalPages) this.currentPage += 1; }

    // ===== Lookup de Oportunidad =====
    handleOpportunityFocus()    { this.showOpportunityDropdown = true; }
    handleOpportunityInput(event) {
        const value = event.target.value;
        this.quote = { ...this.quote, OpportunityName: value, OpportunityId: null };
        clearTimeout(this._opportunitySearchTimer);
        this._opportunitySearchTimer = setTimeout(async () => {
            if (value && value.length >= 2) {
                try {
                    this.opportunityResults = await searchOpportunities({ searchTerm: value });
                } catch (e) { this.opportunityResults = []; }
            } else {
                this.opportunityResults = [];
            }
        }, 300);
    }
    async selectOpportunity(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const ramo = event.currentTarget.dataset.ramo || '';
        // Reseteamos producto/coberturas porque el Ramo puede haber cambiado
        this.quote = {
            ...this.quote,
            OpportunityId: id,
            OpportunityName: name,
            Ramo__c: ramo,
            Product__c: null,
            ProductName: ''
        };
        this.coverages = [];
        this.showOpportunityDropdown = false;
        this.opportunityResults = [];
        if (ramo) await this.loadProductsByRamo(ramo);
    }

    // ===== Lookup de Aseguradora =====
    handleAseguradoraFocus()    { this.showAseguradoraDropdown = true; }
    handleAseguradoraInput(event) {
        const value = event.target.value;
        this.quote = { ...this.quote, AseguradoraName: value, Aseguradora__c: null };
        clearTimeout(this._aseguradoraSearchTimer);
        this._aseguradoraSearchTimer = setTimeout(async () => {
            if (value && value.length >= 2) {
                try {
                    this.aseguradoraResults = await searchAseguradoras({ searchTerm: value });
                } catch (e) { this.aseguradoraResults = []; }
            } else {
                this.aseguradoraResults = [];
            }
        }, 300);
    }
    selectAseguradora(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.quote = { ...this.quote, Aseguradora__c: id, AseguradoraName: name };
        this.showAseguradoraDropdown = false;
        this.aseguradoraResults = [];
    }

    handleClickOutside(event) {
        // Cerrar dropdowns si el click no fue dentro de un .lookup-container
        const insideLookup = event.target.closest && event.target.closest('.lookup-container');
        if (!insideLookup) {
            this.showOpportunityDropdown = false;
            this.showAseguradoraDropdown = false;
        }
    }

    // ============================================================
    // ACCIONES PRINCIPALES
    // ============================================================
    handleCreateNew() {
        this.resetForm();
        this.viewMode = VIEW_MODES.CREATE;
    }

    async handleEditQuote(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        await this.loadQuoteData(id);
        this.viewMode = VIEW_MODES.EDIT;
    }

    handleViewQuote(event) {
        // Ver y Editar llevan al mismo formulario custom.
        return this.handleEditQuote(event);
    }

    async handleDeleteQuote(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const ok = await LightningConfirm.open({
            message: `¿Eliminar la cotización "${name}"? Esta acción no se puede deshacer.`,
            variant: 'header',
            label: 'Confirmar eliminación',
            theme: 'warning'
        });
        if (!ok) return;
        try {
            await deleteQuote({ quoteId: id });
            // Quitar localmente (más rápido que recargar)
            this.quotes = this.quotes.filter(q => q.Id !== id);
            this.showToast('Éxito', 'Cotización eliminada correctamente', 'success');
        } catch (error) {
            this.showToast('Error', 'No se pudo eliminar la cotización', 'error');
        }
    }

    handleBackToList() {
        // Si la cotización pertenece a una oportunidad, volvemos a esa
        // oportunidad (Crear_Oportunidad con c__opportunityId).
        const oppId = this.quote?.OpportunityId;
        if (oppId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: 'Crear_Oportunidad' },
                state: { c__opportunityId: oppId }
            });
            return;
        }
        // Fallback: si no hay oportunidad asociada, mostramos la lista.
        this.viewMode = VIEW_MODES.LIST;
        this.resetForm();
    }

    async handleSave() {
        if (!this.validateForm()) return;
        this.isSaving = true;
        try {
            // Limpiar campos auxiliares antes de mandar al Apex
            const payload = { ...this.quote };
            delete payload.AseguradoraName;
            delete payload.OpportunityName;
            delete payload.ProductName;

            const savedQuote = await saveQuote({ quote: payload });

            // Coberturas: upsert de todas (vienen del producto, siempre incluidas)
            const coveragesToSave = (this.coverages || []).map(c => ({
                Id: c.Id || null,
                Quote__c: savedQuote.Id,
                Product__c: c.Product__c || this.quote.Product__c,
                Product_Coverage__c: c.Product_Coverage__c || null,
                Coverage_Name__c: c.Coverage_Name__c || c.Name,
                Coverage_Code__c: c.Coverage_Code__c || '',
                Sum_Insured__c: c.Sum_Insured__c || 0,
                Deductible__c: c.Deductible__c || 0,
                Coinsurance__c: c.Coinsurance__c || 0,
                Premium__c: c.Premium__c || 0,
                Base_Rate__c: c.Base_Rate__c || 0,
                Is_Included__c: true,
                Is_Selected__c: true
            }));

            if (coveragesToSave.length > 0) {
                await saveCoverages({ coverages: coveragesToSave });
            }

            this.showToast('Éxito', this.isEditMode ? 'Cotización actualizada' : 'Cotización creada', 'success');
            await this.loadQuotes();
            this.handleBackToList();
        } catch (error) {
            this.showToast('Error', 'Error al guardar la cotización', 'error');
        } finally {
            this.isSaving = false;
        }
    }

    // ============================================================
    // VALIDACIÓN
    // ============================================================
    validateForm() {
        if (!this.quote.Name)              return this.toastError('El nombre de la cotización es requerido');
        if (!this.quote.OpportunityId)     return this.toastError('Debes seleccionar una oportunidad');
        if (!this.quote.Aseguradora__c)    return this.toastError('La aseguradora es requerida');
        if (!this.quote.Ramo__c)           return this.toastError('La oportunidad seleccionada no tiene ramo. Defínelo en la oportunidad antes de cotizar.');
        if (!this.quote.Product__c)        return this.toastError('Selecciona un producto del catálogo');
        if (!this.quote.Status)            return this.toastError('El estado es requerido');

        const total = parseFloat(this.quote.TotalPrice ?? this.quote.TotalPremium);
        if (!total || total <= 0) return this.toastError('La prima total debe ser mayor a 0');

        // Vigencia
        if (this.quote.EffectiveDate && this.quote.ExpirationDate) {
            if (new Date(this.quote.ExpirationDate) < new Date(this.quote.EffectiveDate)) {
                return this.toastError('La fecha fin de vigencia no puede ser anterior a la fecha inicio.');
            }
        }
        return true;
    }
    toastError(msg) { this.showToast('Error', msg, 'error'); return false; }

    // ============================================================
    // UTILIDADES
    // ============================================================
    getDefaultQuote() {
        const today = new Date();
        const oneYearLater = new Date(); oneYearLater.setFullYear(today.getFullYear() + 1);
        return {
            Id: null,
            Name: '',
            OpportunityId: null, OpportunityName: '',
            Aseguradora__c: null, AseguradoraName: '',
            Ramo__c: '',
            Product__c: null, ProductName: '',
            Status: 'Draft',
            TotalPrice: 0, TotalPremium: 0,
            EffectiveDate: this.formatDateForInput(today),
            ExpirationDate: this.formatDateForInput(oneYearLater),
            Description: '',
            Observations__c: ''
        };
    }

    resetForm() {
        this.quote = this.getDefaultQuote();
        this.coverages = [];
        this.availableProducts = [];
        this.showOpportunityDropdown = false;
        this.showAseguradoraDropdown = false;
        this.opportunityResults = [];
        this.aseguradoraResults = [];
    }

    parseSafeDate(value) {
        if (!value) return null;
        const d = new Date(value);
        if (isNaN(d.getTime())) return null;
        if (d.getFullYear() < 1970) return null;
        return d;
    }

    getCompanyColor(name) {
        if (!name) return '#667eea';
        const map = {
            'GNP': '#004b87', 'Qualitas': '#2c3e50', 'AXA': '#003f6b', 'AXA Seguros': '#003f6b',
            'HDI': '#003a6b', 'HDI Seguros': '#003a6b', 'Mapfre': '#c8102e', 'MAPFRE': '#c8102e',
            'BBVA': '#0066b3', 'Monterrey': '#8b0000', 'Zurich': '#005a8c'
        };
        return map[name] || '#0052CC';
    }
    getRamoColor(ramo) {
        const map = {
            'Automoviles': '#0052CC', 'Auto': '#0052CC',
            'GMM': '#00875A', 'Vida': '#DE350B', 'Viajes': '#0065FF',
            'Danos': '#FF8C00', 'Daños': '#FF8C00',
            'Empresarial': '#00A3BF', 'RC': '#00A3BF', 'Transporte': '#00A3BF'
        };
        return map[ramo] || '#6B7280';
    }
    getRamoIcon(ramo) {
        const map = {
            'Automoviles': 'utility:car', 'Auto': 'utility:car',
            'GMM': 'utility:health', 'Vida': 'utility:heart', 'Viajes': 'utility:flight',
            'Danos': 'utility:warning', 'Daños': 'utility:warning',
            'Empresarial': 'utility:company', 'RC': 'utility:law', 'Transporte': 'utility:ship'
        };
        return map[ramo] || 'utility:document';
    }
    getStatusBadgeClass(status, isExpired) {
        if (isExpired) return 'status-badge status-expired';
        switch (status) {
            case 'Accepted': return 'status-badge status-accepted';
            case 'Sent':     return 'status-badge status-sent';
            case 'Rejected': return 'status-badge status-rejected';
            case 'Expired':  return 'status-badge status-expired';
            case 'Draft':
            default:         return 'status-badge status-draft';
        }
    }

    adjustBrightness(hex, percent) {
        if (!hex || !hex.startsWith('#')) return hex;
        let R = parseInt(hex.substring(1, 3), 16);
        let G = parseInt(hex.substring(3, 5), 16);
        let B = parseInt(hex.substring(5, 7), 16);
        R = Math.min(255, Math.max(0, R + percent));
        G = Math.min(255, Math.max(0, G + percent));
        B = Math.min(255, Math.max(0, B + percent));
        return `#${(R < 16 ? '0' : '') + R.toString(16)}${(G < 16 ? '0' : '') + G.toString(16)}${(B < 16 ? '0' : '') + B.toString(16)}`;
    }

    formatCurrency(value) {
        if (value === null || value === undefined || value === '') return '$0.00 MXN';
        const num = parseFloat(value);
        if (isNaN(num)) return '$0.00 MXN';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency', currency: 'MXN', minimumFractionDigits: 2, maximumFractionDigits: 2
        }).format(num);
    }

    formatDate(dateString) {
        if (!dateString) return 'Sin fecha';
        const d = new Date(dateString);
        if (isNaN(d.getTime()) || d.getFullYear() < 1970) return 'Sin fecha';
        return d.toLocaleDateString('es-MX', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    formatDateForInput(date) {
        if (!date) return '';
        const d = (date instanceof Date) ? date : new Date(date);
        if (isNaN(d.getTime())) return '';
        const y = d.getFullYear();
        const m = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}