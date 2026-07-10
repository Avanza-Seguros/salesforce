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
    @track isPdfJsLoaded = false;

    // Recibe los Ids por navegación (desde el botón "Póliza" de Crear Oportunidad).
    @wire(CurrentPageReference)
    wiredPageRef(pageRef) {
        if (!pageRef || !pageRef.state) { return; }
        this.quoteId = pageRef.state.c__quoteId;
        this.opportunityId = pageRef.state.c__opportunityId;
        this.loadPolicy();
    }

    renderedCallback() {
        if (!this.isPdfJsLoaded && !this.pdfJsError) {
            this.loadPdfJs();
        }
    }

    async loadPdfJs() {
        try {
            console.log('📦 Iniciando carga de PDF.js...');
            this.checkEnvironment();
            await this.loadPdfJsScript();
            await this.setupWorker();
            await this.testPdfJs();
            
            this.isPdfJsLoaded = true;
            this.pdfJsError = false;
            console.log('✅ PDF.js cargado exitosamente');
        } catch (error) {
            console.error('❌ Error cargando PDF.js:', error);
            this.handleLoadError(error);
        }
    }

    async setupWorker() {
        try {
            console.log('🔧 Configurando PDF.js sin worker (modo Locker Service)...');
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdf.worker.js';
            
            if (window.pdfjsLib.GlobalWorkerOptions.workerPort) {
                window.pdfjsLib.GlobalWorkerOptions.workerPort = PDFJS + '/pdf.worker.min.js';
            }
            console.log('✅ PDF.js configurado sin worker');
        } catch (workerError) {
            console.warn('⚠️ Error configurando worker:', workerError);
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = null;
        }
    }

    async testPdfJs() {
        try {
            console.log('🧪 Probando PDF.js...');
            const pdfData = new Uint8Array([
                0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25,
                0xC3, 0xA4, 0xC3, 0xBC, 0xC3, 0xB6, 0xC3, 0x9F, 0x0A, 0x31,
                0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F,
                0x54, 0x79, 0x70, 0x65, 0x2F, 0x43, 0x61, 0x74, 0x61, 0x6C,
                0x6F, 0x67, 0x2F, 0x50, 0x61, 0x67, 0x65, 0x73, 0x20, 0x32,
                0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x0A, 0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A
            ]);
            
            const loadingTask = window.pdfjsLib.getDocument({ data: pdfData });
            const timeout = new Promise((_, reject) => 
                setTimeout(() => reject(new Error('Timeout probando PDF.js')), 5000)
            );
            
            const pdf = await Promise.race([loadingTask.promise, timeout]);
            if (pdf && pdf.destroy) {
                await pdf.destroy();
            }
            
            console.log('✅ PDF.js funciona correctamente');
        } catch (testError) {
            console.warn('⚠️ Test de PDF.js falló:', testError.message);
        }
    }

    reloadPdfJs() {
        this.pdfJsError = false;
        this.isPdfJsLoaded = false;
        this.loadPdfJs();
    }

    checkEnvironment() {
        console.log('🔍 Verificando entorno...');
        const requiredAPIs = ['FileReader', 'ArrayBuffer', 'Uint8Array', 'Promise'];
        const missingAPIs = requiredAPIs.filter(api => typeof window[api] === 'undefined');
        
        if (missingAPIs.length > 0) {
            throw new Error(`APIs faltantes: ${missingAPIs.join(', ')}`);
        }
        console.log('✅ Entorno verificado');
    }

    async loadPdfJsScript() {
        try {
            console.log('📦 Cargando script PDF.js...');
            const mainScript = PDFJS + '/pdf.js';
            await loadScript(this, mainScript);
            
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('pdfjsLib no se definió después de cargar el script');
            }
            console.log('✅ Script PDF.js cargado');
        } catch (error) {
            console.warn('⚠️ Falló versión principal, intentando versión min...');
            const minScript = PDFJS + '/pdf.min.js';
            await loadScript(this, minScript);
            
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('pdfjsLib no disponible en ninguna versión');
            }
        }
    }

    async loadPolicy() {
        console.debug('PolicyCreator.loadPolicy: Cargando póliza para quoteId = ' + this.quoteId + ', opportunityId = ' + this.opportunityId);
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
        console.debug('PolicyCreator.hasPolicy: policyId = ' + this.policyId);
        return !!this.policyId;
    }

    handleSuccess() {
        this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
    }
    handleError(event) {
        console.error('PolicyCreator.handleError: Error al guardar la póliza:', event);
        const msg = (event && event.detail && event.detail.message) || 'No se pudo guardar la póliza.';
        this.showToast('Error', msg, 'error');
    }

    // Abre el selector de archivo para analizar un PDF de póliza.
    handleAnalizarPdf() {
        console.debug('PolicyCreator.handleAnalizarPdf: Abriendo selector de archivo...');
        const input = this.template.querySelector('input.pdf-file-input');
        if (input) { input.value = null; input.click(); }
    }

    async handleFileSelected(event) {
        console.debug('PolicyCreator.handleFileSelected: Archivo seleccionado ');
        const file = event.target.files && event.target.files[0];
        if (!file) { return; }
        if (typeof window.pdfjsLib === 'undefined') {
            this.showToast('Aviso', 'El lector de PDF aún se está cargando. Intenta de nuevo en unos segundos.', 'warning');
            return;
        }
        this.analizando = true;
        try {
            const texto = await this.extractPdfText(file);
            console.debug('PolicyCreator.handleFileSelected: Texto extraído del PDF: ' + texto);
            if (!texto) {
                this.showToast('Aviso', 'No se pudo leer texto del PDF (¿está escaneado?).', 'warning');
                return;
            }
            const jsonStr = await analizarPoliza({ textoPoliza: texto });
            console.debug('PolicyCreator.handleFileSelected: JSON devuelto por la IA: ' + jsonStr);
            const datos = JSON.parse(jsonStr || '{}');
            this.fillForm(datos);
            this.showToast('Listo', 'Datos de la póliza cargados. Revisa y guarda.', 'success');
        } catch (e) {
            console.error('PolicyCreator.handleFileSelected: Error al analizar el PDF:', e);
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error al analizar el PDF.';
            this.showToast('Error', msg, 'error');
        } finally {
            this.analizando = false;
        }
    }

    // Extrae el texto de un PDF con pdf.js (mismo enfoque que el flujo de cotizaciones).
    async extractPdfText(file) {
        console.debug('PolicyCreator.extractPdfText: Extrayendo texto del PDF...');
        const fontsUrl = fontsResource + '/';
        try {
            const arrayBuffer = await file.arrayBuffer();
            console.debug('PolicyCreator.extractPdfText: ArrayBuffer obtenido del archivo PDF.');
            const loadingTask = window.pdfjsLib.getDocument({
                data: new Uint8Array(arrayBuffer),
                isEvalSupported: false,
                useWorkerFetch: false,
                standardFontDataUrl: fontsUrl,
                disableFontFace: true
            });
            const pdf = await loadingTask.promise;
            let text = '';
            console.debug('PolicyCreator.extractPdfText: Número de páginas del PDF: ' + pdf.numPages);
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
        console.debug('PolicyCreator.fillForm: Llenando formulario con datos:');
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

        const map = {
            // Datos generales
            UniversalPolicyNumber: d.numeroPoliza,
            PolicyName: d.numeroPoliza,
            Aseguradora__c: d.aseguradora,
            PolicyType: d.ramo || d.tipoPoliza,
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
        console.debug('PolicyCreator.handleReintentar: Reintentando cargar la póliza...');
        this.loadPolicy();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}