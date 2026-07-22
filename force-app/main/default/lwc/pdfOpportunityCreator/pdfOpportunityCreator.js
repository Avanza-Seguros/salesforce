import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { loadScript } from "lightning/platformResourceLoader";
import PDFJS from "@salesforce/resourceUrl/pdfjs";
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';
import analyzeQuotes from "@salesforce/apex/PdfOpportunityCreatorController.analyzeQuotes";

const MAX_SIZE = 4500000; // ~4.5 MB por archivo: límite práctico para enviar base64/texto a Apex
const MIN_FILES = 2;
const MIN_PREFIX_LENGTH = 3;

export default class PdfOpportunityCreator extends LightningElement {

	@track isPdfJsLoaded = false;
	@track pdfJsError = false;
	
	files = [];
	isProcessing = false;
	statusMessage = "";
	error = "";
	prefixWarning = "";

	// Resumen tras enviar los datos al formulario del padre.
	done = false;
	extractedCount = 0;
	clienteDetectado = "";
	ramoDetectado = "";

	// Estado de pdf.js (para extraer el texto de los PDFs en el navegador).
	pdfLibInit = false;
	pdfLibReady = false;
	// Confirmación cuando la IA detecta posible discrepancia de cliente/auto.
	needsConfirm = false;
	validacionAlerta = "";
	_pendingRes = null;

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
					console.log(':::pdfOpportunityCreator::: ✅ PDF.js cargado exitosamente');
			} catch (error) {
					console.error(':::pdfOpportunityCreator::: ❌ Error cargando PDF.js:', JSON.stringify(error));
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
					console.log(':::pdfOpportunityCreator::: ✅ Script PDF.js cargado');
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
						standardFontDataUrl: fontsUrl
					});
					const timeout = new Promise((_, reject) => 
							setTimeout(() => reject(new Error('Timeout probando PDF.js')), 5000)
					);
					
					const pdf = await Promise.race([loadingTask.promise, timeout]);
					if (pdf && pdf.destroy) {
							await pdf.destroy();
					}
					
					console.log(':::pdfOpportunityCreator::: ✅ PDF.js funciona correctamente');
			} catch (testError) {
					console.warn('⚠️ Test de PDF.js falló:', testError.message);
			}
	}


	// ============================================================
	// GETTERS DE VISTA
	// ============================================================
	get showUploadStep() {
		return !this.isProcessing && !this.done && !this.needsConfirm;
	}
	get hasFiles() {
		return this.files && this.files.length > 0;
	}
	get fileList() {
		return this.files.map((f) => ({ name: f.name }));
	}
	get sharedPrefix() {
		if (!this.hasFiles || this.files.length < MIN_FILES) {
			return "";
		}
		return computeSharedPrefix(this.files.map((f) => f.name));
	}
	get continueDisabled() {
		if (this.isProcessing) {
			return true;
		}
		if (!this.hasFiles || this.files.length < MIN_FILES) {
			return true;
		}
		return !this.sharedPrefix;
	}
	get doneMessage() {
		const c = this.clienteDetectado || "el cliente";
		return `Se extrajeron ${this.extractedCount} cotización(es) para ${c}. Revisa los datos en el formulario y guarda la oportunidad.`;
	}

	// ============================================================
	// EVENTOS DE ARCHIVOS
	// ============================================================
	handleFileChange(event) {
		this.error = "";
		this.prefixWarning = "";
		const selected = Array.from(event.target.files || []);
		if (selected.length === 0) {
			this.files = [];
			return;
		}
		const accepted = [];
		for (const f of selected) {
			if (
				f.type !== "application/pdf" &&
				!f.name.toLowerCase().endsWith(".pdf")
			) {
				this.showToast(
					"Archivo no válido",
					`"${f.name}" no es un PDF y fue descartado.`,
					"warning"
				);
				continue;
			}
			if (f.size > MAX_SIZE) {
				this.showToast(
					"Archivo muy grande",
					`"${f.name}" supera ~4.5 MB y fue descartado.`,
					"warning"
				);
				continue;
			}
			accepted.push(f);
		}
		this.files = accepted;

		if (this.files.length > 0 && this.files.length < MIN_FILES) {
			this.prefixWarning = `Sube al menos ${MIN_FILES} PDFs para comparar cotizaciones.`;
			return;
		}
		if (this.files.length >= MIN_FILES && !this.sharedPrefix) {
			this.prefixWarning =
				"Los nombres de los PDFs no comparten un prefijo común. Renómbralos para que empiecen igual (mín. " +
				MIN_PREFIX_LENGTH +
				" caracteres en común).";
		}
	}

	// ============================================================
	// ANALIZAR Y ALIMENTAR EL FORMULARIO DEL PADRE
	// ============================================================
	async handleContinue() {
		if (!this.hasFiles || this.files.length < MIN_FILES) {
			this.showToast(
				"Faltan archivos",
				`Sube al menos ${MIN_FILES} PDFs para continuar.`,
				"error"
			);
			return;
		}
		if (!this.sharedPrefix) {
			this.showToast(
				"Nombres no coinciden",
				"Los PDFs deben compartir un prefijo común en el nombre.",
				"error"
			);
			return;
		}

		this.isProcessing = true;
		this.error = "";
		// Avisa al padre que empezó el análisis (para mostrar spinner).
		this.dispatchEvent(new CustomEvent("analysisstart"));
		try {
			this.statusMessage = "Leyendo el contenido de los PDFs…";
			const fileNames = this.files.map((f) => f.name);
			const pdfTexts = await Promise.all(
				this.files.map((f) => this.extractPdfText(f))
			);

			this.statusMessage = "Analizando cotizaciones con IA…";
			const res = await analyzeQuotes({ fileNames, pdfTexts });
			console.log(':::pdfOpportunityCreator::: ✅ Respuesta de Apex:', JSON.stringify(res));
			const quotes = (res && res.quotes) || [];
			if (quotes.length === 0) {
				throw new Error(
					"No se pudieron leer cotizaciones de los PDFs. Revisa que tengan texto seleccionable."
				);
			}

			// ¿La IA detectó que NO son del mismo cliente/auto? Pedimos confirmación.
			const val = (res && res.validacion) || {};
			if (val.alerta) {
				this._pendingRes = res;
				this.validacionAlerta = val.alerta;
				this.needsConfirm = true;
				return; // esperamos a que el usuario confirme o revise
			}

			this.emitResults(res);
		} catch (e) {
			this.error = this.reduceError(e);
			this.showToast("Error", this.error, "error");
		} finally {
			this.isProcessing = false;
			this.statusMessage = "";
			// Avisa al padre que terminó el análisis (para ocultar el spinner).
			this.dispatchEvent(new CustomEvent("analysisdone"));
		}
	}

	// Continúa pese a la advertencia de discrepancia.
	confirmAndContinue() {
		const res = this._pendingRes;
		this.needsConfirm = false;
		this.validacionAlerta = "";
		this._pendingRes = null;
		if (res) {
			this.emitResults(res);
		}
	}

	// Cancela y vuelve al paso de carga para revisar/cambiar los PDFs.
	cancelValidation() {
		this.needsConfirm = false;
		this.validacionAlerta = "";
		this._pendingRes = null;
	}

	// Emite las cotizaciones al padre (combinando vehículo + cliente comunes).
	emitResults(res) {
		console.log(':::pdfOpportunityCreator::: Emitiendo resultados al padre:', JSON.stringify(res));
		const quotes = (res && res.quotes) || [];
		const det = (res && res.detalle) || (res && res.vehiculo) || {};
		const cli = (res && res.cliente) || {};

		quotes.forEach((q, i) => {
			const detail = toPlainObject({
				...q,
				...det,                       // ← datos específicos del ramo (marca, destino, asegurados, etc.)
				ramo: q.ramo || (res && res.ramo) || "",
				ramoLabel: q.ramo || (res && res.ramo) || "",
				esGanadora: !!q.esGanadora,
				// Cliente (común)
				clienteNombre: cli.nombre || "",
				clienteRFC: cli.rfc || "",
				clienteEmail: cli.email || "",
				clienteTelefono: cli.telefono || "",
				clienteCP: cli.cp || "",
				clienteDireccion: cli.direccion || "",
				id: `pdf-${Date.now()}-${i}`,
				nombreArchivo: q.archivoOrigen || `Cotización ${i + 1}`,
				extractionConfidence: 90,
				hasCoberturas: Array.isArray(q.tablaCompletaCoberturas)
					? q.tablaCompletaCoberturas.length > 0
					: false,
				coberturasCount: Array.isArray(q.tablaCompletaCoberturas)
					? q.tablaCompletaCoberturas.length
					: 0
			});
			this.dispatchEvent(new CustomEvent("pdfdataextracted", { detail }));
		});

		this.extractedCount = quotes.length;
		this.clienteDetectado = cli.nombre || "";
		this.ramoDetectado = (res && res.ramo) || "";
		const recTexto =
			(res && res.recomendacion && res.recomendacion.en_pocas_palabras) || "";

		this.dispatchEvent(
			new CustomEvent("analysiscomplete", {
				detail: toPlainObject({
					count: quotes.length,
					cliente: this.clienteDetectado,
					ramo: this.ramoDetectado,
					ganadora: (res && res.ganadora) || "",
					recomendacion: recTexto,
					aviso: (res && res.aviso) || "",
						comparativoHtml: (res && res.comparativo_html) || ""
				})
			})
		);

		this.done = true;
		this.showToast(
			"Datos extraídos",
			`Se enviaron ${quotes.length} cotizaciones al formulario.`,
			"success"
		);
	}

	handleReset() {
		this.needsConfirm = false;
		this.validacionAlerta = "";
		this._pendingRes = null;
		this.files = [];
		this.error = "";
		this.prefixWarning = "";
		this.done = false;
		this.extractedCount = 0;
		this.clienteDetectado = "";
		this.ramoDetectado = "";
		const input = this.template.querySelector('lightning-input[type="file"]');
		if (input) {
			input.value = null;
		}
	}

	// Extrae el texto de un PDF con pdf.js. Devuelve "" si no se puede (p. ej. escaneado
	// o si pdf.js falla en este entorno). Tiene un timeout para no dejar el spinner
	// girando si pdf.js se cuelga (caso del "fake worker" en Lightning Web Security).
	async extractPdfText(file) {

		const TIMEOUT_MS = 15000;
		const fontsUrl = fontsResource + '/';

		const extraction = (async () => {
			const arrayBuffer = await file.arrayBuffer();
			const loadingTask = window.pdfjsLib.getDocument({
				data: new Uint8Array(arrayBuffer),
				isEvalSupported: false,   // ← Salesforce (LWS) bloquea eval()
				useWorkerFetch: false,    // ← evita fetch bloqueado por CSP
				standardFontDataUrl: fontsUrl,
				disableFontFace: true     // ← evita cargar fuentes externas
			});
			const pdf = await loadingTask.promise;
			let text = "";
			for (let p = 1; p <= pdf.numPages; p++) {
				const page = await pdf.getPage(p);
				const content = await page.getTextContent();
				text += content.items.map((it) => it.str).join(" ") + "\n";
			}
			return text.trim();
		})();
		try {
			// Si pdf.js no resuelve en el tiempo límite, seguimos con texto vacío
			// (el servidor usará su respaldo). Así el spinner nunca se queda atorado.
			return await Promise.race([
				extraction,
				new Promise((resolve) => {
					// eslint-disable-next-line @lwc/lwc/no-async-operation
					setTimeout(() => resolve(""), TIMEOUT_MS);
				})
			]);
		} catch (e) {
			console.error(':::pdfOpportunityCreator::: ❌ Error extrayendo texto del PDF:', JSON.stringify(e));
			return "";
		}
	}

	reduceError(e) {
		if (e && e.body && e.body.message) {
			return e.body.message;
		}
		if (e && e.message) {
			return e.message;
		}
		return "Ocurrió un error inesperado durante el análisis.";
	}

	showToast(title, message, variant) {
		this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
	}
}

// Convierte cualquier objeto (incluidos los que devuelve Apex) en un objeto
// plano y clonable, para poder enviarlo en el detail de un CustomEvent sin que
// LWC lance DataCloneError.
function toPlainObject(obj) {
	try {
		return JSON.parse(JSON.stringify(obj));
	} catch (e) {
		return obj;
	}
}

function computeSharedPrefix(names) {
	if (!names || names.length === 0) {
		return "";
	}
	const bases = names.map((n) => {
		const dot = n.lastIndexOf(".");
		const base = dot > 0 ? n.substring(0, dot) : n;
		return base.toLowerCase();
	});
	let prefix = bases[0];
	for (let i = 1; i < bases.length; i++) {
		const other = bases[i];
		const max = Math.min(prefix.length, other.length);
		let j = 0;
		while (j < max && prefix.charAt(j) === other.charAt(j)) {
			j++;
		}
		prefix = prefix.substring(0, j);
		if (!prefix) {
			return "";
		}
	}
	while (prefix.length > 0 && "._- ".includes(prefix.charAt(prefix.length - 1))) {
		prefix = prefix.substring(0, prefix.length - 1);
	}
	return prefix.length >= MIN_PREFIX_LENGTH ? prefix : "";
}