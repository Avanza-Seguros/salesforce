import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS from '@salesforce/resourceUrl/pdfjs';
import fontsResource from '@salesforce/resourceUrl/fuentes_pdf';

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
const MAX_FILE_DIVIDE = MAX_FILE_SIZE / 1024 / 1024;

export default class CotizacionOpLector extends LightningElement {
    @track isLoading = false;
    @track isPdfJsLoaded = false;
    @track files = [];
    @track cotizaciones = [];
    @track isProcessing = false;
    @track showResults = false;
    @track pdfJsError = false;
    @track dragDropSetup = false;
    @track progress = {
        current: 0,
        total: 0,
        percent: 0,
        currentFileName: ''
    };

    @api selectedRamo = ''; // Ramo seleccionado desde el padre

    // =============================================
    // CONSTANTES
    // =============================================
    
    RAMO_TYPES = {
        AUTOMOVILES: 'AUTOMOVILES',
        GASTOS_MEDICOS: 'GASTOS_MEDICOS',
        VIAJES: 'VIAJES',
        HOGAR: 'HOGAR',
        VIDA: 'VIDA',
        DANOS: 'DANOS',
        DENTAL: 'DENTAL',
        EMPRESARIAL: 'EMPRESARIAL',
        RESPONSABILIDAD_CIVIL: 'RESPONSABILIDAD_CIVIL',
        VISION: 'VISION'
    };

    // =============================================
    // LIFECYCLE HOOKS
    // =============================================

    connectedCallback() {
        console.log(':::CotizacionOpLector::: Componente conectado');
        this.isLoading = true;
        this.loadPdfJs();
    }

    renderedCallback() {
        if (!this.dragDropSetup) {
            this.setupDragDropOnce();
            this.dragDropSetup = true;
        }
        
        if (!this.isPdfJsLoaded && !this.pdfJsError) {
            this.loadPdfJs();
        }
    }

    // =============================================
    // CONFIGURACIÓN INICIAL
    // =============================================

    async loadPdfJs() {
        try {
            await this.loadPdfJsScript();
            await this.setupWorker();
            await this.testPdfJs();
            
            this.isPdfJsLoaded = true;
            this.pdfJsError = false;
            console.log(':::CotizacionOpLector::: ✅ PDF.js cargado exitosamente');
        } catch (error) {
            console.error(':::CotizacionOpLector::: ❌ Error cargando PDF.js:', JSON.stringify(error));
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
            console.log(':::CotizacionOpLector::: ✅ Script PDF.js cargado');
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
            
            console.log(':::CotizacionOpLector::: ✅ PDF.js funciona correctamente');
        } catch (testError) {
            console.warn('⚠️ Test de PDF.js falló:', testError.message);
        }
    }

    setupDragDropOnce() {
        setTimeout(() => {
            const dropZone = this.template.querySelector('[data-dropzone]');
            if (!dropZone) {
                console.error(':::CotizacionOpLector::: ❌ No se encontró el elemento dropzone');
                return;
            }
            
            dropZone.ondragover = (e) => {
                e.preventDefault();
                e.stopPropagation();
                dropZone.classList.add('drag-over');
            };
            
            dropZone.ondragleave = (e) => {
                e.preventDefault();
                e.stopPropagation();
                dropZone.classList.remove('drag-over');
            };
            
            dropZone.ondrop = (e) => {
                e.preventDefault();
                e.stopPropagation();
                dropZone.classList.remove('drag-over');
                
                if (e.dataTransfer?.files?.length > 0) {
                    this.procesarArchivos(Array.from(e.dataTransfer.files));
                }
            };
            
            dropZone.onclick = () => {
                this.openFileSelector();
            };
            
        }, 100);
    }

    // =============================================
    // GESTIÓN DE ARCHIVOS
    // =============================================

    openFileSelector() {
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) {
            fileInput.click();
        }
    }

    handleFileChange(event) {
        const files = Array.from(event.target.files || []);
        this.procesarArchivos(files);
        if (event.target) {
            event.target.value = null;
        }
    }

    procesarArchivos(files) {
        if (!files || files.length === 0) return;
        
        const nuevosArchivos = files.filter(file => {
            if (file.type !== 'application/pdf') {
                this.showToast('Error', `${file.name} no es un archivo PDF`, 'error');
                return false;
            }
            if (file.size > MAX_FILE_SIZE) {
                this.showToast('Error', `${file.name} excede el tamaño máximo de ${MAX_FILE_DIVIDE}MB`, 'error');
                return false;
            }
            return true;
        }).map(file => ({
            id: `file_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            name: file.name,
            size: file.size,
            type: file.type,
            status: 'pending',
            file: file
        }));

        if (nuevosArchivos.length > 0) {
            this.files = [...this.files, ...nuevosArchivos];
            this.showToast('Éxito', `Se agregaron ${nuevosArchivos.length} archivo(s)`, 'success');
        }
    }

    removeFile(event) {
        const fileId = event.currentTarget?.dataset?.id;
        if (fileId) {
            this.files = this.files.filter(f => f.id !== fileId);
            this.showToast('Archivo eliminado', 'Archivo removido de la lista', 'info');
        }
    }



    createSafeCopy(obj) {
        if (!obj) return null;
        
        try {
            return JSON.parse(JSON.stringify(obj));
        } catch (e) {
            
            const safeCopy = {};
            const propsToCopy = [
                'id', 'nombreArchivo', 'compania', 'ramo', 'ramoLabel', 'plan',
                'primaTotal', 'primaTotalFormatted', 'extractionConfidence', 'fechaExtraccion',
                'clienteNombre', 'clienteRFC', 'clienteCP', 'clienteEmail', 
                'clienteTelefono', 'clienteDireccion', 'marca', 'modelo', 'placa',
                'serie', 'anio', 'descripcion', 'destino', 'numViajeros',
                'edadVida', 'sumaFallecimiento', 'aportacionAnual',
                'tablaCompletaCoberturas', 'hasCoberturas', 'coberturasCount',
                'tipoRC', 'profesion', 'actividad', 'mascotaNombre', 'raza', 'edadMascota',
                'redHospitalaria', 'sumaAsegurada', 'deducible', 'coaseguro', 'lugarResidencia',
                'tipoNegocio', 'maternidad', 'asegurados', 'sumaEdificio', 'sumaContenido',
                'bienesCubiertos', 'medioTransporte', 'limiteEmbarque', 'riesgosAmparados'
            ];
            
            propsToCopy.forEach(prop => {
                if (obj.hasOwnProperty(prop)) {
                    try {
                        if (Array.isArray(obj[prop])) {
                            safeCopy[prop] = obj[prop].map(item => {
                                if (typeof item === 'object' && item !== null) {
                                    return JSON.parse(JSON.stringify(item));
                                }
                                return item;
                            });
                        } else if (typeof obj[prop] !== 'object') {
                            safeCopy[prop] = obj[prop];
                        } else {
                            safeCopy[prop] = JSON.parse(JSON.stringify(obj[prop]));
                        }
                    } catch (e) {
                        console.warn(`No se pudo copiar la propiedad ${prop}:`, e);
                        safeCopy[prop] = null;
                    }
                }
            });
            
            return safeCopy;
        }
    }

    // =============================================
    // EXTRACCIÓN DE DATOS DEL PDF
    // =============================================

    async extraerDatosCotizacion(fileItem) {
        let pdf = null;
        
        try {
            const file = fileItem.file;
            
            if (!file) {
                console.error(':::CotizacionOpLector::: ❌ Archivo no disponible');
                return null;
            }
            
            const buffer = await file.arrayBuffer();

            const fontsUrl = fontsResource + '/';
            
            const loadingTask = window.pdfjsLib.getDocument({ 
                data: buffer,
                isEvalSupported: false,   // ← Salesforce (LWS) bloquea eval()
                useWorkerFetch: false,    // ← evita fetch bloqueado por CSP
                standardFontDataUrl: fontsUrl,
                disableFontFace: true     // ← evita cargar fuentes externas 
            });
            pdf = await loadingTask.promise;
            
            let textoCompleto = '';
            for (let i = 1; i <= pdf.numPages; i++) {
                const page = await pdf.getPage(i);
                const textContent = await page.getTextContent();
                const pageText = textContent.items.map(item => item.str || '').join(' ');
                textoCompleto += pageText + '\n';
                page.cleanup();
            }
            
            if (!textoCompleto || textoCompleto.trim() === '') {
                console.error(':::CotizacionOpLector::: ❌ No se pudo extraer texto del PDF');
                return null;
            }
            
            const textoLimpio = this.limpiarTexto(textoCompleto);
            
            return this.analizarContenidoCotizacion(textoLimpio, file.name, textoCompleto);
            
        } catch (error) {
            console.error(':::CotizacionOpLector::: ❌ Error procesando archivo:', JSON.stringify(error));
            return null;
        } finally {
            if (pdf && pdf.destroy) {
                try {
                    await pdf.destroy();
                } catch (e) {
                    console.warn('Error al destruir PDF:', e);
                }
            }
        }
    }

    limpiarTexto(texto) {
        if (!texto) return '';
        return texto.replace(/\s+/g, ' ').trim();
    }

    analizarContenidoCotizacion(textoLimpio, nombreArchivo, textoOriginal) {
        try {
            if (!textoLimpio || textoLimpio.trim() === '') {
                return this.crearCotizacionVacia(nombreArchivo);
            }
            
            const contenidoUpper = textoLimpio.toUpperCase();
            const lineas = textoOriginal ? textoOriginal.split('\n') : [];
            
            // DETECCIÓN DE RAMO (priorizando campos explícitos)
            let ramo = this.selectedRamo || 'DESCONOCIDO';

            if (!this.selectedRamo) {
                ramo = this.detectarRamo(contenidoUpper, nombreArchivo, lineas, textoOriginal);
            } else {
                // console.log(':::CotizacionOpLector::: ✅ Usando ramo seleccionado por el usuario:', ramo);
            }
            
            const compania = this.detectarCompania(contenidoUpper, nombreArchivo);
            const clienteData = this.extractClienteData(textoLimpio, contenidoUpper, lineas, textoOriginal);

            // EXTRACCIÓN DE DATOS DE LA COTIZACIÓN (PLAN, PRIMA, ETC)
            const cotizacionData = this.extractCotizacionData(textoOriginal);
            
            let datosEspecificos = {};
            if (ramo === 'AUTOMOVILES' || ramo === 'AUTOMOVIL') {
                datosEspecificos = this.extractAutoData(null, textoOriginal);
            } else if (ramo === 'DANOS') {
                datosEspecificos = this.extractDanosData(null, textoOriginal);
            } else if (ramo === 'DENTAL') {
                datosEspecificos = this.extractDentalData(null, textoOriginal);
            } else if (ramo === 'EMPRESARIAL') {
                datosEspecificos = this.extractEmpresarialData(null, textoOriginal);
            } else if (ramo === 'GASTOS_MEDICOS') {
                datosEspecificos = this.extractGMMData(null, textoOriginal);
            } else if (ramo === 'RESPONSABILIDAD_CIVIL') {
                datosEspecificos = this.extractRCData(null, textoOriginal);
            } else if (ramo === 'VIAJES' || ramo === 'VIAJE') {
                datosEspecificos = this.extractViajeData(null, textoOriginal);
            } else if (ramo === 'VIDA') {
                datosEspecificos = this.extractVidaData(null, textoOriginal);
            } else if (ramo === 'VISION') {
                datosEspecificos = this.extractVisionData(null, textoOriginal);
            } else if (ramo === 'HOGAR') {
                datosEspecificos = this.extractHogarData(null, textoOriginal);
            }
            
            const primaTotalNumerica = this.extractPrimaTotal(textoOriginal) || cotizacionData.primaTotal;
            const coberturasData = this.extractCoberturasData(null, textoOriginal);
            
            const quoteBase = {
                id: `cot_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                nombreArchivo: nombreArchivo || 'documento.pdf',
                compania: String(compania || 'Desconocida'),
                ramo: String(ramo || 'DESCONOCIDO'),
                ramoLabel: this.getRamoLabel(ramo) || 'Desconocido',
                plan: cotizacionData.plan || (datosEspecificos && datosEspecificos.plan) || this.extraerPlan(contenidoUpper) || 'No especificado',
                primaTotal: primaTotalNumerica || 0,
                primaTotalFormatted: this.formatCurrency(primaTotalNumerica || 0),
                formaPago: cotizacionData.formaPago || '',
                vigencia: cotizacionData.vigencia || '',
                moneda: cotizacionData.moneda || 'MXN',
                extractionConfidence: 80,
                fechaExtraccion: new Date().toISOString(),
                
                clienteNombre: clienteData.nombre || '',
                clienteRFC: clienteData.rfc || '',
                clienteCP: clienteData.cp || '',
                clienteEmail: clienteData.email || '',
                clienteTelefono: clienteData.telefono || '',
                clienteDireccion: clienteData.direccion || '',
                
                ...this.flattenObject(datosEspecificos),
                
                tablaCompletaCoberturas: coberturasData || [],
                hasCoberturas: coberturasData.length > 0,
                coberturasCount: coberturasData.length
            };
            
            const quoteConCoberturasProcesadas = this.procesarCoberturas(quoteBase);
            return this.enrichQuoteForDisplay(quoteConCoberturasProcesadas);
            
        } catch (error) {
            console.error(':::CotizacionOpLector::: ❌ Error crítico en analizarContenidoCotizacion:', JSON.stringify(error));
            return this.crearCotizacionVacia(nombreArchivo);
        }
    }

    extractDanosData(quote, textoOriginal) {
       
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const danosData = {
            tipoDanos: '',
            bienesAsegurados: '',
            ubicacion: '',
            sumaAsegurada: '',
            deducible: '',
            coberturas: []
        };
        
        // Buscar tipo de daños
        if (/\bINCENDIO\b/i.test(texto)) danosData.tipoDanos = 'Incendio';
        if (/\bROBO\b/i.test(texto)) danosData.tipoDanos = danosData.tipoDanos ? 'Múltiple' : 'Robo';
        if (/\bHURAC[ÁA]N\b/i.test(texto)) danosData.tipoDanos = 'Fenómenos Naturales';
        
        // Buscar bienes asegurados
        const bienesMatch = texto.match(/(?:BIENES?\s+ASEGURADOS?|OBJETO\s+DEL\s+SEGURO)[:\s]*([^,\n]+?)(?=\.|\n|$)/i);
        if (bienesMatch) danosData.bienesAsegurados = bienesMatch[1].trim();
        
        // Buscar ubicación
        const ubicacionMatch = texto.match(/(?:UBICACI[OÓ]N|LUGAR\s+DEL\s+RIESGO|DOMICILIO)[:\s]*([^,\n]+?)(?=\.|\n|$)/i);
        if (ubicacionMatch) danosData.ubicacion = ubicacionMatch[1].trim();
        
        // Buscar suma asegurada
        const sumaMatch = texto.match(/(?:SUMA\s+ASEGURADA|CAPITAL\s+ASEGURADO)[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (sumaMatch) danosData.sumaAsegurada = sumaMatch[1].replace(',', '');
        
        // Buscar deducible
        const deducibleMatch = texto.match(/DEDUCIBLE[^\d]*(\d+%)?[^\d]*(?:\$?\s*([\d,]+))?/i);
        if (deducibleMatch) {
            danosData.deducible = deducibleMatch[1] || (deducibleMatch[2] ? `$${deducibleMatch[2]}` : '');
        }
        
        return danosData;
    }

    extractDentalData(quote, textoOriginal) {
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const dentalData = {
            planDental: '',
            tipoCobertura: '',
            sumaAseguradaAnual: '',
            deducible: '',
            coaseguro: '',
            serviciosIncluidos: []
        };
        
        // Buscar plan dental
        const planMatch = texto.match(/(?:PLAN|PRODUCTO)[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:COBERTURA|SUMA|$))/i);
        if (planMatch) dentalData.planDental = planMatch[1].trim();
        
        // Buscar suma asegurada anual
        const sumaMatch = texto.match(/(?:SUMA\s+ASEGURADA\s+ANUAL|L[IÍ]MITE\s+ANUAL)[^\d]*\$?\s*([\d,]+)/i);
        if (sumaMatch) dentalData.sumaAseguradaAnual = sumaMatch[1].replace(',', '');
        
        // Lista de servicios dentales comunes
        const servicios = [
            'LIMPIEZA', 'CONSULTA', 'EXTRACCIÓN', 'AMALGAMA', 'RESINA',
            'ENDODONCIA', 'PERIODONCIA', 'ORTODONCIA', 'PRÓTESIS', 'CORONA',
            'PUENTE', 'RAYOS X', 'BLANQUEAMIENTO'
        ];
        
        servicios.forEach(servicio => {
            if (new RegExp(servicio, 'i').test(texto)) {
                dentalData.serviciosIncluidos.push(
                    servicio.charAt(0).toUpperCase() + servicio.slice(1).toLowerCase()
                );
            }
        });
        
        return dentalData;
    }   
    
    extractVisionData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de VISIÓN');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const visionData = {
            planVision: '',
            sumaAsegurada: '',
            deducible: '',
            coaseguro: '',
            serviciosIncluidos: []
        };
        
        // Buscar plan de visión
        const planMatch = texto.match(/(?:PLAN|PRODUCTO)[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:COBERTURA|SUMA|$))/i);
        if (planMatch) visionData.planVision = planMatch[1].trim();
        
        // Buscar suma asegurada
        const sumaMatch = texto.match(/(?:SUMA\s+ASEGURADA|L[IÍ]MITE\s+ANUAL)[^\d]*\$?\s*([\d,]+)/i);
        if (sumaMatch) visionData.sumaAsegurada = sumaMatch[1].replace(',', '');
        
        // Lista de servicios de visión comunes
        const servicios = [
            'CONSULTA', 'EXAMEN DE LA VISTA', 'ANTEOJOS', 'LENTES', 'ARMAZÓN',
            'MICAS', 'CONTACTOLOGÍA', 'LENTES DE CONTACTO', 'CIRUGÍA REFRACTIVA',
            'RETINA', 'GLAUCOMA', 'CATARATAS'
        ];
        
        servicios.forEach(servicio => {
            if (new RegExp(servicio, 'i').test(texto)) {
                visionData.serviciosIncluidos.push(
                    servicio.charAt(0).toUpperCase() + servicio.slice(1).toLowerCase()
                );
            }
        });
        
        return visionData;
    }

    extractEmpresarialData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de EMPRESARIAL');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const empresarialData = {
            tipoEmpresa: '',
            giro: '',
            numeroEmpleados: '',
            sumaAsegurada: '',
            coberturas: []
        };
        
        // Buscar tipo de empresa
        const tipoMatch = texto.match(/(?:TIPO\s+DE\s+EMPRESA|GIRO)[:\s]*([^,\n]+?)(?=\.|\n|$)/i);
        if (tipoMatch) empresarialData.tipoEmpresa = tipoMatch[1].trim();
        
        // Buscar número de empleados
        const empleadosMatch = texto.match(/(\d+)\s*(?:EMPLEADOS?|TRABAJADORES?)/i);
        if (empleadosMatch) empresarialData.numeroEmpleados = empleadosMatch[1];
        
        // Buscar suma asegurada
        const sumaMatch = texto.match(/(?:SUMA\s+ASEGURADA|L[IÍ]MITE)[^\d]*\$?\s*([\d,]+)/i);
        if (sumaMatch) empresarialData.sumaAsegurada = sumaMatch[1].replace(',', '');
        
        return empresarialData;
    }

    esDanos(contenidoUpper) {
        const keywords = [
            'INCENDIO', 'ROBO', 'HURACÁN', 'INUNDACIÓN', 'TERREMOTO',
            'DAÑOS MATERIALES', 'DAÑOS A LA PROPIEDAD', 'TODO RIESGO',
            'FENÓMENOS NATURALES', 'EQUIPO ELECTRÓNICO', 'CRISTALES',
            'MERMA', 'DERRAME', 'ROTURA DE MAQUINARIA'
        ];
        
        for (const keyword of keywords) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esDental(contenidoUpper) {
        const keywords = [
            'DENTAL', 'ODONTOLOGÍA', 'ODONTOLOGIA', 'LIMPIEZA DENTAL',
            'EXTRACCIÓN', 'ENDODONCIA', 'PERIODONCIA', 'ORTODONCIA',
            'PRÓTESIS DENTAL', 'CORONA DENTAL', 'BLANQUEAMIENTO',
            'RAYOS X DENTAL', 'CONSULTA DENTAL'
        ];
        
        for (const keyword of keywords) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esVision(contenidoUpper) {
        const keywords = [
            'VISIÓN', 'VISION', 'OPTICO', 'ÓPTICO', 'LENTES',
            'ANTEOJOS', 'EXAMEN DE LA VISTA', 'CONTACTOLOGÍA',
            'LENTES DE CONTACTO', 'CIRUGÍA REFRACTIVA', 'GLAUCOMA',
            'CATARATAS', 'RETINA', 'OPTOMETRÍA'
        ];
        
        for (const keyword of keywords) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esEmpresarial(contenidoUpper) {
        const keywords = [
            'EMPRESARIAL', 'EMPRESA', 'PYME', 'COMERCIO', 'NEGOCIO',
            'FLOTILLAS', 'MULTIRRIESGO EMPRESARIAL', 'EMPRENDEDOR',
            'PEQUEÑA EMPRESA', 'MEDIANA EMPRESA', 'INDUSTRIAL'
        ];
        
        for (const keyword of keywords) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    flattenObject(obj) {
        if (!obj || typeof obj !== 'object') return {};
        
        const result = {};
        
        Object.keys(obj).forEach(key => {
            const value = obj[key];
            
            if (value === null || value === undefined) {
                result[key] = '';
            } else if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
                result[key] = value;
            } else if (Array.isArray(value)) {
                if (value.length === 0 || typeof value[0] !== 'object') {
                    result[key] = value;
                } else {
                    try {
                        result[key] = JSON.parse(JSON.stringify(value));
                    } catch (e) {
                        result[key] = [];
                    }
                }
            } else {
                try {
                    result[key] = JSON.stringify(value);
                } catch (e) {
                    result[key] = '';
                }
            }
        });
        
        return result;
    }

    crearCotizacionVacia(nombreArchivo) {
        return {
            id: `cot_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            nombreArchivo: nombreArchivo || 'documento.pdf',
            compania: 'Desconocida',
            ramo: 'DESCONOCIDO',
            ramoLabel: 'Desconocido',
            plan: 'No especificado',
            primaTotal: 0,
            primaTotalFormatted: '$0',
            extractionConfidence: 0,
            fechaExtraccion: new Date().toISOString(),
            clienteNombre: '',
            clienteRFC: '',
            clienteCP: '',
            clienteEmail: '',
            clienteTelefono: '',
            clienteDireccion: '',
            tablaCompletaCoberturas: [],
            hasCoberturas: false,
            coberturasCount: 0,
            
            key: `quote-${Date.now()}`,
            ramoIcon: 'utility:question',
            headerStyle: 'background: linear-gradient(135deg, #a0aec0 0%, #718096 100%);',
            confidenceBarStyle: 'width: 0%; background-color: #f56565;',
            confidenceTextStyle: 'color: #f56565; font-weight: bold;',
            uploadDateFormatted: new Date().toLocaleDateString('es-ES'),
            isExpanded: true,
            expandIcon: 'utility:chevronup',
            expandText: 'Colapsar',
            showClienteInfo: false,
            clienteIcon: 'utility:chevronright',
            showCoberturas: false,
            coberturasIcon: 'utility:chevronright'
        };
    }

    // =============================================
    // DETECCIÓN DE RAMO Y COMPAÑÍA (MEJORADA CON LOGS)
    // =============================================

    detectarRamo(contenidoUpper, nombreArchivo, lineas, textoOriginal) {
        if (!contenidoUpper) return 'DESCONOCIDO';
        
        // console.log(':::CotizacionOpLector::: 🔍 Detectando ramo en contenido...');
        console.log(':::CotizacionOpLector::: 📄 Nombre archivo:', nombreArchivo);
        
        // PASO 1: Buscar campos explícitos de ramo en el texto
        const ramoExplicito = this.buscarRamoExplicito(textoOriginal || contenidoUpper);
        if (ramoExplicito) {
            return ramoExplicito.codigo;
        }
        
        // PASO 2: Si no hay campo explícito, usar detección por contenido con prioridades
        const ramo = this.detectarRamoPorContenido(contenidoUpper, lineas, nombreArchivo);
        // console.log(`🎯 Ramo detectado por contenido: ${ramo}`);
        return ramo;
    }

    buscarRamoExplicito(texto) {
        if (!texto) return null;
        
        // Patrones para buscar el ramo (case insensitive)
        const patrones = [
            /RAMO:\s*([^\n\r]+)/i,
            /PRODUCTO:\s*([^\n\r]+)/i,
            /TIPO\s+DE\s+SEGURO\s*([^\n\r]+)/i, 
            /TIPO\s+DE\s+SEGURO:\s*([^\n\r]+)/i, 
            /LÍNEA\s+DE\s+NEGOCIO:\s*([^\n\r]+)/i,
            /LINEA\s+DE\s+NEGOCIO:\s*([^\n\r]+)/i,
            /DESCRIPCI[OÓ]N\s+DEL\s+VEH[IÍ]CULO/i,
            /SEGURO\s+DE:\s*([^\n\r]+)/i,
            /SEGURO\s+DE\s*([^\n\r]+)/i,
            /SEGURO\s*([^\n\r]+)/i,
            /COTIZACION\s*([^\n\r]+)/i,
            /COTIZACION DE\s*([^\n\r]+)/i,
            /COTIZACIÓN\s*([^\n\r]+)/i,
            /COTIZACIÓN DE\s*([^\n\r]+)/i,
            // Agregar patrones específicos para frases comunes
            /AUTO\s+INDIVIDUAL/i,
            /AUTOMOVILES?\s+(?:SERVICIO\s+PUBLICO|IMPORTADOS|RESIDENTES)/i,
            /VEH[IÍ]CULOS?\s+RESIDENTES/i
        ];
        
        for (const patron of patrones) {
            const match = texto.match(patron);
            if (match) {
                const textoRamo = match[1] ? match[1].trim().toUpperCase() : match[0].trim().toUpperCase();
                // console.log(`🔎 Patrón encontrado: "${match[0].trim()}" -> "${textoRamo}"`);
                
                // Si el patrón es específico de auto (como "AUTO INDIVIDUAL"), devolvemos auto directamente
                if (patron.toString().includes('AUTO\\s+INDIVIDUAL') ||
                    patron.toString().includes('AUTOMOVILES?\\s+') ||
                    patron.toString().includes('VEH[IÍ]CULOS?\\s+RESIDENTES')) {
                    return { texto: textoRamo, codigo: 'AUTOMOVIL' };
                }
                
                // Si es "DESCRIPCIÓN DEL VEHÍCULO", inferimos auto
                if (patron.toString().includes('DESCRIPCI[OÓ]N\\s+DEL\\s+VEH[IÍ]CULO')) {
                    return { texto: textoRamo, codigo: 'AUTOMOVIL' };
                }
                
                const codigo = this.mapearRamoExplicito(textoRamo);
                if (codigo) {
                    return { texto: textoRamo, codigo: codigo };
                }
            }
        }
        
        return null;
    }

    mapearRamoExplicito(textoRamo) {
        // Mapeo de palabras clave a códigos de ramo (ordenado por prioridad)
        const mapping = [
            // Gastos Médicos (prioridad alta por ser específico)
            { keywords: ['GASTOS MÉDICOS MAYORES', 'GMM', 'SALUD', 'MÉDICO', 'MEDICO', 'HOSPITAL', 'MEDICAL', 'QSALUD', 'KERALTY', 'BUPA', 'PLAN SEGURO', 'METDENTAL', 'MÉDICALIFE', 'MEDICALIFE', 'FLEX PLUS', 'QCONTIGO', 'OPTIMO', 'ALTA PROTECCIÓN', 'PRÁCTICO', 'DEPENDIENTES ECONÓMICOS', 'TITULAR', 'CONYUGE', 'HIJO', 'PERIODO DE PAGO DE SINIESTROS', 'GAMA HOSPITALARIA'], codigo: 'GASTOS_MEDICOS' },
            // Viaje
            { keywords: ['VIAJE', 'TRAVEL', 'ASISTENCIA AL VIAJERO', 'NEW BUSINESS PROTG', 'PAIS DESTINO', 'PAIS ORIGEN', 'SEGURVIAJE', 'TERRAWIND', 'CANCELACIÓN DE VIAJE', 'REPATRIACIÓN', 'TRASLADO MÉDICO', 'EQUIPAJE'], codigo: 'VIAJE' },
            // Responsabilidad Civil
            { keywords: ['RESPONSABILIDAD CIVIL', 'RC', 'PROFESIONAL', 'PROTECCIÓN', 'EMPRESARIAL FLEXIBLE APEX', 'RC PROFESIONAL', 'R.C.', 'COMERCIO', 'RESTAURANT', 'AGENTES DE SEGUROS', 'RC PARA EMPRESAS', 'RESPONSABILIDAD CIVIL EMPRESARIAL', 'ACTIVIDAD PROFESIONAL', 'GIRO DEL NEGOCIO'], codigo: 'RESPONSABILIDAD_CIVIL' },
            // Transporte
            { keywords: ['TRANSPORTE', 'TRANSPORTES', 'CARGA', 'MERCANCÍAS', 'FLETES', 'RIESGOS ORDINARIOS DE TRANSITO', 'ROBO DE BULTO', 'MOJADURAS', 'MEDIOS DE CONDUCCIÓN', 'LÍMITE MÁXIMO POR EMBARQUE', 'BODEGA A BODEGA', 'EMBARQUE'], codigo: 'TRANSPORTE' },
            // Vida
            { keywords: ['VIDA', 'LIFE', 'FALLECIMIENTO', 'APORTACIÓN', 'OPTIMAXX', 'PLAZO COMPROMETIDO', 'TASA ANUAL PROYECTADA', 'FIDEICOMISO', 'BENEFICIO DEDUCIBILIDAD', 'SALDO DEL FONDO', 'BONO DE FIDELIDAD', 'INVALIDEZ', 'SUMA ASEGURADA POR FALLECIMIENTO'], codigo: 'VIDA' },
            // Mascotas
            { keywords: ['MASCOTA', 'MASCOTAS', 'PET', 'PERRO', 'GATO', 'VETERINARIO', 'DESPARASITACIÓN', 'ANTIRRÁBICA', 'CANINO', 'CANINA', 'VETERINARIA', 'RAZA', 'SEGURO MASCOTA', 'VACUNA', 'HOSPEDAJE DE LA MASCOTA'], codigo: 'MASCOTAS' },
            // Hogar
            { keywords: ['HOGAR', 'CASA', 'HOME', 'VIVIENDA', 'CASA HABITACIÓN', 'EDIFICIO', 'CONTENIDO', 'DEPARTAMENTO', 'CONDOMINIO', 'TERREMOTO', 'HIDROMETEOROLÓGICOS', 'BIENES A LA INTEMPERIE', 'ROBO CON VIOLENCIA', 'CRISTALES', 'GASTOS EXTRAS', 'REMOCIÓN DE ESCOMBROS', 'ASISTENCIA EN EL HOGAR'], codigo: 'HOGAR' },
            // Automóvil
            { keywords: ['AUTOMÓVIL', 'AUTOMOVIL', 'AUTO', 'VEHÍCULO', 'VEHICULO', 'AUTOS', 'PICK UPS', 'SERVICIO PUBLICO', 'RESIDENTES', 'AUTOMOVILES', 'AUTOPLUS', 'PLACA', 'SERIE DEL VEHÍCULO', 'MOTOR', 'CILINDROS', 'PUERTAS', 'TRANSMISIÓN', 'AIRE ACONDICIONADO', 'VALOR COMERCIAL', 'PÉRDIDA TOTAL', 'PÉRDIDA PARCIAL', 'DAÑOS MATERIALES', 'ROBO TOTAL', 'CRISTALES', 'AUTOMOVILES SERVICIO PUBLICO', 'AUTO INDIVIDUAL', 'VEHÍCULOS RESIDENTES', 'AUTOS Y PICK UPS', 'SUV', 'SEDAN', 'HATCHBACK', 'PICK UP', 'GASTOS MÉDICOS OCUPANTES'], codigo: 'AUTOMOVIL' }
        ];
        
        for (const item of mapping) {
            for (const keyword of item.keywords) {
                if (textoRamo.includes(keyword)) {
                    // console.log(`   -> Coincide con keyword "${keyword}" -> ${item.codigo}`);
                    return item.codigo;
                }
            }
        }
        
        // console.log(':::CotizacionOpLector:::    -> No se encontró keyword en mapping');
        return null;
    }

    // =============================================
    // ENRIQUECIMIENTO PARA UI (CON LOGS)
    // =============================================

    enrichQuoteForDisplay(quote) {
        if (!quote) return this.crearCotizacionVacia('');
        
        const confidence = quote.extractionConfidence || 0;
        
        let confidenceColor = '#f56565';
        let confidenceTextColor = '#f56565';
        if (confidence >= 80) {
            confidenceColor = '#38b2ac';
            confidenceTextColor = '#38b2ac';
        } else if (confidence >= 60) {
            confidenceColor = '#ed8936';
            confidenceTextColor = '#ed8936';
        }

        // Usar el ramo del quote
        const ramoOriginal = quote.ramo || 'DESCONOCIDO';
        const ramoNormalizado = this.normalizarRamoParaCSS(ramoOriginal);
        const companiaNormalizada = this.normalizarCompaniaParaCSS(quote.compania);
        
        let ramoIcon = this.getIconForRamo(ramoNormalizado);
        let ramoLabel = quote.ramoLabel || this.getRamoLabel(ramoOriginal);
        
        // Determinar banderas
        const isAutomovil = ramoNormalizado === 'Automoviles';
        const isTransporte = ramoNormalizado === 'Transporte';
        const isGastosMedicos = ramoNormalizado === 'GMM';
        const isMascotas = ramoNormalizado === 'Mascotas';
        const isHogar = ramoNormalizado === 'Hogar';
        const isRC = ramoNormalizado === 'RC';
        const isViaje = ramoNormalizado === 'Viajes';
        const isVida = ramoNormalizado === 'Vida';
        const isEmpresarial = ramoNormalizado === 'Empresarial';
        const isDental = ramoNormalizado === 'Dental';
        const isFianzas = ramoNormalizado === 'Fianzas';
        const isVision = ramoNormalizado === 'Vision';
        const isDanos = ramoNormalizado === 'Danos';
        
        // PROCESAR COBERTURAS PARA AGREGAR KEYS ÚNICAS
        const quoteConCoberturasProcesadas = this.procesarCoberturas(quote);
        
        // console.log(':::CotizacionOpLector:::    Banderas:', { isAutomovil, isTransporte, isGastosMedicos, isMascotas, isHogar, isRC, isViaje, isVida });
        
        return {
            ...quoteConCoberturasProcesadas,
            key: `quote-${quote.id || Date.now()}`,
            ramo: ramoNormalizado,
            compania: companiaNormalizada,
            ramoLabel,
            ramoIcon,
            confidenceBarStyle: `width: ${confidence}%; background-color: ${confidenceColor};`,
            confidenceTextStyle: `color: ${confidenceTextColor}; font-weight: bold;`,
            uploadDateFormatted: quote.fechaExtraccion ? 
                new Date(quote.fechaExtraccion).toLocaleDateString('es-ES', {
                    day: '2-digit',
                    month: 'short',
                    hour: '2-digit',
                    minute: '2-digit'
                }) : '',
            
            // Banderas
            isAutomovil,
            isTransporte,
            isGastosMedicos,
            isMascotas,
            isHogar,
            isRC,
            isViaje,
            isVida,
            isEmpresarial,
            isDental,
            isFianzas,
            isVision,
            isDanos,
            
            // UI state
            isExpanded: quote.isExpanded !== undefined ? quote.isExpanded : true,
            expandIcon: quote.isExpanded ? 'utility:chevronup' : 'utility:chevrondown',
            expandText: quote.isExpanded ? 'Colapsar' : 'Expandir',
            showClienteInfo: quote.showClienteInfo || false,
            clienteIcon: quote.showClienteInfo ? 'utility:chevronup' : 'utility:chevronright',
            showCoberturas: quote.showCoberturas || false,
            coberturasIcon: quote.showCoberturas ? 'utility:chevronup' : 'utility:chevronright'
        };
    }

    normalizarRamoParaCSS(ramo) {
        if (!ramo) return 'Desconocido';
        
        const ramoUpper = String(ramo).toUpperCase();
        
        const mapping = {
            'AUTOMOVILES': 'Automoviles',
            'AUTOMOVIL': 'Automoviles',
            'AUTOMÓVIL': 'Automoviles',
            'AUTOS': 'Automoviles',
            'AUTO': 'Automoviles',
            'VEHICULO': 'Automoviles',
            'VEHÍCULO': 'Automoviles',
            
            'GASTOS_MEDICOS': 'GMM',
            'GASTOS MÉDICOS': 'GMM',
            'GMM': 'GMM',
            
            'DANOS': 'Danos',
            'DAÑOS': 'Danos',
            
            'HOGAR': 'Hogar',
            'CASA': 'Hogar',
            
            'VIAJES': 'Viajes',
            'VIAJE': 'Viajes',
            'TRAVEL': 'Viajes',
            
            'VIDA': 'Vida',
            'LIFE': 'Vida',
            
            'EMPRESARIAL': 'Empresarial',
            'BUSINESS': 'Empresarial',
            
            'DENTAL': 'Dental',
            'ODONTOLOGIA': 'Dental',
            'ODONTOLOGÍA': 'Dental',
            
            'RESPONSABILIDAD_CIVIL': 'RC',
            'RESPONSABILIDAD CIVIL': 'RC',
            'RC': 'RC',
            
            'VISION': 'Vision',
            'VISIÓN': 'Vision',
            'OPTICO': 'Vision',
            'OPTICA': 'Vision'
        };
        
        for (const [key, value] of Object.entries(mapping)) {
            if (ramoUpper.includes(key)) {
                return value;
            }
        }
        
        return ramo;
    }

    normalizarCompaniaParaCSS(compania) {
        if (!compania) return 'Desconocida';
        
        const companiaUpper = String(compania).toUpperCase();
        
        const mapping = {
            'GNP': 'GNP',
            'MAPFRE': 'MAPFRE',
            'HDI': 'HDI',
            'AXA': 'AXA',
            'SURA': 'SURA',
            'BOLIVAR': 'BOLIVAR',
            'QUALITAS': 'QUALITAS',
            'QUÁLITAS': 'QUALITAS',
            'QUALTAS': 'QUALITAS'
        };
        
        for (const [key, value] of Object.entries(mapping)) {
            if (companiaUpper.includes(key)) {
                return value;
            }
        }
        
        return 'Desconocida';
    }

    getIconForRamo(ramo) {
        const icons = {
            'Automoviles': 'utility:car',
            'GMM': 'utility:health',
            'Danos': 'utility:warning',
            'Hogar': 'standard:home',
            'Viajes': 'utility:flight',
            'Vida': 'standard:health',
            'Empresarial': 'standard:company',
            'Dental': 'utility:tooth',
            'RC': 'utility:law',
            'Vision': 'utility:eye'
        };
        
        return icons[ramo] || 'utility:document';
    }

    // =============================================
    // MÉTODOS DE EXTRACCIÓN COMPLETOS
    // =============================================

    safeToUpperCase(text) {
        if (!text) return '';
        if (typeof text === 'string') return text.toUpperCase();
        if (typeof text === 'number') return text.toString().toUpperCase();
        return String(text).toUpperCase();
    }

    formatCurrency(amount) {
        if (!amount && amount !== 0) return '';
        const numAmount = parseFloat(amount) || 0;
        return new Intl.NumberFormat('es-MX', {
            style: 'currency',
            currency: 'MXN',
            minimumFractionDigits: 2
        }).format(numAmount);
    }

    extractNumberFromCurrency(currencyString) {
        if (!currencyString) return 0;
        const match = currencyString.toString().match(/\d+([.,]\d+)?/);
        return match ? parseFloat(match[0].replace(',', '')) : 0;
    }

    extractSimpleValue(texto, patron) {
        if (!texto) return '';
        const match = texto.match(patron);
        return match && match[1] ? match[1].trim() : '';
    }

    extractMonto(texto, patron) {
        if (!texto) return '';
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        const match = textoString.match(patron);
        if (match && match[1]) {
            return match[1].replace(',', '');
        }
        return '';
    }

    // ========== EXTRACCIÓN MASCOTAS ==========
    
    processMascotasData(quote) {
        if (!quote) return {};
        
        const textoCompleto = typeof quote === 'string' ? quote : JSON.stringify(quote);
        
        return {
            mascotaNombre: this.extractMascotaNombre(textoCompleto),
            especie: this.safeToUpperCase(textoCompleto).includes('PERRO') ? 'Perro' : 
                this.safeToUpperCase(textoCompleto).includes('GATO') ? 'Gato' : '',
            raza: this.extractMascotaRaza(textoCompleto),
            edadMascota: this.extractMascotaEdad(textoCompleto),
            sexoMascota: this.safeToUpperCase(textoCompleto).includes('MACHO') ? 'Macho' : 
                this.safeToUpperCase(textoCompleto).includes('HEMBRA') ? 'Hembra' : '',
            responsable: this.extractMascotaResponsable(textoCompleto),
            plan: this.safeToUpperCase(textoCompleto).includes('CUIDADO MÁXIMO') ? 'Cuidado Máximo' :
                this.safeToUpperCase(textoCompleto).includes('CUIDADO SUPERIOR') ? 'Cuidado Superior' :
                this.safeToUpperCase(textoCompleto).includes('CUIDADO ESENCIAL') ? 'Cuidado Esencial' : '',
            sumaAseguradaMascota: this.extractMonto(textoCompleto, /GASTOS M[ÉE]DICOS[^\d]*\$?\s*([\d,]+)/i)
        };
    }

    extractMascotaNombre(texto) {
        if (!texto) return '';
        
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        
        if (textoString.includes('FENDER')) {
            return 'FENDER';
        }
        
        const patrones = [
            /NOMBRE DE LA MASCOTA:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s+(?:TIPO|RAZA|COLOR|EDAD|SEXO|$))/i,
            /MASCOTA:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s+(?:TIPO|RAZA|COLOR|$))/i,
            /(?:\bLLAMADO\b|\bLLAMADA\b)\s+([A-Z][A-Z\s]{2,30}?)(?=\s+(?:DE|QUE|ES|$))/i
        ];
        
        for (const patron of patrones) {
            const match = textoString.match(patron);
            if (match && match[1]) {
                return this.cleanMascotaNombre(match[1].trim());
            }
        }
        
        return '';
    }

    extractMascotaRaza(texto) {
        if (!texto) return '';
        
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        const textoUpper = this.safeToUpperCase(textoString);
        
        if (textoUpper.includes('OTRO / MESTIZO PERRO')) {
            return 'Mestizo';
        }
        
        const patrones = [
            /RAZA:?\s*([A-Z\s\/]{3,40}?)(?=\s+(?:COLOR|EDAD|SEXO|RESPONSABLE|$))/i,
            /RAZA\s+([A-Z\s]{3,40}?)(?=\s+(?:COLOR|EDAD|SEXO|$))/i
        ];
        
        for (const patron of patrones) {
            const match = textoString.match(patron);
            if (match && match[1]) {
                let raza = match[1].trim();
                if (raza.includes('OTRO') || raza.includes('MESTIZO')) {
                    return 'Mestizo';
                }
                raza = raza.replace(/PERRO|GATO/g, '').trim();
                return raza.charAt(0).toUpperCase() + raza.slice(1).toLowerCase();
            }
        }
        
        return '';
    }

    extractMascotaEdad(texto) {
        if (!texto) return '';
        
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        
        const patrones = [
            /EDAD:?\s*(\d+)\s*(AÑOS?|MESES?)/i,
            /(\d+)\s*(AÑOS?|MESES?)\s+DE\s+EDAD/i,
            /(\d+)\s*(AÑOS?|MESES?)/i
        ];
        
        for (const patron of patrones) {
            const match = textoString.match(patron);
            if (match) {
                const numero = match[1];
                const unidad = match[2] || 'años';
                return `${numero} ${unidad.toLowerCase()}`;
            }
        }
        
        return '';
    }

    extractMascotaResponsable(texto) {
        if (!texto) return '';
        
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        
        const patrones = [
            /RESPONSABLE:?\s*([A-Z][A-Z\s]{5,50}?)(?=\s+(?:CORREO|TELÉFONO|EMAIL|$))/i,
            /PROPIETARIO:?\s*([A-Z][A-Z\s]{5,50}?)(?=\s+(?:CORREO|TELÉFONO|$))/i,
            /TITULAR:?\s*([A-Z][A-Z\s]{5,50}?)(?=\s+(?:CORREO|TELÉFONO|$))/i
        ];
        
        for (const patron of patrones) {
            const match = textoString.match(patron);
            if (match && match[1]) {
                return this.cleanNombreResponsable(match[1].trim());
            }
        }
        
        return '';
    }

    cleanMascotaNombre(nombre) {
        if (!nombre) return '';
        
        let clean = nombre;
        
        const palabrasNoDeseadas = [
            'TIPO', 'DE', 'MASCOTA', 'RAZA', 'COLOR', 'EDAD', 'SEXO',
            'RESPONSABLE', 'CORREO', 'ELECTRÓNICO', 'TELÉFONO', 'AÑOS', 'MESES',
            'MACHO', 'HEMBRA', 'PERRO', 'GATO', 'OTRO', 'MESTIZO'
        ];
        
        palabrasNoDeseadas.forEach(palabra => {
            const regex = new RegExp(`\\b${palabra}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        clean = clean.replace(/\d+/g, '');
        clean = clean.replace(/\s+/g, ' ').trim();
        
        return clean;
    }

    cleanNombreResponsable(nombre) {
        if (!nombre) return '';
        
        let clean = nombre;
        
        const palabrasNoDeseadas = [
            'RESPONSABLE', 'PROPIETARIO', 'TITULAR', 'CORREO', 'EMAIL',
            'TELÉFONO', 'TEL', 'MASCOTA', 'PERRO', 'GATO', 'FENDER'
        ];
        
        palabrasNoDeseadas.forEach(palabra => {
            const regex = new RegExp(`\\b${palabra}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        clean = clean.toLowerCase()
            .split(' ')
            .map(palabra => palabra.charAt(0).toUpperCase() + palabra.slice(1))
            .join(' ');
        
        return clean;
    }

    // ========== EXTRACCIÓN GASTOS MÉDICOS ==========

    extractGMMData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de GMM');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const gmmData = {
            plan: '',
            redHospitalaria: '',
            sumaAsegurada: '',
            sumaAseguradaNum: 0,
            deducible: '',
            deducibleNum: 0,
            coaseguro: '',
            topeCoaseguro: '',
            topeCoaseguroNum: 0,
            tabuladorMedico: '',
            lugarResidencia: '',
            tipoNegocio: '',
            maternidad: false,
            asegurados: [],
            primaNeta: '',
            primaTotal: '',
            iva: '',
            derechoPoliza: ''
        };
        
        const planMatch = texto.match(/PRODUCTO:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s*\n|\s*$|\s*[|]|\s*VIGENCIA)/i) ||
                        texto.match(/(?:FLEX\s*PLUS|ALTA\s*PROTECCI[ÓO]N|PR[ÁA]CTICO|QCONTIGO|OPTIMO)/i);
        if (planMatch) {
            gmmData.plan = planMatch[1] || planMatch[0];
        }
        
        const sumaMatch = texto.match(/SUMA\s+ASEGURADA:?\s*\$?\s*([\d,]+(?:\.?\d*)?)(?=\s*(?:\n|\s*DEDUCIBLE|\s*COASEGURO|\s*$))/i) ||
                        texto.match(/SUMA\s+ASEGURADA[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (sumaMatch && sumaMatch[1]) {
            gmmData.sumaAsegurada = sumaMatch[1].replace(',', '');
            gmmData.sumaAseguradaNum = parseFloat(gmmData.sumaAsegurada) || 0;
        }
        
        const deducibleMatch = texto.match(/DEDUCIBLE:?\s*\$?\s*([\d,]+(?:\.?\d*)?)(?=\s*(?:\n|\s*COASEGURO|\s*TOPE|\s*$))/i) ||
                            texto.match(/DEDUCIBLE[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (deducibleMatch && deducibleMatch[1]) {
            gmmData.deducible = deducibleMatch[1].replace(',', '');
            gmmData.deducibleNum = parseFloat(gmmData.deducible) || 0;
        }
        
        const coaseguroMatch = texto.match(/COASEGURO:?\s*(\d+)%\s*(?=\s*(?:\n|\s*TOPE|\s*$))/i) ||
                            texto.match(/COASEGURO[^\d]*(\d+)%/i);
        if (coaseguroMatch) {
            gmmData.coaseguro = coaseguroMatch[1] + '%';
        }
        
        const topeMatch = texto.match(/(?:TOPE\s+(?:DE\s+)?COASEGURO:?\s*\$?\s*([\d,]+(?:\.?\d*)?))(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (topeMatch && topeMatch[1]) { 
            gmmData.topeCoaseguro = topeMatch[1].replace(',', '');
            gmmData.topeCoaseguroNum = parseFloat(gmmData.topeCoaseguro) || 0;
        }
        
        const negocioMatch = texto.match(/(?:TIPO\s+DE\s+NEGOCIO:?\s*)(NUEVO\s+NEGOCIO|RENOVACI[ÓO]N)/i) ||
                            texto.match(/\b(NUEVO\s+NEGOCIO|RENOVACI[ÓO]N)\b/i);
        if (negocioMatch) {
            gmmData.tipoNegocio = negocioMatch[1] || negocioMatch[0];
        }
        
        gmmData.maternidad = /MATERNIDAD:?\s*SI\b/i.test(texto) || 
                            /MATERNIDAD\s+INCLUIDA/i.test(texto) ||
                            /MATERNIDAD.*?(?:SÍ|SI)/i.test(texto);
        
        if (/\bNACIONAL\b/i.test(texto) && !/\bINTERNACIONAL\b/i.test(texto)) {
            gmmData.redHospitalaria = 'Nacional';
        } else if (/\bINTERNACIONAL\b/i.test(texto)) {
            gmmData.redHospitalaria = 'Internacional';
        } else {
            const redMatch = texto.match(/RED\s+HOSPITALARIA:?\s*([A-Z][A-Z\s]{2,20}?)(?=\s*(?:\n|\s*[A-Z]|$))/i);
            if (redMatch) {
                gmmData.redHospitalaria = redMatch[1].trim();
            }
        }
        
        const residenciaMatch = texto.match(/(?:LUGAR\s+DE\s+RESIDENCIA:?\s*|RESIDENCIA:?\s*)([^,\n]+)(?=[,\n]|$)/i);
        if (residenciaMatch) {
            gmmData.lugarResidencia = residenciaMatch[1].trim();
        } else {
            const zonaMatch = texto.match(/([A-Z][A-Z\s]+?)\s*\(ZONA\s*\d+\)/i);
            if (zonaMatch) {
                gmmData.lugarResidencia = zonaMatch[1].trim() + ' ' + zonaMatch[2];
            }
        }
        
        const tabuladorMatch = texto.match(/TABULADOR\s+M[ÉE]DICO:?\s*([A-Z0-9]+)(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (tabuladorMatch) {
            gmmData.tabuladorMedico = tabuladorMatch[1];
        }
        
        const primaNetaMatch = texto.match(/(?:PRIMA\s+NETA|PRIMA\s+BASE)(?::?\s*\$?\s*([\d,]+(?:\.?\d*)?))(?=\s*(?:\n|\s*[A-Z]|\s*DERECHO|\s*IVA|$))/i);
        if (primaNetaMatch && primaNetaMatch[1]) {
            gmmData.primaNeta = primaNetaMatch[1].replace(',', '');
        }
        
        const primaTotalMatch = texto.match(/(?:PRIMA\s+TOTAL|COSTO\s+TOTAL|PAGO\s+ANUAL\s+TOTAL)(?::?\s*\$?\s*([\d,]+(?:\.?\d*)?))(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (primaTotalMatch && primaTotalMatch[1]) {
            gmmData.primaTotal = primaTotalMatch[1].replace(',', '');
        }
        
        const ivaMatch = texto.match(/(?:IVA|I\.V\.A\.)(?::?\s*\$?\s*([\d,]+(?:\.?\d*)?))(?=\s*(?:\n|\s*[A-Z]|$))/i);
        if (ivaMatch && ivaMatch[1]) {
            gmmData.iva = ivaMatch[1].replace(',', '');
        }
        
        const derechoMatch = texto.match(/(?:DERECHO\s+DE\s+P[ÓO]LIZA|DERECHO\s+DE\s+P[OÓ]LIZA)(?::?\s*\$?\s*([\d,]+(?:\.?\d*)?))(?=\s*(?:\n|\s*IVA|$))/i);
        if (derechoMatch && derechoMatch[1]) {
            gmmData.derechoPoliza = derechoMatch[1].replace(',', '');
        }
        
        gmmData.asegurados = this.extractAseguradosPreciso(texto);
        
        return gmmData;
    }

    extractAseguradosPreciso(texto) {
        const asegurados = [];
        const lineas = texto.split('\n');
        
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].trim();
            
            if (linea.includes('Titular') && linea.includes('Beneficiario')) {
                for (let j = i + 1; j < Math.min(i + 10, lineas.length); j++) {
                    const dataLine = lineas[j].trim();
                    if (dataLine && !dataLine.includes(':')) {
                        const parts = dataLine.split(/\s+/);
                        if (parts.length >= 3) {
                            const nombre = parts[0];
                            const edad = parts[parts.length - 2];
                            const parentesco = dataLine.includes('Titular') ? 'Titular' : 
                                            dataLine.includes('Cónyuge') ? 'Cónyuge' :
                                            dataLine.includes('Hijo') ? 'Hijo(a)' : '';
                            
                            asegurados.push({
                                nombre: nombre,
                                edad: edad,
                                parentesco: parentesco,
                                genero: dataLine.includes('Hombre') ? 'Masculino' : 
                                        dataLine.includes('Mujer') ? 'Femenino' : '',
                                esTitular: parentesco === 'Titular',
                                key: `asegurado-${asegurados.length}`
                            });
                        }
                    }
                }
                break;
            }
            
            if (linea.includes('ID') && linea.includes('Nombre')) {
                for (let j = i + 1; j < lineas.length; j++) {
                    const dataLine = lineas[j].trim();
                    if (dataLine.match(/^\d+\s+[A-Z]/)) {
                        const parts = dataLine.split(/\s+/);
                        if (parts.length >= 5) {
                            const nombre = parts.slice(1, -3).join(' ');
                            const parentesco = parts[parts.length - 3];
                            const genero = parts[parts.length - 2];
                            const edad = parts[parts.length - 1];
                            
                            asegurados.push({
                                nombre: nombre,
                                edad: edad,
                                parentesco: parentesco,
                                genero: genero === 'M' ? 'Masculino' : 
                                        genero === 'F' ? 'Femenino' : genero,
                                esTitular: parentesco === 'TITULAR' || parentesco === 'Titular',
                                key: `asegurado-${asegurados.length}`
                            });
                        }
                    }
                    if (dataLine.includes('PRIMA NETA')) break;
                }
                break;
            }
        }
        
        if (asegurados.length === 0) {
            const titularMatch = texto.match(/TITULAR:?\s*([A-Z][A-Z\s]{3,30}?)(?=\s*(?:\n|EDAD|SEXO|$))/i);
            if (titularMatch) {
                asegurados.push({
                    nombre: titularMatch[1].trim(),
                    edad: '',
                    parentesco: 'Titular',
                    esTitular: true,
                    key: `asegurado-${asegurados.length}`
                });
            }
        }
        
        return asegurados;
    }

    // ========== EXTRACCIÓN RESPONSABILIDAD CIVIL ==========

    extractRCData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de RC');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        const textoUpper = texto.toUpperCase();
        
        const rcData = {
            tipoRC: '',
            tipoEspecifico: '',
            profesion: '',
            actividad: '',
            giro: '',
            sumaAsegurada: '',
            deducible: '',
            primaTotal: ''
        };
        
        if (/\bPROFESIONAL\b/i.test(texto)) {
            rcData.tipoRC = 'Profesional';
            if (/\bAGENTES?\s+DE\s+SEGUROS?\b/i.test(texto)) {
                rcData.tipoEspecifico = 'Agentes de Seguros';
            }
        } else if (/\bEMPRESARIAL\b/i.test(texto)) {
            rcData.tipoRC = 'Empresarial';
        } else if (/\bNEGOCIO\b/i.test(texto)) {
            rcData.tipoRC = 'Negocio';
        } else if (/\bFAMILIAR\b/i.test(texto)) {
            rcData.tipoRC = 'Familiar';
        } else if (/\bPATRONAL\b/i.test(texto)) {
            rcData.tipoRC = 'Patronal';
        } else if (/\bCOMERCIO\b/i.test(texto)) {
            rcData.tipoRC = 'Comercio';
        }
        
        const profesionMatch = texto.match(/(?:PROFESI[ÓO]N|PROFESIÓN DEL ASEGURADO):?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:ACTIVIDAD|GIRO|SUMA|DEDUCIBLE|PRIMA|\n|\.|$))/i);
        if (profesionMatch) {
            rcData.profesion = profesionMatch[1].trim();
        } else {
            const rcProfMatch = texto.match(/RC\s+PROFESIONAL\s+([A-Z][A-Z\s]{3,50}?)(?=\s*(?:$|\n|CON|PARA|AGENTES))/i);
            if (rcProfMatch) {
                rcData.profesion = rcProfMatch[1].trim();
            }
        }
        
        const actividadMatch = texto.match(/(?:ACTIVIDAD|ACTIVIDAD DEL NEGOCIO|DESCRIPCIÓN DE LA ACTIVIDAD):?\s*([A-Z][A-Z\s]{3,100}?)(?=\s*(?:GIRO|COBERTURA|SUMA|DEDUCIBLE|PRIMA|\n|\.|$))/i);
        if (actividadMatch) {
            let actividad = actividadMatch[1].trim();
            const rcIndex = actividad.toUpperCase().indexOf('RESPONSABILIDAD CIVIL');
            if (rcIndex > 0) {
                actividad = actividad.substring(0, rcIndex).trim();
            }
            rcData.actividad = this.cleanRCText(actividad);
        }
        
        const giroMatch = texto.match(/(?:GIRO|GIRO DEL NEGOCIO):?\s*([A-Z][A-Z\s\/]{3,100}?)(?=\s*(?:COBERTURA|SUMA|DEDUCIBLE|PRIMA|\n|\.|$))/i);
        if (giroMatch) {
            rcData.giro = this.cleanRCText(giroMatch[1].trim());
        }
        
        const sumaPatterns = [
            /RESPONSABILIDAD\s+CIVIL[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i,
            /LÍMITE\s+ÚNICO\s+COMBINADO[^\d]*\$?\s*([\d,]+)/i,
            /SUMA\s+ASEGURADA[^\d]*\$?\s*([\d,]+)/i
        ];
        
        for (const pattern of sumaPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                rcData.sumaAsegurada = match[1].replace(',', '');
                break;
            }
        }
        
        const deduciblePatterns = [
            /DEDUCIBLE[^\d]*(\d+%)[^\d]*(?:MÍNIMO[^\d]*\$?\s*([\d,]+))?/i,
            /DEDUCIBLE[^\d]*\$?\s*([\d,]+)/i,
            /DEDUCIBLE[^\d]*(\d+%)(?:\s*(?:CON|Y)\s*MÍNIMO[^\d]*\$?\s*([\d,]+))?/i
        ];
        
        for (const pattern of deduciblePatterns) {
            const match = texto.match(pattern);
            if (match) {
                if (match[1] && match[1].includes('%')) {
                    rcData.deducible = match[1];
                    if (match[2]) {
                        rcData.deducible += ` (Mín: $${match[2].replace(',', '')})`;
                    }
                } else if (match[1]) {
                    rcData.deducible = `$${match[1].replace(',', '')}`;
                }
                break;
            }
        }
        
        const primaMatch = texto.match(/(?:PRIMA\s+TOTAL|TOTAL\s+A\s+PAGAR)[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (primaMatch && primaMatch[1]) {
            rcData.primaTotal = primaMatch[1].replace(',', '');
        }
        
        return rcData;
    }

    cleanRCText(texto) {
        if (!texto) return '';
        
        let clean = texto;
        
        clean = clean.replace(/\$[\d,]+\.?\d*/g, '');
        clean = clean.replace(/\d+\s*%/g, '');
        clean = clean.replace(/\d+\s*UMA/g, '');
        
        const palabrasClave = [
            'RESPONSABILIDAD CIVIL', 'R.C.', 'RC', 'COMERCIO',
            'ROBO CON VIOLENCIA', 'ASALTO', 'DAÑOS MATERIALES',
            'EQUIPO ELECTRÓNICO', 'VIRUS INFORMÁTICO',
            'SOLUCIÓN TECNOLÓGICA', 'AMPARADA', 'NO APLICA',
            'DEDUCIBLE', 'MÍNIMO', 'MÁXIMO', 'UMA',
            'SOBRE EL MONTO', 'VALOR DE REPOSICIÓN',
            'PRIMA NETA', 'OTROS DESCUENTOS', 'GASTOS DE EXPEDICIÓN',
            'IVA', 'NOTAS DEL RIESGO', 'VIGENCIA', 'PÁGINA',
            'EN CUMPLIMIENTO', 'ARTÍCULO', 'LEY DE INSTITUCIONES',
            'CONDUSEF', 'CHUBB', 'SEGUROS', 'MÉXICO'
        ];
        
        palabrasClave.forEach(palabra => {
            const regex = new RegExp(`\\b${palabra}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        clean = clean.replace(/P[ÁA]GINA\s+\d+\s+DE\s+\d+/gi, '');
        clean = clean.replace(/\d{1,2}\s+DE\s+[A-Z]+\s+DE\s+\d{4}/gi, '');
        clean = clean.replace(/\d{2}\/\d{2}\/\d{4}/g, '');
        
        clean = clean.replace(/\s+/g, ' ').trim();
        
        if (!clean || clean.length < 3) return '';
        
        return clean;
    }

    // ========== EXTRACCIÓN HOGAR ==========

    extractHogarData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de HOGAR');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        const lineas = texto.split('\n');
        
        const hogarData = {
            direccion: '',
            cp: '',
            tipoVivienda: '',
            tipoConstruccion: '',
            niveles: 1,
            noSotanos: 0,
            sumaEdificio: '',
            sumaContenido: '',
            sumaResponsabilidadCivil: '',
            coberturasAdicionales: []
        };
        
        const direccionPatterns = [
            /DOMICILIO(?:\s+DE\s+LA\s+CASA)?:?\s*([^,\n]+(?:[^,\n]*)?)(?=,|\n|$)/i,
            /DIRECCI[OÓ]N:?\s*([^,\n]+(?:[^,\n]*)?)(?=,|\n|$)/i,
            /DOMICILIO\s+FISCAL:?\s*([^,\n]+(?:[^,\n]*)?)(?=,|\n|$)/i
        ];
        
        for (const pattern of direccionPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                hogarData.direccion = this.cleanHogarDireccion(match[1].trim());
                break;
            }
        }
        
        if (!hogarData.direccion) {
            for (let i = 0; i < Math.min(20, lineas.length); i++) {
                const linea = lineas[i].trim();
                if (linea.includes('CALLE') || linea.includes('AV.') || linea.includes('AVENIDA') || 
                    linea.includes('BOULEVARD') || linea.includes('BLVD') || linea.includes('PRIVADA') ||
                    linea.includes('ANDADOR') || linea.includes('PASEO')) {
                    hogarData.direccion = this.cleanHogarDireccion(linea);
                    break;
                }
            }
        }
        
        const cpMatch = texto.match(/\bC\.?P\.?\s*[:\s]*(\d{5})\b/i);
        if (cpMatch) {
            hogarData.cp = cpMatch[1];
        }
        
        if (/\bCASA\s+HABITACI[OÓ]N\b/i.test(texto)) {
            hogarData.tipoVivienda = 'Casa Habitación';
        } else if (/\bDEPARTAMENTO\b/i.test(texto)) {
            hogarData.tipoVivienda = 'Departamento';
        } else if (/\bCONDOMINIO\b/i.test(texto)) {
            hogarData.tipoVivienda = 'Condominio';
        }
        
        if (/\bCONCRETO\b/i.test(texto)) {
            hogarData.tipoConstruccion = 'Concreto';
        } else if (/\bBLOCK\b/i.test(texto)) {
            hogarData.tipoConstruccion = 'Block';
        } else if (/\bLADRILLO\b/i.test(texto)) {
            hogarData.tipoConstruccion = 'Ladrillo';
        } else if (/\bMACIZO\b/i.test(texto)) {
            hogarData.tipoConstruccion = 'Macizo';
        }
        
        const nivelesMatch = texto.match(/(?:NO\.?\s*NIVELES|NIVELES|PISOS):?\s*(\d+)/i);
        if (nivelesMatch) {
            hogarData.niveles = parseInt(nivelesMatch[1]) || 1;
        }
        
        const sotanosMatch = texto.match(/(?:NO\.?\s*S[OÓ]TANOS|S[OÓ]TANOS):?\s*(\d+)/i);
        if (sotanosMatch) {
            hogarData.noSotanos = parseInt(sotanosMatch[1]) || 0;
        }
        
        const sumaEdificioMatch = texto.match(/(?:INCENDIO\s+EDIFICIO|EDIFICIO|MI\s+CASA)[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (sumaEdificioMatch && sumaEdificioMatch[1]) {
            hogarData.sumaEdificio = sumaEdificioMatch[1].replace(',', '');
        }
        
        const sumaContenidoMatch = texto.match(/(?:CONTENIDOS?|MIS\s+COSAS)[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (sumaContenidoMatch && sumaContenidoMatch[1]) {
            hogarData.sumaContenido = sumaContenidoMatch[1].replace(',', '');
        }
        
        const sumaRCMatch = texto.match(/(?:RESPONSABILIDAD\s+CIVIL\s+FAMILIAR|R\.?C\.?\s+FAMILIAR)[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (sumaRCMatch && sumaRCMatch[1]) {
            hogarData.sumaResponsabilidadCivil = sumaRCMatch[1].replace(',', '');
        }
        
        const coberturasAdicionales = [];
        const coberturasPatterns = [
            'TERREMOTO', 'FENÓMENOS HIDROMETEOROLÓGICOS', 'BIENES A LA INTEMPERIE',
            'ROBO CON VIOLENCIA', 'CRISTALES', 'GASTOS EXTRAS', 'REMOCIÓN DE ESCOMBROS',
            'ASISTENCIA', 'MASCOTAS'
        ];
        
        coberturasPatterns.forEach(cobertura => {
            if (new RegExp(cobertura, 'i').test(texto)) {
                coberturasAdicionales.push(cobertura.charAt(0).toUpperCase() + cobertura.slice(1).toLowerCase());
            }
        });
        
        hogarData.coberturasAdicionales = coberturasAdicionales;
        
        return hogarData;
    }

    cleanHogarDireccion(direccion) {
        if (!direccion) return '';
        
        let clean = direccion;
        
        const etiquetas = [
            'DOMICILIO', 'DIRECCIÓN', 'DIRECCION', 'DOMICILIO FISCAL',
            'DOMICILIO DE LA CASA', 'C.P.', 'CÓDIGO POSTAL', 'CODIGO POSTAL',
            'TELÉFONO', 'TEL', 'EMAIL', 'CORREO ELECTRÓNICO', 'RFC',
            'AVANZA SEGURO', 'AGENTE DE SEGUROS', 'CLAVE', 'OFICINA',
            'INCISO', 'ENDOSO', 'FECHA DE COTIZACIÓN', 'VIGENCIA',
            'FORMA DE PAGO', 'MONEDA', 'TIPO DE PÓLIZA'
        ];
        
        etiquetas.forEach(etiqueta => {
            const regex = new RegExp(`\\b${etiqueta}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        clean = clean.replace(/\s+/g, ' ').trim();
        clean = clean.replace(/,+/g, ',').trim();
        clean = clean.replace(/,\s*,/g, ',');
        
        if (clean.length > 100) {
            clean = clean.substring(0, 100).trim();
            const lastComma = clean.lastIndexOf(',');
            if (lastComma > 0) {
                clean = clean.substring(0, lastComma + 1);
            }
        }
        
        return clean;
    }

    // ========== EXTRACCIÓN TRANSPORTE ==========

    extractTransporteData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de TRANSPORTE');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const transporteData = {
            bienesCubiertos: '',
            medioTransporte: '',
            origen: '',
            destino: '',
            limiteEmbarque: '',
            riesgosAmparados: []
        };
        
        const bienesMatch = texto.match(/(?:BIENES\s+CUBIERTOS?|MERCANC[IÍ]A):?\s*([^,\n]+?)(?=\.|\n|DATOS|MEDIOS|$)/i);
        if (bienesMatch && bienesMatch[1]) {
            transporteData.bienesCubiertos = bienesMatch[1].trim();
        }
        
        const medioMatch = texto.match(/(?:MEDIOS?\s+DE\s+CONDUCCI[OÓ]N|MEDIO\s+DE\s+TRANSPORTE):?\s*([^,\n]+?)(?=\.|\n|ES|HASTA|DESDE|$)/i);
        if (medioMatch && medioMatch[1]) {
            transporteData.medioTransporte = medioMatch[1].trim().split(' ').slice(0, 5).join(' ');
        }
        
        const origenMatch = texto.match(/(?:DESDE|ORIGEN):?\s*([^,\n]+?)(?=\.|\n|HASTA|$)/i);
        if (origenMatch && origenMatch[1]) {
            transporteData.origen = origenMatch[1].trim();
        }
        
        const destinoMatch = texto.match(/(?:HASTA|DESTINO):?\s*([^,\n]+?)(?=\.|\n|$)/i);
        if (destinoMatch && destinoMatch[1]) {
            transporteData.destino = destinoMatch[1].trim();
        }
        
        const limiteMatch = texto.match(/(?:L[IÍ]MITE\s+M[ÁA]XIMO\s+POR\s+EMBARQUE):?\s*\$?\s*([\d,]+(?:\.?\d*)?)/i);
        if (limiteMatch && limiteMatch[1]) {
            transporteData.limiteEmbarque = limiteMatch[1].replace(',', '');
        }
        
        const riesgos = [];
        const lineas = texto.split('\n');
        let enRiesgos = false;
        let riesgoCount = 0;
        
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].toUpperCase();
            
            if (linea.includes('RIESGOS AMPARADOS')) {
                enRiesgos = true;
                continue;
            }
            
            if (enRiesgos && riesgoCount < 8) {
                const riesgoMatch = linea.match(/([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{5,40}?)\s+(?:DEDUCIBLE|\d+%|AMPARADA)/i);
                if (riesgoMatch && riesgoMatch[1]) {
                    const riesgo = riesgoMatch[1].trim();
                    if (riesgo.length > 3 && !riesgo.includes('PRIMA') && !riesgo.includes('TOTAL')) {
                        let deducible = '';
                        const deducibleMatch = linea.match(/DEDUCIBLE\s+([^%]*\d+%[^$]*(?:\$?\s*[\d,]+)?)/i);
                        if (deducibleMatch) {
                            deducible = deducibleMatch[1].trim();
                        } else {
                            const porcentajeMatch = linea.match(/(\d+%)\s+(?:SOBRE|DEL)/i);
                            if (porcentajeMatch) {
                                deducible = porcentajeMatch[1];
                            }
                        }
                        
                        riesgos.push({
                            nombre: riesgo,
                            deducible: deducible || 'No especificado'
                        });
                        riesgoCount++;
                    }
                }
            }
            
            if (enRiesgos && (linea.includes('PRIMA NETA') || linea.includes('PÁGINA') || riesgoCount >= 8)) {
                enRiesgos = false;
            }
        }
        
        transporteData.riesgosAmparados = riesgos;
        
        return transporteData;
    }

    // ========== EXTRACCIÓN AUTO ==========
    extractAutoData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de AUTO');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        const textoUpper = texto.toUpperCase();
        const lineas = texto.split('\n');
        
        const autoData = {
            marca: '',
            modelo: '',
            anio: '',
            placa: '',
            serie: '',
            motor: '',
            uso: '',
            servicio: '',
            descripcion: ''
        };
        
        // Buscar sección de descripción del vehículo
        let descripcionSection = '';
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].toUpperCase();
            if (linea.includes('DESCRIPCION DEL VEHICULO') || 
                linea.includes('DESCRIPCIÓN DEL VEHÍCULO') ||
                linea.includes('DATOS DEL VEHICULO') ||
                linea.includes('VEHICULO ASEGURADO')) {
                // Tomar las siguientes líneas hasta encontrar una línea vacía o nueva sección
                for (let j = i + 1; j < Math.min(i + 10, lineas.length); j++) {
                    const sigLinea = lineas[j].trim();
                    if (sigLinea === '' || sigLinea.includes(':')) break;
                    descripcionSection += sigLinea + ' ';
                }
                break;
            }
        }
        
        // Buscar en sección de resumen
        if (!descripcionSection) {
            for (let i = 0; i < lineas.length; i++) {
                const linea = lineas[i].toUpperCase();
                if (linea.includes('RESUMEN')) {
                    for (let j = i + 1; j < Math.min(i + 15, lineas.length); j++) {
                        const sigLinea = lineas[j].trim();
                        if (sigLinea.includes('PRIMA') || sigLinea.includes('TOTAL')) break;
                        if (sigLinea.length > 15) {
                            descripcionSection += sigLinea + ' ';
                        }
                    }
                    break;
                }
            }
        }
        
        // Si encontramos una sección de descripción, procesarla
        if (descripcionSection) {
            autoData.descripcion = this.cleanAutoDescripcion(descripcionSection);
            
            // Intentar extraer marca y modelo de la descripción
            const partes = descripcionSection.split(/\s+/);
            if (partes.length >= 2) {
                // La marca suele ser la primera palabra
                autoData.marca = partes[0];
                
                // El modelo podría ser la segunda palabra o el resto
                if (partes.length > 1) {
                    autoData.modelo = partes.slice(1).join(' ').substring(0, 50);
                }
            }
        }
        
        // Buscar marca en el texto
        const marcas = [
            'PEUGEOT', 'CHEVROLET', 'NISSAN', 'TOYOTA', 'VOLKSWAGEN', 'FORD', 
            'HONDA', 'MAZDA', 'BMW', 'MERCEDES', 'AUDI', 'KIA', 'HYUNDAI', 
            'RENAULT', 'SEAT', 'FIAT', 'JEEP', 'DODGE', 'CHRYSLER', 'MITSUBISHI',
            'SUZUKI', 'SUBARU', 'VOLVO', 'MINI', 'SMART', 'ACURA', 'INFINITI',
            'LEXUS', 'LINCOLN', 'CADILLAC', 'BUICK', 'GMC'
        ];
        
        for (const marca of marcas) {
            if (textoUpper.includes(marca)) {
                autoData.marca = marca;
                // console.log(':::CotizacionOpLector::: ✅ Marca encontrada:', marca);
                break;
            }
        }
        
        // Buscar año
        const anioPatterns = [
            /(?:A[ÑN]O|MODELO|DEL?)[:\s]*(\b20\d{2}\b)/i,
            /\b(20\d{2})\b(?=\s*(?:[A-Z]|$))/
        ];
        
        for (const pattern of anioPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                const anio = parseInt(match[1]);
                if (anio >= 2000 && anio <= 2030) {
                    autoData.anio = match[1];
                    // console.log(':::CotizacionOpLector::: ✅ Año encontrado:', autoData.anio);
                    break;
                }
            }
        }
        
        // Buscar placa
        const placaPatterns = [
            /PLACAS?[:\s]*([A-Z0-9]{3,8})(?=\s*(?:$|\n|SERIE|MOTOR|USO))/i,
            /\b([A-Z]{3}[-\s]?\d{3})\b/i,
            /\b([A-Z]{2}[-\s]?\d{4})\b/i
        ];
        
        for (const pattern of placaPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                const placa = match[1].replace(/[-\s]/g, '');
                if (placa.length >= 5 && placa.length <= 8) {
                    autoData.placa = placa;
                    // console.log(':::CotizacionOpLector::: ✅ Placa encontrada:', autoData.placa);
                    break;
                }
            }
        }
        
        // Buscar serie (VIN)
        const seriePatterns = [
            /SERIE[:\s]*([A-Z0-9]{10,17})/i,
            /VIN[:\s]*([A-Z0-9]{10,17})/i,
            /\b([A-HJ-NPR-Z0-9]{17})\b/ // VIN típico de 17 caracteres
        ];
        
        for (const pattern of seriePatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                autoData.serie = match[1];
                // console.log(':::CotizacionOpLector::: ✅ Serie encontrada:', autoData.serie);
                break;
            }
        }
        
        // Buscar motor
        const motorPatterns = [
            /MOTOR[:\s]*([A-Z0-9]{5,20})/i,
            /N[ÚU]MERO\s+DE\s+MOTOR[:\s]*([A-Z0-9]{5,20})/i
        ];
        
        for (const pattern of motorPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                autoData.motor = match[1];
                // console.log(':::CotizacionOpLector::: ✅ Motor encontrado:', autoData.motor);
                break;
            }
        }
        
        // Buscar uso
        if (/\bUSO\s+PARTICULAR\b/i.test(texto) || /\bPARTICULAR\b/i.test(texto)) {
            autoData.uso = 'Particular';
        } else if (/\bUSO\s+P[ÚU]BLICO\b/i.test(texto)) {
            autoData.uso = 'Público';
        } else if (/\bSERVICIO\s+PUBLICO\b/i.test(texto)) {
            autoData.uso = 'Público';
        }
        
        // Buscar servicio
        if (/\bSERVICIO\s+PARTICULAR\b/i.test(texto)) {
            autoData.servicio = 'Particular';
        } else if (/\bSERVICIO\s+P[ÚU]BLICO\b/i.test(texto)) {
            autoData.servicio = 'Público';
        }
        
        // console.log(':::CotizacionOpLector::: 📊 Datos AUTO extraídos:', autoData);
        return autoData;
    }

    cleanAutoDescripcion(descripcion) {
        if (!descripcion) return '';
        
        let clean = descripcion;
        
        // Eliminar etiquetas comunes
        const etiquetas = [
            'DESCRIPCION DEL VEHICULO', 'DESCRIPCIÓN DEL VEHÍCULO',
            'DATOS DEL VEHICULO', 'VEHICULO ASEGURADO',
            'MARCA', 'MODELO', 'AÑO', 'PLACA', 'SERIE', 'MOTOR'
        ];
        
        etiquetas.forEach(etiqueta => {
            const regex = new RegExp(etiqueta, 'gi');
            clean = clean.replace(regex, '');
        });
        
        // Eliminar múltiples espacios
        clean = clean.replace(/\s+/g, ' ').trim();
        
        return clean;
    }

    // ========== EXTRACCIÓN VIAJE ==========

    extractViajeData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de VIAJE');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const viajeData = {
            destino: '',
            origen: 'México',
            fechaSalida: '',
            fechaLlegada: '',
            numViajeros: 1,
            duracion: '',
            plan: '',
            coberturasViaje: [],
            asistenciasIncluidas: []
        };
        
        const destinoPatterns = [
            /DESTINO:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:\||\n|$|VIGENCIA|FECHA|TARIFA|BENEFICIOS))/i,
            /PAIS\s+DESTINO:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:\||\n|$))/i,
            /VIAJE\s+A\s+([A-Z][A-Z\s]{2,30}?)(?=\s*(?:\||\n|$|FECHA))/i
        ];
        
        for (const pattern of destinoPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                viajeData.destino = match[1].trim().split('|')[0].trim();
                break;
            }
        }
        
        if (!viajeData.destino) {
            const destinosComunes = ['NORTEAMÉRICA', 'EUROPA', 'ASIA', 'CANADÁ', 'ESTADOS UNIDOS', 'EUA', 'USA'];
            for (const destino of destinosComunes) {
                if (texto.toUpperCase().includes(destino)) {
                    viajeData.destino = destino;
                    break;
                }
            }
        }
        
        const origenPatterns = [
            /ORIGEN:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:\||\n|$))/i,
            /PAIS\s+ORIGEN:?\s*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:\||\n|$))/i
        ];
        
        for (const pattern of origenPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                viajeData.origen = match[1].trim();
                break;
            }
        }
        
        const fechaPatterns = [
            /(?:FECHA\s+DE\s+SALIDA|SALIDA)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
            /(?:FECHA\s+DE\s+LLEGADA|REGRESO|LLEGADA)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i
        ];
        
        const rangoMatch = texto.match(/(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\s*(?:AL?|\s*[-–])\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i);
        if (rangoMatch) {
            viajeData.fechaSalida = rangoMatch[1];
            viajeData.fechaLlegada = rangoMatch[2];
        } else {
            for (const pattern of fechaPatterns) {
                const match = texto.match(pattern);
                if (match) {
                    if (pattern.source.includes('SALIDA')) {
                        viajeData.fechaSalida = match[1];
                    } else {
                        viajeData.fechaLlegada = match[1];
                    }
                }
            }
        }
        
        const viajerosPatterns = [
            /(?:N[º°]?\s*DE\s+(?:ASEGURADOS|PASAJEROS)|CANTIDAD\s+DE\s+PASAJEROS)[:\s]*(\d+)/i,
            /PASAJEROS:?\s*(\d+)/i,
            /(\d+)\s*(?:ASEGURADOS?|PASAJEROS?|VIAJEROS?)(?=\s*(?:\||\n|$))/i
        ];
        
        for (const pattern of viajerosPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                viajeData.numViajeros = parseInt(match[1]) || 1;
                break;
            }
        }
        
        const duracionPatterns = [
            /(?:DURACI[OÓ]N|VIGENCIA)[:\s]*(\d+)\s*(?:D[IÍ]AS?)/i,
            /(\d+)\s*(?:D[IÍ]AS?)\s*(?:DE\s*)?(?:VIAJE|ESTANCIA)/i
        ];
        
        for (const pattern of duracionPatterns) {
            const match = texto.match(pattern);
            if (match) {
                viajeData.duracion = match[1] + ' días';
                break;
            }
        }
        
        const planes = [
            { nombre: 'Platinum', regex: /PLATINUM/i },
            { nombre: 'Gold', regex: /GOLD/i },
            { nombre: 'Silver', regex: /SILVER/i },
            { nombre: 'Premium', regex: /PREMIUM/i },
            { nombre: 'Básico', regex: /B[ÁA]SICO/i }
        ];
        
        for (const plan of planes) {
            if (plan.regex.test(texto)) {
                viajeData.plan = plan.nombre;
                break;
            }
        }
        
        const coberturasViaje = [];
        const lineas = texto.split('\n');
        
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i];
            
            if (linea.includes('USD') && !linea.includes('TASA')) {
                const match = linea.match(/([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{5,50}?)\s*:\s*USD\s*([\d,]+)/i);
                if (match) {
                    coberturasViaje.push({
                        nombre: match[1].trim(),
                        suma: match[2].replace(',', '')
                    });
                }
            }
        }
        
        viajeData.coberturasViaje = coberturasViaje
            .filter((cov, index, self) => index === self.findIndex(c => c.nombre === cov.nombre))
            .slice(0, 8);
        
        return viajeData;
    }

    // ========== EXTRACCIÓN VIDA ==========

    extractVidaData(quote, textoOriginal) {
        // console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos de VIDA');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        
        const vidaData = {
            edadVida: '',
            sexoVida: '',
            fumador: false,
            ocupacion: '',
            sumaFallecimiento: '',
            sumaInvalidez: '',
            aportacionAnual: '',
            plazo: '',
            tasaProyectada: '',
            perfilInversion: ''
        };
        
        const edadPatterns = [
            /EDAD:?\s*(\d+)(?=\s*(?:A[ÑN]OS?|$))/i,
            /(\d+)\s*(?:A[ÑN]OS?)\s*(?:DE\s*)?EDAD/i,
            /\b(\d+)\b(?=\s*(?:A[ÑN]OS?)\s*(?:CUMPLIDOS)?)/
        ];
        
        for (const pattern of edadPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.edadVida = match[1];
                break;
            }
        }
        
        if (/\bMUJER\b|\bFEMENINO\b|\bF\b/i.test(texto)) {
            vidaData.sexoVida = 'Femenino';
        } else if (/\bHOMBRE\b|\bMASCULINO\b|\bM\b/i.test(texto)) {
            vidaData.sexoVida = 'Masculino';
        }
        
        vidaData.fumador = /\bFUMADOR:?\s*SI\b/i.test(texto) || 
                        /\bTABAQUISMO\b/i.test(texto) ||
                        /\bSI\s+FUMA\b/i.test(texto);
        
        const ocupacionPatterns = [
            /OCUPACI[OÓ]N:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:$|\n|EDAD|SEXO|FUMADOR))/i,
            /PROFESI[OÓ]N:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:$|\n|EDAD|SEXO))/i
        ];
        
        for (const pattern of ocupacionPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.ocupacion = match[1].trim();
                break;
            }
        }
        
        const fallecimientoPatterns = [
            /FALLECIMIENTO[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i,
            /SUMA\s+ASEGURADA[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)(?=\s*(?:POR|EN\s+CASO\s+DE)\s+FALLECIMIENTO)/i,
            /MUERTE[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i
        ];
        
        for (const pattern of fallecimientoPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.sumaFallecimiento = match[1].replace(',', '');
                break;
            }
        }
        
        const invalidezPatterns = [
            /INVALIDEZ[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i,
            /INVALIDEZ\s+TOTAL\s+Y\s+PERMANENTE[^\d]*\$?\s*([\d,]+)/i
        ];
        
        for (const pattern of invalidezPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.sumaInvalidez = match[1].replace(',', '');
                break;
            }
        }
        
        const aportacionPatterns = [
            /APORTACI[OÓ]N\s+ANUAL[^\d]*\$?\s*([\d,]+(?:\.?\d*)?)/i,
            /APORTACI[OÓ]N[^\d]*\$?\s*([\d,]+)/i,
            /PRIMA[^\d]*\$?\s*([\d,]+)(?=\s*(?:ANUAL|AÑO))/i
        ];
        
        for (const pattern of aportacionPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.aportacionAnual = match[1].replace(',', '');
                break;
            }
        }
        
        const plazoPatterns = [
            /PLAZO[^\d]*(\d+)\s*(?:A[ÑN]OS?)/i,
            /(\d+)\s*(?:A[ÑN]OS?)\s*(?:DE\s*)?PLAZO/i,
            /PLAZO\s+COMPROMETIDO[^\d]*(\d+)/i
        ];
        
        for (const pattern of plazoPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.plazo = match[1] + ' años';
                break;
            }
        }
        
        const tasaPatterns = [
            /TASA\s+(?:ANUAL\s+)?PROYECTADA[^\d]*(\d+\.?\d*%)/i,
            /TASA[^\d]*(\d+\.?\d*%)(?=\s*(?:ANUAL|PROYECTADA))/i,
            /RENDIMIENTO[^\d]*(\d+\.?\d*%)/i
        ];
        
        for (const pattern of tasaPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                vidaData.tasaProyectada = match[1];
                break;
            }
        }
        
        if (/\bCONSERVADOR\b/i.test(texto)) {
            vidaData.perfilInversion = 'Conservador';
        } else if (/\bMODERADO\b/i.test(texto)) {
            vidaData.perfilInversion = 'Moderado';
        } else if (/\bDIN[ÁA]MICO\b/i.test(texto)) {
            vidaData.perfilInversion = 'Dinámico';
        }
        
        return vidaData;
    }

    // ========== EXTRACCIÓN CLIENTE ==========

    extractClienteData(textoLimpio, contenidoUpper, lineas, textoOriginal) {
        console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos del cliente');
        
        const texto = textoOriginal || textoLimpio || '';
        const lineasArray = texto.split('\n');
        
        const clienteData = {
            nombre: '',
            rfc: '',
            cp: '',
            email: '',
            telefono: '',
            direccion: ''
        };
        
        // ========== NOMBRE DEL CLIENTE ==========
        const nombrePatterns = [
            // Formatos comunes con etiquetas
            /(?:NOMBRE\s+DEL\s+(?:TITULAR|CLIENTE|ASEGURADO|CONTRATANTE)|(?:TITULAR|CLIENTE|ASEGURADO|CONTRATANTE)):?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:RFC|C\.P\.|DOMICILIO|EMAIL|CORREO|TEL[EÉ]FONO|@|$))/i,
            /(?:ESTIMADO|ESTIMADA)[,\s]+([A-Z][A-Z\s]{3,50}?)(?=\s*(?:,|\.|$|\n))/i,
            /DATOS\s+GENERALES:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:EDAD|SEXO|RFC|$))/i,
            /INFORMACION\s+DEL\s+ASEGURADO:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:C\.P\.|RFC|$))/i,
            /DESCRIPCION\s+DEL\s+VEHICULO\s+ASEGURADO:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:MARCA|MODELO|$))/i,
            /información\s+contacto\s*:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:TEL|CORREO|$))/i,
            /Condiciones\s+Particulares:?\s*([A-Z][A-Z\s]{3,50}?)(?=\s*(?:RAMO|PRODUCTO|$))/i,
            // Nombre al inicio de línea (mayúsculas sostenidas)
            /^([A-Z][A-Z\s]{5,50})$/
        ];
        
        for (const pattern of nombrePatterns) {
            const match = texto.match(pattern);
            if (match && match[1] && match[1].length > 5) {
                clienteData.nombre = this.cleanClienteNombre(match[1].trim());
                console.log(':::CotizacionOpLector::: ✅ Nombre encontrado con patrón:', pattern, '->', clienteData.nombre);
                break;
            }
        }
        
        // Si no se encontró, buscar en líneas que parezcan nombres
        if (!clienteData.nombre) {
            for (let i = 0; i < Math.min(20, lineasArray.length); i++) {
                const linea = lineasArray[i].trim();
                // Buscar líneas con formato de nombre (mayúsculas, sin caracteres especiales)
                if (linea.length > 10 && linea.length < 60 && 
                    !linea.includes('@') && !linea.includes('http') &&
                    !linea.includes('RFC') && !linea.includes('C.P.') &&
                    !linea.includes('TEL') && !linea.includes('FAX') &&
                    /^[A-Z][A-Z\s]+$/.test(linea)) {
                    clienteData.nombre = this.cleanClienteNombre(linea);
                    console.log(':::CotizacionOpLector::: ✅ Nombre encontrado en línea:', linea);
                    break;
                }
            }
        }
        
        // ========== RFC ==========
        const rfcPattern = /\b([A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3})\b/;
        const rfcMatch = texto.match(rfcPattern);
        if (rfcMatch) {
            clienteData.rfc = rfcMatch[1];
            console.log(':::CotizacionOpLector::: ✅ RFC encontrado:', clienteData.rfc);
        }
        
        // ========== CÓDIGO POSTAL ==========
        const cpPatterns = [
            /C\.?P\.?[:\s]*(\d{5})/i,
            /C[OÓ]DIGO\s+POSTAL[:\s]*(\d{5})/i,
            /\bCP\.?\s*(\d{5})\b/i,
            /\b(\d{5})\b(?=\s*(?:$|\n|,|\.|MEXICO|MÉXICO))/
        ];
        
        for (const pattern of cpPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                const cp = parseInt(match[1]);
                if (cp >= 1000 && cp <= 99999) {
                    clienteData.cp = match[1];
                    console.log(':::CotizacionOpLector::: ✅ CP encontrado:', clienteData.cp);
                    break;
                }
            }
        }
        
        // ========== EMAIL ==========
        const emailPattern = /\b([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\b/;
        const emailMatch = texto.match(emailPattern);
        if (emailMatch) {
            clienteData.email = emailMatch[1].toLowerCase();
            console.log(':::CotizacionOpLector::: ✅ Email encontrado:', clienteData.email);
        }
        
        // ========== TELÉFONO ==========
        const telefonoPatterns = [
            /(?:TEL[EÉ]FONO|TEL\.?|TEL|PHONE)[:\s]*([0-9\s\-\(\)]{7,15})(?=\s*(?:$|\n|EMAIL|CORREO))/i,
            /\b(\d{2,4}[-\s]?\d{2,4}[-\s]?\d{2,4})\b/,
            /\(\d{2,3}\)\s?\d{4}[\s-]?\d{4}/
        ];
        
        for (const pattern of telefonoPatterns) {
            const match = texto.match(pattern);
            if (match) {
                const telefonoRaw = match[1] || match[0];
                const telefono = telefonoRaw.replace(/[^\d]/g, '');
                if (telefono.length >= 7 && telefono.length <= 15) {
                    clienteData.telefono = telefono;
                    console.log(':::CotizacionOpLector::: ✅ Teléfono encontrado:', clienteData.telefono);
                    break;
                }
            }
        }
        
        // ========== DIRECCIÓN ==========
        const direccionPatterns = [
            /(?:DOMICILIO|DIRECCI[OÓ]N|DOMICILIO FISCAL|ADDRESS)[:\s]*([^,\n]+(?:[^,\n]*?))(?=,|\n|$)/i,
            /(?:CALLE|AV\.|AVENIDA|BOULEVARD|BLVD|PASEO|ANDADOR|PRIVADA|CERRO)\s+([^,\n]+(?:[^,\n]*?))(?=,|\n|$)/i,
            // Buscar dirección después de CP
            new RegExp(clienteData.cp + '\\s+([^\\n]+)', 'i'),
            // Buscar líneas que contengan palabras típicas de dirección
        ];
        
        for (const pattern of direccionPatterns) {
            const match = texto.match(pattern);
            if (match && match[1] && match[1].length > 10) {
                clienteData.direccion = this.cleanClienteDireccion(match[1].trim());
                console.log(':::CotizacionOpLector::: ✅ Dirección encontrada:', clienteData.direccion);
                break;
            }
        }
        
        // Si no se encontró con patrones, buscar líneas con palabras clave
        if (!clienteData.direccion) {
            for (let i = 0; i < Math.min(30, lineasArray.length); i++) {
                const linea = lineasArray[i].trim();
                if ((linea.includes('CALLE') || linea.includes('AV.') || linea.includes('AVENIDA') || 
                    linea.includes('BOULEVARD') || linea.includes('BLVD') || linea.includes('PRIVADA') ||
                    linea.includes('ANDADOR') || linea.includes('PASEO') || linea.includes('CERRO')) &&
                    !linea.includes('@') && !linea.includes('http')) {
                    clienteData.direccion = this.cleanClienteDireccion(linea);
                    console.log(':::CotizacionOpLector::: ✅ Dirección encontrada en línea:', linea);
                    break;
                }
            }
        }
        
        console.log(':::CotizacionOpLector::: 📊 Datos del Cliente extraídos:', clienteData);
        return clienteData;
    }

    extractCotizacionData(texto) {
        console.log(':::CotizacionOpLector::: 🔍 Extrayendo datos generales de cotización');
        
        const cotizacionData = {
            plan: '',
            primaTotal: 0,
            formaPago: '',
            vigencia: '',
            moneda: 'MXN'
        };
        
        if (!texto) return cotizacionData;
        
        // Buscar plan
        const planPatterns = [
            /PLAN[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:VIGENCIA|PRIMA|FORMA|$))/i,
            /PAQUETE[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:VIGENCIA|PRIMA|FORMA|$))/i,
            /PRODUCTO[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:VIGENCIA|PRIMA|FORMA|$))/i,
            /TIPO\s+DE\s+SEGURO[:\s]*([A-Z][A-Z\s]{2,30}?)(?=\s*(?:VIGENCIA|PRIMA|FORMA|$))/i
        ];
        
        for (const pattern of planPatterns) {
            const match = texto.match(pattern);
            if (match && match[1] && match[1].length > 2) {
                cotizacionData.plan = match[1].trim();
                console.log(':::CotizacionOpLector::: ✅ Plan encontrado:', cotizacionData.plan);
                break;
            }
        }
        
        // Buscar prima total (ya existe extractPrimaTotal, pero aquí podemos obtener más datos)
        const primaPatterns = [
            /PRIMA\s+TOTAL[^\d]*\$?\s*([\d,]+\.?\d*)/i,
            /TOTAL\s+A\s+PAGAR[^\d]*\$?\s*([\d,]+\.?\d*)/i,
            /COSTO\s+TOTAL[^\d]*\$?\s*([\d,]+\.?\d*)/i,
            /PRIMA\s+ANUAL[^\d]*\$?\s*([\d,]+\.?\d*)/i
        ];
        
        for (const pattern of primaPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                cotizacionData.primaTotal = parseFloat(match[1].replace(',', '')) || 0;
                console.log(':::CotizacionOpLector::: ✅ Prima total encontrada:', cotizacionData.primaTotal);
                break;
            }
        }
        
        // Buscar forma de pago
        const formaPagoPatterns = [
            /FORMA\s+DE\s+PAGO[:\s]*([A-Z][A-Z\s]{3,20}?)(?=\s*(?:$|\n|PRIMA))/i,
            /PAGO[:\s]*([A-Z][A-Z\s]{3,20}?)(?=\s*(?:$|\n|PRIMA))/i,
            /FRECUENCIA\s+DE\s+PAGO[:\s]*([A-Z][A-Z\s]{3,20}?)(?=\s*(?:$|\n|PRIMA))/i
        ];
        
        for (const pattern of formaPagoPatterns) {
            const match = texto.match(pattern);
            if (match && match[1]) {
                cotizacionData.formaPago = match[1].trim();
                console.log(':::CotizacionOpLector::: ✅ Forma de pago encontrada:', cotizacionData.formaPago);
                break;
            }
        }
        
        // Buscar vigencia
        const vigenciaPatterns = [
            /VIGENCIA[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\s*(?:AL?|[-–])\s*\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
            /DESDE[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\s*(?:HASTA|AL?)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i,
            /V[ÁA]LIDO\s*(?:DEL?|DESDE)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})\s*(?:AL?|HASTA)[:\s]*(\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4})/i
        ];
        
        for (const pattern of vigenciaPatterns) {
            const match = texto.match(pattern);
            if (match) {
                if (match[1] && match[2]) {
                    cotizacionData.vigencia = `${match[1]} - ${match[2]}`;
                } else if (match[1]) {
                    cotizacionData.vigencia = match[1];
                }
                console.log(':::CotizacionOpLector::: ✅ Vigencia encontrada:', cotizacionData.vigencia);
                break;
            }
        }
        
        // Buscar moneda
        const monedaPatterns = [
            /MONEDA[:\s]*(MXN|PESOS|D[OÓ]LARES|USD)/i,
            /(MXN|PESOS|D[OÓ]LARES|USD)\s*(?:M.N.|NACIONAL|AMERICANA)?/i
        ];
        
        for (const pattern of monedaPatterns) {
            const match = texto.match(pattern);
            if (match) {
                const monedaText = (match[1] || match[0]).toUpperCase();
                if (monedaText.includes('USD') || monedaText.includes('DÓLAR') || monedaText.includes('DOLAR')) {
                    cotizacionData.moneda = 'USD';
                } else {
                    cotizacionData.moneda = 'MXN';
                }
                console.log(':::CotizacionOpLector::: ✅ Moneda encontrada:', cotizacionData.moneda);
                break;
            }
        }
        
        return cotizacionData;
    }

    cleanClienteNombre(nombre) {
        if (!nombre) return '';
        
        let clean = nombre;
        
        // Eliminar títulos y palabras clave
        const palabrasNoDeseadas = [
            'SR', 'SRA', 'SRTA', 'LIC', 'DR', 'DRA', 'ING', 'MTRO', 'MTRA',
            'C.', 'CIUDADANO', 'CIUDADANA', 'SEÑOR', 'SEÑORA', 'SEÑORITA',
            'DON', 'DOÑA', 'EL', 'LA', 'LOS', 'LAS', 'Y', 'E', 'DE', 'DEL',
            'RFC', 'C.P.', 'DOMICILIO', 'DIRECCIÓN', 'TELÉFONO', 'EMAIL',
            'CORREO ELECTRÓNICO', 'AVANZA SEGURO', 'AGENTE', 'CLAVE',
            'ESTIMADO', 'ESTIMADA', 'DATOS GENERALES', 'INFORMACION'
        ];
        
        palabrasNoDeseadas.forEach(palabra => {
            const regex = new RegExp(`\\b${palabra}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        // Eliminar números y caracteres especiales
        clean = clean.replace(/[0-9.,;:()\-_]/g, '');
        
        // Capitalizar correctamente
        clean = clean.toLowerCase()
            .split(' ')
            .filter(word => word.length > 1)
            .map(word => word.charAt(0).toUpperCase() + word.slice(1))
            .join(' ');
        
        return clean;
    }

    cleanClienteDireccion(direccion) {
        if (!direccion) return '';
        
        let clean = direccion;
        
        const palabrasNoDeseadas = [
            'DOMICILIO', 'DIRECCIÓN', 'DOMICILIO FISCAL',
            'C.P.', 'CÓDIGO POSTAL', 'TELÉFONO', 'EMAIL',
            'RFC', 'AVANZA SEGURO', 'AGENTE', 'CLAVE'
        ];
        
        palabrasNoDeseadas.forEach(palabra => {
            const regex = new RegExp(`\\b${palabra}\\b`, 'gi');
            clean = clean.replace(regex, '');
        });
        
        clean = clean.replace(/\s+/g, ' ').trim();
        
        return clean;
    }

    extractPrimaTotal(texto) {
        if (!texto) return 0;
        
        const textoString = typeof texto === 'string' ? texto : JSON.stringify(texto);
        
        const patrones = [
            /PRIMA TOTAL[^\d]*\$?\s*([\d,]+\.?\d*)/i,
            /TOTAL A PAGAR[^\d]*\$?\s*([\d,]+\.?\d*)/i,
            /COSTO TOTAL[^\d]*\$?\s*([\d,]+\.?\d*)/i
        ];
        
        for (const patron of patrones) {
            const match = textoString.match(patron);
            if (match && match[1]) {
                return parseFloat(match[1].replace(',', '')) || 0;
            }
        }
        
        return 0;
    }

    extractCoberturasData(quote, textoOriginal) {
        console.log(':::CotizacionOpLector::: 🔍 Extrayendo coberturas');
        
        const texto = textoOriginal || (quote ? JSON.stringify(quote) : '');
        const lineas = texto.split('\n');
        
        const coberturas = [];
        let enCoberturas = false;
        let enTabla = false;
        let tablaHeaders = [];
        
        // ========== MÉTODO 1: BÚSQUEDA POR SECCIONES ==========
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].trim();
            
            // Detectar inicio de sección de coberturas (múltiples formatos)
            if (/(?:COBERTURAS?|DETALLE\s+DE\s+COBERTURAS|COBERTURAS?\s+AMPARADAS|TABLA\s+DE\s+COBERTURAS|COBERTURAS\s+DEL\s+PLAN|COBERTURAS\s+INCLUIDAS|LO\s+QUE\s+TE\s+COMPLEMENTA|LO\s+INDISPENSABLE|LO\s+B[ÁA]SICO|BENEFICIOS\s+INCLUIDOS)/i.test(linea)) {
                enCoberturas = true;
                console.log(':::CotizacionOpLector::: 📍 Inicio de sección coberturas:', linea.substring(0, 50));
                continue;
            }
            
            if (enCoberturas) {
                // Detectar encabezados de tabla
                if (linea.includes('SUMA ASEGURADA') || linea.includes('DEDUCIBLE') || 
                    linea.includes('COASEGURO') || linea.includes('LÍMITE') ||
                    linea.includes('MONTO') || linea.includes('PRIMA') ||
                    linea.includes('COBERTURA') && linea.includes('SUMA')) {
                    enTabla = true;
                    // Guardar headers para referencia
                    tablaHeaders = linea.split(/\s{2,}|\t/).filter(h => h.trim());
                    continue;
                }
                
                if (enTabla) {
                    // ===== FORMATO 1: CON MONTO =====
                    const coberturaMatch = linea.match(/([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{3,60}?)\s+\$?\s*([\d,]+(?:\.?\d*)?)/i);
                    if (coberturaMatch && coberturaMatch[1]) {
                        const nombre = this.limpiarNombreCobertura(coberturaMatch[1].trim());
                        const suma = coberturaMatch[2].replace(',', '');
                        
                        if (this.esCoberturaValida(nombre)) {
                            coberturas.push({
                                cobertura: nombre,
                                sumaAsegurada: suma
                            });
                            continue;
                        }
                    }
                    
                    // ===== FORMATO 2: CON AMPARADA =====
                    if (/AMPARADA|INCLUIDA|CUBIERTA|S[ÍI]|CON\s+COBERTURA/i.test(linea) && !/\$/.test(linea)) {
                        const nombreMatch = linea.match(/([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{3,60}?)\s+(?:AMPARADA|INCLUIDA|CUBIERTA|S[ÍI])/i);
                        if (nombreMatch && nombreMatch[1]) {
                            const nombre = this.limpiarNombreCobertura(nombreMatch[1].trim());
                            if (this.esCoberturaValida(nombre)) {
                                coberturas.push({
                                    cobertura: nombre,
                                    sumaAsegurada: 'Incluida'
                                });
                                continue;
                            }
                        }
                    }
                    
                    // ===== FORMATO 3: TABLA CON MÚLTIPLES COLUMNAS =====
                    if (tablaHeaders.length > 0) {
                        const parts = linea.split(/\s{2,}|\t/).filter(p => p.trim());
                        if (parts.length >= 2) {
                            const posibleNombre = parts[0].trim();
                            if (this.esCoberturaValida(posibleNombre) && 
                                !posibleNombre.includes('SUMA') && 
                                !posibleNombre.includes('DEDUCIBLE')) {
                                
                                // Buscar un monto en las siguientes columnas
                                for (let j = 1; j < parts.length; j++) {
                                    const montoMatch = parts[j].match(/\$?\s*([\d,]+(?:\.?\d*)?)/);
                                    if (montoMatch && montoMatch[1]) {
                                        coberturas.push({
                                            cobertura: this.limpiarNombreCobertura(posibleNombre),
                                            sumaAsegurada: montoMatch[1].replace(',', '')
                                        });
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Salir de la sección de coberturas
                if (enCoberturas && (linea.includes('PRIMA') || linea.includes('FORMA DE PAGO') || 
                    linea.includes('TOTAL') || linea.includes('OBSERVACIONES') ||
                    linea.includes('NOTAS') || linea.includes('CONDICIONES'))) {
                    enCoberturas = false;
                    enTabla = false;
                    tablaHeaders = [];
                }
            }
        }
        
        // ========== MÉTODO 2: BÚSQUEDA POR PATRONES ESPECÍFICOS ==========
        if (coberturas.length === 0) {
            this.buscarCoberturasPorPatrones(texto, coberturas);
        }
        
        // ========== MÉTODO 3: BÚSQUEDA EN LISTAS CON VIÑETAS ==========
        if (coberturas.length < 3) {
            this.buscarCoberturasPorViñetas(lineas, coberturas);
        }
        
        // ========== MÉTODO 4: BÚSQUEDA EN TABLAS HTML ==========
        if (coberturas.length < 3) {
            this.buscarCoberturasEnHTML(texto, coberturas);
        }
        
        // ========== MÉTODO 5: BÚSQUEDA POR PALABRAS CLAVE COMUNES ==========
        if (coberturas.length === 0) {
            this.buscarCoberturasPorPalabrasClave(texto, coberturas);
        }
        
        // Eliminar duplicados y limitar
        const coberturasUnicas = this.eliminarDuplicadosCoberturas(coberturas);
        
        console.log(`:::CotizacionOpLector::: ✅ ${coberturasUnicas.length} coberturas extraídas`);
        if (coberturasUnicas.length > 0) {
            console.log(':::CotizacionOpLector::: 📋 Primeras 3:', coberturasUnicas.slice(0, 3));
        }
        
        return coberturasUnicas;
    }

    // ========== MÉTODOS AUXILIARES ==========

    limpiarNombreCobertura(nombre) {
        if (!nombre) return '';
        
        let limpio = nombre
            .replace(/\s+/g, ' ')
            .replace(/^\s+|\s+$/g, '')
            .replace(/[•·●]/g, '')
            .replace(/[^\w\sáéíóúñÁÉÍÓÚÑ]/g, '');
        
        // Capitalizar primera letra de cada palabra
        limpio = limpio.toLowerCase()
            .split(' ')
            .map(palabra => palabra.charAt(0).toUpperCase() + palabra.slice(1))
            .join(' ');
        
        return limpio;
    }

    esCoberturaValida(nombre) {
        if (!nombre || nombre.length < 3) return false;
        
        const palabrasExcluidas = [
            'SUMA', 'DEDUCIBLE', 'PRIMA', 'TOTAL', 'COASEGURO',
            'FORMA', 'PAGO', 'MONEDA', 'VIGENCIA', 'IVA',
            'TASA', 'IMPORTE', 'DESCUENTO', 'RECARGO',
            'DERECHO', 'EXPEDICIÓN', 'FINANCIAMIENTO',
            'REDUCCIÓN', 'AUTORIZADA', 'PÁGINA', 'NOTA',
            'OBSERVACIONES', 'CONDICIONES', 'CLÁUSULA'
        ];
        
        for (const palabra of palabrasExcluidas) {
            if (nombre.toUpperCase().includes(palabra)) {
                return false;
            }
        }
        
        return true;
    }

    buscarCoberturasPorPatrones(texto, coberturas) {
        const patronesEspecificos = [
            // GMM / Salud
            { nombre: 'Gastos Médicos', patron: /GASTOS?\s+M[ÉE]DICOS?/i, prioridad: 10 },
            { nombre: 'Maternidad', patron: /MATERNIDAD/i, prioridad: 9 },
            { nombre: 'Atención Dental', patron: /(?:ATENCI[OÓ]N\s+)?DENTAL/i, prioridad: 8 },
            { nombre: 'Visión', patron: /VISI[OÓ]N|OPTICO/i, prioridad: 8 },
            { nombre: 'Consulta Médica', patron: /CONSULTAS?\s+M[ÉE]DICAS?/i, prioridad: 7 },
            { nombre: 'Hospitalización', patron: /HOSPITALIZACI[OÓ]N/i, prioridad: 9 },
            { nombre: 'Medicamentos', patron: /MEDICAMENTOS/i, prioridad: 7 },
            
            // Auto
            { nombre: 'Responsabilidad Civil', patron: /RESPONSABILIDAD\s+CIVIL/i, prioridad: 10 },
            { nombre: 'Daños Materiales', patron: /DA[ÑN]OS?\s+MATERIALES?/i, prioridad: 10 },
            { nombre: 'Robo Total', patron: /ROBO\s+TOTAL/i, prioridad: 9 },
            { nombre: 'Robo Parcial', patron: /ROBO\s+PARCIAL/i, prioridad: 8 },
            { nombre: 'Cristales', patron: /CRISTALES/i, prioridad: 7 },
            { nombre: 'Gastos Médicos Ocupantes', patron: /GASTOS?\s+M[ÉE]DICOS?\s+OCUPANTES?/i, prioridad: 8 },
            
            // Hogar
            { nombre: 'Incendio', patron: /INCENDIO/i, prioridad: 10 },
            { nombre: 'Terremoto', patron: /TERREMOTO/i, prioridad: 9 },
            { nombre: 'Fenómenos Hidrometeorológicos', patron: /FEN[OÓ]MENOS?\s+HIDROMETEOROL[OÓ]GICOS/i, prioridad: 9 },
            { nombre: 'Bienes a la Intemperie', patron: /BIENES?\s+A?\s+LA?\s+INTEMPERIE/i, prioridad: 8 },
            { nombre: 'Robo con Violencia', patron: /ROBO\s+CON\s+VIOLENCIA/i, prioridad: 9 },
            
            // Viaje
            { nombre: 'Asistencia Médica', patron: /ASISTENCIA\s+M[ÉE]DICA/i, prioridad: 10 },
            { nombre: 'Equipaje', patron: /EQUIPAJE/i, prioridad: 8 },
            { nombre: 'Cancelación', patron: /CANCELACI[OÓ]N/i, prioridad: 9 },
            { nombre: 'Repatriación', patron: /REPATRIACI[OÓ]N/i, prioridad: 10 },
            
            // Vida
            { nombre: 'Fallecimiento', patron: /FALLECIMIENTO/i, prioridad: 10 },
            { nombre: 'Invalidez', patron: /INVALIDEZ/i, prioridad: 9 },
            
            // Transporte
            { nombre: 'Riesgos Ordinarios de Tránsito', patron: /RIESGOS?\s+ORDINARIOS?\s+DE?\s+TR[ÁA]NSITO?/i, prioridad: 10 },
            { nombre: 'Robo de Bulto', patron: /ROBO\s+DE\s+BULTO/i, prioridad: 9 },
            { nombre: 'Mojaduras', patron: /MOJADURAS/i, prioridad: 8 },
            
            // RC
            { nombre: 'Responsabilidad Civil Profesional', patron: /RESPONSABILIDAD\s+CIVIL\s+PROFESIONAL/i, prioridad: 10 },
            { nombre: 'Responsabilidad Civil Empresarial', patron: /RESPONSABILIDAD\s+CIVIL\s+EMPRESARIAL/i, prioridad: 10 },
            
            // Daños
            { nombre: 'Daños por Agua', patron: /DA[ÑN]OS?\s+POR\s+AGUA/i, prioridad: 8 },
            { nombre: 'Daños Eléctricos', patron: /DA[ÑN]OS?\s+EL[ÉE]CTRICOS?/i, prioridad: 8 }
        ];
        
        // Ordenar por prioridad
        patronesEspecificos.sort((a, b) => b.prioridad - a.prioridad);
        
        for (const patron of patronesEspecificos) {
            if (patron.patron.test(texto)) {
                // Buscar monto asociado
                const montoMatch = texto.match(new RegExp(`${patron.patron.source}[^\\d]*\\$?\\s*([\\d,]+(?:\\\\.?\\d*)?)`, 'i'));
                const yaExiste = coberturas.some(c => 
                    c.cobertura.toUpperCase().includes(patron.nombre.toUpperCase())
                );
                
                if (!yaExiste) {
                    coberturas.push({
                        cobertura: patron.nombre,
                        sumaAsegurada: montoMatch ? montoMatch[1].replace(',', '') : 'Amparada'
                    });
                }
            }
        }
    }

    buscarCoberturasPorViñetas(lineas, coberturas) {
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].trim();
            
            // Detectar líneas con viñetas (•, -, *, etc.)
            if (/^[•\-*●]\s+([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{5,60}?)(?:\s+\$?\s*([\d,]+))?/i.test(linea)) {
                const match = linea.match(/^[•\-*●]\s+([A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]{5,60}?)(?:\s+\$?\s*([\d,]+))?/i);
                if (match) {
                    const nombre = this.limpiarNombreCobertura(match[1].trim());
                    if (this.esCoberturaValida(nombre)) {
                        const suma = match[2] ? match[2].replace(',', '') : 'Incluida';
                        
                        const yaExiste = coberturas.some(c => 
                            c.cobertura.toUpperCase() === nombre.toUpperCase()
                        );
                        
                        if (!yaExiste) {
                            coberturas.push({
                                cobertura: nombre,
                                sumaAsegurada: suma
                            });
                        }
                    }
                }
            }
        }
    }

    buscarCoberturasEnHTML(texto, coberturas) {
        // Buscar tablas HTML
        const tablaMatches = texto.match(/<table[^>]*>.*?<\/table>/gis);
        if (tablaMatches) {
            for (const tabla of tablaMatches) {
                // Buscar filas de tabla
                const filas = tabla.match(/<tr[^>]*>.*?<\/tr>/gis) || [];
                for (const fila of filas) {
                    const celdas = fila.match(/<t[dh][^>]*>.*?<\/t[dh]>/gis) || [];
                    if (celdas.length >= 2) {
                        const posibleNombre = celdas[0].replace(/<[^>]*>/g, '').trim();
                        const posibleMonto = celdas[1].replace(/<[^>]*>/g, '').trim();
                        
                        if (posibleNombre && posibleNombre.length > 3 && 
                            !posibleNombre.includes('SUMA') && 
                            !posibleNombre.includes('COBERTURA')) {
                            
                            const montoMatch = posibleMonto.match(/\$?\s*([\d,]+)/);
                            const yaExiste = coberturas.some(c => 
                                c.cobertura.toUpperCase() === posibleNombre.toUpperCase()
                            );
                            
                            if (!yaExiste && this.esCoberturaValida(posibleNombre)) {
                                coberturas.push({
                                    cobertura: this.limpiarNombreCobertura(posibleNombre),
                                    sumaAsegurada: montoMatch ? montoMatch[1].replace(',', '') : 'Amparada'
                                });
                            }
                        }
                    }
                }
            }
        }
    }

    buscarCoberturasPorPalabrasClave(texto, coberturas) {
        const palabrasClave = [
            'INCENDIO', 'ROBO', 'RESPONSABILIDAD CIVIL', 'TERREMOTO',
            'GASTOS MÉDICOS', 'CRISTALES', 'EQUIPO ELECTRÓNICO',
            'ASISTENCIA', 'REPATRIACIÓN', 'CANCELACIÓN', 'EQUIPAJE',
            'FALLECIMIENTO', 'INVALIDEZ', 'HOSPITALIZACIÓN',
            'MATERNIDAD', 'DENTAL', 'VISIÓN', 'CONSULTA',
            'DAÑOS MATERIALES', 'PÉRDIDA TOTAL', 'PÉRDIDA PARCIAL',
            'FENÓMENOS NATURALES', 'HURACÁN', 'INUNDACIÓN'
        ];
        
        for (const palabra of palabrasClave) {
            if (new RegExp(`\\b${palabra}\\b`, 'i').test(texto)) {
                // Buscar un monto cercano
                const regex = new RegExp(`${palabra}[^\\d]*\\$?\\s*([\\d,]+(?:\\\\.?\\d*)?)`, 'i');
                const montoMatch = texto.match(regex);
                
                const yaExiste = coberturas.some(c => 
                    c.cobertura.toUpperCase().includes(palabra)
                );
                
                if (!yaExiste) {
                    coberturas.push({
                        cobertura: palabra.charAt(0).toUpperCase() + palabra.slice(1).toLowerCase(),
                        sumaAsegurada: montoMatch ? montoMatch[1].replace(',', '') : 'Amparada'
                    });
                }
            }
        }
    }

    eliminarDuplicadosCoberturas(coberturas) {
        const unicas = [];
        const vistos = new Set();
        
        for (const cov of coberturas) {
            const key = cov.cobertura.toUpperCase();
            if (!vistos.has(key)) {
                vistos.add(key);
                unicas.push(cov);
            }
        }
        
        return unicas.slice(0, 20); // Limitar a 20 coberturas
    }

    // =============================================
    // DETECCIÓN DE RAMO Y COMPAÑÍA (MEJORADA)
    // =============================================


    detectarRamoPorContenido(contenidoUpper, lineas, nombreArchivo) {
        if (this.esGastosMedicos(contenidoUpper, lineas)) {
            return 'GASTOS_MEDICOS';
        }
        
        if (this.esSeguroViaje(contenidoUpper)) {
            return 'VIAJES';
        }
        
        if (this.esResponsabilidadCivil(contenidoUpper)) {
            return 'RESPONSABILIDAD_CIVIL';
        }
        
        if (this.esEmpresarial(contenidoUpper)) {
            return 'EMPRESARIAL';
        }
        
        if (this.esHogar(contenidoUpper)) {
            return 'HOGAR';
        }
        
        if (this.esDanos(contenidoUpper)) {
            return 'DANOS';
        }
        
        if (this.esDental(contenidoUpper)) {
            return 'DENTAL';
        }
        
        if (this.esVision(contenidoUpper)) {
            return 'VISION';
        }
        
        if (this.esAutomovil(contenidoUpper, lineas)) {
            return 'AUTOMOVILES';
        }
        
        if (this.esVida(contenidoUpper)) {
            return 'VIDA';
        }
        
        // Fallback por nombre de archivo
        return this.detectarRamoPorNombreArchivo(nombreArchivo);
    }

    detectarRamoPorPalabrasClave(contenidoUpper, lineas, nombreArchivo) {
        // VIDA
        if (contenidoUpper.includes('OPTIMAXX') || 
            contenidoUpper.includes('APORTACIÓN ANUAL') ||
            contenidoUpper.includes('SALDO DEL FONDO') ||
            contenidoUpper.includes('BENEFICIO DEDUCIBILIDAD') ||
            contenidoUpper.includes('FIDEICOMISO') ||
            (contenidoUpper.includes('VIDA') && contenidoUpper.includes('ALLIANZ'))) {
            console.log(':::CotizacionOpLector::: ✅ Ramo VIDA detectado por palabras clave');
            return 'VIDA';
        }
        
        // VIAJE
        if (contenidoUpper.includes('NEW BUSINESS') && contenidoUpper.includes('PROTG') ||
            contenidoUpper.includes('SEGURVIAJE') ||
            contenidoUpper.includes('PAIS DESTINO') ||
            contenidoUpper.includes('FECHA DE SALIDA') && contenidoUpper.includes('FECHA DE LLEGADA') ||
            contenidoUpper.includes('CANCELACIÓN DE VIAJE') ||
            contenidoUpper.includes('ASISTENCIA AL VIAJERO') ||
            contenidoUpper.includes('TERRAWIND')) {
            console.log(':::CotizacionOpLector::: ✅ Ramo VIAJE detectado por palabras clave');
            return 'VIAJE';
        }
        
        // TRANSPORTE
        if (contenidoUpper.includes('TRANSPORTE DE CARGA') ||
            contenidoUpper.includes('TRANSPORTE DE MERCANCÍAS') ||
            contenidoUpper.includes('RIESGOS ORDINARIOS DE TRANSITO') ||
            contenidoUpper.includes('LÍMITE MÁXIMO POR EMBARQUE') ||
            contenidoUpper.includes('MEDIOS DE CONDUCCIÓN') ||
            contenidoUpper.includes('EMBARQUE') && contenidoUpper.includes('MERCANCÍAS')) {
            console.log(':::CotizacionOpLector::: ✅ Ramo TRANSPORTE detectado por palabras clave');
            return 'TRANSPORTE';
        }
        
        // RESPONSABILIDAD CIVIL
        if (contenidoUpper.includes('RESPONSABILIDAD CIVIL PROFESIONAL') ||
            contenidoUpper.includes('RC PROFESIONAL') ||
            (contenidoUpper.includes('RESPONSABILIDAD CIVIL') && contenidoUpper.includes('ACTIVIDADES E INMUEBLES')) ||
            (contenidoUpper.includes('RC') && contenidoUpper.includes('ACTIVIDADES E INMUEBLES')) ||
            contenidoUpper.includes('R.C. COMERCIO') ||
            contenidoUpper.includes('ABASEGURO EMPRESARIAL') ||
            contenidoUpper.includes('EMPRESARIAL FLEXIBLE APEX')) {
            console.log(':::CotizacionOpLector::: ✅ Ramo RESPONSABILIDAD_CIVIL detectado por palabras clave');
            return 'RESPONSABILIDAD_CIVIL';
        }
        
        return 'DESCONOCIDO';
    }

    // Las siguientes funciones ya deberían estar en tu código, pero asegúrate de que contengan todas las keywords.
    // Si alguna falta, reemplázala con la versión de abajo.

    esResponsabilidadCivil(contenidoUpper) {
        // Patrones específicos para RC
        const keywordsRC = [
            // Profesional
            'RESPONSABILIDAD CIVIL PROFESIONAL',
            'RC PROFESIONAL',
            'RC PROFESIONAL AGENTES DE SEGUROS',
            
            // Empresarial / Negocio
            'RESPONSABILIDAD CIVIL ACTIVIDADES E INMUEBLES',
            'RC ACTIVIDADES E INMUEBLES',
            'R.C. COMERCIO',
            'RC ARRENDATARIO',
            'CARGA Y DESCARGA',
            'ABASEGURO EMPRESARIAL',
            'EMPRESARIAL FLEXIBLE APEX',
            
            // Generales
            'RESPONSABILIDAD CIVIL',
            'R.C.',
            'RC',
            
            // Contextos específicos
            'AGENTES DE SEGUROS',
            'RESPONSABILIDAD CIVIL GENERAL'
        ];
        
        for (const keyword of keywordsRC) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esTransporte(contenidoUpper) {
        const keywordsTransporte = [
            'TRANSPORTE DE CARGA',
            'TRANSPORTE DE MERCANCÍAS',
            'CARGA',
            'EMBARQUE',
            'MERCANCÍAS',
            'FLETES',
            'RIESGOS ORDINARIOS DE TRANSITO',
            'ROBO DE BULTO',
            'MOJADURAS',
            'MEDIOS DE CONDUCCIÓN',
            'LÍMITE MÁXIMO POR EMBARQUE',
            'BODEGA A BODEGA',
            'CONTAMINACION POR CONTACTO',
            'MERMA O DERRAME',
            'MANIOBRAS DE CARGA Y DESCARGA'
        ];
        
        for (const keyword of keywordsTransporte) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esSeguroViaje(contenidoUpper) {
        const keywordsViaje = [
            'SEGURO DE VIAJE',
            'ASISTENCIA AL VIAJERO',
            'VIAJE INTERNACIONAL',
            'DESTINO',
            'FECHA DE SALIDA',
            'FECHA DE LLEGADA',
            'CANCELACIÓN DE VIAJE',
            'REPATRIACIÓN',
            'TRASLADO MÉDICO',
            'EQUIPAJE',
            'PASAJEROS',
            'TERRAWIND',
            'SEGURVIAJE',
            'NEW BUSINESS PROTG',
            'PAIS ORIGEN',
            'PAIS DESTINO'
        ];
        
        for (const keyword of keywordsViaje) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esVida(contenidoUpper) {
        const keywordsVida = [
            'OPTIMAXX',
            'OPTIMAXx PLUS',
            'SEGURO DE VIDA',
            'APORTACIÓN ANUAL',
            'FALLECIMIENTO',
            'PLAZO COMPROMETIDO',
            'TASA ANUAL PROYECTADA',
            'FIDEICOMISO',
            'BENEFICIO DEDUCIBILIDAD',
            'SALDO DEL FONDO',
            'BONO DE FIDELIDAD',
            'INVALIDEZ',
            'SUMA ASEGURADA POR FALLECIMIENTO'
        ];
        
        for (const keyword of keywordsVida) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        return false;
    }

    esMascotas(contenidoUpper) {
        const keywords = [
            'MASCOTA', 'PERRO', 'GATO', 'VETERINARIO', 'DESPARASITACIÓN',
            'ANTIRRÁBICA', 'CANINO', 'CANINA', 'VETERINARIA', 'RAZA',
            'SEGURO MASCOTA', 'VACUNA', 'HOSPEDAJE DE LA MASCOTA'
        ];
        let count = 0;
        for (const keyword of keywords) {
            if (contenidoUpper.includes(keyword)) {
                count++;
                if (count >= 2) return true;
            }
        }
        if (count === 1) {
            if (contenidoUpper.includes('SEGURO MASCOTA') || contenidoUpper.includes('HOSPEDAJE DE LA MASCOTA')) {
                return true;
            }
        }
        return false;
    }

    esGastosMedicos(contenidoUpper, lineas) {
        // Palabras clave EXCLUSIVAS de GMM (evitando "GASTOS MÉDICOS OCUPANTES")
        const keywordsExclusivas = [
            'GASTOS MÉDICOS MAYORES',
            'GMM',
            'COASEGURO MÉDICO',
            'TABULADOR MÉDICO',
            'RED HOSPITALARIA',
            'MATERNIDAD',
            'PLAN DE SALUD',
            'HOSPITALIZACIÓN',
            'CONSULTA MÉDICA',
            'MEDICINA GENERAL',
            'ATENCIÓN DENTAL',
            'VISIÓN',
            'QSALUD',
            'KERALTY',
            'BUPA',
            'PLAN SEGURO',
            'METDENTAL',
            'MÉDICALIFE',
            'MEDICALIFE',
            'FLEX PLUS',
            'QCONTIGO',
            'OPTIMO',
            'ALTA PROTECCIÓN',
            'PRÁCTICO',
            'DEPENDIENTES ECONÓMICOS',
            'TITULAR',
            'CONYUGE',
            'HIJO',
            'PERIODO DE PAGO DE SINIESTROS',
            'GAMA HOSPITALARIA'
        ];
        
        for (const keyword of keywordsExclusivas) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        
        // Buscar "GASTOS MÉDICOS" pero asegurando que no sea "OCUPANTES"
        if (contenidoUpper.includes('GASTOS MÉDICOS') && !contenidoUpper.includes('GASTOS MÉDICOS OCUPANTES')) {
            // Verificar que no sea en contexto de auto
            if (!contenidoUpper.includes('VEHÍCULO') && !contenidoUpper.includes('AUTO')) {
                return true;
            }
        }
        
        // Buscar en líneas específicas
        for (let i = 0; i < Math.min(20, lineas.length); i++) {
            const linea = lineas[i].toUpperCase();
            
            // Detectar tablas de asegurados típicas de GMM
            if (linea.includes('ID') && linea.includes('NOMBRE') && 
                (linea.includes('PARENTESCO') || linea.includes('EDAD'))) {
                return true;
            }
            
            if (linea.includes('TITULAR') && linea.includes('CONYUGE') && linea.includes('HIJO')) {
                return true;
            }
            
            // Detectar estructura de tabla de GMM
            if (linea.includes('PRIMA NETA') && linea.includes('DERECHO DE PÓLIZA')) {
                return true;
            }
        }
        
        return false;
    }

    esAutomovil(contenidoUpper, lineas) {
        // Palabras clave de AUTO (incluyendo "GASTOS MÉDICOS OCUPANTES" como pista)
        const keywordsAuto = [
            'AUTOMÓVIL',
            'AUTOMOVIL',
            'VEHÍCULO',
            'VEHICULO',
            'AUTO',
            'PLACA',
            'SERIE DEL VEHÍCULO',
            'MOTOR',
            'CILINDROS',
            'PUERTAS',
            'TRANSMISIÓN',
            'AIRE ACONDICIONADO',
            'VALOR COMERCIAL',
            'PÉRDIDA TOTAL',
            'PÉRDIDA PARCIAL',
            'DAÑOS MATERIALES',
            'ROBO TOTAL',
            'CRISTALES',
            'AUTOMOVILES SERVICIO PUBLICO',
            'AUTO INDIVIDUAL',
            'VEHÍCULOS RESIDENTES',
            'AUTOS Y PICK UPS',
            'SUV',
            'SEDAN',
            'HATCHBACK',
            'PICK UP',
            'GASTOS MÉDICOS OCUPANTES'  // Esta es clave para autos
        ];
        
        // Verificar que NO sea GMM primero (para evitar falsos positivos)
        if (this.esGastosMedicos(contenidoUpper, lineas)) {
            return false;
        }
        
        for (const keyword of keywordsAuto) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        
        // Buscar marcas de autos (pero solo si no hay indicios de GMM)
        const marcasAuto = [
            'PEUGEOT', 'CHEVROLET', 'NISSAN', 'TOYOTA', 'VOLKSWAGEN', 'FORD',
            'HONDA', 'MAZDA', 'BMW', 'MERCEDES', 'AUDI', 'KIA', 'HYUNDAI',
            'RENAULT', 'SEAT', 'FIAT', 'JEEP', 'DODGE', 'CHRYSLER', 'MITSUBISHI',
            'SUZUKI', 'SUBARU', 'VOLVO'
        ];
        
        for (const marca of marcasAuto) {
            if (contenidoUpper.includes(marca)) {
                // Verificar que no sea un contexto de GMM
                if (!contenidoUpper.includes('GASTOS MÉDICOS MAYORES') && 
                    !contenidoUpper.includes('HOSPITAL') &&
                    !contenidoUpper.includes('CONSULTA')) {
                    return true;
                }
            }
        }
        
        return false;
    }

    esHogar(contenidoUpper) {
        const keywordsHogar = [
            'HOGAR', 'CASA HABITACIÓN', 'EDIFICIO', 'CONTENIDO', 'VIVIENDA',
            'CASA', 'DEPARTAMENTO', 'CONDOMINIO', 'TERREMOTO', 'HIDROMETEOROLÓGICOS',
            'BIENES A LA INTEMPERIE', 'ROBO CON VIOLENCIA', 'CRISTALES',
            'GASTOS EXTRAS', 'REMOCIÓN DE ESCOMBROS', 'ASISTENCIA EN EL HOGAR'
        ];
        
        for (const keyword of keywordsHogar) {
            if (contenidoUpper.includes(keyword)) {
                return true;
            }
        }
        
        return false;
    }

    detectarRamoPorNombreArchivo(nombreArchivo) {
        const nombreUpper = nombreArchivo.toUpperCase();
        
        const mapping = [
            { keywords: ['GMM', 'GASTOS MEDICOS', 'SALUD', 'BUPA', 'KERALTY', 'QSALUD', 'PLAN SEGURO', 'METLIFE'], ramo: 'GASTOS_MEDICOS' },
            { keywords: ['VIAJE', 'VIAJES', 'TRAVEL', 'TERRAWIND'], ramo: 'VIAJES' },
            { keywords: ['HOGAR', 'CASA', 'HOME'], ramo: 'HOGAR' },
            { keywords: ['VIDA', 'LIFE', 'ALLIANZ'], ramo: 'VIDA' },
            { keywords: ['RC', 'RESPONSABILIDAD', 'CHUBB'], ramo: 'RESPONSABILIDAD_CIVIL' },
            { keywords: ['DANOS', 'DAÑOS', 'INCENDIO', 'MULTIRRIESGO'], ramo: 'DANOS' },
            { keywords: ['DENTAL', 'ODONTOLOGIA', 'SMILES'], ramo: 'DENTAL' },
            { keywords: ['VISION', 'VISIÓN', 'OPTICO', 'LENTES'], ramo: 'VISION' },
            { keywords: ['EMPRESARIAL', 'PYME', 'COMERCIO', 'NEGOCIO'], ramo: 'EMPRESARIAL' },
            { keywords: ['AUTO', 'AUTOMOVIL', 'VEHICULO', 'AFIRME'], ramo: 'AUTOMOVILES' }
        ];
        
        for (const item of mapping) {
            for (const keyword of item.keywords) {
                if (nombreUpper.includes(keyword)) {
                    console.log(`✅ Ramo detectado por nombre archivo: ${item.ramo} (${keyword})`);
                    return item.ramo;
                }
            }
        }
        
        return 'DESCONOCIDO';
    }

    detectarCompania(contenidoUpper, nombreArchivo) {
        if (!contenidoUpper) return 'Desconocida';
        
        console.log(':::CotizacionOpLector::: 🔍 Detectando compañía en contenido');
        
        const companias = [
            // Ordenado por especificidad (más específico primero)
            { nombres: ['TERRAWIND'], label: 'TERRAWIND' },
            
            { nombres: ['AXA SALUD'], label: 'AXA' },
            { nombres: ['AXA SEGUROS'], label: 'AXA' },
            { nombres: ['AXA'], label: 'AXA' },
            
            { nombres: ['ALLIANZ MÉXICO'], label: 'ALLIANZ' },
            { nombres: ['ALLIANZ'], label: 'ALLIANZ' },
            
            { nombres: ['BUPA MÉXICO'], label: 'BUPA' },
            { nombres: ['BUPA'], label: 'BUPA' },
            
            { nombres: ['GNP SEGUROS'], label: 'GNP' },
            { nombres: ['GRUPO NACIONAL PROVINCIAL'], label: 'GNP' },
            { nombres: ['GNP AUTOS'], label: 'GNP' },
            { nombres: ['GNP'], label: 'GNP' },
            
            { nombres: ['HDI SEGUROS'], label: 'HDI' },
            { nombres: ['HDI AUTOS'], label: 'HDI' },
            { nombres: ['HDI'], label: 'HDI' },
            
            { nombres: ['KERALTY SALUD'], label: 'KERALTY' },
            { nombres: ['KERALTY'], label: 'KERALTY' },
            
            { nombres: ['MAPFRE MÉXICO'], label: 'MAPFRE' },
            { nombres: ['MAPFRE'], label: 'MAPFRE' },
            
            { nombres: ['METLIFE MÉXICO'], label: 'METLIFE' },
            { nombres: ['MÉDICALIFE'], label: 'METLIFE' },
            { nombres: ['MEDICALIFE'], label: 'METLIFE' },
            { nombres: ['METLIFE'], label: 'METLIFE' },
            
            { nombres: ['PLAN SEGURO', 'PLANSEGURO', 'PLANSEGUROMX'], label: 'PLAN SEGURO' },
            
            { nombres: ['QSALUD'], label: 'QSALUD' },
            { nombres: ['Q SALUD'], label: 'QSALUD' },
            
            { nombres: ['QUALITAS'], label: 'QUALITAS' },
            { nombres: ['QUÁLITAS'], label: 'QUALITAS' },
            
            { nombres: ['AFIRME GRUPO FINANCIERO'], label: 'AFIRME' },
            { nombres: ['SEGUROS AFIRME'], label: 'AFIRME' },
            { nombres: ['AFIRME'], label: 'AFIRME' },
            
            { nombres: ['CHUBB'], label: 'CHUBB' },
            { nombres: ['SURA'], label: 'SURA' },
            { nombres: ['BOLIVAR'], label: 'BOLIVAR' }
        ];
        
        // Buscar en el contenido del PDF
        for (const compania of companias) {
            for (const nombre of compania.nombres) {
                if (contenidoUpper.includes(nombre)) {
                    console.log(`✅ Compañía detectada: ${compania.label}`);
                    return compania.label;
                }
            }
        }
        
        // Si no se encuentra en el contenido, buscar en el nombre del archivo
        const nombreUpper = nombreArchivo.toUpperCase();
        for (const compania of companias) {
            for (const nombre of compania.nombres) {
                if (nombreUpper.includes(nombre)) {
                    console.log(`✅ Compañía detectada por nombre archivo: ${compania.label}`);
                    return compania.label;
                }
            }
        }
        
        return 'Desconocida';
    }

    getRamoLabel(ramo) {
        const labels = {
            'AUTOMOVILES': 'Automóviles',
            'AUTOMOVIL': 'Automóviles',
            'DANOS': 'Daños',
            'DENTAL': 'Dental',
            'EMPRESARIAL': 'Empresarial',
            'GASTOS_MEDICOS': 'Gastos Médicos',
            'HOGAR': 'Hogar',
            'RESPONSABILIDAD_CIVIL': 'Responsabilidad Civil',
            'VIAJES': 'Viajes',
            'VIAJE': 'Viajes',
            'VIDA': 'Vida',
            'VISION': 'Visión',
            'SALUD': 'Salud',
            'DESCONOCIDO': 'Desconocido'
        };
        return labels[ramo] || ramo;
    }

    extraerPlan(contenidoUpper) {
        if (!contenidoUpper) return 'No especificado';
        const planes = ['AMPLIA', 'BÁSICA', 'PREMIUM', 'ESTÁNDAR', 'PLUS', 'TOTAL', 'VIP'];
        for (const plan of planes) {
            if (contenidoUpper.includes(plan)) {
                return plan.charAt(0).toUpperCase() + plan.slice(1).toLowerCase();
            }
        }
        return 'No especificado';
    }

    // =============================================
    // MÉTODO PRINCIPAL DE PROCESAMIENTO 
    // =============================================

    async processAllFiles() {
        if (!this.files || this.files.length === 0) {
            this.showToast('Atención', 'No hay archivos seleccionados', 'warning');
            return;
        }

        if (!this.isPdfJsLoaded) {
            this.showToast('Error', 'PDF.js no está cargado. Recarga la página.', 'error');
            return;
        }

        const archivosPendientes = this.files.filter(f => f.status === 'pending');
        if (archivosPendientes.length === 0) {
            this.showToast('Atención', 'Todos los archivos ya fueron procesados', 'info');
            return;
        }
        
        this.isLoading = true;
        this.isProcessing = true;
        this.cotizaciones = [];
        
        this.progress = {
            current: 0,
            total: archivosPendientes.length,
            percent: 0,
            currentFileName: ''
        };

        let procesados = 0;
        let errores = 0;
        const cotizacionesProcesadas = [];

        for (let i = 0; i < archivosPendientes.length; i++) {
            const fileItem = archivosPendientes[i];
            this.progress.current = i + 1;
            this.progress.currentFileName = fileItem.name;
            this.progress.percent = Math.round(((i + 1) / archivosPendientes.length) * 100);

            try {
                const cotizacion = await this.extraerDatosCotizacion(fileItem);
                
                if (cotizacion && cotizacion.id) {
                    // Guardar en array local
                    cotizacionesProcesadas.push(cotizacion);
                    this.cotizaciones.push(cotizacion);
                    fileItem.status = 'completed';
                    procesados++;
                    
                } else {
                    fileItem.status = 'error';
                    errores++;
                    console.warn('Cotización sin ID para archivo:', fileItem.name);
                    this.showToast('Advertencia', `No se pudieron extraer datos de ${fileItem.name}`, 'warning');
                }
                
            } catch (error) {
                console.error(':::CotizacionOpLector::: Error procesando archivo:', error);
                fileItem.status = 'error';
                errores++;
                this.showToast('Error', `Error en ${fileItem.name}: ${error.message || 'Error desconocido'}`, 'error');
            }
            
            // Forzar actualización de la UI
            this.files = [...this.files];
        }
        
        this.showResults = this.cotizaciones.length > 0;

        if (this.showResults) {
            const mensaje = procesados > 0 
                ? `Se procesaron ${procesados} cotización(es)${errores > 0 ? ` (${errores} con error)` : ''}`
                : 'No se pudo procesar ningún archivo';
            
            this.showToast(errores > 0 ? 'Advertencia' : 'Éxito', mensaje, errores > 0 ? 'warning' : 'success');
            
            // IMPORTANTE: Emitir eventos DESPUÉS de que todo esté procesado
            // y asegurarse de que los datos estén completos
            
            // Emitir evento para cada cotización (con un pequeño retraso para no bloquear)
            for (const cotizacion of cotizacionesProcesadas) {
                try {
                    const copiaSegura = this.createSafeCopy(cotizacion);
                    // Asegurar que tenga todas las propiedades necesarias
                    const copiaCompleta = this.asegurarPropiedadesUI(copiaSegura);
                    await this.emitDataExtracted(copiaCompleta);
                    // Pequeña pausa para no saturar el event loop
                    await new Promise(resolve => setTimeout(resolve, 10));
                } catch (e) {
                    console.error('Error emitiendo dataextracted:', e);
                }
            }
            
            // Emitir evento de comparación completa
            try {
                const cotizacionesSeguras = cotizacionesProcesadas.map(q => this.createSafeCopy(q));
                await this.emitComparisonComplete(cotizacionesSeguras);
            } catch (e) {
                console.error('Error emitiendo comparisoncomplete:', e);
            }
            
        } else {
            this.showToast('Error', 'No se pudo procesar ningún archivo', 'error');
        }
        
        this.isProcessing = false;
        this.isLoading = false;
    }

    // =============================================
    // MÉTODO PARA ASEGURAR PROPIEDADES DE UI
    // =============================================

    asegurarPropiedadesUI(quote) {
        if (!quote) return quote;
        
        return {
            ...quote,
            // Propiedades de UI que el padre espera
            isExpanded: true,
            expandIcon: 'utility:chevronup',
            expandText: 'Colapsar',
            showClienteInfo: false,
            clienteIcon: 'utility:chevronright',
            showCoberturas: false,
            coberturasIcon: 'utility:chevronright',
            
            // Asegurar que las banderas existan
            isAutomovil: quote.isAutomovil || false,
            isTransporte: quote.isTransporte || false,
            isGastosMedicos: quote.isGastosMedicos || false,
            isMascotas: quote.isMascotas || false,
            isHogar: quote.isHogar || false,
            isRC: quote.isRC || false,
            isViaje: quote.isViaje || false,
            isVida: quote.isVida || false,
            isEmpresarial: quote.isEmpresarial || false,
            isDental: quote.isDental || false,
            isDanos: quote.isDanos || false,
            isVision: quote.isVision || false,
            
            // Asegurar que las fechas estén formateadas
            uploadDateFormatted: quote.fechaExtraccion ? 
                new Date(quote.fechaExtraccion).toLocaleDateString('es-ES', {
                    day: '2-digit',
                    month: 'short',
                    hour: '2-digit',
                    minute: '2-digit'
                }) : new Date().toLocaleDateString('es-ES'),
            
            // Asegurar que haya un key
            key: quote.key || `quote-${quote.id || Date.now()}`
        };
    }

    // =============================================
    // VERSIÓN CORREGIDA DE EMIT DATA EXTRACTED
    // =============================================

    async emitDataExtracted(cotizacion) {
        if (!cotizacion || !cotizacion.id) {
            console.warn('No se puede emitir evento: cotización inválida');
            return;
        }
        
        try {
            // Asegurar que todos los valores sean serializables
            const datosSeguros = {
                id: String(cotizacion.id || ''),
                nombreArchivo: String(cotizacion.nombreArchivo || ''),
                compania: String(cotizacion.compania || ''),
                ramo: String(cotizacion.ramo || ''),
                ramoLabel: String(cotizacion.ramoLabel || ''),
                plan: String(cotizacion.plan || ''),
                primaTotal: Number(cotizacion.primaTotal) || 0,
                primaTotalFormatted: String(cotizacion.primaTotalFormatted || this.formatCurrency(0)),
                extractionConfidence: Number(cotizacion.extractionConfidence) || 0,
                fechaExtraccion: String(cotizacion.fechaExtraccion || new Date().toISOString()),
                
                // UI State
                isExpanded: true,
                expandIcon: 'utility:chevronup',
                expandText: 'Colapsar',
                showClienteInfo: false,
                clienteIcon: 'utility:chevronright',
                showCoberturas: false,
                coberturasIcon: 'utility:chevronright',
                
                // Cliente
                clienteNombre: String(cotizacion.clienteNombre || ''),
                clienteRFC: String(cotizacion.clienteRFC || ''),
                clienteCP: String(cotizacion.clienteCP || ''),
                clienteEmail: String(cotizacion.clienteEmail || ''),
                clienteTelefono: String(cotizacion.clienteTelefono || ''),
                clienteDireccion: String(cotizacion.clienteDireccion || ''),
                
                // Auto
                marca: String(cotizacion.marca || ''),
                modelo: String(cotizacion.modelo || ''),
                placa: String(cotizacion.placa || ''),
                serie: String(cotizacion.serie || ''),
                anio: String(cotizacion.anio || ''),
                descripcion: String(cotizacion.descripcion || ''),
                
                // Viaje
                destino: String(cotizacion.destino || ''),
                numViajeros: Number(cotizacion.numViajeros) || 1,
                
                // Vida
                edadVida: Number(cotizacion.edadVida) || 0,
                sumaFallecimiento: String(cotizacion.sumaFallecimiento || ''),
                aportacionAnual: String(cotizacion.aportacionAnual || ''),
                
                // RC
                tipoRC: String(cotizacion.tipoRC || ''),
                profesion: String(cotizacion.profesion || ''),
                actividad: String(cotizacion.actividad || ''),
                
                // Mascotas
                mascotaNombre: String(cotizacion.mascotaNombre || ''),
                raza: String(cotizacion.raza || ''),
                edadMascota: String(cotizacion.edadMascota || ''),
                
                // GMM
                redHospitalaria: String(cotizacion.redHospitalaria || ''),
                sumaAsegurada: String(cotizacion.sumaAsegurada || ''),
                deducible: String(cotizacion.deducible || ''),
                coaseguro: String(cotizacion.coaseguro || ''),
                
                // Hogar
                sumaEdificio: String(cotizacion.sumaEdificio || ''),
                sumaContenido: String(cotizacion.sumaContenido || ''),
                
                // Transporte
                bienesCubiertos: String(cotizacion.bienesCubiertos || ''),
                medioTransporte: String(cotizacion.medioTransporte || ''),
                limiteEmbarque: String(cotizacion.limiteEmbarque || ''),
                
                // Coberturas
                hasCoberturas: Boolean(cotizacion.hasCoberturas),
                coberturasCount: Number(cotizacion.coberturasCount) || 0,
                tablaCompletaCoberturas: Array.isArray(cotizacion.tablaCompletaCoberturas) ? 
                    cotizacion.tablaCompletaCoberturas.map(c => ({
                        ...c,
                        key: c.key || `cov-${Date.now()}-${Math.random()}`
                    })) : [],
                
                // === BANDERAS DE RAMO ===
                isAutomovil: Boolean(cotizacion.isAutomovil),
                isTransporte: Boolean(cotizacion.isTransporte),
                isGastosMedicos: Boolean(cotizacion.isGastosMedicos),
                isMascotas: Boolean(cotizacion.isMascotas),
                isHogar: Boolean(cotizacion.isHogar),
                isRC: Boolean(cotizacion.isRC),
                isViaje: Boolean(cotizacion.isViaje),
                isVida: Boolean(cotizacion.isVida),
                isEmpresarial: Boolean(cotizacion.isEmpresarial),
                isDental: Boolean(cotizacion.isDental),
                isDanos: Boolean(cotizacion.isDanos),
                isVision: Boolean(cotizacion.isVision),
                
                // Key para iteradores
                key: `quote-${cotizacion.id}`
            };
            
            // Verificar que el objeto sea serializable
            const testSerialization = JSON.stringify(datosSeguros);
            
            const event = new CustomEvent('dataextracted', {
                detail: datosSeguros,
                bubbles: true,
                composed: true
            });
            
            this.dispatchEvent(event);
            console.log(':::CotizacionOpLector::: 📤 Evento dataextracted emitido para:', cotizacion.compania, datosSeguros.ramo);
            
        } catch (error) {
            console.error(':::CotizacionOpLector::: Error creando evento dataextracted:', error);
            
            // Fallback con objeto mínimo
            try {
                const objetoMinimo = {
                    id: String(cotizacion.id || ''),
                    nombreArchivo: String(cotizacion.nombreArchivo || ''),
                    compania: String(cotizacion.compania || ''),
                    ramo: String(cotizacion.ramo || ''),
                    primaTotal: Number(cotizacion.primaTotal) || 0,
                    key: `quote-${cotizacion.id}`
                };
                
                const event = new CustomEvent('dataextracted', {
                    detail: objetoMinimo,
                    bubbles: true,
                    composed: true
                });
                
                this.dispatchEvent(event);
                console.log(':::CotizacionOpLector::: 📤 Evento dataextracted (mínimo) emitido');
            } catch (fallbackError) {
                console.error(':::CotizacionOpLector::: Error incluso con objeto mínimo:', fallbackError);
            }
        }
    }

    async emitComparisonComplete(cotizaciones) {
        if (!cotizaciones || cotizaciones.length === 0) return;
        
        try {
            const cotizacionesSeguras = cotizaciones.map(q => ({
                id: q.id || '',
                nombreArchivo: q.nombreArchivo || '',
                compania: q.compania || '',
                ramo: q.ramo || '',
                primaTotal: Number(q.primaTotal) || 0
            }));
            
            const event = new CustomEvent('comparisoncomplete', {
                detail: {
                    cotizaciones: cotizacionesSeguras,
                    total: cotizaciones.length
                },
                bubbles: true,
                composed: true
            });
            
            this.dispatchEvent(event);
            console.log(':::CotizacionOpLector::: 📤 Evento comparisoncomplete emitido');
        } catch (error) {
            console.error(':::CotizacionOpLector::: Error emitiendo evento comparisoncomplete:', JSON.stringify(error));
        }
    }

    // =============================================
    // UI HELPERS
    // =============================================

    showToast(title, message, variant) {
        try {
            this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
        } catch (error) {
            console.error(':::CotizacionOpLector::: Error mostrando toast:', JSON.stringify(error));
        }
    }

    get hasFiles() {
        return this.files && this.files.length > 0;
    }

    get disabledProcess() {
        return !this.hasFiles || this.isProcessing || !this.isPdfJsLoaded;
    }

    get progressStyle() {
        return `width: ${this.progress.percent || 0}%;`;
    }

    get maxFile() {
        return MAX_FILE_SIZE / 1024 / 1024;
    }

    get disabledResult() {
        return !this.showResults;
    }

    // Método para procesar coberturas y agregar keys únicas
    procesarCoberturas(quote) {
        console.log(':::CotizacionOpLector::: Procesando coberturas para quote:', JSON.stringify(quote));
        
        if (!quote) return quote;
        
        // Crear copia para no modificar el original directamente
        const quoteProcesado = { ...quote };
        
        // ===== 1. INICIALIZAR ARRAY DE COBERTURAS SI NO EXISTE =====
        if (!quoteProcesado.tablaCompletaCoberturas) {
            quoteProcesado.tablaCompletaCoberturas = [];
        }
        
        // ===== 2. SI HAY COBERTURAS VIAJE, INTEGRARLAS =====
        if (quoteProcesado.coberturasViaje && Array.isArray(quoteProcesado.coberturasViaje) && 
            quoteProcesado.coberturasViaje.length > 0) {
            
            // Convertir coberturasViaje al formato de tablaCompletaCoberturas
            const coberturasViajeConvertidas = quoteProcesado.coberturasViaje.map(cov => ({
                cobertura: cov.nombre || 'Cobertura',
                sumaAsegurada: cov.suma || cov.sumaAsegurada || 'Incluida'
            }));
            
            // Agregar al array principal (evitando duplicados)
            for (const covViaje of coberturasViajeConvertidas) {
                const existe = quoteProcesado.tablaCompletaCoberturas.some(
                    c => c.cobertura?.toUpperCase() === covViaje.cobertura?.toUpperCase()
                );
                if (!existe) {
                    quoteProcesado.tablaCompletaCoberturas.push(covViaje);
                }
            }
        }
        
        // ===== 3. SI HAY COBERTURAS EN DATOS ESPECÍFICOS, INTEGRARLAS =====
        // Para GMM
        if (quoteProcesado.asegurados && Array.isArray(quoteProcesado.asegurados)) {
            // Las coberturas de GMM ya están manejadas, pero podemos agregar info del plan
            if (quoteProcesado.plan && !quoteProcesado.tablaCompletaCoberturas.some(c => c.cobertura === 'Plan')) {
                quoteProcesado.tablaCompletaCoberturas.unshift({
                    cobertura: 'Plan',
                    sumaAsegurada: quoteProcesado.plan
                });
            }
        }
        
        // Para Hogar (coberturasAdicionales)
        if (quoteProcesado.coberturasAdicionales && Array.isArray(quoteProcesado.coberturasAdicionales)) {
            for (const covAdicional of quoteProcesado.coberturasAdicionales) {
                if (typeof covAdicional === 'string') {
                    const existe = quoteProcesado.tablaCompletaCoberturas.some(
                        c => c.cobertura?.toUpperCase() === covAdicional?.toUpperCase()
                    );
                    if (!existe) {
                        quoteProcesado.tablaCompletaCoberturas.push({
                            cobertura: covAdicional,
                            sumaAsegurada: 'Incluida'
                        });
                    }
                }
            }
        }
        
        // Para Auto (puede tener coberturas específicas)
        if (quoteProcesado.isAutomovil) {
            // Agregar coberturas típicas de auto si no existen
            const coberturasAuto = [
                { nombre: 'Daños Materiales', campo: 'sumaDanos' },
                { nombre: 'Robo Total', campo: 'sumaRobo' },
                { nombre: 'Responsabilidad Civil', campo: 'sumaRC' },
                { nombre: 'Gastos Médicos Ocupantes', campo: 'sumaGastosMedicos' }
            ];
            
            for (const cov of coberturasAuto) {
                if (!quoteProcesado.tablaCompletaCoberturas.some(c => c.cobertura?.includes(cov.nombre))) {
                    // Si hay un campo específico con monto, usarlo
                    if (quoteProcesado[cov.campo]) {
                        quoteProcesado.tablaCompletaCoberturas.push({
                            cobertura: cov.nombre,
                            sumaAsegurada: quoteProcesado[cov.campo]
                        });
                    }
                }
            }
        }
        
        // ===== 4. ASEGURAR QUE CADA COBERTURA TENGA LOS CAMPOS NECESARIOS =====
        if (Array.isArray(quoteProcesado.tablaCompletaCoberturas)) {
            quoteProcesado.tablaCompletaCoberturas = quoteProcesado.tablaCompletaCoberturas
                .filter(cov => cov && (cov.cobertura || cov.nombre)) // Filtrar nulos
                .map((cobertura, idx) => {
                    // Normalizar estructura
                    const nombre = cobertura.cobertura || cobertura.nombre || 'Cobertura';
                    const suma = cobertura.sumaAsegurada || cobertura.suma || 'Amparada';
                    
                    return {
                        cobertura: nombre,
                        sumaAsegurada: suma,
                        // Generar key única para LWC (importante para iteradores)
                        key: `cov-${quoteProcesado.id || 'temp'}-${idx}-${nombre.replace(/\s+/g, '-')}`
                    };
                });
            
            // Actualizar contadores
            quoteProcesado.hasCoberturas = quoteProcesado.tablaCompletaCoberturas.length > 0;
            quoteProcesado.coberturasCount = quoteProcesado.tablaCompletaCoberturas.length;
            
            console.log(`:::CotizacionOpLector::: ✅ ${quoteProcesado.coberturasCount} coberturas procesadas`);
            if (quoteProcesado.coberturasCount > 0) {
                console.log(':::CotizacionOpLector::: 📋 Primeras 3:', quoteProcesado.tablaCompletaCoberturas.slice(0, 3));
            }
        } else {
            quoteProcesado.hasCoberturas = false;
            quoteProcesado.coberturasCount = 0;
            console.log(':::CotizacionOpLector::: ⚠️ No hay coberturas para procesar');
        }
        
        // ===== 5. PROCESAR OTROS ARRAYS (MANTENER FUNCIONALIDAD ORIGINAL) =====
        
        // Procesar coberturasViaje (ya convertidas, pero mantener keys)
        if (quoteProcesado.coberturasViaje && Array.isArray(quoteProcesado.coberturasViaje)) {
            quoteProcesado.coberturasViaje = quoteProcesado.coberturasViaje.map((cov, idx) => ({
                ...cov,
                key: `cov-viaje-${quoteProcesado.id}-${idx}-${(cov.nombre || 'cov').replace(/\s+/g, '-')}`
            }));
        }
        
        // Procesar riesgosAmparados (Transporte)
        if (quoteProcesado.riesgosAmparados && Array.isArray(quoteProcesado.riesgosAmparados)) {
            quoteProcesado.riesgosAmparados = quoteProcesado.riesgosAmparados.map((riesgo, idx) => ({
                ...riesgo,
                key: `riesgo-${quoteProcesado.id}-${idx}-${(riesgo.nombre || 'riesgo').replace(/\s+/g, '-')}`
            }));
        }
        
        // Procesar asegurados (GMM)
        if (quoteProcesado.asegurados && Array.isArray(quoteProcesado.asegurados)) {
            quoteProcesado.asegurados = quoteProcesado.asegurados.map((asegurado, idx) => ({
                ...asegurado,
                key: `asegurado-${quoteProcesado.id}-${idx}-${(asegurado.nombre || 'asegurado').replace(/\s+/g, '-')}`
            }));
        }
        console.log(':::CotizacionOpLector::: Coberturas procesadas con keys únicas');
        console.log(':::CotizacionOpLector::: Coberturas finales:', JSON.stringify(quoteProcesado));
        return quoteProcesado;
    }
}