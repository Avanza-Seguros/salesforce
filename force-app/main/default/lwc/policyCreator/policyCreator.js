import { LightningElement, api, wire, track } from 'lwc';
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
// Tamaño máximo del PDF que se adjunta automáticamente: viaja en base64 dentro de la llamada a Apex y Salesforce
// rechaza peticiones de más de ~4 MB. Los más grandes se adjuntan con el cargador estándar (lightning-file-upload).
const MAX_ADJUNTO_AUTOMATICO = 3 * 1024 * 1024;
// Emisión de colectivos: caracteres por bloque de un censo en PDF que se manda a la IA y asegurados por llamada a Apex.
const BLOQUE_CENSO_PDF = 12000;
const LOTE_CENSO = 2000;
// Archivos que se aceptan en la carga de colectivos.
const ACEPTA_COLECTIVO = '.pdf,.xlsx,.xlsm,.xls,.csv,.txt,.docx,.doc,.jpg,.jpeg,.png';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';
import getPolicyIdByQuote from '@salesforce/apex/PolicyController.getPolicyIdByQuote';
import completarPoliza from '@salesforce/apex/PolicyController.completarPoliza';
import guardarDatosPolizaDesdePdf from '@salesforce/apex/PolicyController.guardarDatosPolizaDesdePdf';
import vincularProducer from '@salesforce/apex/PolicyController.vincularProducer';
import analizarPoliza from '@salesforce/apex/PolicyController.analizarPoliza';
import guardarArchivoEnPoliza from '@salesforce/apex/PolicyController.guardarArchivoEnPoliza';
import getRegistrosPoliza from '@salesforce/apex/PolicyController.getRegistrosPoliza';
import datosBasePoliza from '@salesforce/apex/PolicyController.datosBasePoliza';
import datosSinOportunidad from '@salesforce/apex/PolicyController.datosSinOportunidad';
import buscarAgentes from '@salesforce/apex/PolicyController.buscarAgentes';
import asignarAgente from '@salesforce/apex/PolicyController.asignarAgente';
import complementarCamposPoliza from '@salesforce/apex/PolicyController.complementarCamposPoliza';
import ligarOportunidadPoliza from '@salesforce/apex/PolicyController.ligarOportunidadPoliza';
import polizaExistente from '@salesforce/apex/PolizaNumeroUnico.polizaExistente';
import complementarCenso from '@salesforce/apex/CensoColectivoController.complementarCenso';
import analizarCensoPdf from '@salesforce/apex/CensoColectivoController.analizarCensoPdf';
import movimientosSinContacto from '@salesforce/apex/CensoColectivoController.movimientosSinContacto';
import aplicarBajas from '@salesforce/apex/CensoColectivoController.aplicarBajas';
import LightningConfirm from 'lightning/confirm';
import LightningAlert from 'lightning/alert';
import { abrirTabla } from 'c/lectorArchivos';
import {
    TIPOS, ETIQUETAS_TIPO, detectarTipoTabla, detectarTipoPdf, mapeoComo, filasComoObjetos, normalizarCenso,
    miembrosValidos, lotesCenso, vehiculosDesdeTabla, ubicacionesDesdeTabla, unirVehiculos, unirUbicaciones, vehiculosDeCaratulas, MOVIMIENTOS
} from 'c/clasificadorArchivos';
import getOpportunityDetails from '@salesforce/apex/OpportunityController.getOpportunityDetails';
import cambiarEtapaAPoliza from '@salesforce/apex/OpportunityController.cambiarEtapaAPoliza';

// Datos que una póliza sin oportunidad necesita y que el PDF no siempre trae: se capturan a mano antes de guardar.
const CAMPOS_IMPORTANTES = [
    ['Name', 'Número de póliza'], ['NameInsuredId', 'Asegurado'], ['Aseguradora__c', 'Aseguradora'],
    ['Ramo__c', 'Ramo'], ['ProductId', 'Producto'], ['EffectiveDate', 'Inicio de vigencia'],
    ['ExpirationDate', 'Fin de vigencia'], ['PremiumAmount', 'Prima'], ['PremiumFrequency', 'Frecuencia de pago']
];

export default class PolicyCreator extends NavigationMixin(LightningElement) {
    @track policyId;
    @track quoteId;
    @track opportunityId;
    @track loading = true;
    @track errorMsg = '';
    @track analizando = false;
    arrastrando = false;
    @track dates = {};
    @track readOnly = false;
    @track oppCard = null;
    @track quoteCards = [];
    @track policyDates = {};
    @track coberturas = [];
    @track participantes = [];
    @track bienes = [];
    @track transacciones = [];
    // Archivos adjuntos a la póliza (ContentDocument).
    @track archivos = [];
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
    // La póliza aún no existe: se crea al subir el PDF (ya con su número real) con estos datos
    // base de la oportunidad y la cotización aceptada.
    @track esNueva = false;
    // Agente elegido a mano (pólizas sin oportunidad) y buscador.
    agenteId = null;
    agenteTexto = '';
    @track agenteOpciones = [];
    _agenteTimer = null;
    // Sin oportunidad: tras leer el PDF no se guarda sola; se revisan y completan los datos que faltan.
    revisionManual = false;
    @track faltantes = [];
    // Carga masiva: el PDF se procesa sin preguntas ni revisión a mano y el resultado se devuelve a quien lo pidió.
    _masivo = null;
    _formListo = false;
    // Emisión de COLECTIVOS con varios archivos: archivos seleccionados con el tipo detectado (editable por el
    // usuario antes de procesar), archivos por adjuntar cuando exista la póliza y avance del proceso.
    // Solo datos ligeros (se pintan en la revisión). El contenido de cada archivo (File, filas del Excel, texto del
    // PDF) va en _cargaDatos, fuera del estado reactivo, y las conversiones se guardan en _conversiones.
    cargaArchivos = [];
    _cargaDatos = {};
    _conversiones = {};
    mostrarCarga = false;
    progresoCarga = '';
    tipoContratacion = '';
    _adjuntosPendientes = [];
    // Oportunidad de la póliza existente que se complementa (si es otra que la de la pantalla).
    _oportunidadPoliza = null;
    _datosBase = null;
    _basePintada = false;
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

    connectedCallback() {
        console.log(':::policyCreator::: Componente conectado');
        this.isLoading = true;
        this.loadPdfJs();
    }

	renderedCallback() {
		if (!this.isPdfJsLoaded && !this.pdfJsError) {
			this.loadPdfJs();
		}
	}

	async loadPdfJs() {
        try {
            await this.loadPdfJsScript();
            await this.setupWorker();
            await this.testPdfJs();
            
            this.isPdfJsLoaded = true;
            this.pdfJsError = false;
            console.log(':::policyCreator::: ✅ PDF.js cargado exitosamente');
        } catch (error) {
            console.error(':::policyCreator::: ❌ Error cargando PDF.js:', JSON.stringify(error));
            this.pdfJsError = true;
            this.showToast('Error', 'No se pudo cargar PDF.js. Recarga la página.', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadPdfJsScript() {
        try {
            const mainScript = PDFJS + '/pdf.js';
            await loadScript(this, mainScript);
            
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('pdfjsLib no se definió después de cargar el script');
            }
            console.log(':::policyCreator::: ✅ Script PDF.js cargado');
        } catch (error) {
            console.warn('⚠️ Falló versión principal, intentando versión min...');
            const minScript = PDFJS + '/pdf.min.js';
            await loadScript(this, minScript);
            
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('pdfjsLib no disponible en ninguna versión');
            }
        }
    }

    async setupWorker() {
        try {
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS + '/pdf.worker.js';
        } catch (workerError) {
            console.warn('⚠️ Error configurando worker:', workerError);
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = null;
        }
    }

    async testPdfJs() {
        try {
            const pdfData = new Uint8Array([
                0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A, 0x25,
                0xC3, 0xA4, 0xC3, 0xBC, 0xC3, 0xB6, 0xC3, 0x9F, 0x0A, 0x31,
                0x20, 0x30, 0x20, 0x6F, 0x62, 0x6A, 0x0A, 0x3C, 0x3C, 0x2F,
                0x54, 0x79, 0x70, 0x65, 0x2F, 0x43, 0x61, 0x74, 0x61, 0x6C,
                0x6F, 0x67, 0x2F, 0x50, 0x61, 0x67, 0x65, 0x73, 0x20, 0x32,
                0x20, 0x30, 0x20, 0x52, 0x3E, 0x3E, 0x0A, 0x65, 0x6E, 0x64, 0x6F, 0x62, 0x6A, 0x0A
            ]);

            const fontsUrl = fontsResource + '/';
            
            const loadingTask = window.pdfjsLib.getDocument({ 
                data: pdfData,
                isEvalSupported: false,   // ← Salesforce (LWS) bloquea eval()
                useWorkerFetch: false,    // ← evita fetch bloqueado por CSP
                standardFontDataUrl: fontsUrl,
                disableFontFace: true     // ← evita cargar fuentes externas
            });
            const timeout = new Promise((_, reject) => 
                setTimeout(() => reject(new Error('Timeout probando PDF.js')), 5000)
            );
            
            const pdf = await Promise.race([loadingTask.promise, timeout]);
            if (pdf && pdf.destroy) {
                await pdf.destroy();
            }
            
            console.log(':::policyCreator::: ✅ PDF.js funciona correctamente');
        } catch (testError) {
            console.warn('⚠️ Test de PDF.js falló:', testError.message);
        }
    }

    async loadPolicy() {
        this.loading = true;
        this.errorMsg = '';
        this.policyId = null;
        this.esNueva = false;
        this._oportunidadPoliza = null;
        this._adjuntosPendientes = [];
        this._datosBase = null;
        this._basePintada = false;
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
            } else if (!this.readOnly) {
                // Aún no hay póliza: se creará al subir el PDF, con los datos base precargados
                // (de la oportunidad y la cotización, si se abrió desde una).
                this._datosBase = await datosBasePoliza({
                    opportunityId: this.idOrNull(this.opportunityId),
                    quoteId: this.idOrNull(this.quoteId)
                });
                this.esNueva = true;
            } else {
                this.errorMsg = 'Esta oportunidad todavía no tiene póliza.';
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
    // Formulario visible: póliza existente o alta de una nueva (desde su oportunidad).
    get mostrarFormulario() {
        return !!this.policyId || this.esNueva;
    }
    get isReadOnly() {
        return this.readOnly;
    }
    // Póliza sin oportunidad ni cotización (emisión directa o automática).
    get sinOportunidad() {
        return !this.idOrNull(this.opportunityId) && !this.idOrNull(this.quoteId);
    }
    // El agente se elige a mano cuando no viene de una oportunidad (solo al crear la póliza).
    get agenteEditable() {
        return this.isEditable && this.sinOportunidad && !this.policyId;
    }
    get hayAgenteOpciones() {
        return this.agenteOpciones.length > 0;
    }
    get hayFaltantes() {
        return this.revisionManual && this.faltantes.length > 0;
    }
    get textoFaltantes() {
        return this.faltantes.join(', ');
    }
    get mostrarListoParaGuardar() {
        return this.revisionManual && this.faltantes.length === 0;
    }

    handleAgenteBuscar(event) {
        this.agenteTexto = event.target.value || '';
        if (!this.agenteTexto) { this.agenteId = null; this.revisarFaltantes(); }
        clearTimeout(this._agenteTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._agenteTimer = setTimeout(() => this.cargarAgentes(), 250);
    }
    handleAgenteFoco() {
        if (!this.agenteOpciones.length) { this.cargarAgentes(); }
    }
    async cargarAgentes() {
        try {
            const r = await buscarAgentes({ texto: this.agenteTexto });
            this.agenteOpciones = (r || []).map((a) => ({ ...a, tipo: a.tipo || '' }));
        } catch (e) {
            this.agenteOpciones = [];
        }
    }
    handleAgenteElegir(event) {
        const { id, nombre } = event.currentTarget.dataset;
        this.agenteId = id;
        this.agenteTexto = nombre;
        this.agenteOpciones = [];
        this.revisarFaltantes();
    }
    handleAgenteQuitar() {
        this.agenteId = null;
        this.agenteTexto = '';
        this.agenteOpciones = [];
        this.revisarFaltantes();
    }
    handleCampoCambio() {
        if (this.revisionManual) { this.revisarFaltantes(); }
    }

    // Datos importantes que siguen vacíos (ni el PDF ni los datos base los traen): se piden antes de guardar.
    revisarFaltantes() {
        if (!this.revisionManual) { this.faltantes = []; return; }
        const valores = {};
        this.template.querySelectorAll('lightning-input-field').forEach((f) => { valores[f.fieldName] = f.value; });
        const vacio = (k) => {
            const v = valores[k] !== undefined ? valores[k] : (this.hiddenFields[k] ?? (this._datosBase || {})[k]);
            return v === undefined || v === null || v === '';
        };
        const faltan = CAMPOS_IMPORTANTES.filter(([k]) => vacio(k)).map(([, etiqueta]) => etiqueta);
        if (!this.agenteId) { faltan.push('Agente'); }
        this.faltantes = faltan;
    }

    get textoPolizaNueva() {
        return this.opportunityId || this.quoteId
            ? 'La póliza se creará al cargar su PDF, con el número real. Los datos de la oportunidad y la cotización ya están precargados.'
            : 'Póliza sin oportunidad: se creará al cargar su PDF, con el número real. El cliente (se da de alta si no existe), la aseguradora y el ramo se toman del PDF.';
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
        if (this.analizando && this.progresoCarga) { return this.progresoCarga; }
        return this.analizando ? 'Analizando el PDF de la póliza…' : 'Cargando la póliza…';
    }

    // ============================================================
    // EMISIÓN DE COLECTIVOS: varios archivos por carga
    // ============================================================
    get isColectiva() {
        return this.tipoContratacion === 'Colectiva';
    }
    // Colectivos: se pueden cargar archivos al emitir y también después, para complementar la póliza emitida
    // (salvo en una oportunidad perdida).
    get mostrarCargaColectiva() {
        return this.isColectiva && (this.isEditable || (!!this.policyId && !this.isPerdida));
    }
    get mostrarPdfIndividual() {
        return !this.isColectiva && this.isEditable;
    }
    get aceptaColectivo() {
        return ACEPTA_COLECTIVO;
    }
    get textoBotonArchivos() {
        return this.policyId ? 'Complementar con archivos' : 'Cargar archivos de la póliza';
    }
    get subtituloCarga() {
        return this.policyId
            ? 'La póliza ya existe: se complementa con estos archivos (solo se llenan los datos que faltan y no se duplican asegurados, vehículos ni ubicaciones).'
            : 'Revisa lo que se detectó en cada archivo. La carátula (PDF de la póliza) es necesaria para emitirla.';
    }
    get textoProcesar() {
        return this.policyId ? 'Complementar póliza' : 'Emitir póliza';
    }
    get cargaVista() {
        return this.cargaArchivos.map((a) => ({
            ...a,
            opciones: a.tiposPosibles.map((t) => ({ label: ETIQUETAS_TIPO[t], value: t })),
            detalle: this.detalleArchivo(this.conDatos(a))
        }));
    }
    // Renglón de la revisión con el contenido de su archivo (File, filas, texto).
    conDatos(a) {
        return { ...a, ...(this._cargaDatos[a.key] || {}) };
    }
    get avisoCarga() {
        if (!this.policyId && !this.cargaArchivos.some((a) => a.tipo === TIPOS.POLIZA)) {
            return 'No se detectó la carátula de la póliza. Indica cuál PDF es la póliza o agrégalo a la carga para poder emitirla.';
        }
        return '';
    }

    // Abre el selector de archivos (varios) de un colectivo.
    handleCargarArchivos() {
        const input = this.template.querySelector('input.colectivo-file-input');
        if (input) { input.value = null; input.click(); }
    }

    // Lee cada archivo y detecta su contenido: carátula o censo (PDF), censo / flotilla / ubicaciones (Excel o CSV)
    // o solo adjunto. Un Excel con varias hojas reconocidas da un renglón por hoja.
    async handleArchivosColectivo(event) {
        const files = Array.from((event.target && event.target.files) || []);
        if (!files.length) { return; }
        this.analizando = true;
        this._cargaDatos = {};
        this._conversiones = {};
        const carga = [];
        try {
            for (let i = 0; i < files.length; i++) {
                const file = files[i];
                this.progresoCarga = `Revisando ${file.name} (${i + 1} de ${files.length})…`;
                // eslint-disable-next-line no-await-in-loop
                const renglones = await this.clasificarArchivo(file, i);
                // El contenido pesado se separa del renglón que se pinta.
                renglones.forEach((r) => {
                    const { file: f, filas, texto, ...ligero } = r;
                    this._cargaDatos[r.key] = { file: f, filas, texto };
                    carga.push({ ...ligero, esTabla: !!filas });
                });
            }
            // Si hay varias carátulas, la primera es la principal; las demás (endosos, anexos) se leen solo para
            // vehículos y ubicaciones.
            this.cargaArchivos = carga;
            this.mostrarCarga = true;
        } catch (e) {
            this.showToast('Error', this.mensajeError(e, 'No se pudieron leer los archivos.'), 'error');
        } finally {
            this.analizando = false;
            this.progresoCarga = '';
        }
    }

    async clasificarArchivo(file, i) {
        const ext = (file.name.split('.').pop() || '').toLowerCase();
        const base = { file, archivo: file.name, tamano: this.fmtMb(file.size) };
        if (ext === 'pdf') {
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('El lector de PDF aún se está cargando. Intenta de nuevo en unos segundos.');
            }
            const texto = await this.extractPdfText(file);
            const tipo = detectarTipoPdf(file.name, texto);
            return [{ ...base, key: `a${i}`, etiquetaArchivo: file.name, texto, tipo,
                tiposPosibles: texto ? [TIPOS.POLIZA, TIPOS.CENSO, TIPOS.ADJUNTO] : [TIPOS.ADJUNTO] }];
        }
        if (['xlsx', 'xlsm', 'xls', 'csv', 'txt'].includes(ext)) {
            let tabla;
            try {
                tabla = await abrirTabla(file);
            } catch (e) {
                return [{ ...base, key: `a${i}`, etiquetaArchivo: file.name, tipo: TIPOS.ADJUNTO, tiposPosibles: [TIPOS.ADJUNTO],
                    error: this.mensajeError(e, 'No se pudo leer') }];
            }
            const hojas = tabla.hojas.length ? tabla.hojas : [''];
            const tiposTabla = [TIPOS.CENSO, TIPOS.VEHICULOS, TIPOS.UBICACIONES, TIPOS.ADJUNTO];
            const renglones = [];
            for (let h = 0; h < hojas.length; h++) {
                // eslint-disable-next-line no-await-in-loop
                const filas = await tabla.leerHoja(hojas[h]);
                const det = detectarTipoTabla(filas, `${file.name} ${hojas[h]}`);
                if (det.tipo === TIPOS.ADJUNTO) { continue; }
                renglones.push({ ...base, key: `a${i}h${h}`, hoja: hojas[h], filas, tipo: det.tipo, tiposPosibles: tiposTabla,
                    etiquetaArchivo: hojas.length > 1 ? `${file.name} · hoja «${hojas[h]}»` : file.name });
            }
            if (renglones.length) { return renglones; }
            // Ninguna hoja se reconoció: se puede indicar a mano el tipo de la primera hoja.
            const filas = await tabla.leerHoja(hojas[0]);
            return [{ ...base, key: `a${i}`, hoja: hojas[0], filas, tipo: TIPOS.ADJUNTO, tiposPosibles: tiposTabla,
                etiquetaArchivo: file.name }];
        }
        return [{ ...base, key: `a${i}`, etiquetaArchivo: file.name, tipo: TIPOS.ADJUNTO, tiposPosibles: [TIPOS.ADJUNTO] }];
    }

    // Texto de la columna "Detalle": qué se va a hacer con el archivo según su tipo.
    detalleArchivo(a) {
        if (a.error) { return `${a.error}. Se adjunta a la póliza.`; }
        if (a.tipo === TIPOS.POLIZA) {
            const principal = this.cargaArchivos.find((x) => x.tipo === TIPOS.POLIZA);
            return principal === a || (principal && principal.key === a.key)
                ? 'Se analiza con IA: datos de la póliza, coberturas, primas, vehículos y ubicaciones.'
                : 'Póliza adicional (endoso/anexo): se toman sus vehículos y ubicaciones.';
        }
        if (a.tipo === TIPOS.CENSO && !a.filas) { return 'Censo en PDF: se lee con IA y se agregan los asegurados que falten.'; }
        if (a.tipo === TIPOS.ADJUNTO) { return 'Se adjunta a la póliza.'; }
        const r = this.convertirTabla(a);
        if (r.error) { return r.error; }
        if (a.tipo === TIPOS.CENSO) {
            const mv = r.movimientos || {};
            const movimientos = mv.hay
                ? ` · Movimientos: ${mv.altas} alta(s), ${mv.bajas} baja(s), ${mv.cambios} cambio(s)`
                    + (mv.bajas ? ' (las bajas se quitan del censo y, si la póliza ya existe, de la póliza)' : '')
                : '';
            return `${r.miembros.length} asegurado(s)` + movimientos + (r.conError ? ` · ${r.conError} con error se omiten` : '')
                + ' · se agregan los que falten al censo y a la póliza.';
        }
        if (a.tipo === TIPOS.VEHICULOS) { return `${r.vehiculos.length} vehículo(s) · se crean o completan sus incisos.`; }
        return `${r.ubicaciones.length} ubicación(es) · se crean o completan como bienes de la póliza.`;
    }

    // Convierte una hoja según el tipo elegido: { miembros, conError } / { vehiculos } / { ubicaciones } o { error }.
    // Se guarda por archivo y tipo: la revisión se vuelve a pintar varias veces y un censo puede tener miles de renglones.
    convertirTabla(a) {
        const llave = `${a.key}|${a.tipo}`;
        if (!this._conversiones[llave]) { this._conversiones[llave] = this.convertirTablaSinCache(a); }
        return this._conversiones[llave];
    }
    convertirTablaSinCache(a) {
        const m = mapeoComo(a.tipo, a.filas || []);
        if (!m.valido) {
            return { error: 'No se reconocen las columnas para este tipo. Revisa el archivo o elige «Solo adjuntar».',
                miembros: [], vehiculos: [], ubicaciones: [], conError: 0 };
        }
        if (a.tipo === TIPOS.CENSO) {
            return miembrosValidos(normalizarCenso(filasComoObjetos(a.filas, m.encabezado, m.mapeo)));
        }
        if (a.tipo === TIPOS.VEHICULOS) { return { vehiculos: vehiculosDesdeTabla(a.filas, m.encabezado, m.mapeo) }; }
        return { ubicaciones: ubicacionesDesdeTabla(a.filas, m.encabezado, m.mapeo) };
    }

    handleTipoArchivo(event) {
        const key = event.target.dataset.key;
        const tipo = event.detail.value;
        this.cargaArchivos = this.cargaArchivos.map((a) => (a.key === key ? { ...a, tipo } : a));
    }

    cancelarCarga() {
        this.mostrarCarga = false;
        this.limpiarCarga();
    }

    limpiarCarga() {
        this.cargaArchivos = [];
        this._cargaDatos = {};
        this._conversiones = {};
    }

    // Procesa la carga: analiza la carátula, junta censo, vehículos y ubicaciones de todos los archivos y crea la
    // póliza o, si ya existe, la complementa (solo lo que falta, sin duplicar).
    async procesarCarga() {
        const carga = this.cargaArchivos.map((a) => this.conDatos(a));
        const polizas = carga.filter((a) => a.tipo === TIPOS.POLIZA);
        if (!this.policyId && !polizas.length) {
            this.showToast('Falta la póliza', 'Para emitir la póliza incluye su PDF (carátula) en la carga.', 'warning');
            return;
        }
        this.mostrarCarga = false;
        this.analizando = true;
        try {
            // 1) Carátula principal con IA; los demás PDFs de póliza aportan vehículos y ubicaciones.
            let datos = null;
            if (polizas.length) {
                this.progresoCarga = `Analizando con IA la póliza ${polizas[0].archivo}…`;
                datos = await this.analizarTextoPoliza(polizas[0].texto);
                if (!datos) { return; }
                polizas.slice(1).forEach((p) => {
                    // Un PDF adicional puede ser el endoso de alta de un solo inciso: también cuenta.
                    datos.vehiculos = unirVehiculos(datos.vehiculos, vehiculosDeCaratulas(p.texto, 1));
                    datos.ubicaciones = unirUbicaciones(datos.ubicaciones, this.ubicacionesDesdeTexto(p.texto));
                });
                // 2) Si la póliza (mismo número y vigencia) ya existe, se complementa en lugar de crear otra.
                const seguir = await this.resolverPolizaExistente(datos);
                if (!seguir) { return; }
            }
            const sinCaratula = !datos;
            datos = datos || {};
            datos._sinCaratula = sinCaratula;

            // 3) Excel / CSV: censo, flotilla y ubicaciones.
            let miembros = [];
            let omitidos = 0;
            const revisar = [];
            for (const a of carga) {
                if (a.tipo === TIPOS.CENSO) {
                    this.progresoCarga = `Leyendo el censo ${a.etiquetaArchivo}…`;
                    // eslint-disable-next-line no-await-in-loop
                    const r = a.filas ? this.convertirTabla(a) : await this.censoDesdePdf(a);
                    miembros = miembros.concat(this.desplazarTitulares(r.miembros || [], miembros.length));
                    omitidos += r.conError || 0;
                    (r.revisar || []).forEach((p) => revisar.push({ ...p, archivo: a.etiquetaArchivo }));
                } else if (a.tipo === TIPOS.VEHICULOS && a.filas) {
                    const r = this.convertirTabla(a);
                    if ((r.vehiculos || []).length) {
                        datos.vehiculos = unirVehiculos(datos.vehiculos, r.vehiculos);
                        datos._vehiculosArchivo = true;
                    }
                } else if (a.tipo === TIPOS.UBICACIONES && a.filas) {
                    const r = this.convertirTabla(a);
                    if ((r.ubicaciones || []).length) {
                        datos.ubicaciones = unirUbicaciones(datos.ubicaciones, r.ubicaciones);
                        datos._ubicacionesArchivo = true;
                    }
                }
            }

            // 4) Censo: se agregan a la oportunidad los asegurados que falten; al guardar la póliza se copian a ella.
            const avisos = [];
            if (miembros.length) {
                const oppId = this.idOrNull(this._oportunidadPoliza || this.opportunityId);
                if (!oppId) {
                    avisos.push('el censo no se cargó porque la póliza no tiene oportunidad');
                } else {
                    const lotes = lotesCenso(miembros, LOTE_CENSO);
                    let nuevos = 0;
                    for (let i = 0; i < lotes.length; i++) {
                        this.progresoCarga = lotes.length > 1 ? `Guardando censo (lote ${i + 1} de ${lotes.length})…` : 'Guardando censo…';
                        // eslint-disable-next-line no-await-in-loop
                        const r = await complementarCenso({ opportunityId: oppId, miembrosJson: JSON.stringify(lotes[i]) });
                        nuevos += (r && r.nuevos) || 0;
                    }
                    avisos.push(`censo: ${nuevos} asegurado(s) nuevo(s)` + (omitidos ? `, ${omitidos} renglón(es) con error omitidos` : ''));
                }
            }

            // Bajas (se quitan del censo y, si la póliza ya existe, sus participantes quedan inactivos) y aviso
            // informativo de las bajas y cambios de personas que no existen.
            if (revisar.length) { await this.aplicarMovimientos(revisar, avisos); }

            // 5) Archivos por adjuntar a la póliza (cada archivo una vez; los grandes se suben aparte).
            this.progresoCarga = 'Preparando archivos…';
            await this.prepararAdjuntos(carga);

            // 6) Póliza nueva: mismo flujo que el PDF individual (formulario -> handleSuccess). Ya existe: se complementa.
            if (!this.policyId) {
                this._pdfCargado = true;
                this._datosPoliza = datos;
                this.fillForm(datos);
                if (avisos.length) { this.showToast('Carga de archivos', avisos.join(' · '), 'info'); }
                this.showToast('Listo', 'Datos de la póliza cargados. Guardando…', 'success');
                this.guardarYcerrar();
                return;
            }
            await this.complementarPolizaExistente(datos, sinCaratula, avisos);
        } catch (e) {
            this.showToast('Error', this.mensajeError(e, 'No se pudieron procesar los archivos.'), 'error');
        } finally {
            this.analizando = false;
            this.progresoCarga = '';
            this.limpiarCarga();
        }
    }

    // La póliza ya existe: llena solo sus campos vacíos, adjunta los archivos y crea/completa sus registros hijos.
    async complementarPolizaExistente(datos, sinCaratula, avisos) {
        const policyId = this.policyId;
        if (!sinCaratula) {
            this.progresoCarga = 'Complementando los datos de la póliza…';
            const llenados = await complementarCamposPoliza({ policyId, camposJson: JSON.stringify(this.camposDesdeDatos(datos)) });
            if (llenados && llenados.length) { avisos.push(`${llenados.length} dato(s) de la póliza completados`); }
        }
        // La póliza se liga a la oportunidad desde la que se emite (y a su cotización y agente) si no la tiene.
        const oppEmision = this.idOrNull(this.opportunityId);
        if (oppEmision) {
            try {
                const ligados = await ligarOportunidadPoliza({ policyId, opportunityId: oppEmision, quoteId: this.idOrNull(this.quoteId) });
                if (ligados && ligados.includes('SourceOpportunityId')) { avisos.push('póliza ligada a la oportunidad'); }
                await vincularProducer({ policyId, opportunityId: oppEmision });
            } catch (e) {
                avisos.push(this.mensajeError(e, 'no se pudo ligar la póliza a la oportunidad'));
            }
        }
        this.progresoCarga = 'Adjuntando archivos…';
        await this.adjuntarPendientes();
        this.progresoCarga = 'Guardando asegurados, vehículos, ubicaciones y coberturas…';
        const resumen = await guardarDatosPolizaDesdePdf({
            policyId,
            opportunityId: this.idOrNull(this._oportunidadPoliza || this.opportunityId),
            datosJson: JSON.stringify(datos)
        });
        this.mostrarResumenPoliza(resumen);
        if (avisos.length) { this.showToast('Póliza complementada', avisos.join(' · '), 'info'); }
        notifyRecordUpdateAvailable([{ recordId: policyId }]);
        if (this.readOnly) {
            await this.loadRegistrosPoliza();
            return;
        }
        // Con la carátula, la oportunidad pasa a Póliza (igual que al emitir con el PDF).
        this._pdfCargado = !sinCaratula;
        await this.finalizarEmision();
    }

    // Revisa si ya hay una póliza con el número y la vigencia de la carátula. Si existe y el usuario puede editarla,
    // pregunta y se toma esa póliza para complementarla. Devuelve false si no se debe continuar.
    async resolverPolizaExistente(datos) {
        if (!datos.numeroPoliza) { return true; }
        const vigencia = datos.vigenciaDesde || (this._datosBase && this._datosBase.EffectiveDate) || null;
        const r = await polizaExistente({
            numero: datos.numeroPoliza,
            vigenciaDesde: vigencia ? String(vigencia).substring(0, 10) : null,
            policyId: this.idOrNull(this.policyId)
        }) || {};
        if (r.error) {
            this.showToast('Póliza repetida', r.error, 'error');
            return false;
        }
        if (!r.policyId) { return true; }
        if (this.policyId) {
            this.showToast('Póliza repetida',
                `El número ${datos.numeroPoliza} ya pertenece a otra póliza (${r.nombre}). Esta oportunidad ya tiene su propia póliza.`, 'error');
            return false;
        }
        // Carga masiva: la póliza existente se actualiza sin preguntar.
        const ok = this._masivo ? true : await LightningConfirm.open({
            message: `La póliza ${r.nombre} ya existe con el número ${datos.numeroPoliza} y la misma vigencia. `
                + 'En lugar de crear otra, se actualizará esa póliza: se llenan los datos que le faltan y se crean los participantes, '
            + 'bienes y coberturas que no tenga. ¿Continuar?',
            variant: 'header', label: 'La póliza ya existe', theme: 'info'
        });
        if (!ok) { return false; }
        this.policyId = r.policyId;
        this.esNueva = false;
        this._oportunidadPoliza = r.oportunidadId || null;
        return true;
    }

    // Aplica las bajas del censo y avisa (solo informativo) de las bajas y cambios de personas que no existen: una
    // baja de alguien que no existe no se puede aplicar y un cambio se agrega como asegurado nuevo.
    async aplicarMovimientos(revisar, avisos) {
        const oppId = this.idOrNull(this._oportunidadPoliza || this.opportunityId);
        // Cada renglón se identifica por su posición: las filas se repiten entre archivos.
        const personas = revisar.map((p, i) => ({ ...p, fila: i + 1 }));
        const bajas = personas.filter((p) => p.movimiento === MOVIMIENTOS.BAJA);
        const cambios = personas.filter((p) => p.movimiento === MOVIMIENTOS.CAMBIO);
        const faltan = [];
        if (bajas.length) {
            this.progresoCarga = 'Aplicando bajas…';
            const r = await aplicarBajas({ opportunityId: oppId, policyId: this.idOrNull(this.policyId), personasJson: JSON.stringify(bajas) }) || {};
            const aplicadas = bajas.length - (r.noEncontrados || []).length;
            if (aplicadas) {
                avisos.push(`${aplicadas} baja(s) aplicada(s)` + (r.poliza ? ` (${r.poliza} participante(s) inactivado(s) en la póliza)` : ''));
            }
            faltan.push(...(r.noEncontrados || []));
        }
        if (cambios.length) {
            try {
                faltan.push(...(await movimientosSinContacto({ opportunityId: oppId, accountId: null, personasJson: JSON.stringify(cambios) }) || []));
            } catch (e) {
                // Solo es un aviso: si la revisión falla, la carga sigue.
            }
        }
        if (!faltan.length) { return; }
        const lista = faltan.map((n) => revisar[n - 1]).filter((p) => p);
        const MAX = 15;
        const lineas = lista.slice(0, MAX).map((p) => `• ${p.movimiento}: ${p.nombreCompleto || '(sin nombre)'}`
            + (p.certificado ? ` (cert. ${p.certificado})` : '') + ` — fila ${p.fila} de ${p.archivo}`);
        if (lista.length > MAX) { lineas.push(`… y ${lista.length - MAX} más`); }
        await LightningAlert.open({
            message: `${lista.length === 1 ? 'El siguiente movimiento corresponde a una persona que no está registrada'
                : `Los siguientes ${lista.length} movimientos corresponden a personas que no están registradas`} en la póliza:\n`
                + lineas.join('\n')
                + '\n\nLas bajas no serán procesadas y los cambios se registrarán como altas de asegurados. '
                + 'El resto de la carga continuará normalmente. Se recomienda validar la información con la aseguradora.',
            variant: 'header', label: 'Movimientos no localizados', theme: 'info'
        });
    }

    // Censo en PDF: el texto se manda a la IA por bloques y se valida igual que un Excel.
    async censoDesdePdf(a) {
        const bloques = this.bloquesTexto(a.texto, BLOQUE_CENSO_PDF);
        const datos = [];
        for (let i = 0; i < bloques.length; i++) {
            this.progresoCarga = `Leyendo el censo ${a.archivo} con IA (bloque ${i + 1} de ${bloques.length})…`;
            // eslint-disable-next-line no-await-in-loop
            const json = await analizarCensoPdf({ textoCenso: bloques[i] });
            let r = {};
            try { r = JSON.parse(json || '{}'); } catch (e) { r = {}; }
            (r.asegurados || []).forEach((x) => datos.push({ ...x, fila: datos.length + 1 }));
        }
        return miembrosValidos(normalizarCenso(datos));
    }

    // Parte un texto en bloques de hasta "max" caracteres por renglones completos.
    bloquesTexto(texto, max) {
        const bloques = [];
        let actual = '';
        String(texto || '').split('\n').forEach((l) => {
            if (actual && actual.length + l.length + 1 > max) { bloques.push(actual); actual = ''; }
            actual += l + '\n';
        });
        if (actual.trim()) { bloques.push(actual); }
        return bloques;
    }

    // Al juntar censos de varios archivos, el titularIndex se recorre a su posición en la lista completa.
    desplazarTitulares(miembros, desplazamiento) {
        return miembros.map((m) => ({
            ...m,
            titularIndex: m.titularIndex === null || m.titularIndex === undefined ? null : m.titularIndex + desplazamiento
        }));
    }

    // Lee en base64 los archivos de la carga (cada archivo una sola vez) para adjuntarlos a la póliza. Los que no
    // caben en la llamada a Apex se avisan para subirlos en «Archivos de la póliza».
    async prepararAdjuntos(carga) {
        const vistos = new Set();
        const grandes = [];
        const pendientes = [];
        for (const a of carga) {
            if (vistos.has(a.file)) { continue; }
            vistos.add(a.file);
            if (a.file.size > MAX_ADJUNTO_AUTOMATICO) { grandes.push(a.archivo); continue; }
            // eslint-disable-next-line no-await-in-loop
            pendientes.push({ nombre: a.archivo, base64: await this.readFileAsBase64(a.file) });
        }
        this._adjuntosPendientes = pendientes;
        if (grandes.length) {
            this.showToast('Adjunta estos archivos al terminar',
                `${grandes.join(', ')} pesan más de ${this.fmtMb(MAX_ADJUNTO_AUTOMATICO)} y no se adjuntan automáticamente. Súbelos en la sección «Archivos de la póliza».`,
                'warning');
        }
    }

    // Adjunta a la póliza los archivos pendientes de la carga de colectivos (idempotente por nombre).
    async adjuntarPendientes() {
        if (!this.policyId || !this._adjuntosPendientes.length) { return; }
        const fallidos = [];
        const pendientes = this._adjuntosPendientes;
        this._adjuntosPendientes = [];
        for (const a of pendientes) {
            try {
                // eslint-disable-next-line no-await-in-loop
                await guardarArchivoEnPoliza({ base64: a.base64, nombreArchivo: a.nombre, policyId: this.policyId });
            } catch (e) {
                fallidos.push(a.nombre);
            }
        }
        if (fallidos.length) {
            this.showToast('Algunos archivos no se adjuntaron',
                `${fallidos.join(', ')}. Súbelos en la sección «Archivos de la póliza».`, 'warning');
        }
    }

    mensajeError(e, porDefecto) {
        return (e && e.body && e.body.message) || (e && e.message) || porDefecto;
    }

    // Al cargar el registro, toma los valores de fecha y detecta si son Fecha/Hora.
    handleLoad(event) {
        this._formListo = true;
        // Póliza nueva: muestra los datos base (asegurado, aseguradora, producto, prima…) en el formulario.
        if (!this.policyId && this._datosBase && !this._basePintada) {
            this._basePintada = true;
            this.template.querySelectorAll('lightning-input-field').forEach((f) => {
                let v = this._datosBase[f.fieldName];
                // Las fechas de póliza son Fecha/Hora en esta org.
                if (this.POLICY_DATE_FIELDS.includes(f.fieldName) && /^\d{4}-\d{2}-\d{2}$/.test(v || '')) {
                    v = v + 'T12:00:00.000Z';
                }
                if (v !== undefined && v !== null && (f.value === undefined || f.value === null || f.value === '')) {
                    try { f.value = v; } catch (e) { /* campo de solo lectura */ }
                }
            });
        }
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
        const fields = this.armarCampos({ ...(event.detail ? event.detail.fields : {}) });
        const form = this.template.querySelector('lightning-record-edit-form');
        if (form) { form.submit(fields); }
    }

    // Arma los campos a guardar: lo capturado en pantalla, los datos de la IA que no se
    // muestran, los datos base (solo al crear la póliza) y las fechas en el formato del org.
    armarCampos(fields) {
        // Al crear la póliza: los datos base de la oportunidad y la cotización completan lo vacío.
        if (!this.policyId && this._datosBase) {
            Object.keys(this._datosBase).forEach((k) => {
                const v = fields[k];
                if (v === undefined || v === null || v === '') { fields[k] = this._datosBase[k]; }
            });
            if (this._datosBase.SourceOpportunityId) { fields.SourceOpportunityId = this._datosBase.SourceOpportunityId; }
        }
        // Lo capturado en pantalla manda. Los datos de la IA solo se agregan para campos
        // que NO están en el formulario; si el campo está presente (aunque el usuario lo
        // haya vaciado a propósito) se respeta lo que envía el formulario.
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
        return fields;
    }

    async handleSuccess(event) {
        // Id de la póliza (nueva o existente).
        const savedId = (event && event.detail && event.detail.id) || this.policyId;
        this.policyId = savedId;
        this.esNueva = false;
        // Ya se guardaron: se limpian para no reescribirlos en un guardado posterior.
        this.hiddenFields = {};
        // Refresca el registro para que la pantalla muestre lo guardado.
        if (savedId) {
            // Agente elegido a mano (póliza sin oportunidad): se asigna con Apex (el formulario no admite Producer).
            if (this.agenteId) {
                try {
                    await asignarAgente({ policyId: savedId, producerId: this.agenteId });
                } catch (e) {
                    this.showToast('Agente', this.mensajeError(e, 'No se pudo asignar el agente.'), 'warning');
                }
            }
            notifyRecordUpdateAvailable([{ recordId: savedId }]);
            // Adjunta el PDF que se haya seleccionado antes de que existiera la póliza.
            await this.guardarPdfEnPoliza();
            // Colectivos: los demás archivos de la carga (censo, flotilla, ubicaciones, anexos).
            await this.adjuntarPendientes();
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
        await this.finalizarEmision();
    }

    // Con el PDF de la póliza cargado, la oportunidad pasa a etapa "Póliza" y se muestra la póliza en solo lectura.
    // Sin PDF la oportunidad sigue en emisión y el formulario editable.
    async finalizarEmision() {
        // Sin PDF no cambia la etapa, pero igual se lleva al registro de la póliza.
        if (!this._pdfCargado) { this.navegarAPoliza(); return; }
        try {
            if (this.opportunityId) {
                await cambiarEtapaAPoliza({ opportunityId: this.opportunityId });
            }
            this._pdfCargado = false;
            this.showToast('Póliza emitida', this.opportunityId ? 'La oportunidad pasó a la etapa Póliza.'
                : 'La póliza se emitió sin oportunidad.', 'success');
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.showToast('La póliza se guardó, pero la etapa no cambió', msg, 'warning');
        }
        // Lleva a la vista estándar del registro de la póliza (Insurance Policy).
        this.navegarAPoliza();
    }

    // Redirige a la página de registro estándar de Salesforce de la póliza guardada.
    // Si por alguna razón no hay Id, vuelve a Crear Póliza en modo solo lectura.
    navegarAPoliza() {
        // Carga masiva: aquí termina el proceso del PDF; no se navega.
        if (this._masivo) {
            this.terminarMasivo(this.policyId ? (this._masivo.existente ? 'actualizada' : 'creada') : 'error');
            return;
        }
        if (this.policyId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: this.policyId, objectApiName: 'InsurancePolicy', actionName: 'view' }
            });
            return;
        }
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
        if (r.beneficiarios) { partes.push(`${r.beneficiarios} beneficiario(s)`); }
        if (r.cuenta) { partes.push('datos del cliente'); }
        if (r.vehiculos) { partes.push(`${r.vehiculos} vehículo(s) de flotilla`); } else if (r.vehiculo) { partes.push('vehículo'); }
        if (r.ubicaciones) { partes.push(`${r.ubicaciones} ubicación(es)`); } else if (r.bien) { partes.push('bien asegurado'); }
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
        this.terminarMasivo('error');
    }

    // ----- Arrastrar y soltar el archivo de la póliza -----
    get mostrarZonaArrastre() {
        return this.mostrarPdfIndividual || this.mostrarCargaColectiva;
    }
    get claseZonaArrastre() {
        return 'drop-zone' + (this.arrastrando ? ' drop-zone_activa' : '') + (this.analizando ? ' drop-zone_deshabilitada' : '');
    }
    get textoZonaArrastre() {
        if (this.mostrarCargaColectiva) {
            return 'Arrastra aquí los archivos de la póliza (PDF, Excel o CSV)';
        }
        return 'Arrastra aquí el PDF de la póliza';
    }
    handleClicZonaArrastre() {
        if (this.analizando) { return; }
        if (this.mostrarCargaColectiva) { this.handleCargarArchivos(); } else { this.handleAnalizarPdf(); }
    }
    handleDragOver(event) {
        event.preventDefault();
        if (event.dataTransfer) { event.dataTransfer.dropEffect = this.analizando ? 'none' : 'copy'; }
        if (!this.analizando) { this.arrastrando = true; }
    }
    handleDragLeave(event) {
        // Solo al salir de la zona, no al pasar sobre sus elementos internos.
        if (event.currentTarget && event.relatedTarget && event.currentTarget.contains(event.relatedTarget)) { return; }
        this.arrastrando = false;
    }
    handleDrop(event) {
        event.preventDefault();
        this.arrastrando = false;
        if (this.analizando || this.readOnly) { return; }
        const files = Array.from((event.dataTransfer && event.dataTransfer.files) || []);
        if (!files.length) { return; }
        if (this.mostrarCargaColectiva) {
            this.handleArchivosColectivo({ target: { files } });
            return;
        }
        const pdf = files.find((f) => /\.pdf$/i.test(f.name || '') || f.type === 'application/pdf');
        if (!pdf) {
            this.showToast('Aviso', 'Arrastra un archivo PDF de la póliza.', 'warning');
            return;
        }
        this.handleFileSelected({ target: { files: [pdf] } });
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
                this.terminarMasivo('error');
                return;
            }
            const datos = await this.analizarTextoPoliza(texto);
            if (!datos) { this.terminarMasivo('error', 'La IA no devolvió los datos de la póliza.'); return; }
            if (this._masivo) { this._masivo.numero = datos.numeroPoliza || null; }
            // No puede haber dos pólizas con el mismo número y la misma vigencia: si ya existe (y el usuario
            // puede editarla) se actualiza esa póliza en lugar de crear otra; si no, se avisa y no se guarda nada.
            const polizaAntes = this.policyId;
            if (!(await this.resolverPolizaExistente(datos))) { this.terminarMasivo('error'); return; }
            const actualizarExistente = !polizaAntes && !!this.policyId;
            if (this._masivo) { this._masivo.existente = actualizarExistente; }
            // Guarda el PDF como archivo de la póliza. Si la póliza aún no existe,
            // queda pendiente y se adjunta al crearla (handleSuccess).
            // Un PDF grande no cabe en la llamada a Apex: se pide adjuntarlo en la vista de la póliza.
            this._pdfCargado = true;
            if (file.size > MAX_ADJUNTO_AUTOMATICO) {
                this._pdfPendiente = null;
                this.showToast('Adjunta el PDF al terminar',
                    `El PDF pesa ${this.fmtMb(file.size)} y no se puede adjuntar automáticamente. Al guardar la póliza, súbelo en la sección «Archivos de la póliza».`,
                    'warning');
            } else {
                try {
                    const base64 = await this.readFileAsBase64(file);
                    this._pdfPendiente = { base64, nombre: file.name };
                    await this.guardarPdfEnPoliza();
                } catch (fileErr) {
                    // No bloquea: se reintenta al guardar la póliza.
                }
            }
            // Guarda el JSON para crear/actualizar los objetos hijos al guardar la póliza.
            this._datosPoliza = datos;
            // La póliza ya existía: se actualiza y se crean los participantes, bienes y coberturas que falten.
            if (actualizarExistente) {
                await this.complementarPolizaExistente(datos, false, []);
                return;
            }
            // Sin oportunidad ni cotización (emisión directa o automática): el cliente, la aseguradora y el ramo
            // salen del PDF.
            if (!this.policyId && this.sinOportunidad) {
                await this.completarSinOportunidad(datos, texto);
            }
            this.fillForm(datos);
            // Sin oportunidad: no se guarda sola; se completan a mano el agente y los datos que no trae el PDF.
            // En la carga masiva se guarda con lo que trae el PDF (sin agente).
            if (this.sinOportunidad && !this._masivo) {
                this.revisionManual = true;
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => this.revisarFaltantes(), 500);
                this.showToast('Revisa la póliza',
                    'Completa el agente y los datos que no venían en el PDF, y guarda la póliza.', 'info');
                return;
            }
            // Una vez subido el PDF, se guarda automáticamente y se pasa a la vista de SOLO
            // LECTURA: el usuario ya no puede modificar los valores de la póliza.
            this.showToast('Listo', 'Datos de la póliza cargados. Guardando…', 'success');
            this.guardarYcerrar();
        } catch (e) {
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error al analizar el PDF.';
            this.showToast('Error', msg, 'error');
            this.terminarMasivo('error');
        } finally {
            this.analizando = false;
        }
    }

    // Póliza sin oportunidad: busca (o crea) al cliente por RFC o nombre, y toma la aseguradora y el ramo del PDF.
    // Lo encontrado se agrega a los datos base (completan lo vacío al guardar) y se muestra en el formulario.
    async completarSinOportunidad(datos, texto) {
        const r = (await datosSinOportunidad({
            datosJson: JSON.stringify(datos),
            textoInicio: String(texto || '').substring(0, 4000)
        })) || {};
        const base = { ...(this._datosBase || {}) };
        Object.keys(r).filter((k) => !k.startsWith('_')).forEach((k) => { base[k] = r[k]; });
        this._datosBase = base;
        this.template.querySelectorAll('lightning-input-field').forEach((f) => {
            const v = r[f.fieldName];
            if (v !== undefined && v !== null && !f.fieldName.startsWith('_')
                && (f.value === undefined || f.value === null || f.value === '')) {
                try { f.value = v; } catch (e) { /* campo de solo lectura */ }
            }
        });
        const avisos = [];
        if (r.NameInsuredId) {
            avisos.push(r._clienteNuevo ? `se dio de alta al cliente ${r._clienteNombre}` : `cliente: ${r._clienteNombre}`);
        } else {
            avisos.push('no se encontró el cliente en el PDF: elige el asegurado y guarda');
        }
        if (!r.Aseguradora__c) { avisos.push('no se reconoció la aseguradora'); }
        if (!r.Ramo__c) { avisos.push('no se reconoció el ramo'); }
        this.showToast('Póliza sin oportunidad', avisos.join(' · '), r.NameInsuredId ? 'info' : 'warning');
    }

    // Analiza con la IA el texto de la carátula y lo completa con lo que se lee directo del texto: coberturas,
    // ubicaciones (Daños), vehículos (flotilla) y el número de póliza limpio. null si la IA no respondió un JSON.
    async analizarTextoPoliza(texto) {
        const jsonStr = await analizarPoliza({ textoPoliza: texto });
        console.log('PolicyCreator::: JSON recibido de Apex ->', jsonStr);
        let datos;
        try {
            datos = JSON.parse(jsonStr || '{}');
        } catch (parseErr) {
            console.error('PolicyCreator::: no se pudo parsear el JSON', parseErr);
            this.showToast('Aviso', 'La IA respondió en un formato no válido. Intenta de nuevo.', 'warning');
            return null;
        }
        // Completa límite/deducible/prima de cada cobertura desde su renglón del PDF.
        this.completarCoberturasDesdeTexto(datos, texto);
        // Daños: ubicaciones (incisos) del PDF completo; Apex crea un bien del cliente por cada una.
        datos.ubicaciones = this.ubicacionesDesdeTexto(texto);
        // Flotilla / colectiva de autos: todos los vehículos (incisos); Apex crea su bien e inciso de flotilla.
        datos.vehiculos = this.vehiculosDesdeTexto(texto);
        // Endoso de alta de un solo inciso de una flotilla ("Inciso: 101"): es un inciso de flotilla, no una póliza
        // individual (Apex lo trata como flotilla con _vehiculosArchivo).
        const uno = datos.vehiculos.length ? [] : vehiculosDeCaratulas(texto, 1);
        if (uno.length === 1 && Number(uno[0].inciso) > 1) {
            datos.vehiculos = uno;
            datos._vehiculosArchivo = true;
        }
        // Número de póliza SIN endoso ni inciso (ej. Quálitas: "0971273390 000000 0001").
        datos.numeroPoliza = this.limpiarNumeroPoliza(datos.numeroPoliza, texto);
        return datos;
    }

    // Guarda automáticamente la póliza tras subir el PDF y la deja en SOLO LECTURA.
    // Envía el formulario (mismo flujo que "Guardar Póliza": handleSubmit -> handleSuccess
    // -> navegarAPoliza, que abre el registro de la póliza). Espera un momento a que el formulario pinte los valores del PDF.
    guardarYcerrar() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const form = this.template.querySelector('lightning-record-edit-form');
            if (!form) { this.terminarMasivo('error', 'No se encontró el formulario de la póliza.'); return; }
            // submit() desde código no dispara onsubmit: se arman aquí los mismos campos que
            // en handleSubmit (pantalla + datos ocultos de la IA + datos base al crear).
            const fields = {};
            this.template.querySelectorAll('lightning-input-field').forEach((f) => {
                if (f.fieldName && f.value !== undefined) { fields[f.fieldName] = f.value; }
            });
            form.submit(this.armarCampos(fields));
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
            // Se conserva pendiente para reintentar al guardar la póliza; si ya existe la póliza se avisa.
            const msg = (e && e.body && e.body.message) || (e && e.message) || 'Error desconocido';
            this.showToast('No se pudo adjuntar el PDF',
                `${msg}. Súbelo en la sección «Archivos de la póliza».`, 'warning');
        }
    }

    // Tamaño legible de un archivo ("12.8 MB").
    fmtMb(bytes) {
        return bytes >= 1024 * 1024 ? `${(bytes / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(bytes / 1024))} KB`;
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

    // Vehículos de una póliza de flotilla / colectiva de autos (ej. Afirme: una carátula por inciso), leídos del texto
    // completo (la IA solo recibe una parte). La lectura vive en c/clasificadorArchivos para que el censo de
    // vehículos y la flotilla lean igual el mismo PDF. Con menos de dos vehículos, [] (póliza individual).
    vehiculosDesdeTexto(texto) {
        return vehiculosDeCaratulas(texto);
    }

    // Ubicaciones de una póliza de Daños (ej. HDI "PÓLIZA MAESTRA": un inciso por ubicación), leídas del texto completo
    // (la IA solo recibe una parte): domicilio, incisos, datos del inmueble ("Información de la Empresa": techos, muros,
    // pisos, sótanos, cajones, zonas, giro...), suma asegurada de contenidos y prima del inciso. Sin ubicaciones, [].
    ubicacionesDesdeTexto(texto) {
        const t = String(texto || '');
        const etiqueta = /(?:Domicilio de la Empresa|Domicilio del Riesgo|Ubicaci[oó]n del Riesgo|Ubicaci[oó]n Asegurada)\s*:\s*/gi;
        const fin = /\n\s*(?:Informaci[oó]n de la Empresa|Muros|Consta de|Entrepisos|Giro|Techos|Sustancias|Pisos|Cliente|No\. P[oó]liza|Datos|Tipo de|BIENES)\b/i;
        // Datos del inmueble: el valor llega hasta la siguiente etiqueta del renglón ("Muros: TABIQUE Entrepisos: NO APLICA").
        const CAMPOS = {
            techos: 'Techos', muros: 'Muros', entrepisos: 'Entrepisos', pisosAltos: 'Pisos Altos', sotanos: 'S[oó]tanos',
            constaDe: 'Consta de', sustanciasExplosivas: 'Sustancias Explosivas', sustanciasInflamables: 'Sustancias Inflamables',
            cajones: 'Cajones', zonaTev: 'Zona TEV', zonaFh: 'Zona FH', giro: 'Giro'
        };
        const numero = /^\d+$/;
        const VALIDOS = {
            pisosAltos: numero, sotanos: numero, cajones: numero, constaDe: /^[A-ZÁÉÍÓÚÑ][^:]*[A-Za-zÁÉÍÓÚÑ]$/i,
            sustanciasExplosivas: /^[\d.,]+\s*(kg|%)?$/i, sustanciasInflamables: /^[\d.,]+\s*(kg|%)?$/i, zonaTev: /^[A-Z0-9]{1,4}$/i,
            zonaFh: /^[A-Z0-9]{1,4}$/i
        };
        const siguiente = `(?=\\s+(?:${Object.values(CAMPOS).join('|')}|Porcentaje Multicl[aá]usula|Informaci[oó]n de la Empresa)\\s*:|\\n|$)`;
        const monto = (v) => (v ? Number(String(v).replace(/[$,\s]/g, '')) : null);
        const conIncisos = /Inciso:\s*\d+/i.test(t);
        const porDireccion = new Map();
        let m;
        while ((m = etiqueta.exec(t)) !== null) {
            const ini = m.index + m[0].length;
            const resto = t.substring(ini, ini + 400);
            const corte = resto.search(fin);
            const direccion = (corte >= 0 ? resto.substring(0, corte) : resto.split('\n').slice(0, 2).join(' '))
                .replace(/\s+/g, ' ').replace(/[,\s]+$/, '').trim();
            if (direccion.length < 10) { continue; }
            // El inciso es el último "Inciso: n" antes del domicilio.
            const incisos = [...t.substring(Math.max(0, m.index - 1500), m.index).matchAll(/Inciso:\s*(\d+)/gi)];
            const inciso = incisos.length ? incisos[incisos.length - 1][1] : '';
            // La misma dirección (repetida en cada página del inciso o en otro inciso) es una sola ubicación.
            const llave = direccion.toLowerCase().normalize('NFD').replace(/[^a-z0-9]/g, '');
            const u = porDireccion.get(llave) || { direccion, incisos: [] };
            if (inciso && !u.incisos.includes(inciso)) { u.incisos.push(inciso); }
            porDireccion.set(llave, u);
            // En una póliza por incisos, los datos solo se toman de las páginas del inciso (no de la maestra).
            if (conIncisos && !inciso) { continue; }
            const datos = t.substring(ini, ini + 1500).split(/BIENES Y RIESGOS|SECCI[OÓ]N/i)[0];
            Object.keys(CAMPOS).forEach((k) => {
                if (u[k]) { return; }
                const v = ((datos.match(new RegExp(`${CAMPOS[k]}\\s*:\\s*(.*?)${siguiente}`, 'i')) || [])[1] || '').trim();
                // A veces el PDF desordena el renglón ("PLANTA BAJA Sustancias Explosivas: Consta de: 0.00KG"): solo se
                // acepta un valor con la forma esperada.
                if (VALIDOS[k] ? VALIDOS[k].test(v) : v && !v.includes(':')) { u[k] = v; }
            });
            if (!u.constaDe) {
                const c = datos.match(/\n\s*([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ,]+?)\s+Sustancias Explosivas/);
                if (c) { u.constaDe = c[1].trim(); }
            }
            // Páginas del inciso: hasta que empieza otro inciso.
            let ventana = t.substring(ini, ini + 15000);
            const otro = [...ventana.matchAll(/Inciso:\s*(\d+)/gi)].find((x) => inciso && x[1] !== inciso);
            if (otro) { ventana = ventana.substring(0, otro.index); }
            if (u.sumaAsegurada == null) {
                const s = ventana.match(/Todo Riesgo Incendio (?:Contenidos|Edificio)\s*\$\s*([\d,]+\.\d{2})/i);
                if (s) { u.sumaAsegurada = monto(s[1]); }
            }
            if (u.primaNeta == null) {
                // Renglón de montos bajo "Prima Neta ... Prima Total". Las columnas pueden venir desordenadas: el total es
                // el mayor, el IVA el que equivale al 16% de la base (total / 1.16) y la prima neta el mayor de los demás.
                const p = ventana.match(/Prima Neta[^\n]*Prima Total[^\n]*\n([^\n]+)/i);
                const montos = p ? (p[1].match(/\$\s*[\d,]+\.\d{2}/g) || []).map(monto) : [];
                if (montos.length >= 2) {
                    const total = Math.max(...montos);
                    const resto = [...montos];
                    resto.splice(resto.indexOf(total), 1);
                    const ivaEsperado = total * 0.16 / 1.16;
                    const iva = resto.find((x) => Math.abs(x - ivaEsperado) <= Math.max(1, ivaEsperado * 0.01));
                    if (iva !== undefined) { resto.splice(resto.indexOf(iva), 1); }
                    u.primaTotal = total;
                    u.primaNeta = Math.max(...resto);
                }
            }
        }
        return [...porDireccion.values()].map(({ incisos, ...u }) => ({ ...u, inciso: incisos.join(', ') }));
    }

    // Deja solo el número de PÓLIZA. Varias aseguradoras imprimen en el mismo renglón las
    // columnas PÓLIZA / ENDOSO / INCISO (ej. "0971273390 000000 0001") y la IA las junta.
    // Si el número trae varios bloques y el PDF tiene ese encabezado, o el segundo bloque es
    // solo ceros (endoso 000000), se conserva únicamente el primer bloque.
    limpiarNumeroPoliza(numero, texto) {
        if (!numero) { return numero; }
        const partes = String(numero).trim().split(/\s+/);
        if (partes.length < 2) { return String(numero).trim(); }
        const t = this.normCobertura(texto || '');
        const conEndoso = /poliza\s+endoso/.test(t);
        const endosoEnCeros = /^0+$/.test(partes[1]);
        return (conEndoso || endosoEnCeros) ? partes[0] : String(numero).trim();
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

    // Descripción breve de la póliza: quita las frases que hablan de pagos, primas, recibos,
    // vigencia o datos del cliente (el resumen de la IA a veces los incluye).
    descripcionSinPagos(texto, plan) {
        const NO = /(pago|prima|recibo|cobranza|importe|financiamiento|\$|mxn|vigencia|vence|rfc|domicilio|correo|tel[eé]fono|clabe|referencia)/i;
        // El nombre del plan puede decir "15 PAGOS": no cuenta como dato de pago.
        const sinPlan = (s) => (plan ? s.split(plan).join(' ') : s);
        return (texto || '').toString()
            .split(/(?<=[.;])\s+|\n+/)
            .map((s) => s.trim())
            .filter((s) => s && !NO.test(sinPlan(s)))
            .join(' ')
            .replace(/[.;,\s]+$/, '')
            .trim();
    }

    // Campos de la póliza (API name -> valor) a partir del JSON devuelto por la IA. Lo usan el formulario
    // (fillForm) y el complemento de una póliza que ya existe (complementarCamposPoliza: solo llena lo vacío).
    camposDesdeDatos(d) {
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
        // Para los DEMÁS ramos: descripción BREVE (el bien asegurado) y el plan; sin coberturas,
        // pagos, primas ni datos del cliente (esos ya se guardan como registros/campos aparte).
        let descripcionCorta = this.descripcionSinPagos(bien.descripcion || d.descripcion, d.plan);
        const conPlan = (base) => (d.plan && !normTxt(base).includes(normTxt(d.plan))
            ? (base ? `${base} (Plan: ${d.plan})` : `Plan: ${d.plan}`)
            : base);
        descripcionCorta = conPlan(descripcionCorta);
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
            // El nombre de la póliza es el mismo número de póliza del PDF.
            PolicyName: d.numeroPoliza,
            // PlanType es picklist y NO está en el formulario; NO se fuerza desde la IA
            // (un valor fuera del catálogo rompería el guardado). El plan queda en la descripción.
            // El estatus NO se toma del PDF ni se toca al emitir/reanalizar: la póliza conserva el que tiene
            // (una póliza nueva nace con el estatus inicial de datosBasePoliza).
            CancellationReason: d.motivoCancelacion,
            // Primas: PremiumAmount y GrossWrittenPremium = prima TOTAL (con impuestos); la prima neta
            // queda en el desglose (Subtotal, IVA, gastos de expedición).
            PremiumFrequency: d.frecuenciaPago || cob.formaPago,
            PremiumAmount: cob.totalAPagar != null ? cob.totalAPagar
                : (d.primaTotal != null ? d.primaTotal : (cob.primaNeta != null ? cob.primaNeta : d.primaNeta)),
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
            PolicyDescription: esAuto && descripcionAuto ? conPlan(descripcionAuto).substring(0, 255) : descripcionCorta
        };
        return map;
    }

    // Prellena los campos del formulario con el JSON devuelto por la IA.
    fillForm(d) {
        if (!d) { return; }
        const map = this.camposDesdeDatos(d);
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
            this.tipoContratacion = o.Tipo_Contratacion__c || '';
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
                // Role es selección múltiple ("Asegurado;Beneficiario").
                rol: p.rol ? String(p.rol).split(';').join(' · ') : '—',
                relacion: p.relacion || '—',
                // Beneficiarios: "90 % · Por muerte"
                detalleBeneficio: [
                    p.porcentaje != null ? `${Number(p.porcentaje)} %` : null,
                    p.tipoBeneficio
                ].filter(Boolean).join(' · ')
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
            this.archivos = (reg.archivos || []).map((a) => ({
                id: a.id,
                nombre: a.extension ? `${a.nombre}.${a.extension}` : a.nombre,
                tamano: a.tamano != null ? this.fmtMb(a.tamano) : '',
                esPdf: (a.extension || '').toLowerCase() === 'pdf'
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
    get hasArchivos() { return this.archivos && this.archivos.length > 0; }
    // Sin PDF adjunto se resalta el cargador para subir el de la póliza.
    get faltaPdf() { return !!this.policyId && !(this.archivos || []).some((a) => a.esPdf); }
    get archivosClase() { return this.faltaPdf ? 'ro-section ro-archivos ro-archivos--falta' : 'ro-section ro-archivos'; }

    // Archivos subidos con el cargador estándar (ya quedan ligados a la póliza).
    handleArchivoSubido(event) {
        const n = ((event.detail && event.detail.files) || []).length;
        this.showToast('Archivos de la póliza', n === 1 ? 'Archivo adjuntado a la póliza.' : `${n} archivos adjuntados a la póliza.`, 'success');
        this.loadRegistrosPoliza();
    }

    // Abre la vista previa del archivo.
    handleVerArchivo(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: event.currentTarget.dataset.id }
        });
    }

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
        this.handleCampoCambio();
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
        // Carga masiva: los avisos se guardan en el resultado del PDF en lugar de mostrarse.
        if (this._masivo) {
            if (variant !== 'success') { this._masivo.mensajes.push(`${title}: ${message}`); }
            return;
        }
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ----- Carga masiva (pestaña Carga masiva de pólizas) -----

    /**
     * Procesa un PDF de carátula con el mismo flujo que la carga manual (sin oportunidad), sin preguntas ni revisión
     * a mano: crea la póliza o, si ya existe con el mismo número y vigencia, la actualiza.
     * @param file PDF (File)
     * @return {estado: 'creada'|'actualizada'|'error', policyId, numero, mensajes}
     */
    @api
    async procesarPdf(file) {
        await this.esperarListo();
        if (!this.isPdfJsLoaded || !this._formListo) {
            return { estado: 'error', policyId: null, numero: null, mensajes: ['El formulario o el lector de PDF no cargaron.'] };
        }
        return new Promise((resolve) => {
            this._masivo = { resolve, mensajes: [], numero: null, existente: false };
            this.handleFileSelected({ target: { files: [file] } });
        });
    }

    // Espera (hasta ~20 s) a que estén listos el lector de PDF y el formulario de la póliza nueva.
    async esperarListo() {
        for (let i = 0; i < 100 && !(this.isPdfJsLoaded && !this.loading && this._formListo); i++) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            await new Promise((r) => { setTimeout(r, 200); });
        }
    }

    // Entrega el resultado del PDF en proceso (una sola vez).
    terminarMasivo(estado, mensaje) {
        const m = this._masivo;
        if (!m) { return; }
        this._masivo = null;
        if (mensaje) { m.mensajes.push(mensaje); }
        m.resolve({ estado, policyId: this.policyId || null, numero: m.numero, mensajes: m.mensajes });
    }
}