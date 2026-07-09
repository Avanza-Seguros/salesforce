import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import STAGE_FIELD from '@salesforce/schema/Opportunity.StageName';
import TYPE_FIELD from '@salesforce/schema/Opportunity.Type';
import CANAL_FIELD from '@salesforce/schema/Opportunity.Canal__c';
import MERCADO_FIELD from '@salesforce/schema/Opportunity.Mercado__c';
import RAMO_FIELD from '@salesforce/schema/Opportunity.Ramo__c';
import AUTOMOVIL_OBJECT from '@salesforce/schema/Automovil__c';
import MARCA_FIELD from '@salesforce/schema/Automovil__c.Marca__c';
import QUOTE_OBJECT from '@salesforce/schema/Quote';
import FRECUENCIA_FIELD from '@salesforce/schema/Quote.Frecuencia_de_prima__c';
import getOpportunities from '@salesforce/apex/OpportunityController.getOpportunities';
import getOpportunityDetails from '@salesforce/apex/OpportunityController.getOpportunityDetails';
import searchAccounts from '@salesforce/apex/OpportunityController.searchAccounts';
import searchContacts from '@salesforce/apex/OpportunityController.searchContacts';
import searchAgentsProspectors from '@salesforce/apex/OpportunityController.searchAgentsProspectors';
import apexSaveOpportunity from '@salesforce/apex/OpportunityController.saveOpportunity';
import crearCotizacionesDesdePdf from '@salesforce/apex/PdfOpportunityCreatorController.crearCotizacionesDesdePdf';
import searchVehiculos from '@salesforce/apex/OpportunityController.searchVehiculos';
import aceptarCotizacion from '@salesforce/apex/OpportunityController.aceptarCotizacion';
import prepararCotizaciones from '@salesforce/apex/PdfOpportunityCreatorController.prepararCotizaciones';
import getProductosPorAseguradoraRamo from '@salesforce/apex/PdfOpportunityCreatorController.getProductosPorAseguradoraRamo';

// ============================================================
// CONSTANTES
// ============================================================
const VIEW_MODES = {
    LIST: 'list',
    CREATE: 'create',
    EDIT: 'edit',
    PDF: 'pdf'   // NUEVO - vista de creacion desde PDFs
};
const OPPORTUNITY_TYPES = {
    NEW_BUSINESS: 'New_Business',
    INTERNAL_RENEWAL: 'External_Renewal',
    EXTERNAL_RENEWAL: 'Internal_Renewal',
    REISSUE: 'Reissue'
};
const RAMO_TYPES = {
    AUTOMOVIL: 'Automoviles',
    GASTOS_MEDICOS: 'GMM',
    VIDA: 'Vida',
    VIAJE: 'Viajes',
    DANOS: 'Danos',
    EMPRESARIAL: 'Empresarial',
    FIANZAS: 'Fianzas',
    DENTAL: 'Dental',
    VISION: 'Vision',
    RESPONSABILIDAD_CIVIL: 'RC'
};
// Etapas: API value (Salesforce) -> etiqueta visible (UX) + metadatos
const STAGES_DATA = [
    { value: 'Gestion Comercial',    label: 'Gestión Comercial',   probability: 40,  icon: 'utility:money',   color: '#0052CC' },
    { value: 'En proceso de emision',label: 'En proceso de emisión', probability: 70,  icon: 'utility:check',   color: '#00A3BF' },
    { value: 'Póliza',               label: 'Póliza',               probability: 95,  icon: 'utility:policy',  color: '#00875A' },
    { value: 'Closed Won',           label: 'Ganada',               probability: 100, icon: 'utility:success', color: '#00875A' },
    { value: 'Closed Lost',          label: 'Perdida',              probability: 0,   icon: 'utility:error',   color: '#DE350B' }
];
const STAGE_DEFAULT_COLOR = '#6B7280';
// Cantidad de oportunidades a mostrar por página
const PAGE_SIZE = 12;

export default class OpportunityCreator extends NavigationMixin(LightningElement) {
    @api recordId;
    // === Wires y picklists ===
    objectInfo = { data: null, error: null };
    @track stagePicklistValues = [];
    @track typePicklistValues = [];
    @track canalPicklistValues = [];
    @track mercadoPicklistValues = [];
    @track ramoPicklistValues = [];
    @track marcaPicklistValues = [];
    automovilObjectInfo = { data: null, error: null };
    @track frecuenciaPicklistValues = [];
    quoteObjectInfo = { data: null, error: null };
    // === Estado UI / datos ===
    @track viewMode = VIEW_MODES.LIST;
    @track isLoading = false;
    @track isSaving = false;
    @track searchTerm = '';
    @track stageFilter = '';
    @track showOnlyOverdue = false;
    @track currentPage = 1;
    @track opportunities = [];
    // === Estado de creación/edición ===
    @track opportunity = this.getDefaultOpportunity();
    @track automovil = this.getDefaultAutomovil();
    @track gmm = this.getDefaultGMM();
    @track vida = this.getDefaultVida();
    @track viaje = this.getDefaultViaje();
    @track danos = this.getDefaultDanos();
    @track empresarial = this.getDefaultEmpresarial();
    @track fianzas = this.getDefaultFianzas();
    @track rc = this.getDefaultRC();
    @track dental = this.getDefaultDental();
    @track vision = this.getDefaultVision();
    @track uploadedQuotes = [];
    // Comparativo HTML tal cual lo regresa la IA (Prompt Builder).
    // Se renderiza en un iframe vía blob URL (srcdoc no está permitido en LWC).
    @track comparativoHtml = '';
    _comparativoDirty = false;
    @track extractedOpportunityData = null;
    @track hasExtractedData = false;
    @track selectedQuoteRamo = '';
    @track showVehiculoDropdown = false;
    @track vehiculoResults = [];
    _vehiculoSearchTimer = null;
    // Cotizaciones (Quotes) ya relacionadas con la oportunidad (modo edición)
    @track relatedQuotes = [];
    // Lookup de Cuenta (Account / Person Account)
    @track showAccountDropdown = false;
    @track accountResults = [];
    @track isNewAccount = false;
    _accountSearchTimer = null;
    @track showAgenteDropdown = false;
    @track agenteResults = [];
    _agenteSearchTimer = null;
    // Lookup de Contacto (mismo comportamiento que Cuenta cuando el Mercado no es Individual)
    @track showContactoDropdown = false;
    @track contactoResults = [];
    @track isNewContacto = false;
    _contactoSearchTimer = null;
    @track editableQuotes = [];
    // === Estado comparativa (datos extraídos de PDFs) ===
    @track tablaComparativaCache = [];
    @track companiasConCoberturasCache = [];
    @track totalCoberturasUnicas = 0;
    // === Flags por compañía (calculados) ===
    tieneQualitas = false;
    tieneChubb = false;
    tieneGnp = false;
    tieneHdi = false;
    mejorPrecioCompania = '';
    mejorPrecioMonto = 0;
    mejorCoberturaCompania = '';
    mejorCoberturaMonto = 0;
    @track comparisonData = {
        totalQuotes: 0,
        bestPriceCompany: '',
        bestPriceAmount: 0,
        bestCoverageCompany: '',
        bestCoverageAmount: 0,
        selectedCompanies: [],
        rawData: null
    };
    @track showComparisonSummary = false;

    // (Antes había un overlay/modal para el comparativo; ahora se renderiza
    // directamente dentro de la sección de comparativa.)
    // Timer para debounce de la búsqueda
    _searchTimer = null;

    // ============================================================
    // SUB-RAMOS (estáticos)
    // ============================================================
    get vidaSubramos() {
        return [
            { label: 'Educación', value: 'Educación' },
            { label: 'Ahorro', value: 'Ahorro' },
            { label: 'Retiro', value: 'Retiro' },
            { label: 'Temporal', value: 'Temporal' },
            { label: 'Vida Tradicional', value: 'Vida Tradicional' }
        ];
    }
    get danosSubramos() {
        return [
            { label: 'Hogar', value: 'Hogar' },
            { label: 'Mascotas', value: 'Mascotas' },
            { label: 'Responsabilidad Civil', value: 'Responsabilidad Civil' },
            { label: 'Empresarial', value: 'Empresarial (Property)' }
        ];
    }
    get tipoEstructuraOptions() {
        return [
            { label: 'Individual', value: 'Individual' },
            { label: 'Familiar', value: 'Familiar' }
        ];
    }
    get tipoClienteOptions() {
        return [
            { label: 'Persona', value: 'Persona' },
            { label: 'Empresa', value: 'Empresa' }
        ];
    }
    get isPersonAccount() {
        return this.opportunity.tipoCliente === 'Persona';
    }

    get hasVehiculoResults() {
        return this.vehiculoResults && this.vehiculoResults.length > 0;
    }

    // El vehículo NO se puede modificar una vez guardado (ya está ligado a la
    // oportunidad). Si cambió, se debe crear una nueva oportunidad.
    get isVehiculoLocked() {
        return this.isEditMode && !!this.opportunity.Vehiculo__c;
    }
    get isVehiculoReadOnly() {
        return this.isOpportunityReadOnly || this.isVehiculoLocked;
    }

    async loadEditableQuotes() {
        if (!this.uploadedQuotes || !this.uploadedQuotes.length) {
            this.editableQuotes = [];
            return;
        }
        try {
            const res = await prepararCotizaciones({
                quotesJson: JSON.stringify(this.uploadedQuotes)
            });
            this.editableQuotes = (res || []).map(q => ({
                ...q,
                aseguradoraId: q.aseguradoraId,
                aseguradoras: q.aseguradoras || [],
                productId: q.productoSugeridoId,
                frecuencia: q.frecuencia || 'Mensual',
                sinProductos: !(q.productos && q.productos.length)
            }));
        } catch (e) {
            this.editableQuotes = [];
        }
    }

    async handleCrearCotizaciones() {
        if (!this.opportunity.Id || !this.hasEditableQuotes) { return; }
        // Validar que cada cotización tenga producto
        const sinProd = this.editableQuotes.filter(q => !q.productId);
        if (sinProd.length) {
            this.showToast('Falta producto',
                `Selecciona el producto de: ${sinProd.map(q => q.compania).join(', ')}`, 'warning');
            return;
        }
        this.isSaving = true; this.isLoading = true;
        try {
            const payload = this.editableQuotes.map(q => ({
                id: q.id, compania: q.compania, ramo: q.ramo, plan: q.plan,
                primaTotal: q.primaTotal, vigencia: q.vigencia,
                noCotizacion: q.noCotizacion, productId: q.productId,
                aseguradoraId: q.aseguradoraId, frecuencia: q.frecuencia
            }));
            const res = await crearCotizacionesDesdePdf({
                opportunityId: this.opportunity.Id,
                quotesJson: JSON.stringify(payload)
            });
            const n = (res && res.creadas) || 0;
            this.showToast('Cotizaciones', `Se crearon ${n} cotización(es).`, 'success');
            this.uploadedQuotes = [];
            this.editableQuotes = [];
            await this.openOpportunityInEditMode(this.opportunity.Id);
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.showToast('Error', 'No se pudieron crear las cotizaciones: ' + msg, 'error');
        } finally {
            this.isSaving = false; this.isLoading = false;
        }
    }

    handleVehiculoFocus() {
        this.showVehiculoDropdown = true;
    }
    handleVehiculoInput(event) {
        const value = event.target.value;
        this.opportunity = { ...this.opportunity, VehiculoName: value, Vehiculo__c: null };
        this.showVehiculoDropdown = true;
        clearTimeout(this._vehiculoSearchTimer);
        this._vehiculoSearchTimer = setTimeout(async () => {
            if (value && value.length >= 2) {
                try {
                    this.vehiculoResults = await searchVehiculos({ searchTerm: value });
                } catch (e) {
                    this.vehiculoResults = [];
                }
            } else {
                this.vehiculoResults = [];
            }
        }, 300);
    }
    selectVehiculo(event) {
        const id = event.currentTarget.dataset.id;
        const v = (this.vehiculoResults || []).find(x => x.Id === id);
        if (!v) return;
        this.opportunity = { ...this.opportunity, Vehiculo__c: v.Id, VehiculoName: (v.Marca__c || '') + ' ' + (v.Modelo__c || '') };
        this.automovil = {
            ...this.automovil,
            Marca__c: v.Marca__c || '',
            Modelo__c: v.Modelo__c || '',
            Serie__c: v.Serie__c || '',
            Placa__c: v.Placa__c || '',
            Motor__c: v.Motor__c || '',
            descripcion_completa__c: v.Descripcion_Completa__c || ''
        };
        this.showVehiculoDropdown = false;
        this.vehiculoResults = [];
    }

    // ============================================================
    // IDENTIFICACIÓN DEL RAMO ACTIVO
    // ============================================================
    // Detección tolerante a variantes del ramo (acentos, singular/plural, "Auto"),
    // igual que el flujo de PDFs. Antes comparaba exacto y por eso en manual no salía
    // el apartado del ramo si el valor del picklist no era idéntico.
    _ramoEs(keywords, exact) {
        const r = this.opportunity.Ramo__c;
        if (!r) return false;
        if (exact && r === exact) return true;
        return this.matchRamo(r, keywords);
    }
    get isRamoAutomovil()   { return this._ramoEs(['AUTOMOVIL', 'AUTO'], RAMO_TYPES.AUTOMOVIL); }
    get isRamoGMM()         { return this._ramoEs(['GMM', 'GASTOS'], RAMO_TYPES.GASTOS_MEDICOS); }
    get isRamoVida()        { return this._ramoEs(['VIDA'], RAMO_TYPES.VIDA); }
    get isRamoViajes()      { return this._ramoEs(['VIAJE'], RAMO_TYPES.VIAJE); }
    get isRamoDanos()       { return this._ramoEs(['DAÑOS', 'DANOS'], RAMO_TYPES.DANOS); }
    get isRamoEmpresarial() { return this._ramoEs(['EMPRESARIAL'], RAMO_TYPES.EMPRESARIAL); }
    get isRamoFianzas() { return this._ramoEs(['FIANZA'], RAMO_TYPES.FIANZAS); }
    get isRamoRC()      { return this._ramoEs(['RESPONSABILIDAD'], RAMO_TYPES.RESPONSABILIDAD_CIVIL); }
    get isRamoDental()  { return this._ramoEs(['DENTAL'], RAMO_TYPES.DENTAL); }
    get isRamoVision()  { return this._ramoEs(['VISION', 'VISIÓN'], RAMO_TYPES.VISION); }
    get isRamoOtros() {
        return !this.isRamoAutomovil && !this.isRamoGMM && !this.isRamoVida &&
               !this.isRamoViajes && !this.isRamoDanos && !this.isRamoEmpresarial &&
               !this.isRamoFianzas && !this.isRamoRC && !this.isRamoDental && !this.isRamoVision;
    }
    get stagesData() { return STAGES_DATA; }

    get quoteRamoOptions() {
        if (this.ramoPicklistValues && this.ramoPicklistValues.length > 0) {
            return this.ramoPicklistValues;
        }
        return [
            { label: 'Automóvil', value: 'Automoviles' },
            { label: 'Gastos Médicos (GMM)', value: 'GMM' },
            { label: 'Vida', value: 'Vida' },
            { label: 'Viajes', value: 'Viajes' },
            { label: 'Daños', value: 'Danos' },
            { label: 'Empresarial', value: 'Empresarial' },
            { label: 'Responsabilidad Civil (RC)', value: 'RC' },
            { label: 'Transporte', value: 'Transporte' },
            { label: 'Mascotas', value: 'Mascotas' },
            { label: 'Fianzas', value: 'Fianzas' },
            { label: 'Dental', value: 'Dental' },
            { label: 'Visión', value: 'Vision' }
        ];
    }

    // ============================================================
    // FILTROS PARA LA LISTA (etapas)
    // ============================================================
    get stageFilterOptions() {
        const base = [{ label: 'Todas las etapas', value: '' }];
        const fromPicklist = (this.stagePicklistValues || []).map(s => ({
            label: this.getStageLabel(s.value),
            value: s.value
        }));
        const fromConstant = STAGES_DATA.map(s => ({ label: s.label, value: s.value }));
        const map = new Map();
        [...fromPicklist, ...fromConstant].forEach(o => {
            if (!map.has(o.value)) map.set(o.value, o);
        });
        return base.concat(Array.from(map.values()));
    }

    // ============================================================
    // COMPARATIVA DE COTIZACIONES RELACIONADAS (DESDE QUOTES)
    // ============================================================
    /** Hay comparativa cuando hay 2 o más cotizaciones relacionadas con prima válida. */
    get hasQuoteComparison() {
        const valid = (this.comparativaSource  || []).filter(q => q && q.totalAmount > 0);
        return valid.length >= 2;
    }
    /** Aviso cuando solo hay 1 cotización (para invitar a agregar otra). */
    get hasSingleQuote() {
        return (this.relatedQuotes || []).length === 1;
    }

    get editableQuotesCount() {
        return this.editableQuotes ? this.editableQuotes.length : 0;
    }

    /**
     * Cotizaciones enriquecidas para la tabla comparativa.
     * Marca cuál tiene el mejor precio y calcula la diferencia vs. el mejor.
     */
    get comparisonQuotes() {
        const quotes = (this.comparativaSource || []).filter(q => q && q.totalAmount > 0);
        if (quotes.length === 0) return [];
        const minAmount = Math.min(...quotes.map(q => q.totalAmount));
        const maxCoverage = Math.max(...quotes.map(q => q.coverageCount || 0));
        const today = new Date();
        return quotes.map(q => {
            const isBestPrice = q.totalAmount === minAmount;
            const isBestCoverage = maxCoverage > 0 && (q.coverageCount || 0) === maxCoverage;
            const diff = q.totalAmount - minAmount;
            const diffPct = minAmount > 0 ? Math.round((diff / minAmount) * 100) : 0;
            // Días hasta vencimiento
            let daysLabel = '';
            let daysClass = 'days-remaining';
            let hasDaysInfo = false;
            const expDate = this.parseSafeDate(q.expirationDateRaw);
            if (expDate) {
                hasDaysInfo = true;
                const diffDays = Math.ceil((expDate - today) / 86400000);
                if (diffDays < 0) {
                    daysLabel = `Vencida hace ${Math.abs(diffDays)} día${Math.abs(diffDays) === 1 ? '' : 's'}`;
                    daysClass = 'days-remaining is-overdue';
                } else if (diffDays === 0) {
                    daysLabel = 'Vence hoy';
                    daysClass = 'days-remaining is-due-today';
                } else {
                    daysLabel = `${diffDays} día${diffDays === 1 ? '' : 's'}`;
                    daysClass = 'days-remaining is-active';
                }
            }
            return {
                ...q,
                isBestPrice,
                isBestCoverage,
                headerClass: isBestPrice ? 'compare-col best-col' : 'compare-col',
                amountCellClass: isBestPrice ? 'amount-cell best-amount' : 'amount-cell',
                diffCellClass: isBestPrice ? 'diff-cell best-diff' : 'diff-cell',
                coverageCellClass: isBestCoverage
                    ? 'coverage-cell best-coverage'
                    : 'coverage-cell',
                diffLabel: isBestPrice
                    ? 'Mejor precio'
                    : `+${this.formatCurrency(diff)} (+${diffPct}%)`,
                daysLabel,
                daysClass,
                hasDaysInfo
            };
        });
    }
    /**
     * KPIs de resumen de la comparativa: mejor precio, más alto, promedio, ahorro,
     * y una recomendación en lenguaje de negocio.
     */
    get comparisonSummary() {
        const quotes = (this.comparativaSource || []).filter(q => q && q.totalAmount > 0);
        if (quotes.length < 2) {
            return {
                totalQuotes: quotes.length,
                bestPriceFormatted: this.formatCurrency(0),
                bestPriceCompany: '—',
                highestPriceFormatted: this.formatCurrency(0),
                highestPriceCompany: '—',
                averageFormatted: this.formatCurrency(0),
                savingsFormatted: this.formatCurrency(0),
                savingsPercent: 0,
                mostCoveragesCount: 0,
                mostCoveragesCompany: '—',
                recommendation: ''
            };
        }
        const sorted = [...quotes].sort((a, b) => a.totalAmount - b.totalAmount);
        const best = sorted[0];
        const worst = sorted[sorted.length - 1];
        const total = quotes.reduce((s, q) => s + q.totalAmount, 0);
        const avg = total / quotes.length;
        const savings = worst.totalAmount - best.totalAmount;
        const savingsPct = worst.totalAmount > 0
            ? Math.round((savings / worst.totalAmount) * 100)
            : 0;
        // Cotización con más coberturas
        const sortedByCoverage = [...quotes].sort(
            (a, b) => (b.coverageCount || 0) - (a.coverageCount || 0)
        );
        const mostCov = sortedByCoverage[0];
        const mostCoveragesCount   = mostCov.coverageCount || 0;
        const mostCoveragesCompany = mostCoveragesCount > 0 ? mostCov.companiaLabel : '—';
        // Recomendación inteligente
        let recommendation = '';
        if (savings > 0 && best.Id === mostCov.Id && mostCoveragesCount > 0) {
            recommendation = `${best.companiaLabel} es la opción más conveniente: ` +
                             `ofrece la prima más baja (ahorro de ${this.formatCurrency(savings)}, ${savingsPct}%) ` +
                             `y además es la que más coberturas incluye (${mostCoveragesCount}).`;
        } else if (savings > 0) {
            recommendation = `${best.companiaLabel} ofrece la prima más baja con un ahorro de ` +
                             `${this.formatCurrency(savings)} (${savingsPct}%) frente a ${worst.companiaLabel}. ` +
                             (mostCoveragesCount > 0
                                ? `Sin embargo, ${mostCoveragesCompany} incluye más coberturas (${mostCoveragesCount}); ` +
                                  `evalúa qué pesa más para el cliente: precio o protección.`
                                : `Considera esta opción si las coberturas son equivalentes.`);
        } else {
            recommendation = `Todas las cotizaciones presentan primas similares. ` +
                             `Compara coberturas, deducibles y red de servicio para decidir.`;
        }
        return {
            totalQuotes: quotes.length,
            bestPriceFormatted: this.formatCurrency(best.totalAmount),
            bestPriceCompany: best.companiaLabel,
            highestPriceFormatted: this.formatCurrency(worst.totalAmount),
            highestPriceCompany: worst.companiaLabel,
            averageFormatted: this.formatCurrency(avg),
            savingsFormatted: this.formatCurrency(savings),
            savingsPercent: savingsPct,
            mostCoveragesCount,
            mostCoveragesCompany,
            recommendation
        };
    }

    // ============================================================
    // COMPARATIVA (uploadedQuotes — datos de PDFs)
    // ============================================================
    get hasComparativa() {
        return this.uploadedQuotes && this.uploadedQuotes.length >= 2;
    }
    recomputeComparativa() {
        if (!this.uploadedQuotes || this.uploadedQuotes.length === 0) {
            this.tablaComparativaCache = [];
            this.companiasConCoberturasCache = [];
            this.totalCoberturasUnicas = 0;
            this.tieneQualitas = false;
            this.tieneChubb = false;
            this.tieneGnp = false;
            this.tieneHdi = false;
            return;
        }
        const coberturasMap = new Map();
        const companias = [];
        this.uploadedQuotes.forEach(quote => {
            const compania = quote.compania || 'Desconocida';
            if (!companias.includes(compania)) companias.push(compania);
            if (Array.isArray(quote.tablaCompletaCoberturas)) {
                quote.tablaCompletaCoberturas.forEach(cobertura => {
                    const nombre = cobertura.cobertura || cobertura.nombre || 'Cobertura';
                    if (!coberturasMap.has(nombre)) {
                        coberturasMap.set(nombre, { nombre, valores: {} });
                    }
                    coberturasMap.get(nombre).valores[compania] = {
                        suma: cobertura.sumaAsegurada || cobertura.suma || '',
                        deducible: cobertura.deducible || '',
                        coaseguro: cobertura.coaseguro || ''
                    };
                });
            }
            if (quote.isAutomovil)        this.agregarCoberturaAuto(coberturasMap, compania, quote);
            else if (quote.isGastosMedicos) this.agregarCoberturaGMM(coberturasMap, compania, quote);
            else if (quote.isViaje)       this.agregarCoberturaViaje(coberturasMap, compania, quote);
            else if (quote.isRC)          this.agregarCoberturaRC(coberturasMap, compania, quote);
            else if (quote.isTransporte)  this.agregarCoberturaTransporte(coberturasMap, compania, quote);
        });
        this.companiasConCoberturasCache = companias.map(nombre => ({
            nombre,
            primaTotal: this.formatCurrency(
                this.uploadedQuotes.find(q => q.compania === nombre)?.primaTotal || 0
            )
        }));
        this.tieneQualitas = companias.includes('QUALITAS');
        this.tieneChubb    = companias.includes('CHUBB');
        this.tieneGnp      = companias.includes('GNP');
        this.tieneHdi      = companias.includes('HDI');
        const coberturasArray = Array.from(coberturasMap.values());
        this.totalCoberturasUnicas = coberturasArray.length;
        this.tablaComparativaCache = coberturasArray.map(cobertura => ({
            cobertura: cobertura.nombre,
            claseFila: '',
            valores: companias.map(compania => ({
                compania,
                suma: cobertura.valores[compania]?.suma
                    ? this.formatCurrencyOrText(cobertura.valores[compania].suma)
                    : '',
                deducible: cobertura.valores[compania]?.deducible || '',
                coaseguro: cobertura.valores[compania]?.coaseguro || ''
            }))
        }));
    }
    get tablaComparativaConClases() { return this.tablaComparativaCache; }
    get companiasConCoberturas()   { return this.companiasConCoberturasCache; }

    agregarCoberturaAuto(map, compania, q) {
        if (q.sumaAsegurada)       this.agregarOActualizarCobertura(map, 'Daños Materiales',           compania, { suma: q.sumaAsegurada, deducible: q.deducible });
        if (q.sumaRobo)            this.agregarOActualizarCobertura(map, 'Robo Total',                 compania, { suma: q.sumaRobo, deducible: q.deducibleRobo });
        if (q.sumaRC)              this.agregarOActualizarCobertura(map, 'Responsabilidad Civil',     compania, { suma: q.sumaRC, deducible: q.deducibleRC });
        if (q.sumaGastosMedicos)   this.agregarOActualizarCobertura(map, 'Gastos Médicos Ocupantes', compania, { suma: q.sumaGastosMedicos, deducible: q.deducibleGastosMedicos });
    }
    agregarCoberturaGMM(map, compania, q) {
        if (q.sumaAsegurada) this.agregarOActualizarCobertura(map, 'Suma Asegurada', compania, { suma: q.sumaAsegurada, deducible: q.deducible, coaseguro: q.coaseguro });
    }
    agregarCoberturaViaje(map, compania, q) {
        if (Array.isArray(q.coberturasViaje)) {
            q.coberturasViaje.forEach(cov => this.agregarOActualizarCobertura(map, cov.nombre, compania, { suma: cov.suma }));
        }
    }
    agregarCoberturaRC(map, compania, q) {
        if (q.sumaAsegurada) this.agregarOActualizarCobertura(map, 'Suma Asegurada', compania, { suma: q.sumaAsegurada, deducible: q.deducible });
    }
    agregarCoberturaTransporte(map, compania, q) {
        if (Array.isArray(q.riesgosAmparados)) {
            q.riesgosAmparados.forEach(r => this.agregarOActualizarCobertura(map, r.nombre, compania, { deducible: r.deducible }));
        }
        if (q.limiteEmbarque) this.agregarOActualizarCobertura(map, 'Límite por Embarque', compania, { suma: q.limiteEmbarque });
    }
    agregarOActualizarCobertura(map, nombre, compania, valores) {
        if (!map.has(nombre)) map.set(nombre, { nombre, valores: {} });
        const c = map.get(nombre);
        c.valores[compania] = { ...c.valores[compania], ...valores };
    }

    // ============================================================
    // FORMATEO
    // ============================================================
    formatNumber(amount) {
        if (!amount && amount !== 0) return '0';
        const num = parseFloat(amount) || 0;
        return num.toLocaleString('es-MX');
    }
    formatCurrency(amount) {
        if (amount === null || amount === undefined || amount === '') return '$0.00 MXN';
        const num = parseFloat(amount);
        if (isNaN(num)) return '$0.00 MXN';
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(num);
    }
    formatCurrencyOrText(value) {
        if (value === null || value === undefined) return '';
        const num = parseFloat(value);
        if (!isNaN(num) && num > 0) return this.formatCurrency(num);
        return String(value);
    }
    formatDate(dateString) {
        if (!dateString) return 'Sin fecha';
        const date = new Date(dateString);
        if (isNaN(date.getTime()) || date.getFullYear() < 1970) return 'Sin fecha';
        return date.toLocaleDateString('es-MX', {
            day: '2-digit', month: 'short', year: 'numeric'
        });
    }
    formatDateForInput(date) {
        if (!date) return '';
        const d = new Date(date);
        if (isNaN(d.getTime())) return '';
        const year = d.getFullYear();
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    // ============================================================
    // EVENTOS
    // ============================================================
    handleQuoteRamoChange(event) {
        this.selectedQuoteRamo = event.detail.value;
        if (!this.opportunity.Ramo__c) {
            this.opportunity.Ramo__c = this.selectedQuoteRamo;
        }
    }
    handleSearchChange(event) {
        const value = event.target.value;
        if (this._searchTimer) clearTimeout(this._searchTimer);
        this._searchTimer = setTimeout(() => {
            this.searchTerm = value || '';
            this.currentPage = 1;
        }, 250);
    }
    handleStageFilterChange(event) {
        this.stageFilter = event.detail.value || '';
        this.currentPage = 1;
    }
    handleOverdueToggle(event) {
        this.showOnlyOverdue = event.target.checked;
        this.currentPage = 1;
    }
    handleClickOutside(event) {
        const insideLookup = event && event.target && event.target.closest
            && event.target.closest('.lookup-container');
        if (!insideLookup) {
            this.showAccountDropdown = false;
            this.showAgenteDropdown = false;
            this.showVehiculoDropdown = false;
            this.showContactoDropdown = false;
        }
    }

    // ============================================================
    // LOOKUP DE CUENTA (Account / Person Account)
    // ============================================================
    get hasAccountResults() {
        return this.accountResults && this.accountResults.length > 0;
    }
    handleAccountFocus() {
        this.showAccountDropdown = true;
    }
    handleAccountInput(event) {
        const value = event.target.value;
        this.opportunity = { ...this.opportunity, AccountName: value, AccountId: null };
        this.isNewAccount = false;
        this.showAccountDropdown = true;
        clearTimeout(this._accountSearchTimer);
        this._accountSearchTimer = setTimeout(async () => {
            if (value && value.length >= 2) {
                try {
                    this.accountResults = await searchAccounts({ searchTerm: value });
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.error(':::OpportunityCreator::: Error buscando cuentas', e);
                    this.accountResults = [];
                }
            } else {
                this.accountResults = [];
            }
        }, 300);
    }
    // Pone el nombre del cliente en Cuenta, busca si existe y la selecciona;
    // si no existe, la marca como nueva (se creará al guardar).
    async resolveAccountByName(name) {
        const clean = (name || '').trim();
        if (!clean) return;
        try {
            const res = await searchAccounts({ searchTerm: clean });
            const exact = (res || []).find(
                a => (a.Name || '').trim().toLowerCase() === clean.toLowerCase()
            );
            if (exact) {
                this.opportunity = {
                    ...this.opportunity,
                    AccountId: exact.Id,
                    AccountName: exact.Name,
                    tipoCliente: exact.IsPersonAccount ? 'Persona' : 'Empresa',
                    clienteNombre: exact.clienteNombre || exact.Name || this.opportunity.clienteNombre,
                    clienteRFC: exact.clienteRFC || this.opportunity.clienteRFC,
                    clienteEmail: exact.clienteEmail || this.opportunity.clienteEmail,
                    clienteTelefono: exact.clienteTelefono || this.opportunity.clienteTelefono,
                    clienteCP: exact.clienteCP || this.opportunity.clienteCP,
                    clienteDireccion: exact.clienteDireccion || this.opportunity.clienteDireccion
                };
                this.isNewAccount = false;
            } else {
                this.opportunity = { ...this.opportunity, AccountId: null, AccountName: clean };
                this.isNewAccount = true;
            }
        } catch (e) {
            // Si falla la búsqueda, dejamos el nombre escrito para crear al guardar.
            this.opportunity = { ...this.opportunity, AccountName: clean };
            this.isNewAccount = true;
        }
    }
    selectAccount(event) {
        const id = event.currentTarget.dataset.id;
        const acc = (this.accountResults || []).find(a => a.Id === id);
        if (!acc) return;
        this.opportunity = {
            ...this.opportunity,
            AccountId: acc.Id,
            AccountName: acc.Name,
            tipoCliente: acc.IsPersonAccount ? 'Persona' : 'Empresa',
            clienteNombre: acc.clienteNombre || acc.Name || '',
            clienteRFC: acc.clienteRFC || '',
            clienteEmail: acc.clienteEmail || '',
            clienteTelefono: acc.clienteTelefono || '',
            clienteCP: acc.clienteCP || '',
            clienteDireccion: acc.clienteDireccion || ''
        };
        this.isNewAccount = false;
        this.showAccountDropdown = false;
        this.accountResults = [];
    }
    selectNewAccount() {
        const typedName = this.opportunity.AccountName || '';
        this.opportunity = {
            ...this.opportunity,
            AccountId: null,
            AccountName: typedName,
            clienteNombre: '',
            clienteApellidos: '',
            clienteRFC: '',
            clienteEmail: '',
            clienteTelefono: '',
            clienteCP: '',
            clienteDireccion: ''
        };
        this.isNewAccount = true;
        this.showAccountDropdown = false;
        this.accountResults = [];
        this.showToast('Cuenta nueva',
            'Captura los datos en "Información del Cliente". La cuenta se creará al guardar.',
            'info');
    }

    // ============================================================
    // LOOKUP DE CONTACTO
    // ============================================================
    get isMercadoIndividual() {
        return this.opportunity.Mercado__c === 'Individual';
    }
    // Cuando NO es Individual se muestra el buscador de contactos.
    get showContactoLookup() {
        return !this.isMercadoIndividual;
    }
    get hasContactoResults() {
        return this.contactoResults && this.contactoResults.length > 0;
    }
    // Texto a mostrar cuando el Contacto es igual a la Cuenta (Mercado Individual).
    get contactoIgualCuentaText() {
        return this.opportunity.AccountName
            ? `Igual que la cuenta: ${this.opportunity.AccountName}`
            : 'Igual que la cuenta';
    }
    handleContactoFocus() {
        this.showContactoDropdown = true;
    }
    handleContactoInput(event) {
        const value = event.target.value;
        this.opportunity = { ...this.opportunity, ContactoName: value, Contacto__c: null };
        this.isNewContacto = false;
        this.showContactoDropdown = true;
        clearTimeout(this._contactoSearchTimer);
        this._contactoSearchTimer = setTimeout(async () => {
            if (value && value.length >= 2) {
                try {
                    this.contactoResults = await searchContacts({ searchTerm: value });
                } catch (e) {
                    this.contactoResults = [];
                }
            } else {
                this.contactoResults = [];
            }
        }, 300);
    }
    selectContacto(event) {
        const id = event.currentTarget.dataset.id;
        const c = (this.contactoResults || []).find(x => x.Id === id);
        if (!c) return;
        this.opportunity = { ...this.opportunity, Contacto__c: c.Id, ContactoName: c.Name };
        this.isNewContacto = false;
        this.showContactoDropdown = false;
        this.contactoResults = [];
    }
    selectNewContacto() {
        this.opportunity = { ...this.opportunity, Contacto__c: null };
        this.isNewContacto = true;
        this.showContactoDropdown = false;
        this.contactoResults = [];
    }

    handlePrevPage() {
        if (this.currentPage > 1) this.currentPage -= 1;
    }
    handleNextPage() {
        if (this.currentPage < this.totalPages) this.currentPage += 1;
    }
    handleViewOpportunity(event) {
        return this.handleEditOpportunity(event);
    }
    async handleEditOpportunity(event) {
        const id = event.currentTarget.dataset.id;
        if (id) await this.openOpportunityInEditMode(id);
    }
    async openOpportunityInEditMode(id) {
        if (!id) return;
        this.isLoading = true;
        try {
            this.resetWizard();
            const fromList = (this.opportunities || []).find(o => o.Id === id) || {};
            const detail = await getOpportunityDetails({ opportunityId: id });

            // El Apex devuelve { opportunity, quotes, coverageCounts, coverageNamesByQuote }
            let opportunityData = fromList;
            let quotesData = [];
            let coverageCounts = {};
            let coverageNamesByQuote = {};

            if (Array.isArray(detail)) {
                quotesData = detail;
            } else if (detail && typeof detail === 'object') {
                if (detail.opportunity || detail.Opportunity) {
                    const oppPayload = detail.opportunity || detail.Opportunity;
                    opportunityData = { ...fromList, ...oppPayload };
                } else {
                    opportunityData = { ...fromList, ...detail };
                }
                // El vehículo NO está en la oportunidad: viene aparte en el wrapper,
                // buscado por la cuenta de la oportunidad (Automovil__c.Cuenta__c).
                if (detail.automovil) { opportunityData.automovil = detail.automovil; }
                quotesData = detail.quotes || detail.Quotes || detail.relatedQuotes || [];
                coverageCounts = detail.coverageCounts || detail.CoverageCounts || {};
                coverageNamesByQuote = detail.coverageNamesByQuote
                                    || detail.CoverageNamesByQuote || {};
            }

            this.populateFormFromOpportunity(opportunityData, id);
            this.relatedQuotes = Array.isArray(quotesData)
                ? quotesData.map(q => this.mapRelatedQuote(q, coverageCounts, coverageNamesByQuote))
                : [];
            this.viewMode = VIEW_MODES.EDIT;
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(':::OpportunityCreator::: Error al cargar oportunidad para edición', e);
            this.showToast('Error', 'No se pudo cargar la oportunidad para edición', 'error');
        } finally {
            this.isLoading = false;
        }
    }
    populateFormFromOpportunity(detail, id) {
        this.opportunity = {
            ...this.getDefaultOpportunity(),
            Id: id,
            Name:        detail.Name        || '',
            StageName:   detail.StageName   || 'Gestion Comercial',
            Type:        detail.Type        || OPPORTUNITY_TYPES.NEW_BUSINESS,
            Canal__c:    detail.Canal__c    || '',
            Mercado__c:  detail.Mercado__c  || '',
            Ramo__c:     detail.Ramo__c     || '',
            Description: detail.Description || '',
            AccountId:   detail.AccountId   || null,
            AccountName: detail.Account?.Name || detail.AccountName || '',
            Agente__c:   detail.Agente_Relacionado__c || detail.Agente__c || null,
            AgenteName:  detail.Agente_Relacionado__r?.Name || detail.Agente__r?.Name || detail.AgenteName || '',
            Vehiculo__c:  detail.automovil?.Id || null,
            VehiculoName: detail.automovil
                            ? `${detail.automovil.Marca__c || ''} ${detail.automovil.Modelo__c || ''}`.trim()
                            : (detail.VehiculoName || ''),
            Contacto__c:  detail.Contacto__c || null,
            ContactoName: detail.Contacto__r?.Name || detail.ContactoName || '',
            Prima_Neta__c: detail.Prima_neta__c ?? detail.Prima_Neta__c ?? detail.Prima_Total__c ?? detail.Amount ?? null,
            CloseDate:   detail.CloseDate   || null ,
            clienteNombre:    detail.clienteNombre    || detail.Account?.Name           || '',
            clienteRFC:       detail.clienteRFC       || detail.Account?.RFC__c          || '',
            clienteEmail:     detail.clienteEmail     || detail.Account?.Email__c        || detail.Account?.PersonEmail || '',
            clienteTelefono:  detail.clienteTelefono  || detail.Account?.Phone           || '',
            clienteCP:        detail.clienteCP        || detail.Account?.BillingPostalCode || '',
            clienteDireccion: detail.clienteDireccion || detail.Account?.BillingStreet    || ''
        };
        this.selectedQuoteRamo = this.opportunity.Ramo__c;

        // Comparativo de la IA guardado en la oportunidad (Descripcion__c) para
        // mostrarlo en la sección "Comparativa de Cotizaciones" al editar.
        this.comparativoHtml = detail.Descripcion__c || '';
        this._comparativoDirty = true;

        if (this.opportunity.Ramo__c === RAMO_TYPES.EMPRESARIAL || detail.empresarial) {
            this.empresarial = { ...this.getDefaultEmpresarial(), ...(detail.empresarial || {}) };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.FIANZAS || detail.fianzas) {
            this.fianzas = { ...this.getDefaultFianzas(), ...(detail.fianzas || {}) };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.RESPONSABILIDAD_CIVIL || detail.rc) {
            this.rc = { ...this.getDefaultRC(), ...(detail.rc || {}) };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.DENTAL || detail.dental) {
            this.dental = { ...this.getDefaultDental(), ...(detail.dental || {}) };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.VISION || detail.vision) {
            this.vision = { ...this.getDefaultVision(), ...(detail.vision || {}) };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.TRANSPORTE || detail.transporte) {
            this.transporte = { ...this.getDefaultTransporte(), ...(detail.transporte || {}) };
        }
        if (this.isRamoAutomovil || detail.automovil) {
            const a = detail.automovil || detail;
            this.automovil = {
                ...this.getDefaultAutomovil(),
                Marca__c:                a.Marca__c                || '',
                Modelo__c:               a.Modelo__c               || '',
                Anio__c:                 a.Anio__c                 || '',
                Placa__c:                a.Placa__c                || '',
                Serie__c:                a.Serie__c                || '',
                Motor__c:                a.Motor__c                || '',
                descripcion_completa__c: a.Descripcion_Completa__c || a.descripcion_completa__c || ''
            };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.GASTOS_MEDICOS || detail.gmm) {
            const g = detail.gmm || detail;
            this.gmm = {
                ...this.getDefaultGMM(),
                estado:         g.estado         || '',
                tipoEstructura: g.tipoEstructura || '',
                numAsegurados:  g.numAsegurados  || 1
            };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.VIDA || detail.vida) {
            const v = detail.vida || detail;
            this.vida = {
                ...this.getDefaultVida(),
                aseguradoPrincipal: v.aseguradoPrincipal || '',
                contratante:        v.contratante        || '',
                subramo:            v.subramo            || ''
            };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.VIAJE || detail.viaje) {
            const vj = detail.viaje || detail;
            this.viaje = {
                ...this.getDefaultViaje(),
                destino:      vj.destino      || '',
                numPasajeros: vj.numPasajeros || 1
            };
        }
        if (this.opportunity.Ramo__c === RAMO_TYPES.DANOS || detail.danos) {
            const d = detail.danos || detail;
            this.danos = {
                ...this.getDefaultDanos(),
                subramo: d.subramo || ''
            };
        }
    }
    /**
     * Convierte un registro de Quote al formato que usan la tabla de
     * Cotizaciones Relacionadas y la Comparativa.
     * IMPORTANTE: ahora también guarda los valores RAW (totalAmount,
     * expirationDateRaw) para poder hacer cálculos sin re-parsear strings.
     */
    mapRelatedQuote(q, coverageCounts, coverageNamesByQuote) {
        if (!q) return {};
        // Prima total: prioriza TotalPrice; si no hay, usa Subtotal.
        // Mantengo fallbacks para compatibilidad con esquemas futuros.
        // La prima real vive en los campos custom (Prima_Total__c / PrimaAnual__c).
        // TotalPrice/Subtotal son calculados y pueden venir en 0.
        const totalRaw = q.Prima_Total__c ?? q.PrimaAnual__c
                    ?? q.TotalPrice ?? q.Subtotal ?? q.Amount ?? 0;
        const totalAmount = parseFloat(totalRaw) || 0;
        const status = q.Status || q.Estado__c || q.EstadoCotizacion__c || '';
        // Aseguradora: lookup Aseguradora__r.Name; fallback al producto o cuenta.
        const compania = q.Aseguradora__r?.Name
                       || q.Compania__r?.Name
                       || q.Product__r?.Name
                       || q.Compania__c
                       || q.Aseguradora__c
                       || q.Account?.Name
                       || q.AccountName
                       || '—';
        const expirationDateRaw = q.ExpirationDate || q.Vigencia__c || q.FechaVencimiento__c || null;
        // COBERTURAS: el Apex ahora envía un mapa { quoteId: total }
        // calculado con COUNT(Id) sobre Quote_Coverage__c.
        let coverageCount = 0;
        if (coverageCounts && q.Id != null && coverageCounts[q.Id] != null) {
            coverageCount = Number(coverageCounts[q.Id]) || 0;
        } else if (Array.isArray(q.Quote_Coverages__r)) {
            coverageCount = q.Quote_Coverages__r.length;
        } else if (q.Quote_Coverages__r && Array.isArray(q.Quote_Coverages__r.records)) {
            coverageCount = q.Quote_Coverages__r.records.length;
        } else if (typeof q.coverageCount === 'number') {
            coverageCount = q.coverageCount;
        } else if (typeof q.numCoberturas === 'number') {
            coverageCount = q.numCoberturas;
        }
        // Producto cotizado (QuoteLineItem trae el producto)
        let productName = q.Product__r?.Name || '';
        if (!productName) {
            const qli = Array.isArray(q.QuoteLineItems)
                ? q.QuoteLineItems
                : (q.QuoteLineItems?.records || []);
            if (qli.length > 0) {
                productName = qli[0].Product2?.Name || '';
            }
        }
        return {
            Id: q.Id,
            QuoteNumber: q.QuoteNumber || q.Numero__c || '—',
            Name: q.Name || '—',
            companiaLabel: compania,
            statusLabel: status || 'Sin estado',
            statusBadgeClass: this.getQuoteStatusBadgeClass(status),
            // Bandera útil para la tabla: indica la cotización "ganadora" en Salesforce
            isSyncing: !!q.IsSyncing,
            isSelected: !!q.Is_Selected__c,
            totalAmount,
            totalFormatted: this.formatCurrency(totalAmount),
            expirationDateRaw,
            expirationFormatted: this.formatDate(expirationDateRaw),
            coverageCount,
            coverageLabel: coverageCount === 1
                ? '1 cobertura'
                : `${coverageCount} coberturas`,
            // Lista de nombres de cobertura (para el comparativo imprimible)
            coverageNames: (coverageNamesByQuote && q.Id && Array.isArray(coverageNamesByQuote[q.Id]))
                ? coverageNamesByQuote[q.Id]
                : [],
            productName,
            esAceptada: /acept/i.test(status),
            puedeAceptar: !/acept/i.test(status)
        };
    }
    getQuoteStatusBadgeClass(status) {
        if (!status) return 'quote-badge quote-badge-neutral';
        const s = String(status).toLowerCase();
        if (s.includes('acept') || s.includes('ganad') || s.includes('aprob')) return 'quote-badge quote-badge-won';
        if (s.includes('rech') || s.includes('perd') || s.includes('canc'))   return 'quote-badge quote-badge-lost';
        if (s.includes('borr') || s.includes('draft'))                          return 'quote-badge quote-badge-draft';
        if (s.includes('present') || s.includes('envi'))                        return 'quote-badge quote-badge-active';
        return 'quote-badge quote-badge-neutral';
    }
    handleViewQuote(event) {
        return this.handleEditRelatedQuote(event);
    }
    // Marca la cotización como "Aceptado" y refresca la lista.
    async handleAceptarQuote(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) { return; }
        try {
            await aceptarCotizacion({ quoteId: id });
            this.showToast('Cotización aceptada', 'La cotización se marcó como Aceptado.', 'success');
            if (this.opportunity?.Id) {
                await this.openOpportunityInEditMode(this.opportunity.Id);
            }
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.showToast('Error', 'No se pudo aceptar la cotización: ' + msg, 'error');
        }
    }
    handleEditRelatedQuote(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Crear_Cotizacion' },
            state: {
                c__quoteId: id,
                c__opportunityId: this.opportunity?.Id || '',
                c__opportunityName: this.opportunity?.Name || '',
                c__opportunityRamo: this.opportunity?.Ramo__c || ''
            }
        });
    }
    handleAddNewQuote() {
        if (!this.opportunity || !this.opportunity.Id) {
            this.showToast('Aviso', 'Guarda la oportunidad antes de agregar cotizaciones.', 'warning');
            return;
        }
        if (!this.opportunity.Ramo__c) {
            this.showToast('Aviso', 'La oportunidad no tiene un ramo definido. Asígnalo antes de cotizar.', 'warning');
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Crear_Cotizacion' },
            state: {
                c__opportunityId: this.opportunity.Id,
                c__opportunityName: this.opportunity.Name || '',
                c__opportunityRamo: this.opportunity.Ramo__c
            }
        });
    }
    get hasRelatedQuotes()   { return this.relatedQuotes && this.relatedQuotes.length > 0; }
    get relatedQuotesCount() { return this.relatedQuotes ? this.relatedQuotes.length : 0; }

    // ============================================================
    // COMPARATIVO IMPRIMIBLE (formato carta horizontal)
    // ============================================================
    /**
     * Construye un HTML completo con el comparativo de cotizaciones y lo
     * abre en una pestaña nueva. El usuario puede imprimir o guardar como PDF.
     */
    /** Dispara el diálogo nativo de impresión del navegador. */
    handlePrintComparativo() {
        try {
            window.print();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error(':::OpportunityCreator::: Error al imprimir', e);
            this.showToast('Error', 'No se pudo abrir el diálogo de impresión.', 'error');
        }
    }

    // ============================================================
    // DATOS DEL COMPARATIVO (para el render declarativo del overlay)
    // ============================================================
    /**
     * Devuelve toda la información que el overlay necesita para pintar:
     * encabezado, columnas (compañías con badge), filas de precios, número
     * de coberturas y matriz cobertura × compañía con sí/no.
     */
    get comparativoData() {
        const quotes = (this.comparativaSource || []).filter(q => q && q.totalAmount > 0);
        if (quotes.length < 2) {
            return { hasData: false };
        }
        const minPrice = Math.min(...quotes.map(q => q.totalAmount));
        const maxPrice = Math.max(...quotes.map(q => q.totalAmount));
        const maxCov   = Math.max(...quotes.map(q => (q.coverageCount || 0)));
        const bestPriceQuote = quotes.find(q => q.totalAmount === minPrice);
        const bestCovQuote   = quotes.find(q => (q.coverageCount || 0) === maxCov);

        // Columnas (encabezado de la tabla)
        const columns = quotes.map(q => {
            const isPrice = q.Id === bestPriceQuote.Id;
            const isCov   = q.Id === bestCovQuote.Id;
            let badge = '';
            if (isPrice && isCov) badge = '★ Mejor precio y coberturas';
            else if (isPrice)     badge = '★ Mejor precio';
            else if (isCov)       badge = '★ Más coberturas';
            const hl = isPrice || isCov;
            return {
                Id: q.Id,
                name: q.companiaLabel || '—',
                badge,
                hasBadge: !!badge,
                headerClass: hl ? 'doc-th doc-th-rec' : 'doc-th',
                bodyClass:   hl ? 'doc-cell doc-cell-hl' : 'doc-cell',
                priceFormatted: q.totalFormatted,
                priceSub: q.totalAmount === minPrice ? 'el más barato'
                        : (q.totalAmount === maxPrice && quotes.length > 1 ? 'el más caro' : ''),
                hasPriceSub: q.totalAmount === minPrice
                          || (q.totalAmount === maxPrice && quotes.length > 1),
                coverageCount: q.coverageCount || 0
            };
        });

        // Universo de coberturas en orden de aparición
        const allCoverages = [];
        const covSet = new Set();
        quotes.forEach(q => {
            (q.coverageNames || []).forEach(name => {
                const clean = (name || '').trim();
                if (clean && !covSet.has(clean.toLowerCase())) {
                    covSet.add(clean.toLowerCase());
                    allCoverages.push(clean);
                }
            });
        });

        // Matriz cobertura × compañía
        const rows = allCoverages.map((covName, idx) => {
            const cells = quotes.map(q => {
                const includes = (q.coverageNames || []).some(n =>
                    (n || '').trim().toLowerCase() === covName.toLowerCase()
                );
                const isHl = q.Id === bestPriceQuote.Id || q.Id === bestCovQuote.Id;
                let cls = 'doc-cell';
                if (isHl) cls += ' doc-cell-hl';
                if (!includes) cls += ' doc-cell-no';
                return {
                    key: `${idx}-${q.Id}`,
                    text: includes ? 'Sí' : 'No incluida',
                    cellClass: cls
                };
            });
            return { key: `row-${idx}`, name: covName, cells };
        });

        // Cards de mejores opciones
        const isSameWinner = bestPriceQuote.Id === bestCovQuote.Id;
        const cards = isSameWinner
            ? [{
                key: 'unique',
                title: `★ Opción única recomendada — ${bestPriceQuote.companiaLabel} · ${bestPriceQuote.totalFormatted}`,
                text:  `Esta opción combina el mejor precio y el mayor número de coberturas (${bestCovQuote.coverageCount}). Es la más equilibrada del comparativo.`
              }]
            : [{
                key: 'price',
                title: `★ Opción 1 — ${bestPriceQuote.companiaLabel} · ${bestPriceQuote.totalFormatted} (mejor precio)`,
                text:  `La más económica del comparativo, con ${bestPriceQuote.coverageCount} coberturas incluidas. Ideal si el presupuesto manda.`
              }, {
                key: 'coverage',
                title: `★ Opción 2 — ${bestCovQuote.companiaLabel} · ${bestCovQuote.totalFormatted} (más coberturas)`,
                text:  `El paquete más completo, con ${bestCovQuote.coverageCount} coberturas. Mejor protección por un poco más de prima.`
              }];

        // Recomendación
        const savings = maxPrice - minPrice;
        const savingsPct = maxPrice > 0 ? Math.round((savings / maxPrice) * 100) : 0;
        const recomendacion = isSameWinner
            ? `${bestPriceQuote.companiaLabel} es la opción más completa: ofrece el mejor precio (${bestPriceQuote.totalFormatted}) y el mayor número de coberturas (${bestCovQuote.coverageCount}).`
            : `${bestCovQuote.companiaLabel} trae el paquete más completo (${bestCovQuote.coverageCount} coberturas). ${bestPriceQuote.companiaLabel} es la más económica (${bestPriceQuote.totalFormatted}) con un ahorro de ${this.formatCurrency(savings)} (${savingsPct}%). Tú decides qué pesa más: precio o protección.`;

        // Metadata del documento
        const today = new Date();
        const finVig = new Date(today.getFullYear() + 1, today.getMonth(), today.getDate());
        return {
            hasData: true,
            ramoLabel: this.opportunity.Ramo__c || 'Seguro',
            clienteName: this.opportunity.AccountName
                      || this.opportunity.clienteNombre || 'Cliente',
            opportunityName: this.opportunity.Name || 'Cotización',
            vigInicio: this.formatDate(today),
            vigFin: this.formatDate(finVig),
            totalQuotes: quotes.length,
            columns,
            rows,
            cards,
            recomendacion,
            generatedAt: this.formatDate(today)
        };
    }

    /** @deprecated — sustituido por render declarativo bajo LWS. */
    handleDeleteOpportunity(event) {
        const id = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name || 'esta oportunidad';
        if (!id) return;
        // eslint-disable-next-line no-alert
        const confirmed = window.confirm(`¿Eliminar "${name}"? Esta acción no se puede deshacer.`);
        if (!confirmed) return;
        this.showToast('Aviso', 'La eliminación debe completarse desde el detalle del registro.', 'warning');
    }

    // ============================================================
    // WIRES (picklists)
    // ============================================================
    @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    wiredObjectInfo(result) {
        this.objectInfo = result;
    }
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: STAGE_FIELD })
    wiredStagePicklistValues({ error, data }) {
        if (data) {
            this.stagePicklistValues = data.values.map(item => ({ label: item.label, value: item.value }));
            if (!this.opportunity.StageName && this.stagePicklistValues.some(v => v.value === 'Gestion Comercial')) {
                this.opportunity.StageName = 'Gestion Comercial';
            }
        } else if (error) {
            this.stagePicklistValues = [];
        }
    }
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: TYPE_FIELD })
    wiredTypePicklistValues({ data }) { if (data) this.typePicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: CANAL_FIELD })
    wiredCanalPicklistValues({ data }) { if (data) this.canalPicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: MERCADO_FIELD })
    wiredMercadoPicklistValues({ data }) { if (data) this.mercadoPicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: RAMO_FIELD })
    wiredRamoPicklistValues({ data }) { if (data) this.ramoPicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    // Picklist de Marca (objeto Automovil__c)
    @wire(getObjectInfo, { objectApiName: AUTOMOVIL_OBJECT })
    wiredAutomovilObjectInfo(result) { this.automovilObjectInfo = result; }
    @wire(getPicklistValues, { recordTypeId: '$automovilObjectInfo.data.defaultRecordTypeId', fieldApiName: MARCA_FIELD })
    wiredMarcaPicklistValues({ data }) { if (data) this.marcaPicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    // Picklist de Frecuencia de prima (objeto Quote)
    @wire(getObjectInfo, { objectApiName: QUOTE_OBJECT })
    wiredQuoteObjectInfo(result) { this.quoteObjectInfo = result; }
    @wire(getPicklistValues, { recordTypeId: '$quoteObjectInfo.data.defaultRecordTypeId', fieldApiName: FRECUENCIA_FIELD })
    wiredFrecuenciaPicklistValues({ data }) { if (data) this.frecuenciaPicklistValues = data.values.map(i => ({ label: i.label, value: i.value })); }
    // Opciones de Frecuencia (picklist real; fallback a valores comunes).
    get frecuenciaOptions() {
        if (this.frecuenciaPicklistValues && this.frecuenciaPicklistValues.length) {
            return this.frecuenciaPicklistValues;
        }
        return [
            { label: 'Mensual', value: 'Mensual' },
            { label: 'Trimestral', value: 'Trimestral' },
            { label: 'Semestral', value: 'Semestral' },
            { label: 'Anual', value: 'Anual' },
            { label: 'Contado', value: 'Contado' }
        ];
    }

    // ============================================================
    // NAVEGACIÓN ENTRANTE
    // ============================================================
    _pendingOpportunityId = null;
    _opportunitiesLoaded = false;
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) return;
        const oppId = pageRef.state.c__opportunityId;
        if (!oppId) return;
        this._pendingOpportunityId = oppId;
        if (this._opportunitiesLoaded) {
            this.openOpportunityInEditMode(oppId);
            this._pendingOpportunityId = null;
        }
    }
    async connectedCallback() {
        await this.loadOpportunities();
        this._opportunitiesLoaded = true;
        if (this._pendingOpportunityId) {
            await this.openOpportunityInEditMode(this._pendingOpportunityId);
            this._pendingOpportunityId = null;
        }
    }
    async loadOpportunities() {
        this.isLoading = true;
        try {
            this.opportunities = await getOpportunities();
        } catch (error) {
            this.showToast('Error', 'No se pudieron cargar las oportunidades', 'error');
            this.opportunities = [];
        } finally {
            this.isLoading = false;
        }
    }

    // ============================================================
    // GETTERS DE VISTA Y LISTA
    // ============================================================
    get pageTitle() {
        if (this.viewMode === VIEW_MODES.EDIT)   return 'Editar Oportunidad';
        if (this.viewMode === VIEW_MODES.CREATE) return 'Crear Oportunidad';
        if (this.viewMode === VIEW_MODES.PDF)    return 'Crear Oportunidad desde PDFs';   // NUEVO
        return 'Oportunidades';
    }
    get createButtonLabel() {
        return this.viewMode === VIEW_MODES.EDIT ? 'Guardar Cambios' : 'Crear Oportunidad';
    }
    get showListView()   { return this.viewMode === VIEW_MODES.LIST; }
    get showCreateView() { return this.viewMode === VIEW_MODES.CREATE || this.viewMode === VIEW_MODES.EDIT; }
    get showPdfView()    { return this.viewMode === VIEW_MODES.PDF; }   // NUEVO
    get isEditMode()     { return this.viewMode === VIEW_MODES.EDIT; }

    get isOpportunityEditable() {
        if (this.viewMode === VIEW_MODES.CREATE) return true;
        return this.opportunity.StageName === 'Gestion Comercial';
    }
    get isOpportunityReadOnly() {
        return !this.isOpportunityEditable;
    }
    get readOnlyStageLabel() {
        return this.getStageLabel(this.opportunity.StageName);
    }
    get isSaveDisabled() {
        return this.isSaving || this.isOpportunityReadOnly;
    }
    get isLoadingPicklists() {
        const objectReady = !!(this.objectInfo && this.objectInfo.data);
        const stagesReady = (this.stagePicklistValues || []).length > 0;
        const ramoReady   = (this.ramoPicklistValues || []).length > 0;
        return !(objectReady && stagesReady && ramoReady);
    }
    get hasQuotes()   { return this.uploadedQuotes && this.uploadedQuotes.length > 0; }
    get quotesCount() { return this.uploadedQuotes.length; }

    get filteredOpportunities() {
        const term = (this.searchTerm || '').toLowerCase().trim();
        const stage = this.stageFilter;
        const today = new Date();
        return (this.opportunities || []).filter(opp => {
            if (term) {
                const match =
                    (opp.Name || '').toLowerCase().includes(term) ||
                    (opp.StageName || '').toLowerCase().includes(term) ||
                    (this.getStageLabel(opp.StageName) || '').toLowerCase().includes(term) ||
                    (opp.Account?.Name || '').toLowerCase().includes(term) ||
                    (opp.Owner?.Name || '').toLowerCase().includes(term);
                if (!match) return false;
            }
            if (stage && opp.StageName !== stage) return false;
            if (this.showOnlyOverdue) {
                if (this.isClosedStage(opp.StageName)) return false;
                if (!opp.CloseDate) return false;
                const cd = new Date(opp.CloseDate);
                if (isNaN(cd.getTime()) || cd >= today) return false;
            }
            return true;
        });
    }
    get opportunitiesCount() { return this.filteredOpportunities.length; }
    get hasOpportunities()   { return this.filteredOpportunities.length > 0; }
    get totalOpportunitiesAmount() {
        // Usa Prima_neta__c (campo custom de la oportunidad). Fallback a Amount
        // por compatibilidad si algún registro viejo no tiene la prima migrada.
        const total = this.filteredOpportunities.reduce(
            (sum, opp) => sum + (parseFloat(opp.Prima_neta__c) || 0), 0);
        return this.formatCurrency(total);
    }
    get totalPages() {
        return Math.max(1, Math.ceil(this.opportunitiesCount / PAGE_SIZE));
    }
    get isFirstPage() { return this.currentPage <= 1; }
    get isLastPage()  { return this.currentPage >= this.totalPages; }
    get pageInfoLabel() { return `Página ${this.currentPage} de ${this.totalPages}`; }
    get processedOpportunities() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        const end = start + PAGE_SIZE;
        const slice = this.filteredOpportunities.slice(start, end);
        const today = new Date();
        return slice.map((opp, index) => {
            // BLINDAJE: las plantillas LWC no soportan optional chaining,
            // así que aseguramos que Account y Owner SIEMPRE existan.
            // Si la oportunidad no tiene cuenta/propietario cargado, mostramos —.
            const safeAccount = opp.Account && opp.Account.Name
                ? opp.Account
                : { Name: '—' };
            const safeOwner = opp.Owner && opp.Owner.Name
                ? opp.Owner
                : { Name: '—' };
            const stage = STAGES_DATA.find(s => s.value === opp.StageName);
            const closeDate = this.parseSafeDate(opp.CloseDate);
            const hasValidCloseDate = !!closeDate;
            const isClosed = this.isClosedStage(opp.StageName);
            const isWon  = opp.StageName === 'Closed Won';
            const isLost = opp.StageName === 'Closed Lost';
            let daysRemaining = null;
            let daysLabel = '';
            let daysClass = 'days-remaining';
            if (hasValidCloseDate && !isClosed) {
                const diff = Math.ceil((closeDate - today) / 86400000);
                daysRemaining = diff;
                if (diff < 0) {
                    daysLabel = `Vencida hace ${Math.abs(diff)} día${Math.abs(diff) === 1 ? '' : 's'}`;
                    daysClass = 'days-remaining is-overdue';
                } else if (diff === 0) {
                    daysLabel = 'Vence hoy';
                    daysClass = 'days-remaining is-due-today';
                } else {
                    daysLabel = `${diff} día${diff === 1 ? '' : 's'} restantes`;
                    daysClass = 'days-remaining is-active';
                }
            }
            let statusClass = 'status-active';
            if (isWon) statusClass = 'status-won';
            else if (isLost) statusClass = 'status-lost';
            else if (hasValidCloseDate && closeDate < today) statusClass = 'status-overdue';
            const stageColor = stage?.color || STAGE_DEFAULT_COLOR;
            const stageLabel = this.getStageLabel(opp.StageName);
            const stageIcon  = stage?.icon || 'utility:steps';
            const probability = stage?.probability ?? 0;
            return {
                ...opp,
                // Sobreescribimos Account/Owner con las versiones seguras
                Account: safeAccount,
                Owner: safeOwner,
                index,
                displayNumber: (this.currentPage - 1) * PAGE_SIZE + index + 1,
                stageLabel,
                stageIcon,
                statusClass,
                stageStyle: `background-color: ${stageColor}; color: #fff;`,
                progressBarStyle: `width: ${probability}%; background-color: ${stageColor};`,
                progressText: `${probability}% de probabilidad`,
                amountFormatted: this.formatCurrency(opp.Prima_neta__c ?? opp.Prima_Neta__c ?? opp.Prima_Total__c ?? opp.Amount),
                closeDateFormatted: this.formatDate(opp.CloseDate),
                createdDateFormatted: opp.CreatedDate ? this.formatDate(opp.CreatedDate) : '',
                daysRemaining,
                daysLabel,
                daysClass,
                hasDaysInfo: !!daysLabel,
                isOverdue: statusClass === 'status-overdue',
                isClosed,
                typeLabel: this.getTypeLabel(opp.Type)
            };
        });
    }
    parseSafeDate(value) {
        if (!value) return null;
        const d = new Date(value);
        if (isNaN(d.getTime())) return null;
        if (d.getFullYear() < 1970) return null;
        return d;
    }
    isClosedStage(stageName) {
        return stageName === 'Closed Won' || stageName === 'Closed Lost';
    }
    getStageLabel(value) {
        if (!value) return '';
        const stage = STAGES_DATA.find(s => s.value === value);
        return stage ? stage.label : value;
    }
    getTypeLabel(type) {
        if (!type) return '';
        const map = {
            'New_Business': 'Nueva',
            'Internal_Renewal': 'Renovación interna',
            'External_Renewal': 'Renovación externa',
            'Reissue': 'Reexpedición'
        };
        return map[type] || type;
    }

    // ============================================================
    // HANDLERS DE FORMULARIO
    // ============================================================
    handleInputChange(event) {
        const field = event.target.dataset.field;
        if (field) this.opportunity[field] = event.target.value;
    }
    handleComboboxChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.detail.value;
        this.opportunity = { ...this.opportunity, [field]: value };
        // Si el Mercado es Individual, el Contacto es el mismo que la Cuenta.
        if (field === 'Mercado__c') {
            this.syncContactoConMercado();
        }
    }

    // Cuando el Mercado es Individual, el Contacto se toma de la Cuenta (se
    // resuelve en el Apex al guardar). Cuando no, se usa el buscador de contactos.
    syncContactoConMercado() {
        if (this.isMercadoIndividual) {
            this.isNewContacto = false;
            this.showContactoDropdown = false;
            this.contactoResults = [];
            this.opportunity = {
                ...this.opportunity,
                Contacto__c: null,
                ContactoName: this.opportunity.AccountName || ''
            };
        }
    }
    handleAutomovilChange(event) {
        const field = event.target.dataset?.field?.replace('automovil.', '');
        // event.detail.value para combobox (Marca); event.target.value para inputs.
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value : event.target.value;
        if (field && Object.prototype.hasOwnProperty.call(this.automovil, field)) {
            this.automovil = { ...this.automovil, [field]: value };
        }
    }
    handleGMMChange(event) {
        const field = event.target.dataset?.field?.replace('gmm.', '');
        if (field && Object.prototype.hasOwnProperty.call(this.gmm, field)) {
            this.gmm[field] = event.detail?.value || event.target.value;
        }
    }
    handleVidaChange(event) {
        const field = event.target.dataset?.field?.replace('vida.', '');
        if (field && Object.prototype.hasOwnProperty.call(this.vida, field)) {
            this.vida[field] = event.detail?.value || event.target.value;
        }
    }
    handleViajeChange(event) {
        const field = event.target.dataset?.field?.replace('viaje.', '');
        if (field && Object.prototype.hasOwnProperty.call(this.viaje, field)) {
            this.viaje[field] = event.detail?.value || event.target.value;
        }
    }
    handleDanosChange(event) {
        const field = event.target.dataset?.field?.replace('danos.', '');
        if (field && Object.prototype.hasOwnProperty.call(this.danos, field)) {
            this.danos[field] = event.detail?.value || event.target.value;
        }
    }
    handleClienteChange(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.target.value;
        const updated = { ...this.opportunity, [field]: value };
        if (this.isNewAccount && (field === 'clienteNombre' || field === 'clienteApellidos')) {
            if (updated.tipoCliente === 'Persona') {
                updated.AccountName = `${updated.clienteNombre || ''} ${updated.clienteApellidos || ''}`.trim();
            } else {
                updated.AccountName = updated.clienteNombre || '';
            }
        }
        this.opportunity = updated;
    }

    async handleComparisonComplete(event) {
        try {
            if (!event || !event.detail) return;
            const { cotizaciones, total } = event.detail;
            if (!cotizaciones || cotizaciones.length === 0) return;
            this.comparisonData = {
                totalQuotes: total || cotizaciones.length,
                bestPriceCompany: this.findBestPrice(cotizaciones),
                bestPriceAmount: this.findBestPriceAmount(cotizaciones),
                bestCoverageCompany: this.findBestCoverage(cotizaciones),
                bestCoverageAmount: this.findBestCoverageAmount(cotizaciones),
                selectedCompanies: this.extractCompanies([]),
                rawData: { cotizaciones }
            };
            this.showComparisonSummary = true;
            this.showToast('Éxito', `Se procesaron ${cotizaciones.length} cotizaciones`, 'success');
        } catch (error) {
            this.showToast('Error', 'Error al procesar las cotizaciones', 'error');
        }
    }

    // ============================================================
    // MEJOR PRECIO / MEJOR COBERTURA (uploadedQuotes)
    // ============================================================
    findBestPrice(cotizaciones) {
        if (!cotizaciones || cotizaciones.length === 0) return '';
        let best = Infinity, company = '';
        cotizaciones.forEach(c => {
            const p = parseFloat(c.primaTotal) || 0;
            if (p > 0 && p < best) { best = p; company = c.compania || ''; }
        });
        this.mejorPrecioCompania = company;
        this.mejorPrecioMonto = best === Infinity ? 0 : best;
        return company;
    }
    findBestPriceAmount(cotizaciones) {
        if (!cotizaciones || cotizaciones.length === 0) return 0;
        let best = Infinity;
        cotizaciones.forEach(c => {
            const p = parseFloat(c.primaTotal) || 0;
            if (p > 0 && p < best) best = p;
        });
        return best === Infinity ? 0 : best;
    }
    findBestCoverage(cotizaciones) {
        if (!cotizaciones || cotizaciones.length === 0) return '';
        let max = 0, company = '';
        cotizaciones.forEach(c => {
            const n = (c.tablaCompletaCoberturas?.length || 0) +
                      (c.coberturasViaje?.length || 0) +
                      (c.riesgosAmparados?.length || 0);
            if (n > max) { max = n; company = c.compania || ''; }
        });
        this.mejorCoberturaCompania = company;
        this.mejorCoberturaMonto = max;
        return company;
    }
    findBestCoverageAmount(cotizaciones) {
        if (!cotizaciones || cotizaciones.length === 0) return 0;
        let max = 0;
        cotizaciones.forEach(c => {
            const n = (c.tablaCompletaCoberturas?.length || 0) +
                      (c.coberturasViaje?.length || 0) +
                      (c.riesgosAmparados?.length || 0);
            if (n > max) max = n;
        });
        return max;
    }
    extractCompanies(table) {
        if (!table?.length) return [];
        const set = new Set();
        table.forEach(row => {
            if (row.datos) row.datos.forEach(d => { if (d.compania) set.add(d.compania); });
        });
        return Array.from(set);
    }

    // ============================================================
    // NORMALIZACIÓN Y EXTRACCIÓN DE PDF
    // ============================================================
    normalizeQuoteData(quote) {
        if (!quote || typeof quote !== 'object') quote = {};
        const safeString  = v => (v === null || v === undefined ? '' : String(v));
        const safeNumber  = v => { if (v === null || v === undefined) return 0; const n = parseFloat(v); return isNaN(n) ? 0 : n; };
        const safeBoolean = v => (v === null || v === undefined ? false : (typeof v === 'string' ? v.toLowerCase() === 'true' : Boolean(v)));
        const ramoParaUsar = this.selectedQuoteRamo || quote.ramo || 'DESCONOCIDO';
        return {
            id: safeString(quote.id) || `quote-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            nombreArchivo: safeString(quote.nombreArchivo) || 'documento.pdf',
            compania: safeString(quote.compania) || 'Desconocida',
            ramo: ramoParaUsar,
            ramoLabel: this.getRamoLabel(ramoParaUsar),
            primaTotal: safeNumber(quote.primaTotal),
            primaTotalFormatted: safeString(quote.primaTotalFormatted) || this.formatCurrency(safeNumber(quote.primaTotal)),
            extractionConfidence: safeNumber(quote.extractionConfidence),
            isExpanded: quote.isExpanded !== undefined ? quote.isExpanded : true,
            marca: safeString(quote.marca), modelo: safeString(quote.modelo),
            placa: safeString(quote.placa), serie: safeString(quote.serie),
            motor: safeString(quote.motor), descripcion: safeString(quote.descripcion),
            destino: safeString(quote.destino), numViajeros: safeNumber(quote.numViajeros) || 1,
            fechaSalida: safeString(quote.fechaSalida),
            edadVida: safeNumber(quote.edadVida),
            sumaFallecimiento: safeString(quote.sumaFallecimiento),
            aportacionAnual: safeString(quote.aportacionAnual),
            tipoRC: safeString(quote.tipoRC),
            sumaAsegurada: safeString(quote.sumaAsegurada),
            deducible: safeString(quote.deducible),
            coaseguro: safeString(quote.coaseguro),
            redHospitalaria: safeString(quote.redHospitalaria),
            asegurados: quote.asegurados || [],
            bienesCubiertos: safeString(quote.bienesCubiertos),
            limiteEmbarque: safeString(quote.limiteEmbarque),
            clienteNombre: safeString(quote.clienteNombre),
            clienteRFC: safeString(quote.clienteRFC),
            clienteEmail: safeString(quote.clienteEmail),
            clienteTelefono: safeString(quote.clienteTelefono),
            clienteCP: safeString(quote.clienteCP),
            clienteDireccion: safeString(quote.clienteDireccion),
            tablaCompletaCoberturas: quote.tablaCompletaCoberturas || [],
            hasCoberturas: safeBoolean(quote.hasCoberturas),
            coberturasCount: safeNumber(quote.coberturasCount),
            isAutomovil: safeBoolean(quote.isAutomovil),
            isDanos: safeBoolean(quote.isDanos),
            isDental: safeBoolean(quote.isDental),
            isEmpresarial: safeBoolean(quote.isEmpresarial),
            isFianzas: safeBoolean(quote.isFianzas),
            isGastosMedicos: safeBoolean(quote.isGastosMedicos),
            isRC: safeBoolean(quote.isRC),
            isViaje: safeBoolean(quote.isViaje),
            isVida: safeBoolean(quote.isVida),
            isVision: safeBoolean(quote.isVision),
            isTransporte: safeBoolean(quote.isTransporte),
            fechaExtraccion: safeString(quote.fechaExtraccion) || new Date().toISOString(),
            ramoIcon: this.getRamoIcon(ramoParaUsar),
            confidenceBarStyle: safeString(quote.confidenceBarStyle),
            confidenceTextStyle: safeString(quote.confidenceTextStyle),
            uploadDateFormatted: safeString(quote.uploadDateFormatted),
            expandIcon: safeString(quote.expandIcon) || 'utility:chevronup',
            expandText: safeString(quote.expandText) || 'Colapsar'
        };
    }
    async handlePDFDataExtracted(event) {
        try {
            if (!event) return;
            const quote = event.detail || {};
            if (!quote.id) return;
            const ramo = quote.ramo || 'DESCONOCIDO';
            const ramoNormalizado = this.normalizarRamoParaCSS(ramo);
            const flags = {
                isViaje: this.matchRamo(ramo, ['VIAJE','VIAJES']) || ramoNormalizado === 'Viaje',
                isAutomovil: this.matchRamo(ramo, ['AUTOMOVIL','AUTO','AUTOMOVILES']) || ramoNormalizado === 'Automóvil',
                isGastosMedicos: this.matchRamo(ramo, ['GMM','GASTOS_MEDICOS','GASTOS MÉDICOS']) || ramoNormalizado === 'Gastos Médicos',
                isRC: this.matchRamo(ramo, ['RC','RESPONSABILIDAD_CIVIL','RESPONSABILIDAD CIVIL']) || ramoNormalizado === 'Responsabilidad Civil',
                isVida: this.matchRamo(ramo, ['VIDA']) || ramoNormalizado === 'Vida',
                isHogar: this.matchRamo(ramo, ['HOGAR']) || ramoNormalizado === 'Hogar',
                isMascotas: this.matchRamo(ramo, ['MASCOTAS']) || ramoNormalizado === 'Mascotas',
                isTransporte: this.matchRamo(ramo, ['TRANSPORTE']) || ramoNormalizado === 'Transporte',
                isEmpresarial: this.matchRamo(ramo, ['EMPRESARIAL']) || ramoNormalizado === 'Empresarial',
                isDental: this.matchRamo(ramo, ['DENTAL']) || ramoNormalizado === 'Dental',
                isDanos: this.matchRamo(ramo, ['DANOS','DAÑOS']) || ramoNormalizado === 'Daños',
                isVision: this.matchRamo(ramo, ['VISION','VISIÓN']) || ramoNormalizado === 'Visión'
            };
            const tablaCompletaCoberturas = quote.tablaCompletaCoberturas || [];
            const hasCoberturas = tablaCompletaCoberturas.length > 0;
            const quoteWithDefaults = {
                id: quote.id,
                nombreArchivo: quote.nombreArchivo || 'documento.pdf',
                compania: quote.compania || 'Desconocida',
                ramo,
                ramoLabel: quote.ramoLabel || this.getRamoLabel(ramo),
                plan: quote.plan || 'No especificado',
                primaTotal: this.extractPrimaTotal(quote) || 0,
                primaTotalFormatted: quote.primaTotalFormatted || this.formatCurrency(this.extractPrimaTotal(quote) || 0),
                extractionConfidence: quote.extractionConfidence || 0,
                fechaExtraccion: quote.fechaExtraccion || new Date().toISOString(),
                tablaCompletaCoberturas,
                hasCoberturas,
                coberturasCount: tablaCompletaCoberturas.length,
                isExpanded: true,
                expandIcon: 'utility:chevronup',
                expandText: 'Colapsar',
                showClienteInfo: false,
                clienteIcon: 'utility:chevronright',
                showCoberturas: false,
                coberturasIcon: 'utility:chevronright',
                ...flags,
                ...this.extractRamoSpecificData(quote, flags),
                clienteNombre: quote.clienteNombre || '',
                clienteRFC: quote.clienteRFC || '',
                clienteEmail: quote.clienteEmail || '',
                clienteTelefono: quote.clienteTelefono || '',
                clienteCP: quote.clienteCP || '',
                clienteDireccion: quote.clienteDireccion || '',
                formaPago: quote.formaPago || '',
                vigencia: quote.vigencia || '',
                moneda: quote.moneda || 'MXN'
            };
            const quoteWithKeys = this.procesarArraysParaKeys(quoteWithDefaults);
            const confidenceColor = this.getConfidenceColor(quoteWithKeys.extractionConfidence || 0);
            const quoteFinal = {
                ...quoteWithKeys,
                confidenceBarStyle: `width: ${quoteWithKeys.extractionConfidence}%; background-color: ${confidenceColor};`,
                confidenceTextStyle: `color: ${confidenceColor}; font-weight: bold;`,
                uploadDateFormatted: new Date(quoteWithKeys.fechaExtraccion).toLocaleDateString('es-MX', {
                    day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'
                }),
                ramoIcon: this.getRamoIcon(ramoNormalizado)
            };
            const quoteWithIndex = { ...quoteFinal, index: this.uploadedQuotes.length + 1 };
            const existingIndex = this.uploadedQuotes.findIndex(q => q && q.id === quoteWithIndex.id);
            if (existingIndex >= 0) {
                this.uploadedQuotes = [
                    ...this.uploadedQuotes.slice(0, existingIndex),
                    quoteWithIndex,
                    ...this.uploadedQuotes.slice(existingIndex + 1)
                ];
            } else {
                this.uploadedQuotes = [...this.uploadedQuotes, quoteWithIndex];
            }
            try {
                this.updateOpportunityFromExtractedData(quoteWithIndex);
                this.updateBestQuote();
            } catch (e) { /* ignorar */ }
            this.recomputeComparativa();
            this.setPrimaNetaFromQuotes();
            this.hasExtractedData = true;
            this.showToast('Éxito', `PDF procesado: ${quote.compania || 'Desconocido'} - ${quoteWithIndex.ramoLabel}`, 'success');
        } catch (error) {
            this.showToast('Error', `Error al procesar el PDF: ${error.message || 'Error desconocido'}`, 'error');
        }
    }
    matchRamo(ramo, keywords) {
        if (!ramo) return false;
        const up = String(ramo).toUpperCase();
        return keywords.some(k => up.includes(k));
    }
    extractRamoSpecificData(quote, flags) {
        if (flags.isViaje) {
            return {
                destino: quote.destino || '', origen: quote.origen || 'México',
                numViajeros: quote.numViajeros || 1, fechaSalida: quote.fechaSalida || '',
                fechaLlegada: quote.fechaLlegada || '', duracion: quote.duracion || '',
                plan: quote.plan || '', coberturasViaje: quote.coberturasViaje || [],
                asistenciasIncluidas: quote.asistenciasIncluidas || []
            };
        }
        if (flags.isAutomovil) {
            return {
                marca: quote.marca || '', modelo: quote.modelo || '',
                placa: quote.placa || '', serie: quote.serie || '',
                motor: quote.motor || '', anio: quote.anio || '',
                uso: quote.uso || '', servicio: quote.servicio || '',
                descripcion: quote.descripcion || ''
            };
        }
        if (flags.isGastosMedicos) {
            return {
                plan: quote.plan || '', sumaAsegurada: quote.sumaAsegurada || '',
                deducible: quote.deducible || '', coaseguro: quote.coaseguro || '',
                topeCoaseguro: quote.topeCoaseguro || '', redHospitalaria: quote.redHospitalaria || '',
                tabuladorMedico: quote.tabuladorMedico || '', lugarResidencia: quote.lugarResidencia || '',
                tipoNegocio: quote.tipoNegocio || '', maternidad: quote.maternidad || false,
                asegurados: quote.asegurados || [],
                primaNeta: quote.primaNeta || '', primaTotal: quote.primaTotal || 0,
                iva: quote.iva || '', derechoPoliza: quote.derechoPoliza || ''
            };
        }
        if (flags.isRC) {
            return {
                tipoRC: quote.tipoRC || '', tipoEspecifico: quote.tipoEspecifico || '',
                profesion: quote.profesion || '', actividad: quote.actividad || '',
                giro: quote.giro || '', sumaAsegurada: quote.sumaAsegurada || '',
                deducible: quote.deducible || ''
            };
        }
        if (flags.isVida) {
            return {
                edadVida: quote.edadVida || '', sexoVida: quote.sexoVida || '',
                fumador: quote.fumador || false, ocupacion: quote.ocupacion || '',
                sumaFallecimiento: quote.sumaFallecimiento || '', sumaInvalidez: quote.sumaInvalidez || '',
                aportacionAnual: quote.aportacionAnual || '', plazo: quote.plazo || ''
            };
        }
        if (flags.isTransporte) {
            return {
                bienesCubiertos: quote.bienesCubiertos || '', medioTransporte: quote.medioTransporte || '',
                origen: quote.origen || '', destino: quote.destino || '',
                limiteEmbarque: quote.limiteEmbarque || '', riesgosAmparados: quote.riesgosAmparados || []
            };
        }
        return {};
    }
    extractPrimaTotal(quote) {
        if (!quote) return 0;
        const posibles = [quote.Prima_neta__c, quote['Prima Neta'], quote.total, quote.monto];
        for (const p of posibles) {
            if (p) {
                const n = parseFloat(p);
                if (!isNaN(n) && n > 0) return n;
            }
        }
        return 0;
    }
    updateBestQuote() {
        if (this.uploadedQuotes.length === 0) return;
        const best = [...this.uploadedQuotes].sort((a, b) => {
            const ca = a.extractionConfidence || 0, cb = b.extractionConfidence || 0;
            if (ca !== cb) return cb - ca;
            const pa = a.primaTotal || 0, pb = b.primaTotal || 0;
            if (pa > 0 && pb > 0) return pa - pb;
            if (pa > 0) return -1;
            if (pb > 0) return 1;
            return 0;
        })[0];
        this.updateOpportunityFromExtractedData(best);
    }

    // ============================================================
    // NORMALIZACIÓN DE NOMBRES
    // ============================================================
    normalizarRamoParaCSS(ramo) {
        if (!ramo) return 'Desconocido';
        const u = String(ramo).toUpperCase();
        const mapping = {
            'AUTOMOVIL': 'Automóvil', 'AUTO': 'Automóvil',
            'GASTOS_MEDICOS': 'Gastos Médicos', 'GMM': 'Gastos Médicos',
            'VIDA': 'Vida', 'VIAJE': 'Viaje', 'VIAJES': 'Viaje',
            'HOGAR': 'Hogar', 'DANOS': 'Daños', 'DAÑOS': 'Daños',
            'MASCOTAS': 'Mascotas', 'EMPRESARIAL': 'Empresarial',
            'RESPONSABILIDAD_CIVIL': 'Responsabilidad Civil', 'RC': 'Responsabilidad Civil',
            'TRANSPORTE': 'Transporte', 'FIANZAS': 'Fianzas',
            'DENTAL': 'Dental', 'VISION': 'Visión'
        };
        for (const [key, value] of Object.entries(mapping)) if (u.includes(key)) return value;
        return ramo;
    }
    getRamoLabel(ramo) {
        if (!ramo) return 'Desconocido';
        const labels = {
            'AUTOMOVIL': 'Automóvil', 'AUTOMOVILES': 'Automóvil', 'AUTO': 'Automóvil',
            'GASTOS_MEDICOS': 'Gastos Médicos', 'GMM': 'Gastos Médicos',
            'VIDA': 'Vida', 'VIAJE': 'Viaje', 'VIAJES': 'Viaje',
            'HOGAR': 'Hogar', 'DANOS': 'Daños', 'DAÑOS': 'Daños',
            'MASCOTAS': 'Mascotas', 'EMPRESARIAL': 'Empresarial',
            'RESPONSABILIDAD_CIVIL': 'Responsabilidad Civil', 'RC': 'Responsabilidad Civil',
            'TRANSPORTE': 'Transporte', 'FIANZAS': 'Fianzas',
            'DENTAL': 'Dental', 'VISION': 'Visión'
        };
        return labels[String(ramo).toUpperCase()] || ramo;
    }
    getRamoIcon(ramo) {
        if (!ramo) return 'utility:question';
        const icons = {
            'AUTOMOVIL': 'utility:car', 'AUTOMOVILES': 'utility:car', 'AUTO': 'utility:car',
            'GASTOS_MEDICOS': 'utility:health', 'GMM': 'utility:health',
            'VIDA': 'utility:heart', 'VIAJE': 'utility:flight', 'VIAJES': 'utility:flight',
            'HOGAR': 'utility:home', 'DANOS': 'utility:warning', 'DAÑOS': 'utility:warning',
            'MASCOTAS': 'utility:animal_and_nature', 'EMPRESARIAL': 'utility:company',
            'RESPONSABILIDAD_CIVIL': 'utility:law', 'RC': 'utility:law',
            'TRANSPORTE': 'utility:ship', 'FIANZAS': 'utility:money',
            'DENTAL': 'utility:tooth', 'VISION': 'utility:eye'
        };
        return icons[String(ramo).toUpperCase()] || 'utility:document';
    }
    procesarArraysParaKeys(quote) {
        if (!quote) return quote;
        const r = { ...quote };
        if (Array.isArray(r.tablaCompletaCoberturas)) {
            r.tablaCompletaCoberturas = r.tablaCompletaCoberturas.map((item, idx) => ({
                ...item,
                key: `cobertura-${quote.id}-${idx}-${(item.cobertura || item.nombre || 'cov').replace(/\s+/g, '-')}`
            }));
        }
        if (Array.isArray(r.asegurados)) {
            r.asegurados = r.asegurados.map((item, idx) => ({
                ...item,
                key: `asegurado-${quote.id}-${idx}-${(item.nombre || 'aseg').replace(/\s+/g, '-')}`
            }));
        }
        if (Array.isArray(r.coberturasViaje)) {
            r.coberturasViaje = r.coberturasViaje.map((item, idx) => ({
                ...item,
                key: `cov-viaje-${quote.id}-${idx}-${(item.nombre || 'cov').replace(/\s+/g, '-')}`,
                uniqueKey: `cov-viaje-${quote.id}-${idx}`
            }));
        }
        if (Array.isArray(r.riesgosAmparados)) {
            r.riesgosAmparados = r.riesgosAmparados.map((item, idx) => ({
                ...item,
                key: `riesgo-${quote.id}-${idx}-${(item.nombre || 'riesgo').replace(/\s+/g, '-')}`,
                uniqueKey: `riesgo-${quote.id}-${idx}`
            }));
        }
        return r;
    }
    getConfidenceColor(c) {
        if (c >= 80) return '#00875A';
        if (c >= 60) return '#FF8C00';
        return '#DE350B';
    }

    // ============================================================
    // ACTUALIZAR OPORTUNIDAD DESDE DATOS EXTRAÍDOS
    // ============================================================
    updateOpportunityFromExtractedData(extractedData) {
        if (!extractedData || Array.isArray(extractedData)) return;
        try {
            if (!this.opportunity.Name && extractedData.compania) {
                const ramoLabel = extractedData.ramoLabel || extractedData.ramo || 'Seguro';
                const clienteNombre = extractedData.clienteNombre || 'Cliente';
                this.opportunity.Name = `${ramoLabel} - ${extractedData.compania} - ${clienteNombre}`.substring(0, 80);
            }
            if (!this.opportunity.Ramo__c) {
                const mapped = this.mapRamoToOption(extractedData.ramo);
                if (mapped) this.opportunity.Ramo__c = mapped;
            }
            if (!this.opportunity.Prima_neta__c && extractedData.primaTotal) {
                this.opportunity.Prima_neta__c = extractedData.primaTotal;
            }
            if (extractedData.clienteNombre    && !this.opportunity.clienteNombre)    this.opportunity.clienteNombre    = extractedData.clienteNombre;
            if (extractedData.clienteEmail     && !this.opportunity.clienteEmail)     this.opportunity.clienteEmail     = extractedData.clienteEmail;
            if (extractedData.clienteTelefono  && !this.opportunity.clienteTelefono)  this.opportunity.clienteTelefono  = extractedData.clienteTelefono;
            if (extractedData.clienteRFC       && !this.opportunity.clienteRFC)       this.opportunity.clienteRFC       = extractedData.clienteRFC;
            if (extractedData.clienteCP        && !this.opportunity.clienteCP)        this.opportunity.clienteCP        = extractedData.clienteCP;
            if (extractedData.clienteDireccion && !this.opportunity.clienteDireccion) this.opportunity.clienteDireccion = extractedData.clienteDireccion;
            if (extractedData.marca || extractedData.modelo) {
                this.automovil = {
                    ...this.automovil,
                    Marca__c:  extractedData.marca  || this.automovil.Marca__c,
                    Modelo__c: extractedData.modelo || this.automovil.Modelo__c,
                    Placa__c:  extractedData.placa  || this.automovil.Placa__c,
                    Serie__c:  extractedData.serie  || this.automovil.Serie__c,
                    Motor__c:   extractedData.motor   || this.automovil.Motor__c,
                    descripcion_completa__c: extractedData.descripcion || this.automovil.descripcion_completa__c
                };
            }
            // ===== GMM (Gastos Médicos) =====
            if (extractedData.numAsegurados)  this.gmm.numAsegurados  = extractedData.numAsegurados;
            if (extractedData.tipoEstructura) this.gmm.tipoEstructura = extractedData.tipoEstructura;
            if (extractedData.estado)         this.gmm.estado         = extractedData.estado;
            if (extractedData.asegurados && extractedData.asegurados.length > 0 && !extractedData.numAsegurados) {
                this.gmm.tipoEstructura = this.gmm.tipoEstructura
                    || (extractedData.asegurados.length > 1 ? 'Familiar' : 'Individual');
                this.gmm.numAsegurados = extractedData.asegurados.length;
            }
            if (extractedData.redHospitalaria) this.gmm.redHospitalaria = extractedData.redHospitalaria;

            // ===== Viajes =====
            if (extractedData.destino)     this.viaje.destino      = extractedData.destino;
            if (extractedData.numViajeros) this.viaje.numPasajeros = extractedData.numViajeros;
            if (extractedData.fechaSalida) this.viaje.fechaSalida  = extractedData.fechaSalida;

            // ===== Vida =====
            if (extractedData.aseguradoPrincipal) this.vida.aseguradoPrincipal = extractedData.aseguradoPrincipal;
            if (extractedData.contratante)        this.vida.contratante        = extractedData.contratante;
            if (extractedData.edadVida)           this.vida.edadVida           = extractedData.edadVida;

            // ===== Subramo: a Daños o a Vida según el ramo =====
            if (extractedData.subramo) {
                if (this.opportunity.Ramo__c === RAMO_TYPES.DANOS) {
                    this.danos.subramo = extractedData.subramo;
                } else {
                    this.vida.subramo = extractedData.subramo;
                }
            }

            // ===== Ramos con sección propia (Empresarial, Fianzas, RC, Dental, Visión) =====
            const ramoActual = this.opportunity.Ramo__c;
            if (ramoActual === RAMO_TYPES.EMPRESARIAL) {
                this.empresarial = {
                    ...this.empresarial,
                    giro: extractedData.giro || this.empresarial.giro,
                    actividad: extractedData.actividad || this.empresarial.actividad,
                    ubicacion: extractedData.ubicacion || this.empresarial.ubicacion,
                    valorInmueble: extractedData.valorInmueble || this.empresarial.valorInmueble,
                    valorContenidos: extractedData.valorContenidos || this.empresarial.valorContenidos
                };
            } else if (ramoActual === RAMO_TYPES.FIANZAS) {
                this.fianzas = {
                    ...this.fianzas,
                    tipoFianza: extractedData.tipoFianza || this.fianzas.tipoFianza,
                    fiado: extractedData.fiado || this.fianzas.fiado,
                    beneficiario: extractedData.beneficiario || this.fianzas.beneficiario,
                    montoAfianzado: extractedData.montoAfianzado || this.fianzas.montoAfianzado
                };
            } else if (ramoActual === RAMO_TYPES.RESPONSABILIDAD_CIVIL) {
                this.rc = {
                    ...this.rc,
                    tipoRC: extractedData.tipoRC || this.rc.tipoRC,
                    profesion: extractedData.profesion || this.rc.profesion,
                    actividad: extractedData.actividad || this.rc.actividad,
                    giro: extractedData.giro || this.rc.giro
                };
            } else if (ramoActual === RAMO_TYPES.DENTAL) {
                this.dental = {
                    ...this.dental,
                    plan: extractedData.plan || this.dental.plan,
                    numAsegurados: extractedData.numAsegurados || this.dental.numAsegurados,
                    red: extractedData.red || this.dental.red
                };
            } else if (ramoActual === RAMO_TYPES.VISION) {
                this.vision = {
                    ...this.vision,
                    plan: extractedData.plan || this.vision.plan,
                    numAsegurados: extractedData.numAsegurados || this.vision.numAsegurados,
                    red: extractedData.red || this.vision.red
                };
            }

            this.applyCanalRules(extractedData);
            this.extractedOpportunityData = extractedData;
        } catch (e) { /* ignore */ }
    }
    mapRamoToOption(ramoDetectado) {
        if (!ramoDetectado) return null;
        const u = ramoDetectado.toUpperCase();
        const mapping = {
            'AUTOMOVIL': RAMO_TYPES.AUTOMOVIL, 'AUTO': RAMO_TYPES.AUTOMOVIL,
            'VEHICULO': RAMO_TYPES.AUTOMOVIL, 'CARRO': RAMO_TYPES.AUTOMOVIL,
            'VIAJE': RAMO_TYPES.VIAJE, 'TRAVEL': RAMO_TYPES.VIAJE, 'VIAJES': RAMO_TYPES.VIAJE,
            'GASTOS_MEDICOS': RAMO_TYPES.GASTOS_MEDICOS, 'GMM': RAMO_TYPES.GASTOS_MEDICOS,
            'GASTOS MEDICOS': RAMO_TYPES.GASTOS_MEDICOS, 'MEDICO': RAMO_TYPES.GASTOS_MEDICOS,
            'VIDA': RAMO_TYPES.VIDA, 'LIFE': RAMO_TYPES.VIDA,
            'DANOS': RAMO_TYPES.DANOS, 'DAÑOS': RAMO_TYPES.DANOS,
            'HOGAR': RAMO_TYPES.DANOS, 'MASCOTAS': RAMO_TYPES.DANOS,
            'RESPONSABILIDAD CIVIL': RAMO_TYPES.RESPONSABILIDAD_CIVIL, 'RC': RAMO_TYPES.RESPONSABILIDAD_CIVIL,
            'EMPRESARIAL': RAMO_TYPES.EMPRESARIAL, 'BUSINESS': RAMO_TYPES.EMPRESARIAL,
            'FIANZAS': RAMO_TYPES.FIANZAS, 'DENTAL': RAMO_TYPES.DENTAL, 'VISION': RAMO_TYPES.VISION
        };
        for (const [k, v] of Object.entries(mapping)) if (u.includes(k)) return v;
        return null;
    }
    applyCanalRules(quoteData) {
        const directos = ['Avanza Seguro Consultores', 'Abraham González'];
        const agente = quoteData.agente;
        if (agente && directos.includes(agente)) this.opportunity.Canal__c = 'Directo';
        else if (agente)                          this.opportunity.Canal__c = 'Agente';
        else if (quoteData.origen === 'web' || quoteData.origen === 'digital') this.opportunity.Canal__c = 'Digital';
    }

    // ============================================================
    // GUARDAR
    // ============================================================
    async saveOpportunity() {
        if (this.isSaving) return;
        if (this.isOpportunityReadOnly) {
            this.showToast('Bloqueado',
                'Esta oportunidad ya no está en etapa Gestión Comercial; sus datos no se pueden modificar.','warning');
            return;
        }
        this.isSaving = true;
        this.isLoading = true;
        try {
            if (!this.opportunity.Name)     { this.showToast('Error', 'El nombre de la oportunidad es requerido', 'error'); return; }
            if (!this.opportunity.StageName){ this.showToast('Error', 'La etapa es requerida', 'error'); return; }
            if (!this.opportunity.Ramo__c)  { this.showToast('Error', 'El ramo es requerido', 'error'); return; }
            // Serie (VIN) obligatoria cuando el ramo es Automóviles.
            if (this.isRamoAutomovil && !(this.automovil && this.automovil.Serie__c && String(this.automovil.Serie__c).trim())) {
                this.showToast('Error', 'El número de serie (VIN) del vehículo es obligatorio.', 'error');
                return;
            }
            if (!this.opportunity.AccountId && !this.isNewAccount) {
                this.showToast('Error', 'Selecciona una cuenta o elige "Crear cuenta nueva".', 'error');
                return;
            }
            if (this.isNewAccount) {
                let newAccName = this.opportunity.AccountName;
                if (!newAccName) {
                    if (this.opportunity.tipoCliente === 'Persona') {
                        newAccName = `${this.opportunity.clienteNombre || ''} ${this.opportunity.clienteApellidos || ''}`.trim();
                    } else {
                        newAccName = this.opportunity.clienteNombre || '';
                    }
                }
                if (!newAccName) {
                    this.showToast('Error',
                        'Captura el nombre del cliente en "Información del Cliente" para crear la cuenta nueva.',
                        'error');
                    return;
                }
                this.opportunity = { ...this.opportunity, AccountName: newAccName };
            }
            // Payload: oportunidad + detalle del ramo + datos del auto (para Vehiculo__c)
            const payload = {
                ...this.opportunity,
                Automovil__c: this.opportunity.Vehiculo__c || null,
                isNewContacto: this.isNewContacto,
                Descripcion__c: this.comparativoHtml || null,
                detalleRamo: this.getActiveRamoDetail(),
                vehiculo: this.automovil
            };
            const savedId = await apexSaveOpportunity({
                opportunityJson: JSON.stringify(payload),
                isNewAccount: this.isNewAccount
            });
            if (savedId) {
                this.opportunity = { ...this.opportunity, Id: savedId };
            }
            this.showToast('Éxito',
                this.isEditMode ? 'Oportunidad actualizada correctamente' : 'Oportunidad creada correctamente',
                'success');
            await this.loadOpportunities();

            if (this.hasPdfQuotes && savedId) {
                // Venimos del flujo de PDFs: nos quedamos en la oportunidad para
                // validar la comparativa y crear las cotizaciones al confirmar.
                this.viewMode = VIEW_MODES.EDIT;
            } else {
                setTimeout(() => this.handleBackToList(), 1000);
            }
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error(':::OpportunityCreator::: Error al guardar', error);
            const msg = error?.body?.message || error?.message || 'Error al guardar la oportunidad';
            this.showToast('Error', msg, 'error');
        } finally {
            this.isSaving = false;
            this.isLoading = false;
        }
    }

    // ============================================================
    // UTILERÍA / DEFAULTS
    // ============================================================
    getDefaultOpportunity() {
        return {
            Name: '', Type: OPPORTUNITY_TYPES.NEW_BUSINESS,   // "Nuevo"
            StageName: 'Gestion Comercial',
            Canal__c: 'Agente',                               // ← default
            Mercado__c: 'Corporativo',                        // ← default
            Ramo__c: '', Description: '', AccountId: null, AccountName: '',
            Agente__c: null, AgenteName: '',                  // ← nuevo lookup de Agente
            Vehiculo__c: null, VehiculoName: '',
            Contacto__c: null, ContactoName: '',              // ← lookup de Contacto
            Prima_Neta__c: null,                              // ← prima neta de la oportunidad
            Id: null,
            tipoCliente: 'Persona',
            clienteNombre: '', clienteApellidos: '', clienteRFC: '', clienteCP: '',
            clienteEmail: '', clienteTelefono: '', clienteDireccion: ''
        };
    }
    // Devuelve el objeto de detalle del ramo seleccionado (lo que está en el formulario).
    getActiveRamoDetail() {
        const map = {
            'Automoviles': this.automovil,
            'GMM': this.gmm,
            'Vida': this.vida,
            'Viajes': this.viaje,
            'Danos': this.danos,
            'Empresarial': this.empresarial,
            'Fianzas': this.fianzas,
            'RC': this.rc,
            'Dental': this.dental,
            'Vision': this.vision
        };
        return map[this.opportunity.Ramo__c] || {};
    }
    getDefaultAutomovil() { return { descripcion_completa__c: '', Placa__c: '', Serie__c: '', Modelo__c: '', Marca__c: '', Anio__c: '', Motor__c: '' }; }
    getDefaultGMM()       { return { estado: '', tipoEstructura: '', numAsegurados: 1 }; }
    getDefaultVida()      { return { aseguradoPrincipal: '', contratante: '', subramo: '' }; }
    getDefaultViaje()     { return { destino: '', numPasajeros: 1 }; }
    getDefaultDanos()     { return { subramo: '' }; }
    getDefaultEmpresarial() { return { giro: '', actividad: '', ubicacion: '', valorInmueble: '', valorContenidos: '' }; }
    getDefaultFianzas()     { return { tipoFianza: '', fiado: '', beneficiario: '', montoAfianzado: '' }; }
    getDefaultRC()          { return { tipoRC: '', profesion: '', actividad: '', giro: '' }; }
    getDefaultDental()      { return { plan: '', numAsegurados: 1, red: '' }; }
    getDefaultVision()      { return { plan: '', numAsegurados: 1, red: '' }; }
    handleBackToList() {
        this.viewMode = VIEW_MODES.LIST;
        this.resetWizard();
    }
    handleCreateNew() {
        this.resetWizard();
        this.setDefaultAgente();
        this.viewMode = VIEW_MODES.CREATE;
    }
    // NUEVO - abre la vista de carga de PDFs
    handleCreateFromPdf() {
        this.resetWizard();
        this.setDefaultAgente();
        this.viewMode = VIEW_MODES.PDF;
    }
    // NUEVO - el componente de PDFs terminó de extraer y ya llenó el formulario.
    // Cambiamos a la vista de creación para que el usuario revise y guarde.
    handlePdfAnalysisComplete(event) {
        const d = (event && event.detail) || {};
        const n = d.count || this.uploadedQuotes.length;
        // Primero mostramos el formulario (comportamiento de siempre). El comparativo
        // de la IA es opcional y NO debe afectar este flujo.
        this.viewMode = VIEW_MODES.CREATE;
        this.comparativoHtml = d.comparativoHtml || '';
        this._comparativoDirty = true;

        if (d.ganadora) {
            const nota = `Recomendación IA: ${d.ganadora}` +
                (d.recomendacion ? ` — ${d.recomendacion}` : '');
            this.opportunity = {
                ...this.opportunity,
                Description: this.opportunity.Description
                    ? `${this.opportunity.Description}\n\n${nota}`
                    : nota
            };
        }

        // Cuenta: usar el cliente detectado (buscar o marcar para crear) + agente por default.
        this.resolveAccountByName(this.opportunity.clienteNombre);
        this.setDefaultAgente();
        this.loadEditableQuotes();

        this.showToast(
            'Datos listos',
            d.ganadora
                ? `Se extrajeron ${n} cotizaciones. Recomendada: ${d.ganadora}. Revisa y guarda.`
                : `Se extrajeron ${n} cotizaciones. Revisa el formulario y guarda.`,
            'success'
        );
    }

    // Pone Abraham Gonzalez Gonzalez como agente por default (si no hay uno ya).
    async setDefaultAgente() {
        if (this.opportunity.Agente__c) return;
        try {
            const res = await searchAgentsProspectors({ searchTerm: 'Abraham Gonzalez Gonzalez' });
            if (res && res.length > 0) {
                this.opportunity = {
                    ...this.opportunity,
                    Agente__c: res[0].Id,
                    AgenteName: res[0].Name
                };
            }
        } catch (e) {
            // sin agente por default; el usuario puede elegirlo
        }
    }

    get hasEditableQuotes() {
        return this.editableQuotes && this.editableQuotes.length > 0;
    }
    handleQuoteProductChange(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        const val = event.detail.value;
        this.editableQuotes = this.editableQuotes.map((q, i) =>
            i === idx ? { ...q, productId: val } : q);
    }
    handleQuoteFrecuenciaChange(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        const val = event.detail.value;
        this.editableQuotes = this.editableQuotes.map((q, i) =>
            i === idx ? { ...q, frecuencia: val } : q);
    }
    // Al cambiar la aseguradora, recarga los productos de esa aseguradora + ramo.
    async handleQuoteAseguradoraChange(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        const val = event.detail.value;
        const q = this.editableQuotes[idx];
        if (!q) { return; }
        let productos = [];
        try {
            productos = await getProductosPorAseguradoraRamo({ aseguradoraId: val, ramo: q.ramo });
        } catch (e) {
            productos = [];
        }
        const productId = (productos && productos.length) ? productos[0].value : null;
        this.editableQuotes = this.editableQuotes.map((it, i) =>
            i === idx
                ? { ...it, aseguradoraId: val, productos: productos || [], productId, sinProductos: !(productos && productos.length) }
                : it);
    }
    handleQuoteFieldChange(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        const field = event.target.dataset.field;
        const val = event.target.value;
        this.editableQuotes = this.editableQuotes.map((q, i) =>
            i === idx ? { ...q, [field]: val } : q);
    }

    get hasPdfQuotes() {
        return this.uploadedQuotes && this.uploadedQuotes.length > 0;
    }
    get hasComparativoHtml() {
        return !!(this.comparativoHtml && this.comparativoHtml.trim());
    }
    // El comparativo "armado" (KPIs + tabla) solo se muestra si NO hay el
    // comparativo de la IA; con IA se ve igual que la pestaña "Comparativo IA".
    get showComparativaDoc() {
        return !this.hasComparativoHtml && this.comparativoData.hasData;
    }
    // Inyecta el HTML de la IA en un div lwc:dom="manual" (evita iframe/blob que
    // la CSP de Lightning bloquea y provocan "Script error").
    renderedCallback() {
        if (!this._comparativoDirty) { return; }
        const host = this.template.querySelector('.comparativo-ia__host');
        if (!host) { return; }
        this._comparativoDirty = false;
        try {
            host.innerHTML = this.comparativoHtml || '';
        } catch (e) {
            /* no romper el flujo si el HTML no se puede inyectar */
        }
    }
    // Pone en Prima Neta la prima MÁS BAJA de las cotizaciones comparadas.
    setPrimaNetaFromQuotes() {
        const primas = (this.uploadedQuotes || [])
            .map(q => parseFloat(q && q.primaTotal))
            .filter(v => !isNaN(v) && v > 0);
        if (primas.length) {
            this.opportunity = { ...this.opportunity, Prima_Neta__c: Math.min(...primas) };
        }
    }
    get pdfQuotePreview() {
        return (this.uploadedQuotes || []).map((q, i) => ({
            key: q.id || ('pq' + i),
            compania: q.compania || '—',
            plan: q.plan || '',
            primaFormatted: q.primaTotalFormatted || this.formatCurrency(q.primaTotal),
            vigencia: q.vigencia ? this.formatDate(q.vigencia) : '—',
            esGanadora: !!q.esGanadora,
            ramoLabel: q.ramoLabel || q.ramo || '',
            coberturas: (q.tablaCompletaCoberturas || []).map((c, j) => ({
                key: (q.id || i) + '-' + j,
                nombre: c.cobertura || c.nombre || '',
                suma: this.formatCurrencyOrText(c.sumaAsegurada || c.suma || ''),
                deducible: c.deducible || ''
            }))
        }));
    }

    // Fuente de la comparativa: si hay cotizaciones guardadas, esas; si no, las del PDF (preview).
    get comparativaSource() {
        const rel = (this.relatedQuotes || []).filter(q => q && q.totalAmount > 0);
        if (rel.length > 0) return this.relatedQuotes;
        return (this.uploadedQuotes || []).map((q, i) => this.mapPdfQuoteToComparativa(q, i));
    }

    // Convierte una cotización del PDF al formato que usa la comparativa.
    mapPdfQuoteToComparativa(q, i) {
        const total = parseFloat(q.primaTotal) || 0;
        const covs = (q.tablaCompletaCoberturas || [])
            .map(c => (c.cobertura || c.nombre || '').trim())
            .filter(Boolean);
        return {
            Id: q.id || ('pq' + i),
            companiaLabel: q.compania || '—',
            totalAmount: total,
            totalFormatted: this.formatCurrency(total),
            coverageCount: covs.length,
            coverageLabel: covs.length === 1 ? '1 cobertura' : `${covs.length} coberturas`,
            coverageNames: covs,
            expirationDateRaw: q.vigencia || null,
            expirationFormatted: q.vigencia ? this.formatDate(q.vigencia) : '',
            statusLabel: 'Vista previa',
            statusBadgeClass: 'quote-badge quote-badge-neutral',
            isSelected: !!q.esGanadora
        };
    }

    get hasAgenteResults() {
        return this.agenteResults && this.agenteResults.length > 0;
    }
    handleAgenteFocus() {
        this.showAgenteDropdown = true;
    }
    handleAgenteInput(event) {
        const value = event.target.value;
        this.opportunity = { ...this.opportunity, AgenteName: value, Agente__c: null };
        this.showAgenteDropdown = true;
        clearTimeout(this._agenteSearchTimer);
        this._agenteSearchTimer = setTimeout(async () => {
            if (value && value.length >= 3) {
                try {
                    this.agenteResults = await searchAgentsProspectors({ searchTerm: value });
                } catch (e) {
                    this.agenteResults = [];
                }
            } else {
                this.agenteResults = [];
            }
        }, 300);
    }
    selectAgente(event) {
        const id = event.currentTarget.dataset.id;
        const ag = (this.agenteResults || []).find(a => a.Id === id);
        if (!ag) return;
        this.opportunity = { ...this.opportunity, Agente__c: ag.Id, AgenteName: ag.Name };
        this.showAgenteDropdown = false;
        this.agenteResults = [];
    }

    // Manejador genérico: data-field="empresarial.giro", "rc.tipoRC", etc.
    handleRamoDetailChange(event) {
        const raw = event.target.dataset && event.target.dataset.field;
        if (!raw) return;
        const dot = raw.indexOf('.');
        if (dot < 0) return;
        const obj = raw.substring(0, dot);
        const field = raw.substring(dot + 1);
        const value = (event.detail && event.detail.value !== undefined)
            ? event.detail.value : event.target.value;
        if (this[obj] && Object.prototype.hasOwnProperty.call(this[obj], field)) {
            this[obj] = { ...this[obj], [field]: value };
        }
    }

    resetWizard() {
        this.opportunity = this.getDefaultOpportunity();
        this.automovil = this.getDefaultAutomovil();
        this.gmm = this.getDefaultGMM();
        this.vida = this.getDefaultVida();
        this.viaje = this.getDefaultViaje();
        this.danos = this.getDefaultDanos();
        this.empresarial = this.getDefaultEmpresarial();
        this.fianzas = this.getDefaultFianzas();
        this.rc = this.getDefaultRC();
        this.dental = this.getDefaultDental();
        this.vision = this.getDefaultVision();
        this.uploadedQuotes = [];
        this.hasExtractedData = false;
        this.extractedOpportunityData = null;
        this.selectedQuoteRamo = '';
        this.tablaComparativaCache = [];
        this.companiasConCoberturasCache = [];
        this.totalCoberturasUnicas = 0;
        this.relatedQuotes = [];
        this.showAccountDropdown = false;
        this.accountResults = [];
        this.isNewAccount = false;
        this.showContactoDropdown = false;
        this.contactoResults = [];
        this.isNewContacto = false;
        this.comparativoHtml = '';
        this._comparativoDirty = true;
    }
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    addMoreQuotes() {
        const uploader = this.template.querySelector('c-cotizacion-op-lector');
        if (uploader && typeof uploader.openFilePicker === 'function') uploader.openFilePicker();
    }
    toggleQuoteExpand(event) {
        event.preventDefault(); event.stopPropagation();
        const quoteId = event.currentTarget.dataset.quoteId;
        if (!quoteId) return;
        this.uploadedQuotes = this.uploadedQuotes.map(q => {
            if (q.id !== quoteId) return q;
            const isExpanded = !q.isExpanded;
            return {
                ...q, isExpanded,
                expandIcon: isExpanded ? 'utility:chevronup' : 'utility:chevrondown',
                expandText: isExpanded ? 'Colapsar' : 'Expandir'
            };
        });
    }
    removeQuote(event) {
        const quoteId = event.currentTarget.dataset.quoteId;
        if (!quoteId) return;
        this.uploadedQuotes = this.uploadedQuotes.filter(q => q.id !== quoteId);
        this.recomputeComparativa();
    }
}