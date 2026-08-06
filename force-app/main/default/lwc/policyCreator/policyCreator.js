import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import EFFECTIVE_DATE from '@salesforce/schema/InsurancePolicy.EffectiveDate';
import EXPIRATION_DATE from '@salesforce/schema/InsurancePolicy.ExpirationDate';
import PAYMENT_DUE_DATE from '@salesforce/schema/InsurancePolicy.PaymentDueDate';
import CANCELLATION_EFF_DATE from '@salesforce/schema/InsurancePolicy.CancellationEffectiveDate';
import SALE_DATE from '@salesforce/schema/InsurancePolicy.SaleDate';
import PREVIOUS_RENEWAL_DATE from '@salesforce/schema/InsurancePolicy.PreviousRenewalDate';
import RENEWAL_DATE from '@salesforce/schema/InsurancePolicy.RenewalDate';
import PLANNED_RENEWAL_DATE from '@salesforce/schema/InsurancePolicy.PlannedRenewalDate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';
import getPolicyIdByQuote from '@salesforce/apex/PolicyController.getPolicyIdByQuote';
import crearVinculoBien from '@salesforce/apex/PolicyController.crearVinculoBien';
import analizarPoliza from '@salesforce/apex/PolicyController.analizarPoliza';
import guardarArchivoEnPoliza from '@salesforce/apex/PolicyController.guardarArchivoEnPoliza';
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
    // PDF seleccionado que se adjuntará a la póliza (queda pendiente si la póliza aún no existe).
    _pdfPendiente = null;
    _dtFlags = {}; // por campo: true si en la org es Fecha/Hora (para formatear al guardar)

    // Campos de fecha que se manejan como "solo fecha".
    // Las fechas ahora son lightning-input-field (se guardan de forma nativa por el
    // record-edit-form), por eso ya no se manejan aquí. Se deja vacío para no inyectar
    // valores viejos al guardar. Solo la vista de solo lectura usa el wire de fechas.
    DATE_FIELDS = [];

    // Fechas de la póliza que en algunas orgs son de tipo Fecha/Hora (requieren hora).
    POLICY_DATE_FIELDS = ['EffectiveDate', 'ExpirationDate', 'PaymentDueDate',
        'CancellationEffectiveDate', 'SaleDate', 'PreviousRenewalDate',
        'RenewalDate', 'PlannedRenewalDate'];

    // Valores recuperados por la IA que NO se muestran en el formulario,
    // pero que sí se guardan al enviar (no se pierde información).
    hiddenFields = {};

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
    @wire(getRecord, { recordId: '$policyId', fields: [
        EFFECTIVE_DATE, EXPIRATION_DATE, PAYMENT_DUE_DATE, CANCELLATION_EFF_DATE,
        SALE_DATE, PREVIOUS_RENEWAL_DATE, RENEWAL_DATE, PLANNED_RENEWAL_DATE
    ] })
    wiredPolicyDates({ data }) {
        if (data) {
            this.policyDates = {
                EffectiveDate: this.fmtDate(getFieldValue(data, EFFECTIVE_DATE)),
                ExpirationDate: this.fmtDate(getFieldValue(data, EXPIRATION_DATE)),
                PaymentDueDate: this.fmtDate(getFieldValue(data, PAYMENT_DUE_DATE)),
                CancellationEffectiveDate: this.fmtDate(getFieldValue(data, CANCELLATION_EFF_DATE)),
                SaleDate: this.fmtDate(getFieldValue(data, SALE_DATE)),
                PreviousRenewalDate: this.fmtDate(getFieldValue(data, PREVIOUS_RENEWAL_DATE)),
                RenewalDate: this.fmtDate(getFieldValue(data, RENEWAL_DATE)),
                PlannedRenewalDate: this.fmtDate(getFieldValue(data, PLANNED_RENEWAL_DATE))
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
        // Detecta cuáles fechas de la póliza son Fecha/Hora en esta org (traen 'T').
        this.POLICY_DATE_FIELDS.forEach((f) => {
            const cell = rec.fields[f];
            const v = cell ? cell.value : null;
            if (v) { flags[f] = String(v).includes('T'); }
        });
        this.dates = d;
        this._dtFlags = flags;
    }

    handleDateChange(event) {
        const f = event.target.dataset.field;
        if (!f) { return; }
        this.dates = { ...this.dates, [f]: event.target.value };
    }

    // Intercepta el guardado para inyectar las fechas y los datos recuperados
    // que no se muestran en el formulario (así no se pierde información).
    handleSubmit(event) {
        event.preventDefault();
        // Lo capturado en pantalla manda. Los datos de la IA solo se agregan para campos
        // que NO están en el formulario; si el campo está presente (aunque el usuario lo
        // haya vaciado a propósito) se respeta lo que envía el formulario.
        const fields = { ...(event.detail ? event.detail.fields : {}) };
        Object.keys(this.hiddenFields).forEach((k) => {
            if (!(k in fields)) {
                fields[k] = this.hiddenFields[k];
            }
        });
        this.DATE_FIELDS.forEach((f) => {
            const val = this.dates[f];
            if (val) {
                fields[f] = this._dtFlags[f] ? (val + 'T00:00:00.000Z') : val;
            }
        });
        // Las fechas que en esta org son Fecha/Hora requieren componente de hora
        // (ISO 8601). Si llega solo la fecha (YYYY-MM-DD) se le agrega el mediodía UTC
        // para no desfasar el día al mostrarla.
        const soloFechaRegex = /^\d{4}-\d{2}-\d{2}$/;
        this.POLICY_DATE_FIELDS.forEach((f) => {
            const v = fields[f];
            if (typeof v === 'string' && soloFechaRegex.test(v)) {
                const esFechaHora = this._dtFlags[f] === true
                    || (this._dtFlags[f] === undefined && (f === 'EffectiveDate' || f === 'ExpirationDate'));
                if (esFechaHora) { fields[f] = v + 'T12:00:00.000Z'; }
            }
        });
        const form = this.template.querySelector('lightning-record-edit-form');
        if (form) { form.submit(fields); }
    }

    async handleSuccess(event) {
        // Id de la póliza (nueva o existente).
        const savedId = (event && event.detail && event.detail.id) || this.policyId;
        this.policyId = savedId;
        // Ya se guardaron: se limpian para no reescribirlos en un guardado posterior.
        this.hiddenFields = {};
        // Refresca el registro para que la pantalla muestre lo guardado.
        if (savedId) {
            notifyRecordUpdateAvailable([{ recordId: savedId }]);
            // Adjunta el PDF que se haya seleccionado antes de que existiera la póliza.
            await this.guardarPdfEnPoliza();
        }
        // Crea el vínculo póliza-bien (Asset + InsurancePolicyAsset). Reúsa el
        // Asset de la oportunidad si existe; si no, lo crea.
        try {
            if (savedId) {
                await crearVinculoBien({ policyId: savedId });
            }
            this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message)
                || 'La póliza se guardó, pero no se pudo vincular el bien.';
            // No bloquea: la póliza ya quedó guardada.
            this.showToast('Aviso', msg, 'warning');
        }
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
            // Guarda el PDF como archivo de la póliza. Si la póliza aún no existe,
            // queda pendiente y se adjunta al guardarla (handleSuccess).
            try {
                const base64 = await this.readFileAsBase64(file);
                this._pdfPendiente = { base64, nombre: file.name };
                await this.guardarPdfEnPoliza();
            } catch (fileErr) {
                // No bloquea el análisis del PDF; se reintenta al guardar la póliza.
            }

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

    // Adjunta a la póliza el PDF pendiente (si hay uno y la póliza ya existe).
    async guardarPdfEnPoliza() {
        if (!this._pdfPendiente || !this.policyId) { return; }
        try {
            await guardarArchivoEnPoliza({
                base64: this._pdfPendiente.base64,
                nombreArchivo: this._pdfPendiente.nombre,
                policyId: this.policyId
            });
            this._pdfPendiente = null;
        } catch (e) {
            // Si falla, se conserva pendiente para reintentar al guardar la póliza.
        }
    }

    // Lee un archivo y devuelve su contenido en base64 (sin el prefijo data:).
    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = String(reader.result || '');
                const comma = result.indexOf(',');
                resolve(comma >= 0 ? result.substring(comma + 1) : result);
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(file);
        });
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
        // El plan/paquete no se guarda en PlanType (picklist); se conserva en la descripción.
        if (d.plan) { descripcion = (descripcion ? descripcion + '\n\n' : '') + 'Plan/Paquete: ' + d.plan; }

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

        // Datos del cliente extraídos del PDF (contratante, asegurado si difiere, y
        // domicilio). Se agregan a la descripción; el asegurado formal de la póliza se
        // conserva desde la oportunidad y no se sobrescribe.
        const cont = d.contratante || {};
        const aseg = d.asegurado || {};
        const dir = cont.direccion || {};
        const datosCliente = [];
        const nombreCont = cont.nombre || d.aseguradoNombre;
        const rfcCont = cont.rfc || d.rfc;
        if (nombreCont) {
            datosCliente.push(`Contratante: ${nombreCont}${rfcCont ? ' (RFC ' + rfcCont + ')' : ''}`);
        }
        if (aseg && aseg.difiereDelContratante && aseg.nombre) {
            datosCliente.push(`Asegurado: ${aseg.nombre}${aseg.rfc ? ' (RFC ' + aseg.rfc + ')' : ''}`);
        }
        if (d.tipoPersona) { datosCliente.push(`Tipo de persona: ${d.tipoPersona}`); }
        if (cont.email) { datosCliente.push(`Correo: ${cont.email}`); }
        if (cont.telefono) { datosCliente.push(`Teléfono: ${cont.telefono}`); }
        const domPartes = [dir.calle, dir.colonia, dir.cp ? 'C.P. ' + dir.cp : null, dir.municipio, dir.estado].filter(Boolean);
        if (domPartes.length) { datosCliente.push(`Domicilio: ${domPartes.join(', ')}`); }
        if (datosCliente.length) {
            descripcion = (descripcion ? descripcion + '\n\n' : '') + 'Datos del cliente:\n'
                + datosCliente.map((l) => '• ' + l).join('\n');
        }

        // Fechas que llena el análisis (solo fecha, YYYY-MM-DD). Ahora son input-field,
        // así que van dentro del mapeo normal. SaleDate y CancellationEffectiveDate NO se
        // llenan desde el PDF (son automáticas).
        const soloFecha = (v) => (v ? String(v).substring(0, 10) : null);
        const fechaPrimerVenc = cob.fechaVencimientoPrimerPago
            || (Array.isArray(cob.recibos) && cob.recibos[0] ? cob.recibos[0].fechaLimite : null);

        const map = {
            EffectiveDate: soloFecha(d.vigenciaDesde),
            ExpirationDate: soloFecha(d.vigenciaHasta),
            PaymentDueDate: soloFecha(fechaPrimerVenc),
            // Datos generales.
            // NO se actualizan por análisis: Aseguradora__c, PolicyType, NameInsuredId,
            // ProductId, SourceQuoteId y la oportunidad origen (se conservan tal cual).
            // El número de póliza va en Name. Universal Policy Number NO se llena aquí:
            // solo aplica a pólizas colectivas/flotilla/grupal y se captura aparte.
            Name: d.numeroPoliza,
            // PlanType es picklist y NO está en el formulario; NO se fuerza desde la IA
            // (un valor fuera del catálogo rompería el guardado). El plan queda en la descripción.
            Status: this.normalizarEstatus(d.estatusPoliza),
            CancellationReason: d.motivoCancelacion,
            // Primas (definición de negocio): GrossWrittenPremium = prima TOTAL anualizada,
            // PremiumAmount = prima NETA sin impuestos.
            PremiumFrequency: d.frecuenciaPago || cob.formaPago,
            PremiumAmount: cob.primaNeta != null ? cob.primaNeta : d.primaNeta,
            GrossWrittenPremium: cob.totalAPagar != null ? cob.totalAPagar : d.primaTotal,
            // Prima del periodo actual: si la póliza trae el importe real del primer pago
            // se usa ese (incluye financiamiento); si no, se calcula por frecuencia.
            TermPremiumAmount: cob.primerPago != null
                ? cob.primerPago
                : this.calcularTermPremium(
                    cob.totalAPagar != null ? cob.totalAPagar : d.primaTotal,
                    d.frecuenciaPago || cob.formaPago
                  ),
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
        const enFormulario = new Set();
        fields.forEach((f) => {
            enFormulario.add(f.fieldName);
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

        // TODOS los valores recuperados se guardan al enviar (estén o no en el formulario).
        // Así la persistencia no depende de que el formulario "detecte" los valores
        // asignados por código: es lo que hacía que al guardar no se actualizaran.
        const pendientes = { ...this.hiddenFields };
        Object.keys(map).forEach((k) => {
            const v = map[k];
            if (v !== null && v !== undefined && v !== '') { pendientes[k] = v; }
        });
        this.hiddenFields = pendientes;

        console.log('PolicyCreator::: campos llenados =', llenados,
            '| guardados sin mostrar =', Object.keys(this.hiddenFields).length);
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

    // ============================================================
    // Cálculos de negocio
    // ============================================================

    // Normaliza el estatus de la IA al catálogo del picklist (Inicial / Vigente / Cancelada).
    normalizarEstatus(valor) {
        const v = (valor || '').toString().toLowerCase();
        if (!v) { return null; }
        if (v.includes('cancel')) { return 'Cancelada'; }
        if (v.includes('inicial') || v.includes('tramite') || v.includes('trámite')) { return 'Inicial'; }
        if (v.includes('vigen') || v.includes('vigor') || v.includes('emitid') || v.includes('renovad')) { return 'Vigente'; }
        return null;
    }

    // Exhibiciones al año según la frecuencia de pago.
    periodosPorFrecuencia(freq) {
        const f = (freq || '').toString().toLowerCase();
        if (f.includes('mensual')) { return 12; }
        if (f.includes('bimestr')) { return 6; }
        if (f.includes('cuatrimestr')) { return 3; }   // antes que "trimestr" (lo contiene)
        if (f.includes('trimestr')) { return 4; }
        if (f.includes('semestr')) { return 2; }
        return 1; // Anual, Único, Contado o no especificada
    }

    // Lee/escribe el valor actual de un campo del formulario.
    _getFieldValue(fieldName) {
        const el = Array.from(this.template.querySelectorAll('lightning-input-field'))
            .find((f) => f.fieldName === fieldName);
        return el ? el.value : null;
    }
    _setFieldValue(fieldName, value) {
        const el = Array.from(this.template.querySelectorAll('lightning-input-field'))
            .find((f) => f.fieldName === fieldName);
        if (el && value !== null && value !== undefined) {
            try { el.value = value; } catch (e) { /* campo no editable */ }
        }
    }

    // Term Premium = prima del periodo actual de pago.
    // Regla: prima total anualizada / exhibiciones de la frecuencia.
    calcularTermPremium(gwp, freq) {
        const total = Number(gwp);
        if (!total || isNaN(total)) { return null; }
        const periodos = this.periodosPorFrecuencia(freq);
        return Math.round((total / periodos) * 100) / 100;
    }

    // Recalcula el Term Premium al cambiar la prima total o la frecuencia.
    handlePremiumChange(event) {
        const campo = event.target.fieldName;
        const valor = event.detail ? event.detail.value : event.target.value;
        const gwp = campo === 'GrossWrittenPremium' ? valor : this._getFieldValue('GrossWrittenPremium');
        const freq = campo === 'PremiumFrequency' ? valor : this._getFieldValue('PremiumFrequency');
        const term = this.calcularTermPremium(gwp, freq);
        if (term !== null) {
            this._setFieldValue('TermPremiumAmount', term);
            // Se guarda también en hiddenFields para que el valor recalculado se persista al enviar.
            this.hiddenFields = { ...this.hiddenFields, TermPremiumAmount: term };
        }
    }

    handleReintentar() {
        this.loadPolicy();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}