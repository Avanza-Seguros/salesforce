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
import completarPoliza from '@salesforce/apex/PolicyController.completarPoliza';
import guardarDatosPolizaDesdePdf from '@salesforce/apex/PolicyController.guardarDatosPolizaDesdePdf';
import vincularProducer from '@salesforce/apex/PolicyController.vincularProducer';
import analizarPoliza from '@salesforce/apex/PolicyController.analizarPoliza';
import guardarArchivoEnPoliza from '@salesforce/apex/PolicyController.guardarArchivoEnPoliza';
import getRegistrosPoliza from '@salesforce/apex/PolicyController.getRegistrosPoliza';
import getOpportunityDetails from '@salesforce/apex/OpportunityController.getOpportunityDetails';
import cambiarEtapaAPoliza from '@salesforce/apex/OpportunityController.cambiarEtapaAPoliza';

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
    @track coberturas = [];
    @track participantes = [];
    @track bienes = [];
    @track transacciones = [];
    @track policyHero = {};
    // Etapa real de la oportunidad (API): define el aviso y el color de la cabecera.
    oppStage = '';
    // true cuando se cargó el PDF de la póliza: al guardar, la oportunidad pasa a Póliza.
    _pdfCargado = false;

    _pdfJsLoaded = false;
    // PDF seleccionado que se adjuntará a la póliza (queda pendiente si la póliza aún no existe).
    _pdfPendiente = null;
    // Datos del PDF de póliza analizados por la IA (para crear los objetos hijos al guardar).
    _datosPoliza = null;
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
        // Siempre se lee la oportunidad: si ya está en Póliza, Ganada o Perdida se fuerza
        // el modo SOLO LECTURA aunque se haya llegado sin el parámetro c__readonly.
        this.loadResumen();
    }

    // Lee las fechas de la póliza para mostrarlas SIN hora en la vista de solo lectura.
    @wire(getRecord, { recordId: '$policyId', fields: [
        EFFECTIVE_DATE, EXPIRATION_DATE, PAYMENT_DUE_DATE, CANCELLATION_EFF_DATE,
        SALE_DATE, PREVIOUS_RENEWAL_DATE, RENEWAL_DATE, PLANNED_RENEWAL_DATE
    ], optionalFields: [
        'InsurancePolicy.Name', 'InsurancePolicy.UniversalPolicyNumber', 'InsurancePolicy.Status',
        'InsurancePolicy.GrossWrittenPremium', 'InsurancePolicy.PremiumFrequency',
        'InsurancePolicy.Numero_Pagos__c'
    ] })
    wiredPolicyDates({ data }) {
        if (data) {
            const f = (name) => {
                const cell = data.fields && data.fields[name];
                if (!cell) { return null; }
                return cell.displayValue != null ? cell.displayValue : cell.value;
            };
            const prima = data.fields && data.fields.GrossWrittenPremium
                ? data.fields.GrossWrittenPremium.value : null;
            this.policyHero = {
                nombre: f('Name') || 'Póliza',
                numero: f('UniversalPolicyNumber') || 'Sin número',
                estatus: f('Status') || '—',
                prima: this.fmtCurrency(prima),
                frecuencia: f('PremiumFrequency') || '—',
                pagos: f('Numero_Pagos__c') || '—'
            };
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
                quoteId: this.idOrNull(this.quoteId),
                opportunityId: this.idOrNull(this.opportunityId)
            });
            if (id) {
                // Liga el Producer (agente) de la oportunidad a la póliza ANTES de mostrar
                // el formulario, para que el campo Agente (ProducerId) aparezca poblado.
                try { await vincularProducer({ policyId: id, opportunityId: this.idOrNull(this.opportunityId) }); } catch (e) { /* no bloquea */ }
                this.policyId = id;
                if (this.readOnly) { this.loadRegistrosPoliza(); }
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
    // Nombre del agente (Producer) de la oportunidad, para el campo de solo lectura del formulario.
    get agenteNombre() {
        return (this.oppCard && this.oppCard.agente) || '—';
    }
    // Cotización de origen (la aceptada; si no hay, la primera) y oportunidad, como texto.
    get cotizacionOrigen() {
        const qs = this.quoteCards || [];
        const q = qs.find((c) => c.id === this.quoteId) || qs.find((c) => c.aceptada) || qs[0];
        return q ? `${q.numero} · ${q.aseguradora}` : '—';
    }
    get oportunidadOrigen() {
        return (this.oppCard && this.oppCard.name) || '—';
    }
    get topbarSubtitle() {
        return this.readOnly
            ? 'Consulta de la póliza (solo lectura)'
            : 'Carga el PDF de la póliza para emitirla';
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
                // Las fechas de póliza son Fecha/Hora en esta org: se agregan a menos que
                // se haya detectado explícitamente que el campo es de tipo Fecha.
                const esFechaHora = this._dtFlags[f] !== false;
                if (esFechaHora) { fields[f] = v + 'T12:00:00.000Z'; }
            }
        });
        // Nunca enviar campos automáticos/calculados o de solo lectura: la plataforma
        // los rechaza y hace fallar todo el guardado con un error genérico.
        const NO_ESCRIBIBLES = [
            'PolicyTerm',                 // calculado (Expiration - Effective)
            'SaleDate',                   // automático (cambio de etapa)
            'CancellationEffectiveDate',  // automático (módulo de pagos)
            'CancellationDate', 'CurrentDueAmount', 'PastDueAmount', 'PaidToDate',
            'TotalSumInsured', 'IsRenewedPolicy'
        ];
        NO_ESCRIBIBLES.forEach((f) => { delete fields[f]; });

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
        // Completa los registros hijos de la póliza (modelo FSC), de forma idempotente:
        //   bien (InsurancePolicyAsset), asegurados (InsurancePolicyParticipant),
        //   coberturas (InsurancePolicyCoverage) y transacción de prima (InsurancePolicyTransaction).
        try {
            if (savedId) {
                // Si se analizó un PDF, se crean/actualizan los hijos con los datos del PDF
                // (vehículo, coberturas con suma/deducible, participantes, transacción).
                // Si no, se completa con el catálogo del producto.
                const resumen = this._datosPoliza
                    ? await guardarDatosPolizaDesdePdf({
                        policyId: savedId,
                        opportunityId: this.idOrNull(this.opportunityId),
                        datosJson: JSON.stringify(this._datosPoliza)
                      })
                    : await completarPoliza({
                        policyId: savedId,
                        opportunityId: this.idOrNull(this.opportunityId)
                      });
                this.mostrarResumenPoliza(resumen);
            } else {
                this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
            }
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message)
                || 'La póliza se guardó, pero no se pudieron completar sus registros.';
            // No bloquea: la póliza ya quedó guardada.
            this.showToast('Aviso', msg, 'warning');
        }
        // Sin PDF de la póliza la oportunidad sigue en emisión y el formulario editable.
        if (!this._pdfCargado) { return; }
        // Con el PDF cargado, la oportunidad pasa a etapa "Póliza" y ya no se puede modificar.
        try {
            if (this.opportunityId) {
                await cambiarEtapaAPoliza({ opportunityId: this.opportunityId });
            }
            this._pdfCargado = false;
            this.showToast('Póliza emitida', 'La oportunidad pasó a la etapa Póliza.', 'success');
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.showToast('La póliza se guardó, pero la etapa no cambió', msg, 'warning');
            return;
        }
        // Lleva a la vista completa de la póliza en modo lectura (resumen + coberturas,
        // participantes, bien y transacción).
        this.navegarAPoliza();
    }

    // Redirige al mismo LWC de Crear Póliza en modo SOLO LECTURA (igual que el botón
    // "Información"), donde se ve el resumen completo con coberturas, participantes, etc.
    navegarAPoliza() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Crear_Poliza' },
            state: {
                c__opportunityId: this.opportunityId || '',
                c__quoteId: this.quoteId || '',
                c__readonly: '1'
            }
        });
    }

    // Arma un mensaje de resultado a partir del resumen del orquestador.
    mostrarResumenPoliza(resumen) {
        const r = resumen || {};
        const partes = [];
        if (r.coberturas) { partes.push(`${r.coberturas} cobertura(s)`); }
        if (r.asegurados) { partes.push(`${r.asegurados} asegurado(s)`); }
        if (r.cuenta) { partes.push('datos del cliente'); }
        if (r.vehiculo) { partes.push('vehículo'); }
        if (r.bien) { partes.push('bien asegurado'); }
        if (r.transaccion) { partes.push('transacción de prima'); }
        if (r.renovacion) { partes.push('fecha de renovación'); }

        const errores = Object.keys(r)
            .filter((k) => k.endsWith('Error'))
            .map((k) => r[k])
            .filter(Boolean);

        if (errores.length) {
            const detalle = partes.length ? ` Se crearon: ${partes.join(', ')}.` : '';
            this.showToast('Póliza guardada con avisos',
                `Algunos registros no se crearon: ${errores.join(' | ')}.${detalle}`, 'warning');
        } else if (partes.length) {
            this.showToast('Póliza completa',
                `Póliza guardada. Se generaron: ${partes.join(', ')}.`, 'success');
        } else {
            this.showToast('Póliza', 'Póliza guardada correctamente.', 'success');
        }
    }
    handleError(event) {
        const d = (event && event.detail) || {};
        let msg = d.message || 'No se pudo guardar la póliza.';
        // Desenvuelve el error para decir QUÉ campo lo rompe (antes salía genérico).
        const detalles = [];
        const out = d.output || {};
        if (Array.isArray(out.errors)) {
            out.errors.forEach((e) => { if (e && e.message) { detalles.push(e.message); } });
        }
        if (out.fieldErrors) {
            Object.keys(out.fieldErrors).forEach((campo) => {
                (out.fieldErrors[campo] || []).forEach((fe) => {
                    detalles.push(`${campo}: ${fe.message || fe.statusCode || ''}`.trim());
                });
            });
        }
        if (detalles.length) { msg = detalles.join(' | '); }
        // Loguea el detalle completo para diagnóstico.
        console.error('PolicyCreator::: error al guardar la póliza ->', JSON.stringify(d));
        this.showToast('No se pudo guardar la póliza', msg, 'error');
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
                this._pdfCargado = true;
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
            // Completa límite/deducible/prima de cada cobertura desde su renglón del PDF.
            this.completarCoberturasDesdeTexto(datos, texto);
            // Guarda el JSON para crear/actualizar los objetos hijos al guardar la póliza.
            this._datosPoliza = datos;
            this.fillForm(datos);
            // Una vez subido el PDF, se guarda automáticamente y se pasa a la vista de SOLO
            // LECTURA: el usuario ya no puede modificar los valores de la póliza.
            this.showToast('Listo', 'Datos de la póliza cargados. Guardando…', 'success');
            this.guardarYcerrar();
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error al analizar el PDF.';
            this.showToast('Error', msg, 'error');
        } finally {
            this.analizando = false;
        }
    }

    // Guarda automáticamente la póliza tras subir el PDF y la deja en SOLO LECTURA.
    // Envía el formulario (mismo flujo que "Guardar Póliza": handleSubmit -> handleSuccess
    // -> navegarAPoliza). Espera un momento a que el formulario pinte los valores del PDF.
    guardarYcerrar() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const form = this.template.querySelector('lightning-record-edit-form');
            if (form) { form.submit(); }
        }, 400);
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
                text += this.textoPorRenglones(content.items) + '\n';
            }
            return text.trim();
        } catch (e) {
            return '';
        }
    }

    // Arma el texto de la página respetando los renglones: agrupa los fragmentos por su
    // posición vertical y los ordena de izquierda a derecha. Antes todo se unía en una sola
    // línea y la IA no sabía a qué cobertura pertenecía cada suma, deducible o prima.
    textoPorRenglones(items) {
        const tolerancia = 3;
        const filas = [];
        (items || []).forEach((it) => {
            if (!it || typeof it.str !== 'string' || !it.str.trim() || !it.transform) { return; }
            const x = it.transform[4];
            const y = it.transform[5];
            let fila = filas.find((f) => Math.abs(f.y - y) <= tolerancia);
            if (!fila) {
                fila = { y, partes: [] };
                filas.push(fila);
            }
            fila.partes.push({ x, s: it.str.trim() });
        });
        filas.sort((a, b) => b.y - a.y);
        return filas
            .map((f) => f.partes.sort((a, b) => a.x - b.x).map((p) => p.s).join(' ').replace(/\s+/g, ' ').trim())
            .join('\n');
    }

    // Texto en minúsculas y sin acentos para ubicar el renglón de cada cobertura.
    normCobertura(v) {
        return (v || '').toString().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
            .replace(/[^a-z0-9%$., ]/g, ' ').replace(/\s+/g, ' ').trim();
    }

    // Completa suma asegurada (límite), deducible y prima de cada cobertura leyendo su renglón
    // en el texto del PDF. Solo llena lo que la IA dejó vacío. Funciona sin importar el orden de
    // las columnas: el primer monto es el límite y el último (con centavos) la prima.
    completarCoberturasDesdeTexto(datos, texto) {
        if (!datos || !Array.isArray(datos.coberturas) || !texto) { return datos; }
        const lineas = texto.split('\n').map((l) => this.normCobertura(l));
        const MONTO = '\\$\\s?\\d[\\d,]*(?:\\.\\d+)?(?:\\s?(?:usd|mxn|dlls?))?';
        const TEXTO_SUMA = /\b(amparad[ao]|valor comercial|valor convenido|valor factura|incluid[ao])\b/;
        const PCT = /\d+(?:\.\d+)?\s?%/;
        const vacio = (v) => v === null || v === undefined || v === '';
        const aNumero = (s) => {
            const n = parseFloat(String(s).replace(/[^0-9.]/g, ''));
            return isNaN(n) ? null : n;
        };
        // Ubica el renglón de cada cobertura: primero por el nombre completo; si no, por sus
        // palabras clave sin lo que va entre paréntesis ("RC en USA y Canada (Chubb)").
        const ubicar = (c) => {
            const nombre = this.normCobertura(c && c.nombre);
            if (!nombre || nombre.length < 4) { return null; }
            let idx = lineas.findIndex((l) => l.includes(nombre));
            if (idx >= 0) { return { idx, exacto: true, nombre }; }
            const sinParen = this.normCobertura(String(c.nombre).replace(/\([^)]*\)/g, ' '));
            const claves = sinParen.split(' ').filter((t) => t.length >= 3);
            if (claves.length < 2) { return null; }
            idx = lineas.findIndex((l) => claves.every((t) => l.includes(t)));
            return idx >= 0 ? { idx, exacto: false, nombre: sinParen } : null;
        };
        const ubicaciones = datos.coberturas.map(ubicar);
        // Rango de renglones de la tabla principal (coberturas halladas por su nombre exacto).
        const exactos = ubicaciones.filter((u) => u && u.exacto).map((u) => u.idx);
        const hayTabla = exactos.length >= 3;
        const desde = hayTabla ? Math.min(...exactos) - 2 : -1;
        const hasta = hayTabla ? Math.max(...exactos) + 3 : -1;
        const enTabla = (u) => u && u.idx >= desde && u.idx <= hasta;

        // Coberturas de anexos/certificados de otra compañía (ej. "(Chubb)") que NO están en la
        // tabla principal: se descartan para no duplicarlas (la tabla ya incluye esa cobertura).
        datos.coberturas = datos.coberturas.filter((c, i) => {
            const esAnexo = /\([^)]*\)/.test(String((c && c.nombre) || ''));
            return !(hayTabla && esAnexo && !enTabla(ubicaciones[i]));
        });
        const ubicacionesFinales = datos.coberturas.map(ubicar);

        datos.coberturas.forEach((c, i) => {
            const u = ubicacionesFinales[i];
            if (!u) { return; }
            const linea = lineas[u.idx];
            const resto = u.exacto ? linea.replace(u.nombre, ' ')
                : u.nombre.split(' ').filter((t) => t.length >= 3).reduce((acc, t) => acc.replace(t, ' '), linea);
            const montos = resto.match(new RegExp(MONTO, 'gi')) || [];
            const mTexto = resto.match(TEXTO_SUMA);
            let suma = mTexto ? mTexto[0] : null;
            let prima = null;
            if (montos.length >= 2) {
                suma = suma || montos[0];
                prima = montos[montos.length - 1];
            } else if (montos.length === 1) {
                // Un solo monto: con centavos es la prima ("$450.00"); sin centavos, el límite.
                if (suma || /\.\d{2}/.test(montos[0])) { prima = montos[0]; } else { suma = montos[0]; }
            }
            // En la tabla principal de la póliza, lo impreso manda sobre lo que interpretó la IA;
            // fuera de ella solo se llenan los datos que la IA dejó vacíos.
            const manda = hayTabla && enTabla(u);
            if (prima && (manda || vacio(c.prima))) { c.prima = aNumero(prima); }
            if (suma && (manda || vacio(c.sumaAsegurada))) { c.sumaAsegurada = suma.toUpperCase().replace(/\s+/g, ' ').trim(); }
            const mDed = resto.replace(new RegExp(MONTO, 'gi'), ' ').match(PCT);
            if (mDed && (manda || vacio(c.deducible))) { c.deducible = mDed[0].replace(/\s?%/, ' %'); }
        });
        return datos;
    }

    // Prellena los campos del formulario con el JSON devuelto por la IA.
    fillForm(d) {
        if (!d) { return; }
        const bien = d.bienAsegurado || {};
        const cob = d.cobranza || {};
        let descripcion = d.descripcion || '';

        // Para AUTOS, la Policy Description es SOLO Marca, Modelo y Versión.
        const normTxt = (s) => (s || '').toString().toLowerCase();
        const attrBien = (nombre) => {
            const f = (bien.atributos || []).find((a) => a && normTxt(a.campo).includes(nombre));
            return f ? String(f.valor || '').trim() : '';
        };
        const esAuto = /auto|veh[ií]culo/i.test(d.ramo || '') || /veh[ií]culo/i.test(bien.tipo || '');
        let descripcionAuto = '';
        if (esAuto) {
            const marca = attrBien('marca');
            const modelo = attrBien('modelo') || attrBien('submarca');
            const version = attrBien('version') || d.plan || '';
            const partes = [marca, modelo];
            if (version && !normTxt(modelo).includes(normTxt(version))) { partes.push(version); }
            descripcionAuto = partes.filter(Boolean).join(' ').trim();
        }
        // Para los DEMÁS ramos: descripción BREVE (el bien asegurado), sin listar coberturas,
        // montos ni cobranza (esos ya se guardan como registros/campos aparte).
        let descripcionCorta = (bien.descripcion || d.descripcion || '').toString().trim();
        if (d.plan && !normTxt(descripcionCorta).includes(normTxt(d.plan))) {
            descripcionCorta = descripcionCorta ? `${descripcionCorta} (Plan: ${d.plan})` : `Plan: ${d.plan}`;
        }
        if (descripcionCorta.length > 255) { descripcionCorta = descripcionCorta.substring(0, 255); }
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
        // Fechas de la póliza: en esta org son Fecha/Hora, así que se entregan en ISO 8601
        // (con hora) para no romper el guardado. Si el campo fuera de tipo Fecha se deja
        // solo AAAA-MM-DD (según lo detectado en _dtFlags al cargar el formulario).
        const fechaPoliza = (campo, v) => {
            const s = soloFecha(v);
            if (!s || !/^\d{4}-\d{2}-\d{2}$/.test(s)) { return s; }
            return this._dtFlags[campo] === false ? s : (s + 'T12:00:00.000Z');
        };
        const fechaPrimerVenc = cob.fechaVencimientoPrimerPago
            || (Array.isArray(cob.recibos) && cob.recibos[0] ? cob.recibos[0].fechaLimite : null);

        const map = {
            EffectiveDate: fechaPoliza('EffectiveDate', d.vigenciaDesde),
            ExpirationDate: fechaPoliza('ExpirationDate', d.vigenciaHasta),
            PaymentDueDate: fechaPoliza('PaymentDueDate', fechaPrimerVenc),
            // Datos generales.
            // NO se actualizan por análisis: Aseguradora__c, PolicyType, NameInsuredId,
            // ProductId, SourceQuoteId y la oportunidad origen (se conservan tal cual).
            // El número de póliza va en Name. Universal Policy Number NO se llena aquí:
            // solo aplica a pólizas colectivas/flotilla/grupal y se captura aparte.
            Name: d.numeroPoliza,
            // PlanType es picklist y NO está en el formulario; NO se fuerza desde la IA
            // (un valor fuera del catálogo rompería el guardado). El plan queda en la descripción.
            // El estatus NO se toma del PDF: al crear/subir la póliza debe quedar en "Inicial".
            Status: 'Inicial',
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
            PolicyDescription: esAuto ? (descripcionAuto || descripcionCorta) : descripcionCorta
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
            this.oppStage = o.StageName || '';
            if (!this.readOnly && this.isEtapaBloqueada(o.StageName)) {
                this.readOnly = true;
                if (this.policyId) { this.loadRegistrosPoliza(); }
            }
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
                agente: (o.Producer__r && o.Producer__r.Name) ? o.Producer__r.Name
                    : ((o.Agente_Relacionado__r && o.Agente_Relacionado__r.Name) ? o.Agente_Relacionado__r.Name : '—')
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

    // Carga los registros hijos de la póliza (coberturas, participantes, bien, transacción).
    async loadRegistrosPoliza() {
        if (!this.policyId) { return; }
        try {
            const r = await getRegistrosPoliza({ policyId: this.policyId });
            const reg = r || {};
            // Se muestra el texto tal cual la póliza (ej. "5 %", "AMPARADA") cuando existe;
            // si no, el monto numérico. "—" solo cuando no aplica.
            this.coberturas = (reg.coberturas || []).map((c) => ({
                id: c.id,
                nombre: c.nombre || '—',
                suma: c.suma != null ? this.fmtCurrency(c.suma) : (c.sumaTexto || '—'),
                deducible: c.deducibleTexto || (c.deducible != null ? this.fmtCurrency(c.deducible) : '—'),
                prima: c.prima != null ? this.fmtCurrency(c.prima) : '—'
            }));
            this.participantes = (reg.participantes || []).map((p) => ({
                id: p.id,
                nombre: p.nombre || '—',
                rol: p.rol || '—',
                relacion: p.relacion || '—'
            }));
            this.bienes = (reg.bienes || []).map((b) => ({
                id: b.id,
                nombre: b.nombre || '—',
                activo: b.activo ? 'Activo' : 'Inactivo',
                prima: this.fmtCurrency(b.prima)
            }));
            this.transacciones = (reg.transacciones || []).map((t) => ({
                id: t.id,
                nombre: t.nombre || '—',
                tipo: t.tipo || '—',
                estatus: t.estatus || '—',
                monto: this.fmtCurrency(t.monto),
                fecha: this.fmtDate(t.fecha)
            }));
        } catch (e) {
            // Silencioso: si falla, la vista igual muestra el resto de la póliza.
            console.warn('PolicyCreator::: no se pudieron cargar los registros de la póliza', e);
        }
    }

    get hasCoberturas() { return this.coberturas && this.coberturas.length > 0; }
    get hasParticipantes() { return this.participantes && this.participantes.length > 0; }
    get hasBienes() { return this.bienes && this.bienes.length > 0; }
    get hasTransacciones() { return this.transacciones && this.transacciones.length > 0; }

    get hasQuoteCards() {
        return this.quoteCards && this.quoteCards.length > 0;
    }

    // Póliza, Ganada o Perdida: la información ya no se puede modificar.
    isEtapaBloqueada(stage) {
        const s = (stage || '').toString().toLowerCase();
        return /p[oó]liza/.test(s) || s === 'closed won' || s === 'closed lost';
    }
    get isGanada()  { return this.oppStage === 'Closed Won'; }
    get isPerdida() { return this.oppStage === 'Closed Lost'; }
    get heroClass() {
        if (this.isGanada)  { return 'ro-hero ro-hero--won'; }
        if (this.isPerdida) { return 'ro-hero ro-hero--lost'; }
        return 'ro-hero ro-hero--poliza';
    }
    get heroEtapa() {
        if (this.isGanada)  { return 'Ganada'; }
        if (this.isPerdida) { return 'Perdida'; }
        return 'Póliza emitida';
    }
    get heroIcon() {
        if (this.isGanada)  { return 'utility:success'; }
        if (this.isPerdida) { return 'utility:error'; }
        return 'utility:lock';
    }
    get readOnlyMensaje() {
        if (this.isGanada || this.isPerdida) {
            return 'Oportunidad cerrada: la información se muestra en solo lectura.';
        }
        return 'El PDF de la póliza ya fue cargado: la información se muestra en solo lectura.';
    }
    get aseguradoraHero() {
        const q = (this.quoteCards || []).find((c) => c.aceptada) || (this.quoteCards || [])[0];
        return q ? q.aseguradora : '—';
    }
    get vigenciaHero() {
        const d = this.policyDates || {};
        return (d.EffectiveDate || '—') + '  →  ' + (d.ExpirationDate || '—');
    }
    get quoteCardsView() {
        return (this.quoteCards || []).map((q) => ({
            ...q,
            cardClass: q.aceptada ? 'ro-quote-card ro-quote-card--accepted' : 'ro-quote-card'
        }));
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

    // Devuelve el valor solo si parece un Id de Salesforce (15/18 chars); si no, null.
    // Evita el error "Value provided is invalid for action parameter of type 'Id'" al
    // pasar cadenas vacías o ids de vista previa a métodos Apex.
    idOrNull(v) {
        if (!v) { return null; }
        const s = String(v).trim();
        return /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(s) ? s : null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}