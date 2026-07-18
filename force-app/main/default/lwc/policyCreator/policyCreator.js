import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import EFFECTIVE_DATE from '@salesforce/schema/InsurancePolicy.EffectiveDate';
import EXPIRATION_DATE from '@salesforce/schema/InsurancePolicy.ExpirationDate';
import PAYMENT_DUE_DATE from '@salesforce/schema/InsurancePolicy.PaymentDueDate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';
import getPolicyIdByQuote from '@salesforce/apex/PolicyController.getPolicyIdByQuote';
import analizarPoliza from '@salesforce/apex/PolicyController.analizarPoliza';
import getOpportunityDetails from '@salesforce/apex/OpportunityController.getOpportunityDetails';

export default class PolicyCreator extends NavigationMixin(LightningElement) {
    @track policyId;
    @track quoteId;
    @track opportunityId;
    @track loading = true;
    @track errorMsg = '';
    @track analizando = false;
    @track dates = {};
    @track readOnly = false;
    @track oppCard = null;
    @track quoteCards = [];
    @track policyDates = {};

    _pdfJsLoaded = false;
    _dtFlags = {}; // por campo: true si en la org es Fecha/Hora (para formatear al guardar)

    // Campos de fecha que se manejan como "solo fecha".
    DATE_FIELDS = [
        'EffectiveDate', 'ExpirationDate', 'CancellationEffectiveDate', 'SaleDate',
        'PreviousRenewalDate', 'RenewalDate', 'PlannedRenewalDate', 'PaymentDueDate'
    ];

    // Recibe los Ids por navegación (desde el botón "Póliza" de Crear Oportunidad).
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) { return; }
        this.quoteId = pageRef.state.c__quoteId;
        this.opportunityId = pageRef.state.c__opportunityId;
        this.readOnly = pageRef.state.c__readonly === '1';
        this.loadPolicy();
        if (this.readOnly) { this.loadResumen(); }
    }

    // Lee las fechas de la póliza para mostrarlas SIN hora en la vista de solo lectura.
    @wire(getRecord, { recordId: '$policyId', fields: [EFFECTIVE_DATE, EXPIRATION_DATE, PAYMENT_DUE_DATE] })
    wiredPolicyDates({ data }) {
        if (data) {
            this.policyDates = {
                EffectiveDate: this.fmtDate(getFieldValue(data, EFFECTIVE_DATE)),
                ExpirationDate: this.fmtDate(getFieldValue(data, EXPIRATION_DATE)),
                PaymentDueDate: this.fmtDate(getFieldValue(data, PAYMENT_DUE_DATE))
            };
        }
    }

    renderedCallback() {
        if (!this._pdfJsLoaded) {
            this._pdfJsLoaded = true;
            this.loadPdfJs();
        }
    }

    async loadPdfJs() {
        try {
            await loadScript(this, PDFJS + '/pdf.js');
            if (typeof window.pdfjsLib === 'undefined') {
                await loadScript(this, PDFJS + '/pdf.min.js');
            }
            try {
                window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdf.worker.js';
            } catch (e) {
                window.pdfjsLib.GlobalWorkerOptions.workerSrc = null;
            }
        } catch (e) {
            // Si no carga, el botón de análisis avisará al usuario.
            this._pdfJsLoaded = false;
        }
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
    get isReadOnly() {
        return this.readOnly;
    }
    get isEditable() {
        return !this.readOnly;
    }

    get showOverlay() {
        return this.loading || this.analizando;
    }
    get overlayMessage() {
        return this.analizando ? 'Analizando el PDF de la póliza…' : 'Cargando la póliza…';
    }

    // Al cargar el registro, toma los valores de fecha y detecta si son Fecha/Hora.
    handleLoad(event) {
        const recs = event && event.detail ? event.detail.records : null;
        const rec = recs && this.policyId ? recs[this.policyId] : null;
        if (!rec || !rec.fields) { return; }
        const d = { ...this.dates };
        const flags = { ...this._dtFlags };
        this.DATE_FIELDS.forEach((f) => {
            const cell = rec.fields[f];
            const v = cell ? cell.value : null;
            if (v) {
                const s = String(v);
                flags[f] = s.includes('T');       // Fecha/Hora si trae 'T'
                if (!d[f]) { d[f] = s.substring(0, 10); } // solo YYYY-MM-DD
            }
        });
        this.dates = d;
        this._dtFlags = flags;
    }

    handleDateChange(event) {
        const f = event.target.dataset.field;
        if (!f) { return; }
        this.dates = { ...this.dates, [f]: event.target.value };
    }

    // Intercepta el guardado para inyectar las fechas (con formato correcto).
    handleSubmit(event) {
        event.preventDefault();
        const fields = { ...event.detail.fields };
        this.DATE_FIELDS.forEach((f) => {
            const val = this.dates[f];
            if (val) {
                fields[f] = this._dtFlags[f] ? (val + 'T00:00:00.000Z') : val;
            }
        });
        const form = this.template.querySelector('lightning-record-edit-form');
        if (form) { form.submit(fields); }
    }

    handleSuccess() {
        this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
    }
    handleError(event) {
        const msg = (event && event.detail && event.detail.message) || 'No se pudo guardar la póliza.';
        this.showToast('Error', msg, 'error');
    }

    // Abre el selector de archivo para analizar un PDF de póliza.
    handleAnalizarPdf() {
        if (this.readOnly) { return; }
        const input = this.template.querySelector('input.pdf-file-input');
        if (input) { input.value = null; input.click(); }
    }

    async handleFileSelected(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) { return; }
        if (typeof window.pdfjsLib === 'undefined') {
            this.showToast('Aviso', 'El lector de PDF aún se está cargando. Intenta de nuevo en unos segundos.', 'warning');
            return;
        }
        this.analizando = true;
        try {
            const texto = await this.extractPdfText(file);
            if (!texto) {
                this.showToast('Aviso', 'No se pudo leer texto del PDF (¿está escaneado?).', 'warning');
                return;
            }
            const jsonStr = await analizarPoliza({ textoPoliza: texto });
            console.log('PolicyCreator::: JSON recibido de Apex ->', jsonStr);
            let datos;
            try {
                datos = JSON.parse(jsonStr || '{}');
            } catch (parseErr) {
                console.error('PolicyCreator::: no se pudo parsear el JSON', parseErr);
                this.showToast('Aviso', 'La IA respondió en un formato no válido. Intenta de nuevo.', 'warning');
                return;
            }
            this.fillForm(datos);
            this.showToast('Listo', 'Datos de la póliza cargados. Revisa y guarda.', 'success');
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error al analizar el PDF.';
            this.showToast('Error', msg, 'error');
        } finally {
            this.analizando = false;
        }
    }

    // Extrae el texto de un PDF con pdf.js (mismo enfoque que el flujo de cotizaciones).
    async extractPdfText(file) {
        const fontsUrl = fontsResource + '/';
        try {
            const arrayBuffer = await file.arrayBuffer();
            const loadingTask = window.pdfjsLib.getDocument({
                data: new Uint8Array(arrayBuffer),
                isEvalSupported: false,
                useWorkerFetch: false,
                standardFontDataUrl: fontsUrl,
                disableFontFace: true
            });
            const pdf = await loadingTask.promise;
            let text = '';
            for (let p = 1; p <= pdf.numPages; p++) {
                const page = await pdf.getPage(p);
                const content = await page.getTextContent();
                text += content.items.map((it) => it.str).join(' ') + '\n';
            }
            return text.trim();
        } catch (e) {
            return '';
        }
    }

    // Prellena los campos del formulario con el JSON devuelto por la IA.
    fillForm(d) {
        if (!d) { return; }
        const bien = d.bienAsegurado || {};
        const cob = d.cobranza || {};
        let descripcion = d.descripcion || '';

        // Bien asegurado (genérico para cualquier ramo).
        const bienLines = [];
        if (bien.descripcion) {
            bienLines.push(`${bien.tipo ? bien.tipo + ': ' : ''}${bien.descripcion}`);
        }
        if (Array.isArray(bien.atributos)) {
            bien.atributos.forEach((a) => {
                if (a && a.campo && (a.valor !== null && a.valor !== undefined && a.valor !== '')) {
                    bienLines.push(`• ${a.campo}: ${a.valor}`);
                }
            });
        }
        if (bienLines.length) {
            const titulo = bien.tipo ? bien.tipo : 'Bien asegurado';
            descripcion = (descripcion ? descripcion + '\n\n' : '') + titulo + ':\n' + bienLines.join('\n');
        }
        if (Array.isArray(d.coberturas) && d.coberturas.length) {
            const cobs = d.coberturas
                .map((c) => {
                    const suma = c.sumaAsegurada ? ` — Suma: ${c.sumaAsegurada}` : '';
                    const ded = c.deducible ? ` — Deducible: ${c.deducible}` : '';
                    return `• ${c.nombre || ''}${suma}${ded}`;
                })
                .join('\n');
            descripcion = (descripcion ? descripcion + '\n\n' : '') + 'Coberturas:\n' + cobs;
        }

        // Calendario de recibos (lista variable) dentro de la descripción.
        const money = (n) => (n === null || n === undefined || n === '')
            ? null
            : Number(n).toLocaleString('es-MX', { style: 'currency', currency: 'MXN' });
        if (Array.isArray(cob.recibos) && cob.recibos.length) {
            const recs = cob.recibos.map((r) => {
                const parts = [r.numero ? `Recibo ${r.numero}` : 'Recibo'];
                if (r.fechaLimite) parts.push(`vence ${r.fechaLimite}`);
                if (r.importe != null) parts.push(money(r.importe));
                return '• ' + parts.join(' — ');
            }).join('\n');
            descripcion = (descripcion ? descripcion + '\n\n' : '') + 'Calendario de pagos:\n' + recs;
        }

        // Fechas (solo fecha) que llenó la IA → se manejan aparte de los input-field.
        const nuevaFechaVenc = cob.fechaVencimientoPrimerPago
            || (Array.isArray(cob.recibos) && cob.recibos[0] ? cob.recibos[0].fechaLimite : null);
        const dateVals = {
            EffectiveDate: d.vigenciaDesde,
            ExpirationDate: d.vigenciaHasta,
            SaleDate: d.fechaEmision,
            CancellationEffectiveDate: d.fechaCancelacion,
            PaymentDueDate: cob.fechaVencimientoPrimerPago
                || (Array.isArray(cob.recibos) && cob.recibos[0] ? cob.recibos[0].fechaLimite : null)
        };
        const nuevasFechas = { ...this.dates };
        Object.keys(dateVals).forEach((k) => {
            if (dateVals[k]) { nuevasFechas[k] = String(dateVals[k]).substring(0, 10); }
        });
        this.dates = nuevasFechas;

        const map = {
            // Datos generales.
            // NO se actualizan por análisis: Aseguradora__c, PolicyType, NameInsuredId,
            // ProductId, SourceQuoteId y la oportunidad origen (se conservan tal cual).
            UniversalPolicyNumber: d.numeroPoliza,
            PolicyName: d.numeroPoliza,
            PlanType: d.plan,
            Status: d.estatusPoliza,
            CancellationReason: d.motivoCancelacion,
            // Primas / cobranza en campos estándar
            PremiumFrequency: d.frecuenciaPago || cob.formaPago,
            PremiumAmount: cob.primaNeta != null ? cob.primaNeta : d.primaNeta,
            GrossWrittenPremium: cob.totalAPagar != null ? cob.totalAPagar : d.primaTotal,
            // Cobranza en campos personalizados
            Moneda__c: cob.moneda,
            Numero_Pagos__c: cob.numeroPagos,
            Plazo_Pago_Dias__c: cob.plazoPagoDias,
            Primer_Pago__c: cob.primerPago,
            Pago_Subsecuente__c: cob.pagoSubsecuente,
            Pagos_Subsecuentes__c: cob.numeroPagosSubsecuentes,
            Financiamiento__c: cob.financiamiento,
            Gastos_Expedicion__c: cob.gastosExpedicion,
            Derecho_Poliza__c: cob.derechoPoliza,
            Descuento__c: cob.descuento,
            Recargos__c: cob.recargos,
            Subtotal__c: cob.subtotal,
            IVA__c: cob.iva,
            Referencia_Pago__c: cob.referenciaPago,
            CLABE__c: cob.clabe,
            PolicyDescription: descripcion
        };

        const fields = this.template.querySelectorAll('lightning-input-field');
        console.log('PolicyCreator::: campos encontrados en el formulario =', fields.length);
        if (!fields.length) {
            this.showToast('Aviso',
                'El formulario no está mostrando campos. Verifica que los campos de Cobranza estén desplegados y con visibilidad de perfil.',
                'warning');
        }
        let llenados = 0;
        fields.forEach((f) => {
            if (Object.prototype.hasOwnProperty.call(map, f.fieldName)) {
                const val = map[f.fieldName];
                if (val !== null && val !== undefined && val !== '') {
                    try {
                        f.value = val;
                        llenados++;
                    } catch (setErr) {
                        console.warn('PolicyCreator::: no se pudo asignar', f.fieldName, setErr);
                    }
                }
            }
        });
        console.log('PolicyCreator::: campos llenados =', llenados);
    }

    // Carga el resumen (Oportunidad + Cotizaciones) para la vista de solo lectura.
    async loadResumen() {
        if (!this.opportunityId) { return; }
        try {
            const detail = await getOpportunityDetails({ opportunityId: this.opportunityId });
            const o = (detail && detail.opportunity) || {};
            this.oppCard = {
                name: o.Name || '—',
                cuenta: o.Account && o.Account.Name ? o.Account.Name : '—',
                etapa: this.stageLabel(o.StageName),
                ramo: o.Ramo__c || '—',
                tipo: o.Type || '—',
                primaNeta: this.fmtCurrency(o.Prima_neta__c != null ? o.Prima_neta__c
                    : (o.Prima_Neta__c != null ? o.Prima_Neta__c
                    : (o.Prima_Total__c != null ? o.Prima_Total__c : o.Amount))),
                cierre: this.fmtDate(o.CloseDate),
                agente: o.Agente_Relacionado__r && o.Agente_Relacionado__r.Name
                    ? o.Agente_Relacionado__r.Name : '—'
            };
            const counts = (detail && detail.coverageCounts) || {};
            this.quoteCards = ((detail && detail.quotes) || []).map((q) => ({
                id: q.Id,
                numero: q.QuoteNumber || q.Name || '—',
                aseguradora: q.Aseguradora__r && q.Aseguradora__r.Name ? q.Aseguradora__r.Name : '—',
                primaTotal: this.fmtCurrency(q.Prima_Total__c != null ? q.Prima_Total__c : q.TotalPrice),
                status: q.Status || '—',
                aceptada: /accept|acept/i.test(q.Status || ''),
                coberturas: counts[q.Id] != null ? counts[q.Id] : 0
            }));
        } catch (e) {
            // Silencioso: si falla el resumen, igual se muestra la póliza.
            console.warn('PolicyCreator::: no se pudo cargar el resumen', e);
        }
    }

    get hasQuoteCards() {
        return this.quoteCards && this.quoteCards.length > 0;
    }

    stageLabel(stage) {
        if (!stage) { return '—'; }
        if (/won|ganad/i.test(stage)) { return 'Ganada'; }
        if (/lost|perdid/i.test(stage)) { return 'Perdida'; }
        return stage;
    }
    fmtCurrency(n) {
        if (n === null || n === undefined || n === '') { return '—'; }
        return Number(n).toLocaleString('es-MX', { style: 'currency', currency: 'MXN' });
    }
    fmtDate(v) {
        if (!v) { return '—'; }
        const d = new Date(v);
        if (isNaN(d.getTime())) { return String(v); }
        return d.toLocaleDateString('es-MX', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    // Regresa a la lista de Oportunidades.
    handleRegresar() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Crear_Oportunidad' }
        });
    }

    handleReintentar() {
        this.loadPolicy();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}