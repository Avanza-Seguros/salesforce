import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';
import getPolicyIdByQuote from '@salesforce/apex/PolicyController.getPolicyIdByQuote';
import analizarPoliza from '@salesforce/apex/PolicyController.analizarPoliza';

export default class PolicyCreator extends NavigationMixin(LightningElement) {
    @track policyId;
    @track quoteId;
    @track opportunityId;
    @track loading = true;
    @track errorMsg = '';
    @track analizando = false;

    _pdfJsLoaded = false;

    // Recibe los Ids por navegación (desde el botón "Póliza" de Crear Oportunidad).
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) { return; }
        this.quoteId = pageRef.state.c__quoteId;
        this.opportunityId = pageRef.state.c__opportunityId;
        this.loadPolicy();
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

    handleSuccess() {
        this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
    }
    handleError(event) {
        const msg = (event && event.detail && event.detail.message) || 'No se pudo guardar la póliza.';
        this.showToast('Error', msg, 'error');
    }

    // Abre el selector de archivo para analizar un PDF de póliza.
    handleAnalizarPdf() {
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
            const datos = JSON.parse(jsonStr || '{}');
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
        const v = d.vehiculo || {};
        const cob = d.cobranza || {};
        let descripcion = d.descripcion || '';

        if (v && (v.descripcion || v.serie || v.placas)) {
            const veh = `Vehículo: ${v.descripcion || ''}${v.serie ? ' | Serie: ' + v.serie : ''}${v.placas ? ' | Placas: ' + v.placas : ''}`;
            descripcion = (descripcion ? descripcion + '\n\n' : '') + veh;
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

        const map = {
            // Datos generales
            UniversalPolicyNumber: d.numeroPoliza,
            PolicyName: d.numeroPoliza,
            Aseguradora__c: d.aseguradora,
            PolicyType: d.tipoPoliza,
            PlanType: d.plan,
            EffectiveDate: d.vigenciaDesde,
            ExpirationDate: d.vigenciaHasta,
            // Primas / cobranza en campos estándar
            PremiumFrequency: cob.formaPago || d.frecuenciaPago,
            PremiumAmount: cob.primaNeta != null ? cob.primaNeta : d.primaNeta,
            GrossWrittenPremium: cob.totalAPagar != null ? cob.totalAPagar : d.primaTotal,
            PaymentDueDate: cob.fechaVencimientoPrimerPago
                || (Array.isArray(cob.recibos) && cob.recibos[0] ? cob.recibos[0].fechaLimite : null),
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
        fields.forEach((f) => {
            if (Object.prototype.hasOwnProperty.call(map, f.fieldName)) {
                const val = map[f.fieldName];
                if (val !== null && val !== undefined && val !== '') {
                    f.value = val;
                }
            }
        });
    }

    handleReintentar() {
        this.loadPolicy();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}