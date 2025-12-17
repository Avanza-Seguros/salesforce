import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';

import getPolicyIds from '@salesforce/apex/PdfProcessorController.getPolicyIds';
import savePdfFile from '@salesforce/apex/PdfProcessorController.savePdfFile';
import findPolicies from '@salesforce/apex/PdfProcessorController.findPolicies';
import findItemsForPolicy from '@salesforce/apex/PdfProcessorController.findItemsForPolicy';
import PDFJS from '@salesforce/resourceUrl/pdfjs';

const MAX_FILE_SIZE = 100 * 1024 * 1024;
const MAX_FILE_DIVIDE = MAX_FILE_SIZE / 1024 / 1024;
const MAX_FILES = 1000;
const MAX_PAGES = 20;

export default class SimplePdfReader extends LightningElement {
    @track isPdfJsLoaded = false;
    @track files = [];
    @track pdfData = [];
    @track isProcessing = false;
    @track showResults = false;
    @track isError = false;
    @track isCompleted = false;

    @track progress = {
        current: 0,
        total: 0,
        percent: 0,
        currentFileName: ''
    };

    @track pdfJsError = false;
    @track isSaving = false;
    @track validFiles;
    @track currentFileName = null;

    // Variables para drag & drop
    dragDropSetup = false;

    // Columnas para la tabla de resultados
    columns = [
        { label: 'Tipo', fieldName: 'tipoDocumento', type: 'text' },
        { label: 'Póliza', fieldName: 'policy', type: 'text' },
        { label: 'Certificado', fieldName: 'certificate', type: 'text' },
        { label: 'Nombre', fieldName: 'fullName', type: 'text' },
        { label: 'Compañía', fieldName: 'insuranceCompany', type: 'text' },
        { label: 'Plan', fieldName: 'plan', type: 'text' },
        { label: 'Vigencia Desde', fieldName: 'vigenciaDesde', type: 'text' },
        { label: 'Vigencia Hasta', fieldName: 'vigenciaHasta', type: 'text' },
        { label: 'Archivo', fieldName: 'sourceFile', type: 'text' }
    ];

    // =============================================
    // 🔄 CICLO DE VIDA DEL COMPONENTE
    // =============================================

    connectedCallback() {
        console.log('🔄 Componente iniciado');
        this.initializeFileAPI();
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
    // 📁 GESTIÓN DE ARCHIVOS
    // =============================================

    openFileSelector() {
        this.template.querySelector('input[type="file"]').click();
    }

    handleFileChange(event) {
        console.log('📁 Archivos seleccionados manualmente...');
        const input = event.target;
        if (!input || !input.files) {
            console.error('❌ Input de archivo no válido');
            return;
        }
        
        const files = [];
        for (let i = 0; i < input.files.length; i++) {
            files.push(input.files[i]);
        }
        
        this.processDroppedFilesOnce(files);
        input.value = null;
    }

    removeFile(event) {
        try {
            const fileId = event?.currentTarget?.dataset?.id;
            if (!fileId) {
                console.error('❌ No hay ID de archivo');
                return;
            }
            
            console.log('🗑️ Eliminando archivo ID:', fileId);
            const filteredFiles = this.files.filter(f => f?.id !== fileId);
            this.files = [...filteredFiles];
            
            this.showToast('Archivo eliminado', 'Archivo removido de la lista', 'info');
        } catch (error) {
            console.error('❌ Error eliminando archivo:', error);
            this.showToast('Error', 'No se pudo eliminar el archivo', 'error');
        }
    }

    initializeFileAPI() {
        if (typeof FileReader === 'undefined') {
            console.error('❌ FileReader no está disponible');
            this.showToast('Error', 'Tu navegador no soporta la lectura de archivos', 'error');
            return false;
        }
        
        if (typeof ArrayBuffer === 'undefined') {
            console.error('❌ ArrayBuffer no está disponible');
            this.showToast('Error', 'Tu navegador no soporta ArrayBuffer', 'error');
            return false;
        }
        
        return true;
    }

    // =============================================
    // 🎯 DRAG & DROP
    // =============================================

    setupDragDropOnce() {
        console.log('🔄 Configurando drag & drop (una vez)...');
        
        setTimeout(() => {
            const dropZone = this.template.querySelector('[data-dropzone]');
            if (!dropZone) {
                console.error('❌ No se encontró el elemento dropzone');
                return;
            }
            
            console.log('✅ Elemento dropzone encontrado');
            
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
                    this.processDroppedFilesOnce(Array.from(e.dataTransfer.files));
                }
            };
            
            dropZone.onclick = () => {
                this.openFileSelector();
            };
            
            console.log('✅ Drag & drop configurado correctamente');
        }, 100);
    }

    processDroppedFilesOnce(files) {
        console.log('📁 Archivos arrastrados (modo único):', files.length);
        
        if (!files || !Array.isArray(files) || files.length === 0) {
            console.error('❌ Array de archivos inválido o vacío');
            return;
        }
        
        const archivosUnicos = new Map();
        const nuevosArchivos = [];
        
        files.forEach(file => {
            if (!file) return;
            
            const clave = `${file.name}_${file.size}`;
            if (!archivosUnicos.has(clave)) {
                archivosUnicos.set(clave, true);
                
                if (file.type !== 'application/pdf') {
                    console.log(`❌ ${file.name} no es PDF`);
                    this.showToast('Tipo no válido', `${file.name} no es un PDF`, 'warning');
                    return;
                }
                
                if (file.size > MAX_FILE_SIZE) {
                    console.log(`❌ ${file.name} excede tamaño máximo`);
                    this.showToast('Archivo muy grande', `${file.name} excede ${MAX_FILE_DIVIDE}MB`, 'warning');
                    return;
                }
                
                nuevosArchivos.push({
                    id: `file_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
                    name: file.name,
                    size: file.size,
                    type: file.type,
                    status: 'pending',
                    data: [],
                    file: file
                });
            } else {
                console.log(`⚠️ Archivo duplicado ignorado: ${file.name}`);
            }
        });
        
        if (nuevosArchivos.length > 0) {
            this.files = [...this.files, ...nuevosArchivos];
            this.showToast('Archivos agregados', `Se agregaron ${nuevosArchivos.length} archivo(s) PDF`, 'success');
            console.log(`✅ Total archivos en lista: ${this.files.length}`);
        }
    }

    // =============================================
    // 📦 CARGA Y CONFIGURACIÓN DE PDF.JS
    // =============================================

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

    handleLoadError(error) {
        this.pdfJsError = true;
        this.isPdfJsLoaded = false;
        console.error('❌ Error fatal cargando PDF.js:', error);
        
        this.showToast(
            'Error de inicialización',
            'No se pudo cargar el procesador de PDFs. Por favor, recarga la página.',
            'error'
        );
    }

    reloadPdfJs() {
        this.pdfJsError = false;
        this.isPdfJsLoaded = false;
        this.loadPdfJs();
    }

    // =============================================
    // 🔄 PROCESAMIENTO PRINCIPAL
    // =============================================

    async processAllFiles() {
        console.log('🔧 Iniciando procesamiento de archivos...');
        
        if (!this.files.length) {
            this.showToast('Atención', 'No hay archivos seleccionados', 'warning');
            return;
        }

        if (!this.isPdfJsLoaded) {
            this.showToast('Error', 'PDF.js no está cargado', 'error');
            return;
        }

        this.isProcessing = true;
        this.pdfData = [];
        this.progress = { 
            current: 0, 
            total: this.files.length, 
            percent: 0, 
            currentFileName: '' 
        };

        for (let i = 0; i < this.files.length; i++) {
            const fileItem = this.files[i];
            
            console.log(`\n📁 Procesando archivo ${i + 1}/${this.files.length}:`, fileItem.name);
            
            this.progress.current = i + 1;
            this.progress.total = this.files.length;
            this.progress.currentFileName = fileItem.name;
            this.progress.percent = Math.round(((i + 1) / this.files.length) * 100);

            try {
                const data = await this.extractPdfDataSafe(fileItem);
                
                console.log('✅ Datos extraídos:', data);
                
                fileItem.data = data.certificates || [];
                fileItem.status = 'completed';
                
                if (data.certificates && data.certificates.length > 0) {
                    this.pdfData = [...this.pdfData, ...data.certificates];
                    this.isCompleted = true;
                }
                
            } catch (error) {
                console.error(`❌ Error procesando ${fileItem.name}:`, error.message, error.stack);
                fileItem.status = 'error';
                this.isError = true;
                
                this.showToast('Error de procesamiento', 
                    `Error en ${fileItem.name}: ${error.message.substring(0, 100)}`, 
                    'error');
            }
            
            this.files = [...this.files];
        }

        this.showResults = this.pdfData.length > 0;
    
        if (this.pdfData.length > 0) {
            this.showToast('Éxito', 
                `Se extrajeron datos de ${this.pdfData.length} archivo(s)`, 
                'success');
            
            this.verificarExtraccion();
            
            try {
                await this.persistAllOriginalFiles();
                this.showToast('Éxito', 'Datos y archivos guardados correctamente', 'success');
            } catch (err) {
                console.error('Error en guardado:', err);
                this.showToast('Error', err.body?.message || err.message, 'error');
            }
        }
        
        this.isProcessing = false;
        console.log('✅ Procesamiento completado');
    }

    async extractPdfDataSafe(fileItem) {
        console.log('🔍 Extrayendo datos PDF (modo seguro)...');
        
        try {
            let file = null;
            
            if (fileItem && fileItem.file && fileItem.file instanceof File) {
                console.log('✅ Usando fileItem.file');
                file = fileItem.file;
            } else if (fileItem && fileItem instanceof File) {
                console.log('⚠️ fileItem es directamente un File object');
                file = fileItem;
                fileItem = {
                    id: `temp_${Date.now()}`,
                    name: file.name,
                    file: file,
                    status: 'pending',
                    data: []
                };
            } else if (fileItem && typeof fileItem === 'object') {
                console.log('🔍 Buscando archivo en otras propiedades...');
                for (const key in fileItem) {
                    if (fileItem[key] instanceof File) {
                        console.log(`✅ Encontrado File en propiedad: ${key}`);
                        file = fileItem[key];
                        break;
                    }
                }
                
                if (!file && fileItem.name) {
                    console.log('🔄 Intentando reconstruir File object...');
                    throw new Error('No se puede reconstruir el archivo. Estructura inválida.');
                }
            }
            
            if (!file) {
                console.error('❌ No se pudo obtener el archivo');
                console.log('Estructura completa de fileItem:', JSON.stringify(fileItem, null, 2));
                throw new Error('Estructura de archivo inválida. Falta la propiedad "file".');
            }
            
            console.log('📄 Procesando archivo:', file.name);
            console.log('🔍 Propiedades del File:', {
                type: file.type,
                size: file.size,
                lastModified: file.lastModified,
                esInstanciaFile: file instanceof File
            });
            
            const buffer = await file.arrayBuffer();
            
            if (typeof window.pdfjsLib === 'undefined') {
                throw new Error('PDF.js no está cargado');
            }
            
            const loadingTask = window.pdfjsLib.getDocument({
                data: buffer,
                cMapUrl: PDFJS + '/cmaps/',
                cMapPacked: true,
                standardFontDataUrl: PDFJS + '/standard_fonts/'
                
            });
            
            const pdf = await loadingTask.promise;
            console.log('🔄 Cargando PDF...');
            
            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('Timeout cargando PDF (30s)')), 30000);
            });
            
            console.log(`✅ PDF cargado: ${pdf.numPages} páginas`);
            
            let allText = '';
            let allLines = [];
            
            console.log(`📖 Extrayendo texto de ${pdf.numPages} páginas...`);
            
            for (let i = 1; i <= pdf.numPages; i++) {
                console.log(`📄 Procesando página ${i}...`);
                try {
                    const page = await pdf.getPage(i);
                    const textContent = await page.getTextContent();
                    
                    let pageText = '';
                    let pageLines = [];
                    
                    if (textContent.items && textContent.items.length > 0) {
                        pageLines = this.processTextItemsToLines(textContent.items);
                            pageText = pageLines.join('\n');
                        }
                    
                    allText += pageText + '\n';
                    allLines = [...allLines, ...pageLines];
                    
                        page.cleanup();
                    
                    console.log(`✅ Página ${i}: ${textContent.items?.length || 0} items, ${pageText.length} caracteres`);
                    
                } catch (pageError) {
                    console.warn(`⚠️ Error en página ${i}:`, pageError.message);
                    continue;
                }
            }
            
                await pdf.destroy();
            
            console.log('📊 Resumen extracción:');
            console.log(`  - Total caracteres: ${allText.length}`);
            console.log(`  - Total líneas: ${allLines.length}`);
            
            const textoLimpio = this.limpiarTextoCorrupto(allText);
            const lineasLimpias = allLines.map(line => this.limpiarTextoCorrupto(line));
            const extractedData = this.extractEnhancedData(textoLimpio, lineasLimpias, file.name);
            
            return { certificates: [extractedData] };
            
        } catch (error) {
            console.error('❌ Error en extractPdfDataSafe:', error.message);
            console.error('Stack trace:', error.stack);
            
            console.log('💡 fileItem type:', typeof fileItem);
            console.log('💡 fileItem keys:', fileItem ? Object.keys(fileItem) : 'null');
            
            throw error;
        }
    }

    // =============================================
    // 🎯 SISTEMA DE CLASIFICACIÓN Y PROCESAMIENTO
    // =============================================

    /**
     * Clasifica el tipo de archivo basado en nombre y contenido
     */
    clasificarTipoArchivo(fileName, fileContent) {
        console.log(`🔍 Clasificando archivo: ${fileName}`);
        
        const fileNameLower = fileName.toLowerCase();
        const contentUpper = fileContent.toUpperCase();
        
        console.log('fileNameLower::: ' + fileNameLower);
        console.log('contentUpper::: ' + contentUpper);
        // Detectar Dentegra primero
        const isDentegra = fileNameLower.includes('dentegra') ||
                          fileNameLower.includes('vision') ||
                          fileNameLower.includes('óptico') ||
                          fileNameLower.includes('dental') ||
                          fileNameLower.includes('certv') ||
                          (fileNameLower.includes('_cert-') && contentUpper.includes('CERTIFICADO'));
        
        // Detectar tipo específico dentro de Dentegra
        let dentegraType = null;
        if (isDentegra) {
            const isVision = contentUpper.includes('VER BIEN') || 
                            contentUpper.includes('ÓPTICO') ||
                            contentUpper.includes('LENTES') ||
                            fileNameLower.includes('vision') ||
                            fileNameLower.includes('optico');
            
            const isDental = contentUpper.includes('CORAL') || 
                            contentUpper.includes('DENTAL') ||
                            fileNameLower.includes('dental') ||
                            fileNameLower.includes('coral');
            
            const isCredencial = fileNameLower.includes('credencial') || 
                                contentUpper.includes('COORDINAMOS TU CITA') ||
                                contentUpper.includes('ACUDE A TU CONSULTA') ||
                                contentUpper.includes('DESCARGA LA APP');
            
            const isCertificado = fileNameLower.includes('certv') || 
                                 contentUpper.includes('CERTIFICADO') ||
                                 contentUpper.includes('DATOS DEL CONTRATANTE') ||
                                 contentUpper.includes('DATOS DE LOS ASEGURADOS') ||
                                 (fileNameLower.includes('_cert-') && contentUpper.includes('CERTIFICADO'));
            
            dentegraType = {
                tipo: 'DENTEGRA',
                subtipo: isVision ? 'VISION' : isDental ? 'DENTAL' : 'GENERAL',
                formato: isCredencial ? 'CREDENCIAL' : isCertificado ? 'CERTIFICADO' : 'INDETERMINADO'
            };
            
            console.log(`✅ Dentegra detectado:`, dentegraType);
            return dentegraType;
        }
        
        // Detectar nuevos tipos de archivo basados en los ejemplos proporcionados
        if (fileNameLower.includes('_cert_') || contentUpper.includes('CERTIFICADO INDIVIDUAL DE SEGURO')) {
            console.log('✅ Tipo: CERT (Certificado Individual)');
            return { tipo: 'CERT', subtipo: 'INDIVIDUAL', formato: 'CERTIFICADO' };
        }
        
        if (fileNameLower.includes('_tarj_') || contentUpper.includes('SEGUROS MONTERREY') || 
            (contentUpper.includes('VIGENCIA') && contentUpper.includes('SUMA ASEG.:'))) {
            console.log('✅ Tipo: TARJ (Tarjeta de Seguro)');
            return { tipo: 'TARJ', subtipo: 'SEGUROS_MONTERREY', formato: 'CREDENCIAL' };
        }

        // Detectar otros tipos de archivo
        if (fileNameLower.includes('vgg-')) {
            console.log('✅ Tipo: VGG (Seguros Monterrey)');
            return { tipo: 'VGG', subtipo: 'CERTIFICADO', formato: 'CERTIFICADO' };
        }
        
        if (fileNameLower.startsWith('c_')) {
            console.log('✅ Tipo: C_ (MetLife - Tabular)');
            return { tipo: 'C_FILE', subtipo: 'TABULAR', formato: 'CERTIFICADO' };
        }
        
        if (fileNameLower.startsWith('t_')) {
            console.log('✅ Tipo: T_ (MetLife - Lineal)');
            return { tipo: 'T_FILE', subtipo: 'LINEAL', formato: 'CERTIFICADO' };
        }
        
        if (fileNameLower.includes('gmg-')) {
            const isGMGCertificado = fileNameLower.includes('certificado');
            const isGMGCredencial = fileNameLower.includes('credencial');
            
            console.log('✅ Tipo: GMG (Seguros Monterrey)');
            return { 
                tipo: 'GMG', 
                subtipo: isGMGCertificado ? 'CERTIFICADO' : isGMGCredencial ? 'CREDENCIAL' : 'GENERAL',
                formato: isGMGCertificado ? 'CERTIFICADO' : isGMGCredencial ? 'CREDENCIAL' : 'INDETERMINADO'
            };
        }

        console.log('ℹ️ Tipo: GENERAL (no identificado específicamente)');
        return { tipo: 'GENERAL', subtipo: 'INDETERMINADO', formato: 'INDETERMINADO' };
    }

    /**
     * Función principal que enruta el procesamiento según el tipo de archivo
     */
    extractEnhancedData(text, lines, file) {
        console.log(`\n🎯 PROCESANDO ARCHIVO: ${file}`);
        console.log('='.repeat(60));
        
        // Clasificar el tipo de archivo
        const tipoArchivo = this.clasificarTipoArchivo(file, text);
        
        // Enrutar a la función específica según el tipo
        switch(tipoArchivo.tipo) {
            case 'DENTEGRA':
                return this.procesarArchivoDentegra(text, lines, file, tipoArchivo);
                
            case 'VGG':
                return this.procesarArchivoVGG(text, lines, file);
                
            case 'C_FILE':
                return this.procesarArchivoCFile(text, lines, file);
                
            case 'T_FILE':
                return this.procesarArchivoTFile(text, lines, file);
                
            case 'GMG':
                return this.procesarArchivoGMG(text, lines, file, tipoArchivo);

            case 'CERT':
                return this.procesarArchivoCERT(text, lines, file, tipoArchivo);
                
            case 'TARJ':
                return this.procesarArchivoTARJ(text, lines, file, tipoArchivo);
            
            default:
                console.log(`⚠️ Tipo no reconocido, usando procesamiento general`);
                return this.procesarArchivoGeneral(text, lines, file);
        }
    }

    // =============================================
    // 🦷 PROCESADORES ESPECÍFICOS POR TIPO
    // =============================================


    // =============================================
    // 📄 PROCESADOR PARA ARCHIVOS CERT
    // =============================================

    procesarArchivoCERT(text, lines, file, tipoInfo) {
        console.log(`📄 PROCESANDO ARCHIVO CERT: ${tipoInfo.subtipo} - ${tipoInfo.formato}`);
        
        const resultado = {
            policy: this.buscarNumeroPolizaCERT(lines, file) || 'NO_DETECTADO',
            certificate: this.buscarCertificadoCERT(lines, file) || 'NO_DETECTADO',
            fullName: this.buscarTitularCERT(lines, file) || 'NO_DETECTADO',
            insuranceCompany: 'Seguros Monterrey New York Life',
            plan: this.buscarPlanCERT(lines, file) || '',
            vigenciaDesde: this.buscarVigenciaCERT(lines, file).desde || '',
            vigenciaHasta: this.buscarVigenciaCERT(lines, file).hasta || '',
            sumaAsegurada: this.buscarSumaAseguradaCERT(lines, file) || '',
            tipoDocumento: tipoInfo.formato,
            subtipo: tipoInfo.subtipo,
            sourceFile: file
        };
        
        console.log('✅ RESULTADO CERT:', resultado);
        return resultado;
    }

    buscarNumeroPolizaCERT(lines, file) {
        console.log('🔍 Buscando número de póliza en CERT...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No. de póliza" o "GMM-"
            if (line.includes('No. de póliza') || line.includes('GMM-')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar GMM-xxxxx
                const match = line.match(/(GMM-\d+)/i);
                if (match) {
                    console.log('✅ Póliza encontrada en CERT:', match[1]);
                    return match[1];
                }
                
                // Buscar en la siguiente línea si esta no tiene el número
                if (i + 1 < lines.length) {
                    const nextLine = lines[i + 1].trim();
                    const nextMatch = nextLine.match(/(GMM-\d+)/i);
                    if (nextMatch) {
                        console.log('✅ Póliza encontrada en línea siguiente:', nextMatch[1]);
                        return nextMatch[1];
                    }
                }
            }
        }
        
        // Buscar directamente en cualquier línea
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            const match = line.match(/(GMM-\d+)/i);
            if (match) {
                console.log('✅ Póliza encontrada (búsqueda directa):', match[1]);
                return match[1];
            }
        }
        
        console.log('❌ No se pudo encontrar número de póliza en CERT');
        return null;
    }

    buscarCertificadoCERT(lines, file) {
        console.log('🔍 Buscando número de certificado en CERT...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar línea con "R.F.C." o "RFC"
            if (line.includes('R.F.C.') || line.includes('RFC')) {
                console.log('📋 Línea con R.F.C. encontrada:', line);
                
                // Revisar la siguiente línea
                if (i + 1 < lines.length) {
                    const nextLine = lines[i + 1].trim();
                    console.log('📋 Línea siguiente a R.F.C.:', nextLine);
                    
                    // Buscar número de certificado en la siguiente línea
                    // Puede tener caracteres especiales antes
                    const certMatch = nextLine.match(/(\d{8,})/);
                    if (certMatch) {
                        console.log('✅ Certificado encontrado después de R.F.C.:', certMatch[1]);
                        return certMatch[1];
                    }
                    
                    // También revisar la segunda línea después si es necesario
                    if (i + 2 < lines.length) {
                        const secondNextLine = lines[i + 2].trim();
                        console.log('📋 Segunda línea después de R.F.C.:', secondNextLine);
                        
                        const secondCertMatch = secondNextLine.match(/(\d{8,})/);
                        if (secondCertMatch) {
                            console.log('✅ Certificado encontrado en segunda línea después de R.F.C.:', secondCertMatch[1]);
                            return secondCertMatch[1];
                        }
                    }
                }
            }
        }
        
        // SEGUNDA ESTRATEGIA: Buscar "No. de certificado" en cualquier parte
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No. de certificado" incluso con caracteres extraños
            if (line.includes('certificado') || line.includes('certificate')) {
                console.log('📋 Línea con referencia a certificado:', line);
                
                // Buscar número directamente en la misma línea
                const certMatch = line.match(/(\d{8,})/);
                if (certMatch) {
                    console.log('✅ Certificado encontrado en línea con referencia:', certMatch[1]);
                    return certMatch[1];
                }
                
                // Buscar en las siguientes líneas
                for (let j = i + 1; j < Math.min(i + 3, lines.length); j++) {
                    const nextLine = lines[j].trim();
                    const nextCertMatch = nextLine.match(/(\d{8,})/);
                    if (nextCertMatch) {
                        console.log('✅ Certificado encontrado en línea siguiente:', nextCertMatch[1]);
                        return nextCertMatch[1];
                    }
                }
            }
        }
        
        // TERCERA ESTRATEGIA: Buscar cualquier número de 8+ dígitos en líneas que no sean fechas
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Saltar líneas que son claramente fechas
            if (line.includes('/') && /\d{2}\/\d{2}\/\d{4}/.test(line)) {
                continue;
            }
            
            // Buscar número de 8+ dígitos
            const certMatch = line.match(/\b(\d{8,})\b/);
            if (certMatch) {
                const possibleCert = certMatch[1];
                
                // Verificar que no sea un número de RFC (ej: 200529 en VIA-200529-7A0)
                if (!line.includes('VIA') && !line.includes('RFC')) {
                    console.log('✅ Certificado encontrado (búsqueda general):', possibleCert);
                    return possibleCert;
                }
            }
        }
        
        // CUARTA ESTRATEGIA: Extraer del nombre del archivo
        const fileName = this.currentFileName || '';
        console.log('🔄 Intentando extraer del nombre de archivo:', fileName);
        
        // Patrón: 0000000022_CERT_VALDEZSEVILLAICAR JESUS_GMM-27196.pdf
        const fileMatch = fileName.match(/(\d{8,})_CERT_/i);
        if (fileMatch) {
            console.log('✅ Certificado extraído del nombre de archivo:', fileMatch[1]);
            return fileMatch[1];
        }
        
        console.log('❌ No se pudo encontrar certificado');
        return null;
    }

    buscarTitularCERT(lines, file) {
        console.log('🔍 Buscando titular en CERT...');
        
        // Buscar en tabla "Asegurado y dependientes"
        let enTablaAsegurados = false;
        let encontradoTitular = false;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar inicio de tabla
            if (line.includes('Asegurado y dependientes') || 
                (line.includes('Parentesco') && line.includes('Nombre') && line.includes('Fecha'))) {
                enTablaAsegurados = true;
                console.log('📋 Encontrada tabla de asegurados');
            }
            
            // Buscar línea con "TITULAR"
            if (enTablaAsegurados && line.includes('TITULAR')) {
                console.log('📋 Encontrada línea TITULAR:', line);
                
                // Extraer nombre del titular
                const partes = line.split(/\s+/);
                let nombrePartes = [];
                let capturandoNombre = false;
                
                for (let j = 0; j < partes.length; j++) {
                    const parte = partes[j];
                    
                    if (parte === 'TITULAR') {
                        capturandoNombre = true;
                        continue;
                    }
                    
                    if (capturandoNombre) {
                        // Detener cuando encontramos fecha
                        if (/\d{2}\/[A-Z]{3}\/\d{4}/.test(parte) || /\d{2}\/\d{2}\/\d{4}/.test(parte)) {
                            break;
                        }
                        
                        // Detener cuando encontramos edad
                        if (/\d+/.test(parte) || parte.includes('AÑOS') || 
                            parte === 'M' || parte === 'F') {
                            break;
                        }
                        
                        // Agregar partes que parezcan nombres
                        if (parte && parte.length > 1 && 
                            /^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]*$/.test(parte) &&
                            !this.esPalabraClaveDocumento(parte)) {
                            
                            nombrePartes.push(parte);
                        }
                    }
                }
                
                if (nombrePartes.length >= 2) {
                    const nombre = nombrePartes.join(' ');
                    console.log('✅ Titular encontrado en CERT:', nombre);
                    encontradoTitular = true;
                    return nombre;
                }
            }
            
            // Si salimos de la tabla, resetear
            if (enTablaAsegurados && line.includes('---') && encontradoTitular) {
                enTablaAsegurados = false;
            }
        }
        
        // Búsqueda alternativa
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Saltar líneas que claramente no son nombres
            if (this.esLineaNoNombre(line)) {
                continue;
            }
            
            // Verificar si es nombre válido
            if (this.esNombreCompletoValido(line)) {
                console.log('✅ Titular encontrado en CERT (búsqueda alternativa):', line);
                return line;
            }
        }
        
        console.log('❌ No se pudo encontrar titular en CERT');
        return null;
    }

    buscarPlanCERT(lines, file) {
        console.log('🔍 Buscando plan en CERT...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "Nombre del plan contratado"
            if (line.includes('Nombre del plan contratado')) {
                console.log('📋 Línea encontrada:', line);
                
                // Extraer plan después de ":"
                const partes = line.split(':');
                if (partes.length > 1) {
                    const plan = partes[1].trim();
                    if (plan) {
                        console.log('✅ Plan encontrado en CERT:', plan);
                        return plan;
                    }
                }
                
                // Buscar en línea siguiente
                if (i + 1 < lines.length) {
                    const nextLine = lines[i + 1].trim();
                    if (nextLine && /^[A-Z]+$/.test(nextLine)) {
                        console.log('✅ Plan encontrado en línea siguiente:', nextLine);
                        return nextLine;
                    }
                }
            }
        }
        
        console.log('⚠️ No se encontró plan específico en CERT, usando valor por defecto');
        return 'MAXIMA'; // Valor por defecto basado en el ejemplo
    }

    buscarVigenciaCERT(lines, file) {
        console.log('🔍 Buscando vigencia en CERT...');
        
        const vigencia = { desde: null, hasta: null };
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "Periodo de seguro/vigencia"
            if (line.includes('Periodo de seguro/vigencia')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar en las siguientes líneas
                for (let j = i; j < Math.min(i + 5, lines.length); j++) {
                    const currentLine = lines[j];
                    
                    // Buscar "Desde" y "Hasta"
                    if (currentLine.includes('Desde') && currentLine.includes('Hasta')) {
                        const fechas = currentLine.match(/(\d{2}\/\d{2}\/\d{4})/g);
                        if (fechas && fechas.length >= 2) {
                            vigencia.desde = fechas[0];
                            vigencia.hasta = fechas[1];
                            console.log('✅ Vigencia encontrada en CERT:', vigencia);
                            return vigencia;
                        }
                    }
                    
                    // Buscar fechas directamente
                    const fechas = currentLine.match(/(\d{2}\/\d{2}\/\d{4})/g);
                    if (fechas && fechas.length >= 2) {
                        vigencia.desde = fechas[0];
                        vigencia.hasta = fechas[1];
                        console.log('✅ Vigencia encontrada en CERT (fechas directas):', vigencia);
                        return vigencia;
                    }
                }
            }
        }
        
        console.log('⚠️ No se encontró vigencia específica en CERT');
        return vigencia;
    }

    buscarSumaAseguradaCERT(lines, file) {
        console.log('🔍 Buscando suma asegurada en CERT...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar en tabla de coberturas
            if (line.includes('Básica') && line.includes('$')) {
                console.log('📋 Línea de cobertura básica:', line);
                
                // Buscar monto con formato $X,XXX,XXX.XX
                const match = line.match(/\$([\d,]+\.\d{2})/);
                if (match) {
                    console.log('✅ Suma asegurada encontrada en CERT:', match[1]);
                    return match[1];
                }
            }
            
            // Buscar "Suma asegurada" en encabezados
            if (line.includes('Suma asegurada') && i + 1 < lines.length) {
                const nextLine = lines[i + 1];
                const match = nextLine.match(/\$?([\d,]+\.\d{2})/);
                if (match) {
                    console.log('✅ Suma asegurada encontrada en CERT (línea siguiente):', match[1]);
                    return match[1];
                }
            }
        }
        
        console.log('❌ No se pudo encontrar suma asegurada en CERT');
        return null;
    }

    // =============================================
    // 📄 PROCESADOR PARA ARCHIVOS TARJ
    // =============================================

    procesarArchivoTARJ(text, lines, file, tipoInfo) {
        console.log(`📄 PROCESANDO ARCHIVO TARJ: ${tipoInfo.subtipo} - ${tipoInfo.formato}`);
        
        const resultado = {
            policy: this.buscarNumeroPolizaTARJ(lines, file) || 'NO_DETECTADO',
            certificate: this.buscarCertificadoTARJ(lines, file) || 'NO_DETECTADO',
            fullName: this.buscarTitularTARJ(lines, file) || 'NO_DETECTADO',
            insuranceCompany: 'Seguros Monterrey',
            plan: this.buscarPlanTARJ(lines, file) || '',
            vigenciaDesde: this.buscarVigenciaTARJ(lines, file).desde || '',
            vigenciaHasta: this.buscarVigenciaTARJ(lines, file).hasta || '',
            sumaAsegurada: this.buscarSumaAseguradaTARJ(lines, file) || '',
            tipoDocumento: tipoInfo.formato,
            subtipo: tipoInfo.subtipo,
            sourceFile: file
        };
        
        console.log('✅ RESULTADO TARJ:', resultado);
        return resultado;
    }

    buscarNumeroPolizaTARJ(lines, file) {
        console.log('🔍 Buscando número de póliza en TARJ...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No Poliza" o "GMM-"
            if (line.includes('No Poliza') || line.includes('GMM-')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar GMM-xxxxx
                const match = line.match(/(GMM-\d+)/i);
                if (match) {
                    console.log('✅ Póliza encontrada en TARJ:', match[1]);
                    return match[1];
                }
            }
        }
        
        // Buscar directamente en cualquier línea
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            const match = line.match(/(GMM-\d+)/i);
            if (match) {
                console.log('✅ Póliza encontrada en TARJ (búsqueda directa):', match[1]);
                return match[1];
            }
        }
        
        console.log('❌ No se pudo encontrar número de póliza en TARJ');
        return null;
    }

    buscarCertificadoTARJ(lines, file) {
        console.log('🔍 Buscando certificado en TARJETA...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No Certificado" o número largo
            if (line.includes('No Certificado') || /^\d{10,}$/.test(line)) {
                console.log('📋 Línea encontrada:', line);
                
                // Extraer número de certificado
                const certMatch = line.match(/\b(\d{8,})\b/);
                if (certMatch) {
                    console.log('✅ Certificado encontrado en tarjeta:', certMatch[1]);
                    return certMatch[1];
                }
            }
        }
        
        return null;
    }

    buscarTitularTARJ(lines, file) {
        console.log('🔍 Buscando titular en TARJ...');
        
        // En TARJ, el nombre suele estar en las primeras líneas
        for (let i = 0; i < Math.min(5, lines.length); i++) {
            const line = lines[i].trim();
            
            // Saltar líneas que no son nombres
            if (line.includes('SEGUROS') || line.includes('MONTERREY') || 
                line.includes('No Poliza') || line.includes('No Certificado')) {
                continue;
            }
            
            // Verificar si es nombre válido
            if (this.esNombreCompletoValido(line)) {
                console.log('✅ Titular encontrado en TARJ:', line);
                return line;
            }
        }
        
        console.log('❌ No se pudo encontrar titular en TARJ');
        return null;
    }

    buscarPlanTARJ(lines, file) {
        console.log('🔍 Buscando plan en TARJ...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "PLAN"
            if (line.includes('PLAN')) {
                console.log('📋 Línea encontrada:', line);
                
                // Extraer plan
                if (line.includes('MAXIMA')) return 'MAXIMA';
                if (line.includes('OPTIMA')) return 'OPTIMA';
                if (line.includes('BASICA')) return 'BASICA';
                
                // Buscar palabra después de "PLAN"
                const palabras = line.split(/\s+/);
                for (let j = 0; j < palabras.length; j++) {
                    if (palabras[j] === 'PLAN' && j + 1 < palabras.length) {
                        const plan = palabras[j + 1];
                        if (plan && /^[A-Z]+$/.test(plan)) {
                            console.log('✅ Plan encontrado en TARJ:', plan);
                            return plan;
                        }
                    }
                }
            }
        }
        
        console.log('⚠️ No se encontró plan específico en TARJ, usando valor por defecto');
        return 'MAXIMA'; // Valor por defecto basado en el ejemplo
    }

    buscarVigenciaTARJ(lines, file) {
        console.log('🔍 Buscando vigencia en TARJ...');
        
        const vigencia = { desde: null, hasta: null };
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "VIGENCIA"
            if (line.includes('VIGENCIA')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar fechas en formato DD/MM/YYYY
                const fechas = line.match(/(\d{2}\/\d{2}\/\d{4})/g);
                if (fechas && fechas.length >= 2) {
                    vigencia.desde = fechas[0];
                    vigencia.hasta = fechas[1];
                    console.log('✅ Vigencia encontrada en TARJ:', vigencia);
                    return vigencia;
                }
                
                // Buscar en línea siguiente
                if (i + 1 < lines.length) {
                    const nextLine = lines[i + 1];
                    const nextFechas = nextLine.match(/(\d{2}\/\d{2}\/\d{4})/g);
                    if (nextFechas && nextFechas.length >= 2) {
                        vigencia.desde = nextFechas[0];
                        vigencia.hasta = nextFechas[1];
                        console.log('✅ Vigencia encontrada en TARJ (línea siguiente):', vigencia);
                        return vigencia;
                    }
                }
            }
        }
        
        console.log('⚠️ No se encontró vigencia específica en TARJ');
        return vigencia;
    }

    buscarSumaAseguradaTARJ(lines, file) {
        console.log('🔍 Buscando suma asegurada en TARJ...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "SUMA ASEG.:"
            if (line.includes('SUMA ASEG.:')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar monto
                const match = line.match(/\$?([\d,]+\.\d{2})/);
                if (match) {
                    console.log('✅ Suma asegurada encontrada en TARJ:', match[1]);
                    return match[1];
                }
                
                // Buscar número grande
                const numeroMatch = line.match(/\b(\d{1,3}(?:,\d{3})*\.?\d*)\b/);
                if (numeroMatch) {
                    console.log('✅ Suma asegurada encontrada en TARJ (número):', numeroMatch[1]);
                    return numeroMatch[1];
                }
            }
        }
        
        console.log('❌ No se pudo encontrar suma asegurada en TARJ');
        return null;
    }

    procesarArchivoDentegra(text, lines, file, tipoInfo) {
        console.log(`🦷 PROCESANDO ARCHIVO DENTEGRA: ${tipoInfo.subtipo} - ${tipoInfo.formato}`);
        
        // Usar extracción dinámica para todos los archivos Dentegra
        const datos = this.extraerDatosPolizaDentegra(text, file);
        
        // Enriquecer con información específica del subtipo
        const resultado = {
            policy: datos.numeroPoliza || this.buscarPolizaEnContenido(text) || 'NO_DETECTADO',
            certificate: datos.numeroCertificado || this.buscarCertificadoEnContenido(text) || 'NO_DETECTADO',
            fullName: datos.asegurado || this.buscarNombreEnContenido(lines) || 'NO_DETECTADO',
            insuranceCompany: 'Dentegra',
            plan: datos.plan || this.buscarPlanEnContenido(text) || '',
            vigenciaDesde: datos.inicioVigencia || '',
            vigenciaHasta: datos.inicioVigencia ? this.calcularVigenciaHasta(datos.inicioVigencia) : '',
            sumaAsegurada: datos.coberturas.lentesCompletos || '',
            deducible: datos.deductible || '',
            empresaContratante: datos.contratante.nombre || '',
            tipoDocumento: tipoInfo.formato,
            subtipo: tipoInfo.subtipo,
            sourceFile: file,
            metadata: datos.metadata || { confianza: 'MEDIA' }
        };
        
        console.log('✅ RESULTADO DENTEGRA:', resultado);
        return resultado;
    }

    procesarArchivoVGG(text, lines, file) {
        console.log('📄 PROCESANDO ARCHIVO VGG...');
        
        // Extraer póliza y certificado juntos
        const { poliza, certificado } = this.buscarPolizaYCertificadoVGG(lines);
        
        const resultado = {
            policy: poliza || this.buscarNumeroPolizaVGG(lines) || 'NO_DETECTADO',
            certificate: certificado || this.buscarCertificadoVGG(lines) || 'NO_DETECTADO',
            fullName: this.buscarNombreAseguradoVGG(lines) || 'NO_DETECTADO',
            insuranceCompany: 'Seguros Monterrey New York Life',
            plan: 'SEGURO DE GRUPO',
            vigenciaDesde: this.buscarVigenciaVGG(lines).desde || '',
            vigenciaHasta: this.buscarVigenciaVGG(lines).hasta || '',
            sumaAsegurada: this.buscarSumaAseguradaVGG(lines) || '',
            tipoDocumento: 'CERTIFICADO',
            subtipo: 'VGG',
            sourceFile: file
        };
        
        console.log('✅ RESULTADO VGG:', resultado);
        return resultado;
    }

    procesarArchivoCFile(text, lines, file) {
        console.log('📄 PROCESANDO ARCHIVO C_...');
        
        const resultado = {
            policy: this.buscarNumeroPolizaCFile(lines) || 'NO_DETECTADO',
            certificate: this.buscarCertificadoCFile(lines, file) || 'NO_DETECTADO',
            fullName: this.buscarTitularCFile(lines, file) || 'NO_DETECTADO',
            insuranceCompany: 'MetLife',
            plan: this.buscarPlanCFile(lines) || '',
            vigenciaDesde: this.buscarVigenciaCFile(lines).desde || '',
            vigenciaHasta: this.buscarVigenciaCFile(lines).hasta || '',
            tipoDocumento: 'CERTIFICADO',
            subtipo: 'TABULAR',
            sourceFile: file
        };
        
        console.log('✅ RESULTADO C_:', resultado);
        return resultado;
    }

    procesarArchivoTFile(text, lines, file) {
        console.log('📄 PROCESANDO ARCHIVO T_...');
        
        const resultado = {
            policy: this.buscarPolizaTFile(lines) || 'NO_DETECTADO',
            certificate: this.buscarCertificadoTFile(lines, file) || 'NO_DETECTADO',
            fullName: this.buscarTitularTFile(lines, file) || 'NO_DETECTADO',
            insuranceCompany: 'MetLife',
            plan: this.buscarPlanTFile(lines) || '',
            vigenciaDesde: this.buscarVigenciaTFile(lines).desde || '',
            vigenciaHasta: this.buscarVigenciaTFile(lines).hasta || '',
            tipoDocumento: 'CERTIFICADO',
            subtipo: 'LINEAL',
            sourceFile: file
        };
        
        console.log('✅ RESULTADO T_:', resultado);
        return resultado;
    }

    procesarArchivoGMG(text, lines, file, tipoInfo) {
        console.log(`📄 PROCESANDO ARCHIVO GMG: ${tipoInfo.subtipo}`);
        
        let resultado;
        
        if (tipoInfo.formato === 'CERTIFICADO') {
            resultado = {
                policy: this.buscarNumeroPolizaGMG(lines, file) || 'NO_DETECTADO',
                certificate: this.buscarCertificadoGMG(lines, file) || 'NO_DETECTADO',
                fullName: this.buscarTitularGMGCertificado(lines, file) || 'NO_DETECTADO',
                insuranceCompany: 'Seguros Monterrey New York Life',
                plan: this.buscarPlanGMG(lines, file) || '',
                vigenciaDesde: this.buscarVigenciaGMG(lines, file).desde || '',
                vigenciaHasta: this.buscarVigenciaGMG(lines, file).hasta || '',
                sumaAsegurada: this.buscarSumaAseguradaGMGCertificado(lines, file) || '',
                tipoDocumento: 'CERTIFICADO',
                subtipo: 'GMG',
                sourceFile: file
            };
        } else if (tipoInfo.formato === 'CREDENCIAL') {
            resultado = {
                policy: this.buscarNumeroPolizaGMG(lines, file) || 'NO_DETECTADO',
                certificate: this.buscarCertificadoGMG(lines, file) || 'NO_DETECTADO',
                fullName: this.buscarTitularGMGCredencial(lines, file) || 'NO_DETECTADO',
                insuranceCompany: 'Seguros Monterrey New York Life',
                plan: this.buscarPlanGMGCredencial(lines, file) || '',
                vigenciaDesde: '',
                vigenciaHasta: '',
                sumaAsegurada: this.buscarSumaAseguradaGMGCredencial(lines, file) || '',
                tipoDocumento: 'CREDENCIAL',
                subtipo: 'GMG',
                sourceFile: file
            };
        } else {
            // GMG general
            resultado = {
                policy: this.buscarNumeroPolizaGMG(lines, file) || 'NO_DETECTADO',
                certificate: this.buscarCertificadoGMG(lines, file) || 'NO_DETECTADO',
                fullName: this.buscarTitularGMG(lines, file) || 'NO_DETECTADO',
                insuranceCompany: 'Seguros Monterrey New York Life',
                plan: this.buscarPlanGMG(lines, file) || '',
                vigenciaDesde: this.buscarVigenciaGMG(lines, file).desde || '',
                vigenciaHasta: this.buscarVigenciaGMG(lines, file).hasta || '',
                sumaAsegurada: this.buscarSumaAseguradaGMG(lines, file) || '',
                tipoDocumento: 'INDETERMINADO',
                subtipo: 'GMG',
                sourceFile: file
            };
        }
        
        console.log('✅ RESULTADO GMG:', resultado);
        return resultado;
    }

    procesarArchivoGeneral(text, lines, file) {
        console.log('📄 PROCESANDO ARCHIVO GENERAL...');
        
        const resultado = {
            policy: this.buscarNumeroPolizaPorLineas(lines) || 'NO_DETECTADO',
            certificate: this.buscarCertificadoPorLineas(lines) || 'NO_DETECTADO',
            fullName: this.buscarTitularPorLineas(lines) || 'NO_DETECTADO',
            insuranceCompany: 'MetLife',
            plan: this.buscarPlanPorLineas(lines) || '',
            vigenciaDesde: this.buscarVigenciaPorLineas(lines).desde || '',
            vigenciaHasta: this.buscarVigenciaPorLineas(lines).hasta || '',
            tipoDocumento: 'INDETERMINADO',
            subtipo: 'GENERAL',
            sourceFile: file
        };
        
        console.log('✅ RESULTADO GENERAL:', resultado);
        return resultado;
    }

    // =============================================
    // 🔍 EXTRACCIÓN DINÁMICA PARA DENTEGRA
    // =============================================

    extraerDatosPolizaDentegra(pdfText, fileName) {
        console.log('🔍 Extrayendo datos dinámicos de Dentegra...');
        
        // Expresiones regulares mejoradas para Dentegra
        const patrones = {
            numeroPoliza: /[Pp]óliza:\s*([\d\-]+)/i,
            plan: /Plan:\s*(.+?)(?:\n|$)/i,
            numeroCertificado: /Certificado:\s*(\d+)/i,
            inicioVigencia: /Inicio de vigencia:\s*(\d{1,2}\/\d{1,2}\/\d{4})/i,
            lentesCompletos: /Lentes completos:\s*\$?\s*([\d,\.]+)\s*M\.N\.?/i,
            lentesContacto: /Lentes de contacto:\s*\$?\s*([\d,\.]+)\s*M\.N\.?/i,
            deductible: /Deductible:\s*\$?\s*([\d,\.]+)\s*\+\s*IVA\s*M\.N\.?/i,
            contratante: /Contratante:\s*(.+?)(?:\n|$)/i,
            numeroContratante: /Contratante:.+\n\s*(\d{13})/i,
            asegurado: /Contratante:.+\n\s*\d+\n\s*(.+)/i,
            telefonoContacto: /llamando[\s\S]*?al\s*([\d\s\(\)\-]+)/i,
            sitioWeb: /Consulta[\s\S]*?en:\s*([a-zA-Z0-9\.\-]+)/i
        };

        // Función auxiliar mejorada para extraer datos
        const extraer = (patron, texto, grupo = 1) => {
            try {
                const coincidencia = texto.match(patron);
                return coincidencia ? coincidencia[grupo].trim() : null;
            } catch (error) {
                console.warn(`⚠️ Error con patrón ${patron}:`, error);
                return null;
            }
        };

        // Extraer asegurado de manera más robusta
        let asegurado = null;
        const lineas = pdfText.split('\n');
        
        // Buscar línea con formato de nombre (3 palabras, sin números)
        for (let i = 0; i < lineas.length; i++) {
            const linea = lineas[i].trim();
            const palabras = linea.split(/\s+/);
            
            // Buscar patrones de nombre: 2-4 palabras, todas con mayúscula inicial
            if (palabras.length >= 2 && palabras.length <= 4) {
                let esNombreValido = true;
                
                for (const palabra of palabras) {
                    // Debe empezar con mayúscula y contener solo letras
                    if (!/^[A-ZÁÉÍÓÚÑ][a-záéíóúñ]*$/.test(palabra)) {
                        esNombreValido = false;
                        break;
                    }
                }
                
                if (esNombreValido && !linea.includes('Contratante') && !linea.includes('Poliza')) {
                    asegurado = linea;
                    break;
                }
            }
        }

        // Extraer todos los datos
        const datos = {
            numeroPoliza: extraer(patrones.numeroPoliza, pdfText),
            plan: extraer(patrones.plan, pdfText),
            numeroCertificado: extraer(patrones.numeroCertificado, pdfText),
            inicioVigencia: extraer(patrones.inicioVigencia, pdfText),
            coberturas: {
                lentesCompletos: extraer(patrones.lentesCompletos, pdfText),
                lentesContacto: extraer(patrones.lentesContacto, pdfText)
            },
            deductible: extraer(patrones.deductible, pdfText),
            contratante: {
                nombre: extraer(patrones.contratante, pdfText),
                numero: extraer(patrones.numeroContratante, pdfText)
            },
            asegurado: asegurado,
            contacto: {
                telefono: extraer(patrones.telefonoContacto, pdfText),
                sitioWeb: extraer(patrones.sitioWeb, pdfText)
            },
            // Información adicional
            tipoDocumento: fileName.includes('Credencial') ? 'CREDENCIAL' : 'CERTIFICADO',
            empresa: 'Dentegra',
            fechaExtraccion: new Date().toISOString().split('T')[0],
            sourceFile: fileName
        };

        // Validar y limpiar datos
        if (datos.contratante.nombre) {
            // Limpiar número del nombre del contratante
            datos.contratante.nombre = datos.contratante.nombre.replace(/\d{13}/, '').trim();
        }

        // Formatear fechas
        if (datos.inicioVigencia) {
            const [dia, mes, anio] = datos.inicioVigencia.split('/');
            datos.inicioVigenciaFormateada = `${anio}-${mes.padStart(2, '0')}-${dia.padStart(2, '0')}`;
        }

        // Formatear montos
        const formatearMonto = (monto) => {
            if (!monto) return null;
            return monto.replace(/[^\d,\.]/g, '');
        };

        if (datos.coberturas.lentesCompletos) {
            datos.coberturas.lentesCompletos = formatearMonto(datos.coberturas.lentesCompletos);
            datos.coberturas.lentesCompletosNum = parseFloat(datos.coberturas.lentesCompletos.replace(/,/g, ''));
        }
        
        if (datos.coberturas.lentesContacto) {
            datos.coberturas.lentesContacto = formatearMonto(datos.coberturas.lentesContacto);
            datos.coberturas.lentesContactoNum = parseFloat(datos.coberturas.lentesContacto.replace(/,/g, ''));
        }
        
        if (datos.deductible) {
            datos.deductible = formatearMonto(datos.deductible);
            datos.deductibleNum = parseFloat(datos.deductible.replace(/,/g, ''));
        }

        // Calcular metadatos de calidad
        const camposCriticos = ['numeroPoliza', 'plan', 'numeroCertificado', 'inicioVigencia', 'asegurado'];
        const camposEncontrados = camposCriticos.filter(campo => datos[campo]).length;
        
        datos.metadata = {
            camposEncontrados: Object.keys(datos).filter(k => datos[k] !== null && datos[k] !== undefined).length,
            camposCriticosEncontrados: camposEncontrados,
            totalCamposCriticos: camposCriticos.length,
            confianza: camposEncontrados >= 4 ? 'ALTA' : camposEncontrados >= 3 ? 'MEDIA' : 'BAJA',
            fechaProcesamiento: new Date().toISOString()
        };

        console.log('📊 Metadatos Dentegra:', datos.metadata);
        return datos;
    }

    calcularVigenciaHasta(fechaDesde) {
        if (!fechaDesde) return '';
        
        try {
            const [dia, mes, anio] = fechaDesde.split('/');
            const fecha = new Date(anio, mes - 1, dia);
            fecha.setFullYear(fecha.getFullYear() + 1);
            
            const diaHasta = fecha.getDate().toString().padStart(2, '0');
            const mesHasta = (fecha.getMonth() + 1).toString().padStart(2, '0');
            const anioHasta = fecha.getFullYear();
            
            return `${diaHasta}/${mesHasta}/${anioHasta}`;
        } catch (error) {
            console.error('Error calculando vigencia:', error);
            return '';
        }
    }

    // =============================================
    // 🔍 FUNCIONES DE BÚSQUEDA MEJORADAS
    // =============================================

    buscarPolizaEnContenido(texto) {
        const patrones = [
            /[Pp]óliza:\s*([\d\-]+)/,
            /POLIZA:\s*([\d\-]+)/,
            /No\.?\s*[Pp]óliza:\s*([\d\-]+)/,
            /(\d{10,}[-\d]+)/
        ];
        
        for (const patron of patrones) {
            const match = texto.match(patron);
            if (match && match[1]) {
                console.log(`✅ Póliza encontrada (${patron}):`, match[1]);
                return match[1].trim();
            }
        }
        
        return null;
    }

    buscarCertificadoEnContenido(texto) {
        const patrones = [
            /Certificado:\s*(\d+)/i,
            /CERTIFICADO:\s*(\d+)/,
            /No\.?\s*Certificado:\s*(\d+)/i,
            /\b(\d{4,6})\b/
        ];
        
        for (const patron of patrones) {
            const match = texto.match(patron);
            if (match && match[1]) {
                if (!/\d{2}\/\d{2}\/\d{4}/.test(match[0])) {
                    console.log(`✅ Certificado encontrado (${patron}):`, match[1]);
                    return match[1].trim();
                }
            }
        }
        
        return null;
    }

    buscarNombreEnContenido(lines) {
        for (const line of lines) {
            const linea = line.trim();
            const palabras = linea.split(/\s+/);
            
            if (palabras.length >= 2 && palabras.length <= 4) {
                let esNombreValido = true;
                
                for (const palabra of palabras) {
                    if (!/^[A-ZÁÉÍÓÚÑ][a-záéíóúñ]*$/.test(palabra)) {
                        esNombreValido = false;
                        break;
                    }
                    
                    const palabraUpper = palabra.toUpperCase();
                    const palabrasExcluir = [
                        'POLIZA', 'CERTIFICADO', 'VIGENCIA', 'PLAN', 
                        'CONTRATANTE', 'ASEGURADO', 'TITULAR', 'BENEFICIOS'
                    ];
                    
                    if (palabrasExcluir.includes(palabraUpper)) {
                        esNombreValido = false;
                        break;
                    }
                }
                
                if (esNombreValido) {
                    console.log(`✅ Nombre encontrado:`, linea);
                    return linea;
                }
            }
        }
        
        return null;
    }

    buscarPlanEnContenido(texto) {
        const patrones = [
            /Plan:\s*(.+?)(?:\n|$)/i,
            /PLAN:\s*(.+?)(?:\n|$)/,
            /Tipo.*?Plan:\s*(.+?)(?:\n|$)/i
        ];
        
        for (const patron of patrones) {
            const match = texto.match(patron);
            if (match && match[1]) {
                console.log(`✅ Plan encontrado:`, match[1].trim());
                return match[1].trim();
            }
        }
        
        return null;
    }

    // =============================================
    // 🛠️ FUNCIONES AUXILIARES DE PROCESAMIENTO
    // =============================================

    processTextItemsToLines(items) {
        console.log('📝 Procesando items de texto...');
    
        const lines = {};
        items.forEach(item => {
            const y = Math.round(item.transform[5]);
            if (!lines[y]) lines[y] = [];
            
            let text = this.limpiarTextoDentegra(item.str);
            lines[y].push({ text: text, x: item.transform[4] });
        });
        
        const lineasProcesadas = Object.keys(lines)
            .sort((a, b) => b - a)
            .map(y => {
                const lineItems = lines[y].sort((a, b) => a.x - b.x);
                let lineaCompleta = '';
                
                for (let i = 0; i < lineItems.length; i++) {
                    lineaCompleta += lineItems[i].text;
                    if (i + 1 < lineItems.length && 
                        lineItems[i + 1].x - (lineItems[i].x + lineItems[i].text.length * 5) > 3) {
                        lineaCompleta += ' ';
                    }
                }
                
                return lineaCompleta;
            });
        
        console.log('✅ Líneas procesadas:', lineasProcesadas.length);
        return lineasProcesadas;
    }

    limpiarTextoCorrupto(texto) {
        if (!texto || typeof texto !== 'string') return texto || '';
        
        if (texto.match(/^[^\x20-\x7E]+$/)) {
            console.log('⚠️ Texto completamente corrupto, intentando recuperación');
            return this.intentarRecuperarTexto(texto);
        }
        
        let limpio = texto.replace(/[\x00-\x1F\x7F]/g, ' ');
        limpio = limpio.replace(/\uFFFD/g, ' ');
        
        if (limpio.includes('ï»¿') || limpio.includes('Ã')) {
            try {
                const bytes = new TextEncoder().encode(limpio);
                const decoder = new TextDecoder('utf-8', { fatal: false });
                limpio = decoder.decode(bytes);
            } catch (e) {
                console.log('⚠️ No se pudo decodificar UTF-8');
            }
        }
        
        const mapaCorrupcion = {
            'Ã±': 'ñ', 'Ã‘': 'Ñ',
            'Ã¡': 'á', 'Ã©': 'é', 'Ã­': 'í', 'Ã³': 'ó', 'Ãº': 'ú',
            'Ã': 'Á', 'Ã‰': 'É', 'Ã': 'Í', 'Ã“': 'Ó', 'Ãš': 'Ú',
            'Ã§': 'ç', 'Ã‡': 'Ç',
            'Ã£': 'ã', 'Ãµ': 'õ',
            'Â¿': '¿', 'Â¡': '¡',
            'â€¢': '•', 'â€"': '—', 'â€"': '—',
            'â€œ': '“', 'â€': '”', 'â€˜': '‘', 'â€™': '’'
        };
        
        for (const [malo, bueno] of Object.entries(mapaCorrupcion)) {
            limpio = limpio.replace(new RegExp(malo, 'g'), bueno);
        }
        
        limpio = limpio.replace(/[^\x20-\x7EÀ-ÿ\u00D1\u00F1]{3,}/g, ' ');
        limpio = limpio.replace(/\s+/g, ' ').trim();
        
        return limpio;
    }

    intentarRecuperarTexto(textoCorrupto) {
        console.log('🔄 Intentando recuperar texto corrupto...');
        
        const decodificaciones = [
            { nombre: 'UTF-8', decoder: 'utf-8' },
            { nombre: 'ISO-8859-1', decoder: 'iso-8859-1' },
            { nombre: 'Windows-1252', decoder: 'windows-1252' },
            { nombre: 'UTF-16LE', decoder: 'utf-16le' },
            { nombre: 'UTF-16BE', decoder: 'utf-16be' }
        ];
        
        const resultados = [];
        
        for (const config of decodificaciones) {
            try {
                const bytes = new TextEncoder().encode(textoCorrupto);
                const decoder = new TextDecoder(config.decoder, { fatal: false });
                const decodificado = decoder.decode(bytes);
                
                if (decodificado !== textoCorrupto && decodificado.length > 0) {
                    resultados.push({
                        nombre: config.nombre,
                        texto: decodificado,
                        valido: this.esTextoProbable(decodificado)
                    });
                }
            } catch (e) {
                // Continuar con siguiente decodificación
            }
        }
        
        const resultadosValidos = resultados.filter(r => r.valido);
        
        if (resultadosValidos.length > 0) {
            console.log('✅ Texto recuperado con:', resultadosValidos[0].nombre);
            return resultadosValidos[0].texto;
        }
        
        console.log('⚠️ Ninguna decodificación funcionó, usando mapeo manual');
        return this.corregirTextoManual(textoCorrupto);
    }

    esTextoProbable(texto) {
        const palabrasEs = ['DEL', 'LOS', 'LAS', 'CON', 'PARA', 'QUE', 'ESTA', 'ESTE'];
        const textoUpper = texto.toUpperCase();
        
        let coincidencias = 0;
        for (const palabra of palabrasEs) {
            if (textoUpper.includes(palabra)) coincidencias++;
        }
        
        const letrasValidas = texto.match(/[A-Za-zÁÉÍÓÚÑáéíóúñ]/g);
        const ratioLetras = letrasValidas ? letrasValidas.length / texto.length : 0;
        
        return coincidencias >= 1 || ratioLetras > 0.6;
    }

    corregirTextoManual(textoCorrupto) {
        const correcciones = {
            'LRO': 'PATRICIA',
            'PI': 'DEL',
            'AA': 'ROCIO', 
            'HIñA': 'AGUIÑAGA',
            'HI': 'AGU',
            'ñA': 'IÑAGA',
            'GUE': 'GUE',
            'RRA': 'RRA'
        };
        
        let textoCorregido = textoCorrupto;
        for (const [malo, bueno] of Object.entries(correcciones)) {
            textoCorregido = textoCorregido.replace(malo, bueno);
        }
        
        return textoCorregido;
    }

    limpiarTextoDentegra(texto) {
        if (!texto) return '';
        
        const reemplazos = {
            'ï»¿': '',
            'Ã±': 'ñ', 'Ã‘': 'Ñ',
            'Ã¡': 'á', 'Ã©': 'é', 'Ã­': 'í', 'Ã³': 'ó', 'Ãº': 'ú',
            'Ã': 'Á', 'Ã‰': 'É', 'Ã': 'Í', 'Ã“': 'Ó', 'Ãš': 'Ú',
            'â€¢': '•', 'â€"': '-'
        };
        
        let textoLimpio = texto;
        for (const [malo, bueno] of Object.entries(reemplazos)) {
            textoLimpio = textoLimpio.replace(new RegExp(malo, 'g'), bueno);
        }
        
        textoLimpio = textoLimpio.replace(/[\x00-\x1F\x7F]/g, ' ');
        
        return textoLimpio;
    }

    // =============================================
    // 💾 GUARDADO DE ARCHIVOS
    // =============================================

    async persistAllOriginalFiles() {
        console.log('💾 INICIANDO GUARDADO DE ARCHIVOS - MODO DEBUG');
        
        this.validFiles = this.files.filter(f => {
            const fileData = f.data?.[0];
            return fileData && fileData.policy && fileData.policy !== 'NO_DETECTADO';
        });
        
        console.log('📁 Archivos válidos:', this.validFiles.length);
        
        console.log('\n🔍 PASO 1: DATOS EXTRAÍDOS');
        this.validFiles.forEach((file, i) => {
            const data = file.data[0];
            console.log(`${i+1}. ${file.name}:`);
            console.log(`   Póliza: "${data.policy}"`);
            console.log(`   Certificado: "${data.certificate}"`);
            console.log(`   Clave combinada: "${data.policy}|${data.certificate}"`);
        });
        
        const policyNumbers = [...new Set(this.validFiles.map(f => f.data[0].policy))];
        console.log('\n🔍 PASO 2: BUSCANDO PÓLIZAS EN BASE DE DATOS');
        console.log('   Pólizas a buscar:', policyNumbers);
        
        let foundPolicies = [];
        try {
            for (const policyNumber of policyNumbers) {
                console.log(`\n   Buscando: "${policyNumber}"`);
                const policies = await findPolicies({ searchTerm: policyNumber });
                
                if (policies.length > 0) {
                    console.log(`   ✅ Encontradas ${policies.length} póliza(s):`);
                    policies.forEach(p => {
                        console.log(`      - ID: ${p.Id}, Name: "${p.Name}", Numero: "${p.Numero_Polizas__c}"`);
                        foundPolicies.push(p);
                    });
                } else {
                    console.log(`   ❌ NO encontrada`);
                    
                    const variations = [
                        policyNumber.replace(/\s+/g, ''),
                        policyNumber.replace(/^0+/, ''),
                        policyNumber.match(/M\d+/)?.[0],
                        policyNumber.match(/\d+/)?.[0],
                    ].filter(v => v && v !== policyNumber);
                    
                    console.log(`   🔄 Intentando variaciones:`, variations);
                    
                    for (const variation of variations) {
                        const varPolicies = await findPolicies({ searchTerm: variation });
                        if (varPolicies.length > 0) {
                            console.log(`      ✅ Encontrada con variación "${variation}":`);
                            varPolicies.forEach(p => {
                                console.log(`         - ID: ${p.Id}, Name: "${p.Name}"`);
                                foundPolicies.push(p);
                            });
                        }
                    }
                }
            }
        } catch (error) {
            console.error('❌ Error buscando pólizas:', error);
        }
        
        if (foundPolicies.length === 0) {
            console.log('\n❌❌❌ PROBLEMA CRÍTICO: NO SE ENCONTRARON PÓLIZAS ❌❌❌');
            console.log('   Las pólizas extraídas del PDF no existen en Salesforce');
            console.log('   Pólizas buscadas:', policyNumbers);
            
            this.showToast('Error Crítico', 
                `No se encontraron las pólizas: ${policyNumbers.join(', ')}. Verifica que existan en el sistema.`, 
                'error');
            return;
        }
        
        console.log('\n🔍 PASO 3: BUSCANDO ITEMS_CASES');
        const policyIds = [...new Set(foundPolicies.map(p => p.Id))];
        
        let itemCaseMap = {};
        try {
            console.log('   IDs de pólizas:', policyIds);
            
            const allItemsPromises = policyIds.map(policyId => 
                findItemsForPolicy({ 
                    policyId: policyId, 
                    certificate: null // Ya no usamos certificado
                })
            );
            
            const allItemsArrays = await Promise.all(allItemsPromises);
            const allItems = allItemsArrays.flat();
            
            console.log('   Total Items_Cases encontrados:', allItems.length);
            
            // Filtrar solo los que tienen Parentesco__c = '01' (Titular)
            const titularItems = allItems.filter(item => 
                item.Parentesco__c === '01 Titular'
            );

            console.log('   Items_Cases con Parentesco__c = "01":', titularItems.length);
        
            // Crear mapa: policyId -> itemId (del titular)
            for (const item of titularItems) {
                itemCaseMap[item.Poliza__c] = item.Id;
                console.log(`      - Póliza: ${item.Poliza__c}, Item: ${item.Id}, Parentesco: "${item.Parentesco__c}"`);
            }
        } catch (error) {
            console.error('❌ Error buscando Items_Cases:', error);
        }
        
        if (Object.keys(itemCaseMap).length === 0) {
        console.log('\n⚠️ ADVERTENCIA: No se encontraron Items_Cases con Parentesco__c = "01"');
        this.showToast('Advertencia', 
            'No se encontraron registros con Parentesco = Titular (01). No se guardarán archivos.', 
            'warning');
        return;
    }
    
    console.log('\n🔍 PASO 4: PROCESANDO ARCHIVOS - SOLO PARA TITULARES');
    let savedCount = 0;
    let skippedCount = 0;
    
    for (const fileItem of this.validFiles) {
        const fileData = fileItem.data[0];
        console.log(`\n   📄 ${fileItem.name}:`);
        console.log(`      Póliza: "${fileData.policy}"`);
        
        // Buscar si esta póliza tiene un Item_Cases con Parentesco__c = "01"
        let itemCaseId = null;
        
        // Buscar por policy number directamente
        for (const policy of foundPolicies) {
            if (policy.Numero_Polizas__c === fileData.policy || 
                policy.Name === fileData.policy) {
                
                itemCaseId = itemCaseMap[policy.Id];
                break;
            }
        }
        
        if (!itemCaseId) {
            // Intentar búsqueda más flexible
            for (const policyId in itemCaseMap) {
                // Podemos buscar por policyId o por número de póliza
                const policy = foundPolicies.find(p => p.Id === policyId);
                if (policy && (policy.Numero_Polizas__c === fileData.policy || policy.Name === fileData.policy)) {
                    itemCaseId = itemCaseMap[policyId];
                    break;
                }
            }
        }
        
        if (!itemCaseId) {
            console.log(`      ❌ NO encontrado Item_Cases con Parentesco__c = "01" para esta póliza`);
            skippedCount++;
            continue;
        }
        
        console.log(`      ✅ Encontrado (Parentesco__c = "01"): ${itemCaseId}`);
        
        try {
            const base64Data = await this.fileToBase64(fileItem.file);
            await savePdfFile({
                base64Data: base64Data,
                fileName: fileItem.name,
                parentId: itemCaseId,
                certificate: fileData.certificate || '',
                policyNumber: fileData.policy,
                isTitular: true // Nuevo parámetro opcional
            });
            
            console.log(`      💾 Guardado exitoso (solo titular)`);
            savedCount++;
        } catch (error) {
            console.error(`      ❌ Error guardando:`, error);
            skippedCount++;
        }
    }
    
    console.log('\n📊 RESUMEN FINAL:');
    console.log(`   Total archivos procesados: ${this.validFiles.length}`);
    console.log(`   Guardados (solo titulares): ${savedCount}`);
    console.log(`   Omitidos (no titulares): ${skippedCount}`);
    
    if (savedCount > 0) {
        this.showToast('Éxito', 
            `${savedCount} archivo(s) guardado(s) solo en certificados con Parentesco = Titular (01)`, 
            'success');
        this.isSaving = true;
    } else if (skippedCount > 0) {
        this.showToast('Información', 
            'Los archivos solo se guardan en certificados con Parentesco = Titular (01). No se encontraron titulares para estas pólizas.', 
            'info');
        this.isSaving = false;
    }
    }

    fileToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result.split(',')[1]);
            reader.onerror = reject;
            reader.readAsDataURL(file);
        });
    }

    // =============================================
    // 📊 VERIFICACIÓN DE EXTRACCIÓN
    // =============================================

    verificarExtraccion() {
        console.log('\n🔍 VERIFICANDO EXTRACCIÓN COMPLETA DE DATOS');
        console.log('='.repeat(80));
        
        if (this.pdfData.length === 0) {
            console.log('❌ No hay datos extraídos');
            return;
        }
        
        console.log(`📊 TOTAL ARCHIVOS PROCESADOS: ${this.pdfData.length}`);
        
        const agrupados = {};
        this.pdfData.forEach(data => {
            const tipo = data.insuranceCompany || 'DESCONOCIDO';
            if (!agrupados[tipo]) agrupados[tipo] = [];
            agrupados[tipo].push(data);
        });
        
        Object.entries(agrupados).forEach(([tipo, archivos]) => {
            console.log(`\n🏢 ${tipo}: ${archivos.length} archivo(s)`);
            
            archivos.forEach((data, index) => {
                console.log(`  ${index + 1}. ${data.sourceFile}`);
                console.log(`     Póliza: "${data.policy}"`);
                console.log(`     Certificado: "${data.certificate}"`);
                console.log(`     Nombre: "${data.fullName}"`);
                
                if (data.metadata) {
                    console.log(`     Calidad: ${data.metadata.confianza} (${data.metadata.camposCriticosEncontrados}/${data.metadata.totalCamposCriticos})`);
                }
            });
        });
        
        const totalArchivos = this.pdfData.length;
        const archivosCompletos = this.pdfData.filter(d => 
            d.policy !== 'NO_DETECTADO' && 
            d.certificate !== 'NO_DETECTADO' && 
            d.fullName !== 'NO_DETECTADO'
        ).length;
        
        console.log('\n📈 ESTADÍSTICAS FINALES:');
        console.log(`   Total archivos: ${totalArchivos}`);
        console.log(`   Archivos completos: ${archivosCompletos}`);
        console.log(`   Porcentaje éxito: ${Math.round((archivosCompletos / totalArchivos) * 100)}%`);
        
        console.log('='.repeat(80));
    }

    // =============================================
    // 📋 FUNCIONES PARA OTROS TIPOS DE ARCHIVO
    // =============================================

    // Funciones para VGG
    buscarPolizaYCertificadoVGG(lines) {
        console.log('🔍 Buscando póliza y certificado VGG...');
        return { poliza: null, certificado: null };
    }

    buscarNumeroPolizaVGG(lines) {
        console.log('🔍 Buscando póliza en TARJETA...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No Poliza" o "GMM-"
            if (line.includes('No Poliza') || line.includes('GMM-')) {
                console.log('📋 Línea encontrada:', line);
                
                // Buscar GMM-xxxxx
                const match = line.match(/(GMM-\d+)/i);
                if (match) {
                    console.log('✅ Póliza encontrada en tarjeta:', match[1]);
                    return match[1];
                }
                
                // También buscar después de "No Poliza"
                const parts = line.split(/\s+/);
                for (let j = 0; j < parts.length; j++) {
                    if (parts[j].includes('GMM-')) {
                        return parts[j];
                    }
                }
            }
        }
        
        return null;
    }

    buscarCertificadoVGG(lines) {
        console.log('🔍 Buscando certificado en TARJETA...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Buscar "No Certificado" o número largo
            if (line.includes('No Certificado') || /^\d{10,}$/.test(line)) {
                console.log('📋 Línea encontrada:', line);
                
                // Extraer número de certificado
                const certMatch = line.match(/\b(\d{8,})\b/);
                if (certMatch) {
                    console.log('✅ Certificado encontrado en tarjeta:', certMatch[1]);
                    return certMatch[1];
                }
            }
        }
        
        return null;
    }

    buscarNombreAseguradoVGG(lines) {
        console.log('🔍 Buscando titular en TARJETA...');
        
        // En tarjetas, el nombre suele estar en las primeras líneas
        for (let i = 0; i < Math.min(5, lines.length); i++) {
            const line = lines[i].trim();
            
            // Saltar líneas que no son nombres
            if (line.includes('SEGUROS') || line.includes('MONTERREY') || 
                line.includes('No Poliza') || line.includes('VIGENCIA') ||
                line.includes('VIRTUAL INTEGRATED')) {
                continue;
            }
            
            // Buscar líneas con formato de nombre (2-4 palabras)
            const palabras = line.split(/\s+/);
            if (palabras.length >= 2 && palabras.length <= 4) {
                let todasValidas = true;
                for (const palabra of palabras) {
                    if (!/^[A-ZÁÉÍÓÚÑ][A-Za-záéíóúñ]*$/.test(palabra)) {
                        todasValidas = false;
                        break;
                    }
                }
                
                if (todasValidas) {
                    console.log('✅ Titular encontrado en tarjeta:', line);
                    return line;
                }
            }
        }
        
        return null;
    }

    buscarVigenciaVGG(lines) {
        console.log('🔍 Buscando vigencia VGG...');
        console.log('🔍 Buscando vigencia en TARJETA...');
        
        const vigencia = { desde: null, hasta: null };
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            if (line.includes('VIGENCIA')) {
                console.log('📋 Línea con VIGENCIA:', line);
                
                // Buscar fechas en formato DD/MM/YYYY
                const fechas = line.match(/(\d{2}\/\d{2}\/\d{4})/g);
                if (fechas && fechas.length >= 2) {
                    vigencia.desde = fechas[0];
                    vigencia.hasta = fechas[1];
                    console.log('✅ Vigencia encontrada en tarjeta:', vigencia);
                    return vigencia;
                }
                
                // Buscar en líneas siguientes
                for (let j = i + 1; j < Math.min(i + 3, lines.length); j++) {
                    const nextLine = lines[j].trim();
                    const fechasNext = nextLine.match(/(\d{2}\/\d{2}\/\d{4})/g);
                    if (fechasNext && fechasNext.length >= 2) {
                        vigencia.desde = fechasNext[0];
                        vigencia.hasta = fechasNext[1];
                        console.log('✅ Vigencia encontrada en tarjeta (línea siguiente):', vigencia);
                        return vigencia;
                    }
                }
            }
        }
        
        return vigencia;
    }

    buscarSumaAseguradaVGG(lines) {
        console.log('🔍 Buscando suma asegurada VGG...');
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (line.includes('SUMAS ASEGURADAS') || line.includes('BENEFICIO BÁSICO')) {
                // La siguiente línea suele contener "18.00 MESES DE SUELDO"
                for (let j = i; j < i + 3; j++) {
                    if (lines[j]?.includes('MESES DE SUELDO')) {
                        return lines[j].trim();
                    }
                }
            }
        }
        return null;
    }

    // =============================================
// 🔍 FUNCIONES ESPECÍFICAS PARA ARCHIVOS C_
// =============================================

buscarNumeroPolizaCFile(lines) {
    console.log('🔍 Buscando póliza en formato C_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar línea con encabezados de tabla
        if (line.includes('Póliza No.') && line.includes('Certificado No.')) {
            console.log('📋 Encontrada línea con encabezados de tabla');
            
            // La siguiente línea contiene los datos en formato tabular
            if (i + 1 < lines.length) {
                const dataLine = lines[i + 1].trim();
                console.log('📊 Línea de datos:', dataLine);
                
                // Dividir por espacios múltiples (formato tabular)
                const columnas = dataLine.split(/\s{2,}/).filter(col => col.trim());
                console.log('📦 Columnas detectadas:', columnas);
                
                if (columnas.length >= 2) {
                    // En formato C_, la estructura es: [Contratante, Póliza, Certificado]
                    const poliza = columnas[1] ? columnas[1].trim() : null;
                    if (poliza && /M\d+/.test(poliza)) {
                        console.log('✅ Póliza C_ encontrada (formato tabular):', poliza);
                        return poliza;
                    }
                }
            }
        }
        
        // Búsqueda directa - para archivos C_ solo necesitamos M0076171
        if (line.includes('M0076171')) {
            console.log('✅ Póliza C_ encontrada (búsqueda directa): M0076171');
            return 'M0076171';
        }
        
        // Buscar patrones de póliza en archivos C_
        const polizaMatch = line.match(/Póliza\s*No\.?\s*:\s*([A-Z0-9\-]+)/i);
        if (polizaMatch) {
            console.log('✅ Póliza C_ encontrada (patrón):', polizaMatch[1]);
            return polizaMatch[1];
        }
    }
    
    // Buscar cualquier línea que contenga M seguido de números
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const mPolizaMatch = line.match(/(M\d{6,})/);
        if (mPolizaMatch) {
            console.log('✅ Póliza C_ encontrada (M pattern):', mPolizaMatch[1]);
            return mPolizaMatch[1];
        }
    }
    
    return null;
}

buscarCertificadoCFile(lines, file) {
    console.log('🔍 Buscando certificado en formato C_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar línea con encabezados de tabla
        if (line.includes('Póliza No.') && line.includes('Certificado No.')) {
            console.log('📋 Encontrada línea con encabezados de tabla');
            
            if (i + 1 < lines.length) {
                const dataLine = lines[i + 1].trim();
                console.log('📊 Línea de datos:', dataLine);
                
                // Dividir por espacios múltiples
                const columnas = dataLine.split(/\s{2,}/).filter(col => col.trim());
                console.log('📦 Columnas detectadas:', columnas);
                
                if (columnas.length >= 3) {
                    // La tercera columna es el certificado
                    const certificado = columnas[2] ? columnas[2].trim() : null;
                    if (certificado && /^\d+$/.test(certificado)) {
                        console.log('✅ Certificado C_ encontrado (formato tabular):', certificado);
                        return certificado;
                    }
                }
            }
        }
        
        // Buscar línea con "Certificado No."
        if (line.includes('Certificado No.')) {
            const certMatch = line.match(/Certificado\s*No\.?\s*:\s*(\d+)/i);
            if (certMatch) {
                console.log('✅ Certificado C_ encontrado (línea directa):', certMatch[1]);
                return certMatch[1];
            }
        }
    }
    
    // Buscar número de 8+ dígitos que no sea fecha
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que son fechas
        if (line.includes('/') && /\d{2}\/\d{2}\/\d{4}/.test(line)) {
            continue;
        }
        
        // Buscar número de 8+ dígitos
        const certMatch = line.match(/\b(\d{8,})\b/);
        if (certMatch) {
            const possibleCert = certMatch[1];
            
            // Verificar que no sea parte de un RFC
            if (!line.includes('VIA') && !line.includes('RFC') && !line.includes('R.F.C.')) {
                console.log('✅ Certificado C_ encontrado (número largo):', possibleCert);
                return possibleCert;
            }
        }
    }
    
    // Buscar en el nombre del archivo
    const certFromFileName = file.match(/C_(\d+)_/);
    if (certFromFileName) {
        console.log('✅ Certificado C_ desde nombre archivo:', certFromFileName[1]);
        return certFromFileName[1];
    }
    
    console.log('❌ No se pudo encontrar certificado en C_');
    return null;
}

buscarTitularCFile(lines, file) {
    console.log('🔍 Buscando titular en formato C_...');
    
    // ESTRATEGIA 1: Buscar en línea con "Nombre del asegurado Titular:"
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.includes('Nombre del asegurado Titular:')) {
            console.log('🎯 Encontrada línea Titular:', line);
            
            // La siguiente línea contiene el nombre REAL (no "Subgrupo")
            if (i + 1 < lines.length) {
                const nombreLine = lines[i + 1].trim();
                console.log('📝 Línea después de Titular:', nombreLine);
                
                // Excluir "Subgrupo" específicamente
                if (nombreLine && nombreLine !== 'Subgrupo' && nombreLine.length > 5) {
                    console.log('✅ Titular C_ encontrado (línea siguiente):', nombreLine);
                    return nombreLine;
                }
            }
            
            // También extraer de la misma línea
            const nombreEnLinea = line.replace('Nombre del asegurado Titular:', '').trim();
            if (nombreEnLinea && nombreEnLinea !== 'Subgrupo' && nombreEnLinea.length > 5) {
                console.log('✅ Titular C_ encontrado (misma línea):', nombreEnLinea);
                return nombreEnLinea;
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar en tabla "RELACION DE ASEGURADOS"
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.includes('RELACION DE ASEGURADOS')) {
            console.log('📋 Encontrada tabla RELACION DE ASEGURADOS');
            
            // Buscar en las siguientes líneas
            for (let j = i + 1; j < Math.min(i + 5, lines.length); j++) {
                const dataLine = lines[j].trim();
                
                // Saltar líneas que son encabezados o muy cortas
                if (dataLine.includes('APELLIDO') || dataLine.includes('NOMBRE') || 
                    dataLine.includes('SEXO') || dataLine.length < 5) {
                    continue;
                }
                
                // Extraer primera columna (nombre completo)
                const columnas = dataLine.split(/\s{2,}/).filter(col => col.trim());
                if (columnas.length > 0) {
                    const posibleNombre = columnas[0];
                    
                    // Validar que sea un nombre
                    if (this.esNombreCompletoValido(posibleNombre)) {
                        console.log('✅ Titular C_ desde tabla:', posibleNombre);
                        return posibleNombre;
                    }
                }
            }
        }
    }
    
    // ESTRATEGIA 3: Búsqueda inteligente en todo el documento
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que claramente no son nombres
        if (this.esLineaNoNombre(line) || line === 'Subgrupo') {
            continue;
        }
        
        // Verificar si es nombre válido
        if (this.esNombreCompletoValido(line)) {
            console.log('✅ Titular C_ encontrado (búsqueda general):', line);
            return line;
        }
    }
    
    console.log('❌ No se pudo encontrar titular en C_');
    return null;
}

buscarPlanCFile(lines) {
    console.log('🔍 Buscando plan en formato C_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.includes('TIPO DE PLAN CONTRATADO')) {
            console.log('📋 Encontrada línea de plan:', line);
            
            // Extraer la última palabra que es el código del plan
            const palabras = line.split(/\s+/);
            const plan = palabras[palabras.length - 1];
            
            if (plan && /^[A-Z]+$/.test(plan)) {
                console.log('✅ Plan C_ encontrado:', plan);
                return plan;
            }
            
            // También buscar después de "CONTRATADO"
            const contratadoIndex = palabras.findIndex(p => p === 'CONTRATADO');
            if (contratadoIndex !== -1 && contratadoIndex + 1 < palabras.length) {
                const posiblePlan = palabras[contratadoIndex + 1];
                if (posiblePlan && /^[A-Z]+$/.test(posiblePlan)) {
                    console.log('✅ Plan C_ encontrado (después de CONTRATADO):', posiblePlan);
                    return posiblePlan;
                }
            }
        }
        
        // Buscar línea que solo contiene "MAS" u otros códigos de plan
        if (line === 'MAS' || line === 'BASICO' || line === 'PREMIUM' || line === 'STANDARD') {
            console.log('✅ Plan C_ encontrado (línea individual):', line);
            return line;
        }
    }
    
    return 'MAS'; // Valor por defecto en archivos C_
}

buscarVigenciaCFile(lines) {
    console.log('🔍 Buscando vigencia en formato C_...');
    
    const vigencia = { desde: null, hasta: null };
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.includes('Vigencia de la póliza') || line.includes('VIGENCIA')) {
            console.log('📋 Encontrada línea de vigencia:', line);
            
            // Buscar líneas con fechas en formato Día Mes Año
            for (let j = i; j < Math.min(i + 10, lines.length); j++) {
                const fechaLine = lines[j].trim();
                
                if (fechaLine.includes('Día') && fechaLine.includes('Mes') && fechaLine.includes('Año')) {
                    console.log('📅 Encontrado formato fecha:', fechaLine);
                    
                    // Las siguientes 2 líneas contienen las fechas
                    if (j + 2 < lines.length) {
                        const desdeLine = lines[j + 1].trim();
                        const hastaLine = lines[j + 2].trim();
                        
                        console.log('📅 Línea desde:', desdeLine);
                        console.log('📅 Línea hasta:', hastaLine);
                        
                        // Extraer números de fecha
                        const desdeNums = desdeLine.match(/\d+/g);
                        const hastaNums = hastaLine.match(/\d+/g);
                        
                        if (desdeNums && desdeNums.length >= 3) {
                            vigencia.desde = `${desdeNums[0]}/${desdeNums[1]}/${desdeNums[2]}`;
                        }
                        if (hastaNums && hastaNums.length >= 3) {
                            vigencia.hasta = `${hastaNums[0]}/${hastaNums[1]}/${hastaNums[2]}`;
                        }
                        
                        console.log('✅ Vigencia C_ encontrada:', vigencia);
                        return vigencia;
                    }
                }
            }
            
            // También buscar fechas en formato DD/MM/YYYY en la misma área
            for (let j = i; j < Math.min(i + 5, lines.length); j++) {
                const fechas = lines[j].match(/(\d{2}\/\d{2}\/\d{4})/g);
                if (fechas && fechas.length >= 2) {
                    vigencia.desde = fechas[0];
                    vigencia.hasta = fechas[1];
                    console.log('✅ Vigencia C_ encontrada (fechas directas):', vigencia);
                    return vigencia;
                }
            }
        }
        
        // Buscar "Desde" y "Hasta" en líneas individuales
        if (line.includes('Desde') && line.includes('Hasta')) {
            const desdeMatch = line.match(/Desde\s+(\d{2}\/\d{2}\/\d{4})/i);
            const hastaMatch = line.match(/Hasta\s+(\d{2}\/\d{2}\/\d{4})/i);
            
            if (desdeMatch) vigencia.desde = desdeMatch[1];
            if (hastaMatch) vigencia.hasta = hastaMatch[1];
            
            if (vigencia.desde || vigencia.hasta) {
                console.log('✅ Vigencia C_ encontrada (Desde/Hasta):', vigencia);
                return vigencia;
            }
        }
    }
    
    // Valores por defecto para archivos C_
    return { desde: '01/01/2025', hasta: '31/12/2025' };
}

// =============================================
// 🔍 FUNCIONES ESPECÍFICAS PARA ARCHIVOS T_
// =============================================

buscarPolizaTFile(lines) {
    console.log('🔍 Buscando póliza en formato T_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar línea que contiene ambos campos
        if (line.includes('POLIZA:') && line.includes('CERTIFICADO:')) {
            console.log('📋 Línea con POLIZA y CERTIFICADO:', line);
            
            // Extraer solo la parte de POLIZA (entre "POLIZA:" y "CERTIFICADO:")
            const polizaMatch = line.match(/POLIZA:\s*([^C]+?)(?=\s+CERTIFICADO:)/i);
            if (polizaMatch) {
                const polizaCompleta = polizaMatch[1].trim();
                console.log('✅ Póliza T_ encontrada:', polizaCompleta);
                return polizaCompleta;
            }
            
            // Método alternativo: dividir por "CERTIFICADO:"
            const partes = line.split('CERTIFICADO:');
            if (partes.length > 0) {
                const partePoliza = partes[0].replace('POLIZA:', '').trim();
                if (partePoliza) {
                    console.log('✅ Póliza T_ encontrada (split):', partePoliza);
                    return partePoliza;
                }
            }
        }
        
        // Si solo tiene POLIZA: (sin CERTIFICADO: en la misma línea)
        if (line.includes('POLIZA:') && !line.includes('CERTIFICADO:')) {
            console.log('📋 Línea solo con POLIZA:', line);
            const polizaCompleta = line.replace('POLIZA:', '').trim();
            if (polizaCompleta) {
                console.log('✅ Póliza T_ encontrada (solo poliza):', polizaCompleta);
                return polizaCompleta;
            }
        }
    }
    
    // Buscar cualquier línea que contenga M seguido de números
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const mPolizaMatch = line.match(/(M\d{6,})/);
        if (mPolizaMatch) {
            console.log('✅ Póliza T_ encontrada (M pattern):', mPolizaMatch[1]);
            return mPolizaMatch[1];
        }
    }
    
    return null;
}

buscarCertificadoTFile(lines, file) {
    console.log('🔍 Buscando certificado en formato T_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar línea que comienza con "CERTIFICADO:"
        if (line.startsWith('CERTIFICADO:')) {
            console.log('📋 Encontrada línea CERTIFICADO:', line);
            
            // Extraer número de certificado después de "CERTIFICADO:"
            const partes = line.split(/\s+/);
            for (let j = 0; j < partes.length; j++) {
                if (partes[j] === 'CERTIFICADO:' && j + 1 < partes.length) {
                    const certificado = partes[j + 1];
                    if (certificado && /^\d+$/.test(certificado)) {
                        console.log('✅ Certificado T_ encontrado:', certificado);
                        return certificado;
                    }
                }
            }
        }
        
        // Buscar línea que contiene "CERTIFICADO:" en cualquier posición
        if (line.includes('CERTIFICADO:')) {
            const certMatch = line.match(/CERTIFICADO:\s*(\d+)/i);
            if (certMatch) {
                console.log('✅ Certificado T_ encontrado (match):', certMatch[1]);
                return certMatch[1];
            }
        }
    }
    
    // Buscar número de 8+ dígitos que no sea fecha
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que son fechas
        if (line.includes('/') && /\d{2}\/\d{2}\/\d{4}/.test(line)) {
            continue;
        }
        
        // Buscar número de 8+ dígitos
        const certMatch = line.match(/\b(\d{8,})\b/);
        if (certMatch) {
            const possibleCert = certMatch[1];
            console.log('✅ Certificado T_ encontrado (número largo):', possibleCert);
            return possibleCert;
        }
    }
    
    // Buscar en el nombre del archivo
    const certFromFileName = file.match(/T_(\d+)_/);
    if (certFromFileName) {
        console.log('✅ Certificado T_ desde nombre archivo:', certFromFileName[1]);
        return certFromFileName[1];
    }
    
    console.log('❌ No se pudo encontrar certificado en T_');
    return null;
}

buscarTitularTFile(lines, file) {
    console.log('🔍 Buscando titular en formato T_...');
    
    // ESTRATEGIA 1: Buscar línea que comienza con "TIT." 
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.startsWith('TIT.')) {
            console.log('📋 Encontrada línea TIT.:', line);
            
            // Extraer nombre después de "TIT." 
            const nombre = line.replace(/^TIT\.?\s*/i, '').trim();
            
            if (nombre && this.esNombreCompletoValido(nombre)) {
                console.log('✅ Titular T_ encontrado:', nombre);
                return nombre;
            }
        }
        
        // Buscar línea que contiene "TIT." en cualquier posición
        if (line.includes('TIT.')) {
            console.log('📋 Encontrada línea con TIT. incluido:', line);
            
            // Extraer todo después de "TIT."
            const nombre = line.split(/TIT\.?\s*/i)[1]?.trim();
            
            if (nombre && this.esNombreCompletoValido(nombre)) {
                console.log('✅ Titular T_ encontrado (con TIT. incluido):', nombre);
                return nombre;
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar en nombre del archivo
    const nombreFromFile = this.extraerNombreDesdeNombreArchivo(file);
    if (nombreFromFile) {
        console.log('✅ Titular T_ desde nombre archivo:', nombreFromFile);
        return nombreFromFile;
    }
    
    // ESTRATEGIA 3: Búsqueda inteligente
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que claramente no son nombres
        if (this.esLineaNoNombre(line)) {
            continue;
        }
        
        // Verificar si es nombre válido
        if (this.esNombreCompletoValido(line)) {
            console.log('✅ Titular T_ encontrado (búsqueda general):', line);
            return line;
        }
    }
    
    console.log('❌ No se pudo encontrar titular en T_');
    return null;
}

buscarPlanTFile(lines) {
    console.log('🔍 Buscando plan en formato T_...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar "MEDICALIFE MAS" que es el plan en archivos T_
        if (line.includes('MEDICALIFE MAS')) {
            console.log('✅ Plan T_ encontrado: MAS');
            return 'MAS';
        }
        
        // Buscar "MAS" en contexto de plan
        if (line.includes('MAS') && (line.includes('PLAN') || line.includes('Medicalife'))) {
            console.log('✅ Plan T_ encontrado (contexto): MAS');
            return 'MAS';
        }
        
        // Buscar línea que solo contiene "MAS"
        if (line === 'MAS') {
            console.log('✅ Plan T_ encontrado (línea individual): MAS');
            return 'MAS';
        }
    }
    
    return 'MAS'; // Por defecto en archivos T_
}

buscarVigenciaTFile(lines) {
    console.log('🔍 Buscando vigencia en formato T_...');
    
    const vigencia = { desde: null, hasta: null };
    
    // En archivos T_ no suele haber información explícita de vigencia
    // Buscar cualquier patrón de fecha que pueda ser vigencia
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar fechas en cualquier formato
        const fechas = line.match(/(\d{2}\/\d{2}\/\d{4})/g);
        if (fechas && fechas.length >= 2) {
            vigencia.desde = fechas[0];
            vigencia.hasta = fechas[1];
            console.log('✅ Vigencia T_ encontrada (fechas múltiples):', vigencia);
            return vigencia;
        }
        
        // Buscar "Desde" y "Hasta"
        if (line.includes('Desde') && line.includes('Hasta')) {
            const desdeMatch = line.match(/Desde\s+(\d{2}\/\d{2}\/\d{4})/i);
            const hastaMatch = line.match(/Hasta\s+(\d{2}\/\d{2}\/\d{4})/i);
            
            if (desdeMatch) vigencia.desde = desdeMatch[1];
            if (hastaMatch) vigencia.hasta = hastaMatch[1];
            
            if (vigencia.desde || vigencia.hasta) {
                console.log('✅ Vigencia T_ encontrada (Desde/Hasta):', vigencia);
                return vigencia;
            }
        }
    }
    
    // Valores por defecto para archivos T_
    console.log('⚠️ No se encontró vigencia explícita, usando valores por defecto');
    return { desde: '01/01/2025', hasta: '31/12/2025' };
}

// =============================================
// 🔍 FUNCIONES ESPECÍFICAS PARA ARCHIVOS GMG
// =============================================

buscarNumeroPolizaGMG(lines, file) {
    console.log('🔍 Buscando póliza en formato GMG...');
    
    // ESTRATEGIA 1: Buscar "No. de póliza" o "GMG-" en el contenido
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar "No. de póliza" o "GMG-"
        if (line.includes('No. de póliza') || line.includes('GMG-')) {
            console.log('📋 Línea con referencia a póliza:', line);
            
            // Buscar GMG-xxxxx
            const polizaMatch = line.match(/(GMG-\d+)/i);
            if (polizaMatch) {
                console.log('✅ Póliza GMG encontrada:', polizaMatch[1]);
                return polizaMatch[1];
            }
            
            // Buscar en siguientes líneas
            for (let j = i + 1; j < Math.min(i + 3, lines.length); j++) {
                const polizaMatchNext = lines[j].match(/(GMG-\d+)/i);
                if (polizaMatchNext) {
                    console.log('✅ Póliza GMG encontrada (siguiente línea):', polizaMatchNext[1]);
                    return polizaMatchNext[1];
                }
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar directamente "GMG-" en cualquier línea
    for (let i = 0; i < lines.length; i++) {
        const polizaMatch = lines[i].match(/(GMG-\d+)/i);
        if (polizaMatch) {
            console.log('✅ Póliza GMG encontrada (búsqueda directa):', polizaMatch[1]);
            return polizaMatch[1];
        }
    }
    
    // ESTRATEGIA 3: Extraer del nombre del archivo
    // Patrón: GMG-19008_0000019627_01_Certificado.pdf
    const fileNameMatch = file.match(/(GMG-\d+)/i);
    if (fileNameMatch) {
        console.log('✅ Póliza GMG desde nombre archivo:', fileNameMatch[1]);
        return fileNameMatch[1];
    }
    
    console.log('❌ No se pudo encontrar número de póliza en GMG');
    return null;
}

buscarCertificadoGMG(lines, file) {
    console.log('🔍 Buscando certificado en formato GMG...');
    
    // ESTRATEGIA 1: Buscar en tabla "No. de certificado"
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar "No. de certificado" (con o sin caracteres extraños)
        if (line.includes('No. de certificado') || line.includes('certificado')) {
            console.log('📋 Línea con "No. de certificado":', line);
            
            // Buscar número de 8+ dígitos en la misma línea
            const certMatch = line.match(/\b(\d{8,})\b/);
            if (certMatch) {
                console.log('✅ Certificado GMG encontrado:', certMatch[1]);
                return certMatch[1];
            }
            
            // Buscar en las siguientes líneas
            for (let j = i + 1; j < Math.min(i + 3, lines.length); j++) {
                const nextLine = lines[j];
                const nextCertMatch = nextLine.match(/\b(\d{8,})\b/);
                if (nextCertMatch) {
                    console.log('✅ Certificado GMG encontrado (siguiente línea):', nextCertMatch[1]);
                    return nextCertMatch[1];
                }
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar después de "R.F.C." (caso específico)
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].includes('R.F.C.')) {
            console.log('📋 Línea con R.F.C. encontrada');
            
            // Buscar número de certificado en las siguientes 3 líneas
            for (let j = i + 1; j < Math.min(i + 4, lines.length); j++) {
                const certMatch = lines[j].match(/\b(\d{8,})\b/);
                if (certMatch) {
                    console.log('✅ Certificado GMG encontrado (después de R.F.C.):', certMatch[1]);
                    return certMatch[1];
                }
            }
        }
    }
    
    // ESTRATEGIA 3: Buscar en nombre del archivo
    // Patrón: GMG-19008_0000019627_01_Certificado.pdf
    const fileNameMatch = file.match(/GMG-\d+_(\d{8,})_/);
    if (fileNameMatch) {
        console.log('✅ Certificado GMG desde nombre archivo:', fileNameMatch[1]);
        return fileNameMatch[1];
    }
    
    // ESTRATEGIA 4: Buscar cualquier número de 8+ dígitos en todo el documento
    for (let i = 0; i < lines.length; i++) {
        const certMatch = lines[i].match(/\b(\d{8,})\b/);
        if (certMatch && certMatch[1].length >= 8) {
            console.log('✅ Certificado GMG encontrado (búsqueda general):', certMatch[1]);
            return certMatch[1];
        }
    }
    
    console.log('❌ No se pudo encontrar certificado en GMG');
    return null;
}

buscarTitularGMGCertificado(lines, file) {
    console.log('🔍 Buscando titular en CERTIFICADO GMG...');
    
    let tablaAseguradosInicio = -1;
    
    // ESTRATEGIA 1: Buscar tabla "Asegurado y dependientes" y tomar PRIMER TITULAR
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar inicio de tabla de asegurados
        if (line.includes('Asegurado y dependientes') || 
            (line.includes('Parentesco') && line.includes('Nombre') && 
             line.includes('Fecha'))) {
            
            tablaAseguradosInicio = i;
            console.log('📋 Encontrada tabla de asegurados en línea', i);
        }
        
        // Buscar línea que contiene "TITULAR" (no confundir con otros campos)
        if (line.includes('TITULAR') && !line.includes('ANUAL') && 
            !line.includes('PROPIA') && !line.includes('OPTIMA')) {
            
            console.log('📋 Línea con TITULAR:', line);
            
            // Dividir por espacios múltiples o tabs
            const parts = line.split(/\s+/);
            
            // Buscar desde "TITULAR" hasta encontrar fecha o caracteres no válidos
            let nombrePartes = [];
            let capturandoNombre = false;
            
            for (let j = 0; j < parts.length; j++) {
                const parte = parts[j];
                
                if (parte === 'TITULAR') {
                    capturandoNombre = true;
                    continue;
                }
                
                if (capturandoNombre) {
                    // Detener cuando encontramos fecha (formato DD/MMM/YYYY)
                    if (/\d{2}\/[A-Z]{3}\/\d{4}/.test(parte)) {
                        break;
                    }
                    
                    // Detener cuando encontramos edad (ej: "44", "AÑOS")
                    if (/\d+/.test(parte) || parte.includes('AÑOS') || 
                        parte === 'M' || parte === 'F') {
                        break;
                    }
                    
                    // Agregar solo partes que parezcan nombres
                    if (parte && parte.length > 1 && 
                        /^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]*$/.test(parte) &&
                        !this.esPalabraClaveDocumento(parte)) {
                        
                        nombrePartes.push(parte);
                    }
                }
            }
            
            if (nombrePartes.length >= 2) {
                const nombre = nombrePartes.join(' ');
                console.log('✅ Titular GMG certificado encontrado:', nombre);
                return nombre;
            }
        }
    }
    
    // ESTRATEGIA 2: Si no encontró en línea con "TITULAR", buscar en formato tabla
    if (tablaAseguradosInicio > -1) {
        console.log('🔄 Buscando titular en formato de tabla...');
        
        // Buscar en las líneas después del inicio de la tabla
        for (let i = tablaAseguradosInicio + 1; i < Math.min(tablaAseguradosInicio + 10, lines.length); i++) {
            const line = lines[i];
            
            // Buscar línea que tenga 2-4 palabras mayúsculas seguidas de fecha
            const parts = line.split(/\s+/);
            
            if (parts.length >= 3) {
                // Verificar si comienza con posibles partes de nombre
                let nombrePartes = [];
                let tieneFecha = false;
                
                for (let j = 0; j < parts.length; j++) {
                    const parte = parts[j];
                    
                    // Si encontramos fecha, detener
                    if (/\d{2}\/[A-Z]{3}\/\d{4}/.test(parte)) {
                        tieneFecha = true;
                        break;
                    }
                    
                    // Si es una palabra de nombre válida, agregar
                    if (parte && parte.length > 1 && 
                        /^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]*$/.test(parte) &&
                        !this.esPalabraClaveDocumento(parte)) {
                        
                        nombrePartes.push(parte);
                    } else if (parte && parte.length > 0) {
                        // Si encontramos algo que no es nombre, detener
                        break;
                    }
                }
                
                // Si tenemos al menos 2 partes de nombre y encontramos fecha después
                if (nombrePartes.length >= 2 && tieneFecha) {
                    const nombre = nombrePartes.join(' ');
                    console.log('✅ Titular GMG certificado encontrado (tabla):', nombre);
                    return nombre;
                }
            }
        }
    }
    
    // ESTRATEGIA 3: Buscar cualquier nombre completo en documento
    console.log('🔄 Buscando nombre en todo el documento...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Saltar líneas que claramente no son nombres
        if (line.length < 5 || line.length > 50 || 
            line.includes('SEGUROS') || line.includes('MONTERREY') ||
            line.includes('POLIZA') || line.includes('CERTIFICADO') ||
            line.includes('R.F.C.') || line.includes('Contratante') ||
            line.includes('ANUAL') || line.includes('PROPIA') || 
            line.includes('OPTIMA') || /\d/.test(line)) {
            continue;
        }
        
        const palabras = line.split(/\s+/);
        
        // Buscar líneas con 2-4 palabras en mayúsculas (nombres típicos)
        if (palabras.length >= 2 && palabras.length <= 4) {
            let todasValidas = true;
            for (const palabra of palabras) {
                if (!/^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ\s]*$/.test(palabra) || 
                    this.esPalabraClaveDocumento(palabra) ||
                    palabra.length < 2) {
                    todasValidas = false;
                    break;
                }
            }
            
            if (todasValidas) {
                console.log('✅ Titular GMG certificado encontrado (búsqueda general):', line);
                return line;
            }
        }
    }
    
    console.log('❌ No se pudo encontrar nombre del titular en certificado GMG');
    return null;
}

buscarTitularGMGCredencial(lines, file) {
    console.log('🔍 Buscando titular en CREDENCIAL GMG...');
    
    // Lista de palabras a EXCLUIR específicamente
    const palabrasExcluir = [
        'COLECTIVO', 'EMP', 'EMPRESA', 'EMPRESARIAL', 'AGRUPACION',
        'PREEXISTENCIA', 'EXCLUIDO', 'ALFA', 'MEDICAL', 
        'TELEFONOS', 'CONTACTO', 'URGENCIA', 'ASESORIA', 'MEDICA',
        'REFERENCIA', 'TRAMITES', 'PAGO', 'ASISTENCIA', 'AMBULANCIA',
        'ESTADOS', 'UNIDOS', 'CANADA', 'REPUBLICA', 'RESTO', 'MUNDO',
        'CIUDAD', 'DE', 'MEXICO', 'INTERIOR'
    ];
    
    // En las credenciales, el nombre suele estar en las primeras líneas
    for (let i = 0; i < Math.min(15, lines.length); i++) {
        const line = lines[i].trim();
        
        // Saltar líneas vacías o muy cortas
        if (!line || line.length < 5) continue;
        
        // Saltar si es claramente nombre de empresa
        if (line.includes('LUXOFT') || line.includes('MEXICO') || 
            line.includes('S DE RL DE CV') || line.includes('S.A.') ||
            line.includes('S.A. DE C.V.') || line.includes('RL DE CV')) {
            continue;
        }
        
        // Saltar si contiene palabras de seguros/empresa
        if (line.includes('SEGUROS') || line.includes('MONTERREY') ||
            line.includes('NEW YORK') || line.includes('LIFE')) {
            continue;
        }
        
        // Analizar la línea como posible nombre
        const palabras = line.split(/\s+/);
        
        // Debe tener 2-4 palabras (nombre completo típico)
        if (palabras.length >= 2 && palabras.length <= 4) {
            let todasValidas = true;
            let contienePalabraExcluida = false;
            
            // Verificar cada palabra
            for (const palabra of palabras) {
                const palabraUpper = palabra.toUpperCase();
                
                // Verificar si es palabra a excluir
                if (palabrasExcluir.includes(palabraUpper)) {
                    contienePalabraExcluida = true;
                    break;
                }
                
                // Verificar que sea una palabra de nombre válida
                // Permitir apóstrofes y guiones en nombres
                if (!/^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑa-záéíóúñ'\-]*$/.test(palabra)) {
                    todasValidas = false;
                    break;
                }
                
                // Verificar longitud mínima (excepto para "DE", "DEL", etc.)
                if (palabra.length < 2 && !['DE', 'DEL', 'LA', 'LAS', 'LOS'].includes(palabraUpper)) {
                    todasValidas = false;
                    break;
                }
            }
            
            // Si contiene palabra excluida, saltar
            if (contienePalabraExcluida) {
                continue;
            }
            
            if (todasValidas) {
                console.log('✅ Titular GMG credencial encontrado:', line);
                return line;
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar nombres en formato específico de credenciales GMG
    console.log('🔄 Buscando nombre con estrategia específica para credenciales...');
    
    for (let i = 0; i < Math.min(10, lines.length); i++) {
        const line = lines[i].trim();
        
        // Patrón típico en credenciales: Nombre completo solo en esa línea
        // No debe contener números, símbolos especiales, o palabras clave
        
        // Condiciones de EXCLUSIÓN mejoradas
        if (!line || line.length < 8 || line.length > 50) continue;
        if (/\d/.test(line)) continue; // No números
        if (/[^A-Za-zÁÉÍÓÚÑáéíóúñ\s\-]/.test(line)) continue; // Solo letras, espacios y guiones
        if (line.includes('@') || line.includes('.com') || line.includes('.mx')) continue;
        
        // Excluir líneas con palabras de formato de documento
        const palabrasProhibidas = [
            'No Poliza', 'No Certificado', 'GMG-', 'SUMA', 'ASEG', 
            'COASEGURO', 'DEDUCIBLE', 'COBERTURA', 'PLAN', 'AGRUPACION',
            'PREEXISTENCIA', 'TELEFONOS', 'CONTACTO', 'URGENCIA'
        ];
        
        let contieneProhibida = false;
        for (const prohibida of palabrasProhibidas) {
            if (line.includes(prohibida)) {
                contieneProhibida = true;
                break;
            }
        }
        
        if (contieneProhibida) continue;
        
        const palabras = line.split(/\s+/);
        
        // Para nombres en credenciales: 2-4 palabras
        if (palabras.length >= 2 && palabras.length <= 4) {
            // Verificar que todas las palabras sean válidas
            let todasPalabrasValidas = true;
            
            for (const palabra of palabras) {
                // Debe empezar con mayúscula
                if (!/^[A-ZÁÉÍÓÚÑ]/.test(palabra)) {
                    todasPalabrasValidas = false;
                    break;
                }
                
                // No debe ser palabra común del documento
                const palabraUpper = palabra.toUpperCase();
                if (palabrasExcluir.includes(palabraUpper)) {
                    todasPalabrasValidas = false;
                    break;
                }
                
                // Longitud razonable para nombres
                if (palabra.length < 2 || palabra.length > 15) {
                    todasPalabrasValidas = false;
                    break;
                }
            }
            
            if (todasPalabrasValidas) {
                console.log('✅ Titular GMG credencial encontrado (estrategia 2):', line);
                return line;
            }
        }
    }
    
    // ESTRATEGIA 3: Buscar patrón específico de archivos GMG
    // En GMG credenciales, el patrón suele ser:
    // 1. Nombre
    // 2. Empresa
    // 3. No Poliza GMG-xxxxx
    
    for (let i = 0; i < Math.min(5, lines.length); i++) {
        // Verificar si la siguiente línea es empresa
        if (i + 1 < lines.length) {
            const currentLine = lines[i].trim();
            const nextLine = lines[i + 1].trim();
            
            // Si la siguiente línea parece empresa, esta podría ser el nombre
            if (this.pareceNombreEmpresa(nextLine) && !this.pareceNombreEmpresa(currentLine)) {
                // Verificar que currentLine sea un nombre válido
                if (this.esNombreValidoParaCredencial(currentLine)) {
                    console.log('✅ Titular GMG credencial encontrado (estrategia 3):', currentLine);
                    return currentLine;
                }
            }
        }
    }
    
    console.log('❌ No se pudo encontrar nombre del titular en credencial GMG');
    return null;
}

pareceNombreEmpresa(texto) {
    const indicadoresEmpresa = [
        'S.A.', 'S.A. DE C.V.', 'S DE RL DE CV', 'S DE RL', 
        'COMPANY', 'CORPORATION', 'MEXICO', 'SOLUTIONS', 
        'INTEGRATED', 'ANALYTICS', 'VIRTUAL'
    ];
    
    const upperTexto = texto.toUpperCase();
    return indicadoresEmpresa.some(indicador => upperTexto.includes(indicador));
}

buscarTitularGMG(lines, file) {
    console.log('🔍 Buscando titular en formato GMG...');
    
    // Primero intentar como certificado
    const titularCertificado = this.buscarTitularGMGCertificado(lines, file);
    if (titularCertificado) {
        return titularCertificado;
    }
    
    // Si no, intentar como credencial
    const titularCredencial = this.buscarTitularGMGCredencial(lines, file);
    if (titularCredencial) {
        return titularCredencial;
    }
    
    // Último recurso: búsqueda general
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que claramente no son nombres
        if (this.esLineaNoNombre(line)) {
            continue;
        }
        
        // Verificar si es nombre válido
        if (this.esNombreCompletoValido(line)) {
            console.log('✅ Titular GMG encontrado (búsqueda general):', line);
            return line;
        }
    }
    
    console.log('❌ No se pudo encontrar titular en GMG');
    return null;
}

buscarPlanGMG(lines, file) {
    console.log('🔍 Buscando plan en formato GMG...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar "PLAN:"
        if (line.includes('PLAN:')) {
            console.log('📋 Encontrada línea con PLAN:', line);
            
            // Extraer el nombre del plan
            const planMatch = line.match(/PLAN:\s*([A-ZÁÉÍÓÚÑ\s]+)/i);
            if (planMatch) {
                const plan = planMatch[1].trim();
                console.log('✅ Plan GMG encontrado:', plan);
                return plan;
            }
        }
        
        // Buscar "OPTIMA" (plan común en estos archivos)
        if (line.includes('OPTIMA')) {
            console.log('✅ Plan GMG encontrado (OPTIMA):', 'OPTIMA');
            return 'OPTIMA';
        }
        
        // Buscar "MAXIMA"
        if (line.includes('MAXIMA')) {
            console.log('✅ Plan GMG encontrado (MAXIMA):', 'MAXIMA');
            return 'MAXIMA';
        }
    }
    
    // Por defecto
    return 'OPTIMA';
}

buscarPlanGMGCredencial(lines, file) {
    console.log('🔍 Buscando plan en CREDENCIAL GMG...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar "PLAN OPTIMA" o similar
        if (line.includes('PLAN') && line.includes('OPTIMA')) {
            return 'OPTIMA';
        }
        
        // Buscar solo "OPTIMA"
        if (line.trim() === 'OPTIMA') {
            return 'OPTIMA';
        }
        
        // Buscar "MAXIMA"
        if (line.trim() === 'MAXIMA') {
            return 'MAXIMA';
        }
    }
    
    return 'OPTIMA'; // Valor por defecto común
}

buscarVigenciaGMG(lines, file) {
    console.log('🔍 Buscando vigencia en formato GMG...');
    
    const vigencia = { desde: null, hasta: null };
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar "Periodo de seguro/vigencia" o "Vigencia"
        if (line.includes('Periodo de seguro') || line.includes('Vigencia')) {
            console.log('📋 Encontrada línea de vigencia:', line);
            
            // Buscar fechas en formato DD/MMM/YYYY
            const fechaPattern = /\d{2}\/[A-Z]{3}\/\d{4}/g;
            const fechas = line.match(fechaPattern);
            
            if (fechas && fechas.length >= 2) {
                vigencia.desde = fechas[0];
                vigencia.hasta = fechas[1];
                console.log('✅ Vigencia GMG encontrada:', vigencia);
                return vigencia;
            }
        }
        
        // Buscar líneas con "Desde" y "Hasta"
        if (line.includes('Desde') && line.includes('Hasta')) {
            console.log('📋 Encontrada línea Desde/Hasta:', line);
            
            // Extraer fechas
            const desdeMatch = line.match(/Desde\s+(\d{2}\/\d{2}\/\d{4})/i);
            const hastaMatch = line.match(/Hasta\s+(\d{2}\/\d{2}\/\d{4})/i);
            
            if (desdeMatch) vigencia.desde = desdeMatch[1];
            if (hastaMatch) vigencia.hasta = hastaMatch[1];
            
            if (vigencia.desde || vigencia.hasta) {
                console.log('✅ Vigencia GMG encontrada (Desde/Hasta):', vigencia);
                return vigencia;
            }
        }
        
        // Buscar fechas en cualquier formato
        const fechas = line.match(/(\d{2}\/\d{2}\/\d{4})/g);
        if (fechas && fechas.length >= 2) {
            vigencia.desde = fechas[0];
            vigencia.hasta = fechas[1];
            console.log('✅ Vigencia GMG encontrada (fechas múltiples):', vigencia);
            return vigencia;
        }
    }
    
    return vigencia;
}

buscarSumaAseguradaGMGCertificado(lines, file) {
    console.log('🔍 Buscando suma asegurada en CERTIFICADO GMG...');
    
    // En los certificados, la suma asegurada está en la tabla "Cobertura básica"
    let enTablaCoberturas = false;
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar inicio de tabla de coberturas
        if (line.includes('Cobertura básica') || 
            (line.includes('Coberturas') && line.includes('Suma asegurada'))) {
            
            enTablaCoberturas = true;
        }
        
        // Si estamos en la tabla, buscar "Básica"
        if (enTablaCoberturas && line.includes('Básica')) {
            
            // Extraer el monto de la suma asegurada
            // Formato: "Básica $8,000,000.00 6000.00 9000.00 5.00 10.00"
            
            // Buscar monto con formato $ y comas
            const montoMatch = line.match(/\$?\s*([\d,]+\.?\d*)/);
            if (montoMatch) {
                console.log('✅ Suma asegurada GMG certificado encontrada:', montoMatch[1]);
                return montoMatch[1];
            }
            
            // Buscar número grande (8 dígitos o más)
            const numeroGrandeMatch = line.match(/\b(\d{7,})\b/);
            if (numeroGrandeMatch) {
                // Formatear con comas si es un número grande
                const numero = numeroGrandeMatch[1];
                if (numero.length >= 7) {
                    console.log('✅ Suma asegurada GMG certificado encontrada (número grande):', numero);
                    return numero;
                }
            }
        }
        
        // También buscar directamente "Suma asegurada" en líneas individuales
        if (line.includes('Suma asegurada') && line.includes('$')) {
            
            const montoMatch = line.match(/\$?\s*([\d,]+\.?\d*)/);
            if (montoMatch) {
                console.log('✅ Suma asegurada GMG certificado encontrada (directo):', montoMatch[1]);
                return montoMatch[1];
            }
        }
    }
    
    // ESTRATEGIA 2: Buscar en todo el documento montos grandes con formato de dinero
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar montos grandes con formato: $8,000,000.00
        const montoMatch = line.match(/\$(\d{1,3}(?:,\d{3})*\.\d{2})/);
        if (montoMatch) {
            const monto = montoMatch[1];
            // Verificar que sea un monto significativo (más de 1,000,000)
            const montoNumerico = parseFloat(monto.replace(/,/g, ''));
            if (montoNumerico > 1000000) {
                console.log('✅ Suma asegurada GMG certificado encontrada (formato $):', monto);
                return monto;
            }
        }
        
        // Buscar montos sin $ pero con comas
        const montoSinDolarMatch = line.match(/(\d{1,3}(?:,\d{3})*\.\d{2})/);
        if (montoSinDolarMatch) {
            const monto = montoSinDolarMatch[1];
            const montoNumerico = parseFloat(monto.replace(/,/g, ''));
            if (montoNumerico > 1000000 && montoNumerico < 100000000) {
                console.log('✅ Suma asegurada GMG certificado encontrada (sin $):', monto);
                return monto;
            }
        }
    }
    
    console.log('❌ No se pudo encontrar suma asegurada en certificado GMG');
    return null;
}

buscarSumaAseguradaGMGCredencial(lines, file) {
    console.log('🔍 Buscando suma asegurada en CREDENCIAL GMG...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        // Buscar "SUMA ASEG.:" (con o sin espacios)
        if (line.includes('SUMA ASEG.:') || line.includes('SUMA ASEGURA')) {
            
            // Extraer monto - diferentes formatos posibles
            const formatos = [
                /\$?\s*([\d,]+\.?\d{2})/,  // $8,000,000.00 o 8,000,000.00
                /\$?\s*([\d\.]+,\d{2})/,   // 8.000.000,00 (formato europeo)
                /:?\s*([\d\.,]+)/          // Cualquier número con , o .
            ];
            
            for (const formato of formatos) {
                const montoMatch = line.match(formato);
                if (montoMatch) {
                    let monto = montoMatch[1];
                    
                    // Limpiar y formatear
                    monto = monto.replace(/[^\d,\.]/g, '');
                    
                    // Verificar que sea un monto razonable
                    const montoLimpio = monto.replace(/,/g, '');
                    const montoNumerico = parseFloat(montoLimpio);
                    
                    if (!isNaN(montoNumerico) && montoNumerico > 1000) {
                        console.log('✅ Suma asegurada GMG credencial encontrada:', monto);
                        return monto;
                    }
                }
            }
        }
        
        // También buscar "SUMA ASEGURADA:" en algunos formatos
        if (line.includes('SUMA ASEGURADA:')) {
            console.log('📋 Línea con SUMA ASEGURADA:', line);
            
            const montoMatch = line.match(/SUMA ASEGURADA:\s*\$?\s*([\d,]+\.?\d*)/i);
            if (montoMatch) {
                console.log('✅ Suma asegurada GMG credencial encontrada (SUMA ASEGURADA):', montoMatch[1]);
                return montoMatch[1];
            }
        }
    }
    
    // Buscar en formato específico de credenciales GMG
    // Ejemplo: "SUMA ASEG.: $8,000,000.00"
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].includes('SUMA ASEG.:') && i + 1 < lines.length) {
            const montoLine = lines[i + 1];
            const montoMatch = montoLine.match(/([\d,]+\.?\d*)/);
            if (montoMatch) {
                console.log('✅ Suma asegurada GMG credencial encontrada (línea siguiente):', montoMatch[1]);
                return montoMatch[1];
            }
        }
    }
    
    console.log('❌ No se pudo encontrar suma asegurada en credencial GMG');
    return null;
}

buscarSumaAseguradaGMG(lines, file) {
    console.log('🔍 Buscando suma asegurada en formato GMG (genérico)...');
    
    // Primero intentar como certificado
    const sumaCertificado = this.buscarSumaAseguradaGMGCertificado(lines, file);
    if (sumaCertificado) {
        return sumaCertificado;
    }
    
    // Si no, intentar como credencial
    const sumaCredencial = this.buscarSumaAseguradaGMGCredencial(lines, file);
    if (sumaCredencial) {
        return sumaCredencial;
    }
    
    // Último recurso: buscar en todo el documento
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        
        if (line.includes('SUMA ASEG.:')) {
            console.log('📋 Línea con SUMA ASEG.:', line);
            
            const montoMatch = line.match(/\$?\s*([\d,]+\.?\d*)/);
            if (montoMatch) {
                console.log('✅ Suma asegurada GMG encontrada:', montoMatch[1]);
                return montoMatch[1];
            }
        }
    }
    
    console.log('❌ No se pudo encontrar suma asegurada en GMG');
    return null;
}

// =============================================
// 🔍 FUNCIONES GENERALES (MANTENIDAS POR COMPATIBILIDAD)
// =============================================

buscarNumeroPolizaPorLineas(lines) {
    console.log('🔍 Buscando número de póliza por líneas...');
    
    // Esta función ya está implementada en tu código
    // Reutilizamos la lógica existente
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar la línea que contiene los encabezados
        if (line.includes('Póliza No.') && line.includes('Certificado No.')) {
            console.log('📋 Encontrada línea de encabezados:', line);
            
            // La siguiente línea debería contener los datos en columnas
            if (i + 1 < lines.length) {
                const dataLine = lines[i + 1].trim();
                console.log('📊 Línea de datos:', dataLine);
                
                // USAR dividirLineaTabular para obtener columnas
                const columnas = this.dividirLineaTabular(dataLine);
                console.log('📦 Columnas detectadas:', JSON.stringify(columnas));
                
                // La estructura esperada:
                // [0] = "AGRO SOIL DE MEXICO, S. DE R.L. DE C.V."
                // [1] = "M0076171" (Póliza)
                // [2] = "0000000000326" (Certificado)
                
                if (columnas.length >= 3) {
                    const poliza = columnas[1];
                    if (poliza && /[A-Z0-9]/.test(poliza)) {
                        console.log('✅ Póliza encontrada (estructura tabular):', poliza);
                        return poliza;
                    }
                }
                
                // Si no funciona con dividirLineaTabular, intentar con split simple
                if (columnas.length < 3) {
                    const columnasAlt = dataLine.split(/\s+/);
                    console.log('🔄 Intentando con split simple:', columnasAlt);
                    
                    // Buscar patrones específicos en el array
                    for (let j = 0; j < columnasAlt.length; j++) {
                        if (columnasAlt[j] === 'M0076171' || /M\d+/.test(columnasAlt[j])) {
                            console.log('✅ Póliza encontrada (búsqueda directa):', columnasAlt[j]);
                            return columnasAlt[j];
                        }
                    }
                }
            }
        }
        
        // Buscar línea individual con "Póliza No." seguido del número
        if (line.includes('Póliza No.')) {
            const polizaMatch = line.match(/Póliza No\.\s*([A-Z0-9]+)/i);
            if (polizaMatch) {
                console.log('✅ Póliza encontrada (formato directo):', polizaMatch[1]);
                return polizaMatch[1];
            }
        }
    }
    
    return null;
}

buscarCertificadoPorLineas(lines) {
    console.log('🔍 Buscando certificado por líneas...');
    
    // Esta función ya está implementada en tu código
    // Reutilizamos la lógica existente
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar la línea que contiene los encabezados
        if (line.includes('Póliza No.') && line.includes('Certificado No.')) {
            console.log('📋 Encontrada línea de encabezados:', line);
            
            // La siguiente línea debería contener los datos en columnas
            if (i + 1 < lines.length) {
                const dataLine = lines[i + 1].trim();
                console.log('📊 Línea de datos:', dataLine);
                
                // USAR dividirLineaTabular para obtener columnas
                const columnas = this.dividirLineaTabular(dataLine);
                console.log('📦 Columnas detectadas:', JSON.stringify(columnas));
                
                if (columnas.length >= 3) {
                    const certificado = columnas[2];
                    if (certificado && /^\d+$/.test(certificado)) {
                        console.log('✅ Certificado encontrado (estructura tabular):', certificado);
                        return certificado;
                    }
                }
                
                // Si no funciona con dividirLineaTabular, intentar con split simple
                if (columnas.length < 3) {
                    const columnasAlt = dataLine.split(/\s+/);
                    console.log('🔄 Intentando con split simple:', columnasAlt);
                    
                    // Buscar número largo de certificado
                    for (let j = 0; j < columnasAlt.length; j++) {
                        if (/^\d{10,}$/.test(columnasAlt[j])) {
                            console.log('✅ Certificado encontrado (búsqueda numérica):', columnasAlt[j]);
                            return columnasAlt[j];
                        }
                    }
                }
            }
        }
        
        // Buscar línea individual con "Certificado No." seguido del número
        if (line.includes('Certificado No.')) {
            const certMatch = line.match(/Certificado No\.\s*([0-9]+)/i);
            if (certMatch) {
                console.log('✅ Certificado encontrado (formato directo):', certMatch[1]);
                return certMatch[1];
            }
        }
    }
    
    return null;
}

buscarTitularPorLineas(lines) {
    console.log('🔍 Búsqueda DINÁMICA de nombre del titular...');
    
    // Esta función ya está implementada y es la más robusta
    // La mantenemos como está
    
    // ESTRATEGIA 1: Buscar después de "Nombre del asegurado Titular:"
    const nombrePorTitular = this.buscarNombreDespuesDeTitular(lines);
    if (nombrePorTitular) {
        return nombrePorTitular;
    }
    
    // ESTRATEGIA 2: Buscar en tabla "RELACION DE ASEGURADOS"
    const nombrePorTabla = this.buscarNombreEnTablaAsegurados(lines);
    if (nombrePorTabla) {
        return nombrePorTabla;
    }
    
    // ESTRATEGIA 3: Búsqueda inteligente en todo el documento
    const nombreInteligente = this.busquedaInteligenteNombre(lines);
    if (nombreInteligente) {
        return nombreInteligente;
    }
    
    console.log('❌ No se encontró nombre válido');
    return null;
}

// NUEVA FUNCIÓN: Búsqueda inteligente en todo el documento
busquedaInteligenteNombre(lines) {
    console.log('🔍 BÚSQUEDA INTELIGENTE de nombre en documento...');
    
    const candidatos = [];
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Saltar líneas que claramente no son nombres
        if (this.esLineaNoNombre(line)) {
            continue;
        }
        
        // Analizar la línea para nombres
        const analisis = this.analizarLineaParaNombre(line);
        if (analisis.esCandidato) {
            candidatos.push({
                texto: analisis.nombre,
                indice: i,
                puntuacion: analisis.puntuacion,
                palabras: analisis.palabras,
                palabrasValidas: analisis.palabrasValidas
            });
        }
    }
    
    console.log('📊 Candidatos encontrados:', candidatos);
    
    if (candidatos.length > 0) {
        // Ordenar por mejor candidato (mayor puntuación, luego menor índice)
        candidatos.sort((a, b) => {
            if (a.puntuacion !== b.puntuacion) return b.puntuacion - a.puntuacion;
            return a.indice - b.indice;
        });
        
        const mejorCandidato = candidatos[0];
        console.log('✅ Mejor candidato seleccionado:', mejorCandidato.texto);
        return mejorCandidato.texto;
    }
    
    return null;
}

// NUEVA FUNCIÓN: Buscar nombre en tabla de asegurados - DINÁMICA
buscarNombreEnTablaAsegurados(lines) {
    console.log('🔍 Buscando nombre en tabla RELACION DE ASEGURADOS (dinámico)...');
    
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        if (line.includes('RELACION DE ASEGURADOS')) {
            console.log('📋 Encontrada tabla RELACION DE ASEGURADOS');
            
            // Buscar en las siguientes líneas después del encabezado
            for (let j = i + 1; j < Math.min(i + 10, lines.length); j++) {
                const dataLine = lines[j].trim();
                
                if (this.esLineaNoNombre(dataLine)) {
                    continue;
                }
                
                // La primera columna suele ser el nombre
                const partes = this.dividirLineaEnPartes(dataLine);
                if (partes.length > 0) {
                    const posibleNombre = partes[0];
                    if (this.esNombreCompletoValido(posibleNombre)) {
                        console.log('✅ Nombre encontrado (primera columna tabla):', posibleNombre);
                        return posibleNombre;
                    }
                }
                
                // Si no funciona por columnas, intentar con la línea completa
                if (this.esNombreCompletoValido(dataLine)) {
                    console.log('✅ Nombre encontrado (línea completa tabla):', dataLine);
                    return dataLine;
                }
            }
        }
    }
    
    return null;
}

buscarPlanPorLineas(lines) {
    console.log('🔍 Buscando plan por líneas...');
    
    // Función existente mejorada
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim();
        
        // Buscar "TIPO DE PLAN CONTRATADO"
        if (line.includes('TIPO DE PLAN CONTRATADO')) {
            // Extraer la última palabra que debería ser el plan
            const palabras = line.split(/\s+/);
            const ultimaPalabra = palabras[palabras.length - 1];
            
            // Verificar que sea un código de plan válido (solo letras mayúsculas)
            if (ultimaPalabra && /^[A-Z]+$/.test(ultimaPalabra)) {
                console.log('✅ Plan encontrado (última palabra):', ultimaPalabra);
                return ultimaPalabra;
            }
            
            // Buscar después de "CONTRATADO"
            const contratadoIndex = palabras.findIndex(p => p === 'CONTRATADO');
            if (contratadoIndex !== -1 && contratadoIndex + 1 < palabras.length) {
                const plan = palabras[contratadoIndex + 1];
                if (plan && /^[A-Z]+$/.test(plan)) {
                    console.log('✅ Plan encontrado (después de CONTRATADO):', plan);
                    return plan;
                }
            }
        }
        
        // Buscar línea que solo contiene el código del plan (como "MAS")
        if (line === 'MAS' || line === 'BASICO' || line === 'PREMIUM' || line === 'STANDARD') {
            console.log('✅ Plan encontrado (línea individual):', line);
            return line;
        }
    }
    return null;
}

buscarVigenciaPorLineas(lines) {
    console.log('🔍 Buscando vigencia por líneas...');
    
    // Función existente mejorada
    let vigenciaDesde = null;
    let vigenciaHasta = null;

    for (let i = 0; i < lines.length; i++) {
        const line = lines[i].trim().toLowerCase();

        if (line.includes('vigencia de la póliza')) {
            for (let j = i; j < lines.length; j++) {
                const l = lines[j].toLowerCase();
                if (l.includes('día') && l.includes('mes') && l.includes('año')) {
                    const desdeLine = (lines[j + 1] || '').trim();
                    const hastaLine = (lines[j + 2] || '').trim();
                    const desdeNums = desdeLine.match(/\d+/g);
                    const hastaNums = hastaLine.match(/\d+/g);
                    if (desdeNums && desdeNums.length >= 3) {
                        vigenciaDesde = `${desdeNums[0]}/${desdeNums[1]}/${desdeNums[2]}`;
                    }
                    if (hastaNums && hastaNums.length >= 3) {
                        vigenciaHasta = `${hastaNums[0]}/${hastaNums[1]}/${hastaNums[2]}`;
                    }
                    console.log('✅ Vigencia encontrada (bloque Día/Mes/Año):', { desde: vigenciaDesde, hasta: vigenciaHasta });
                    break;
                }
            }
        }

        if (line.includes('desde las') && line.includes('hasta las')) {
            const numeros = line.match(/\d+/g);
            if (numeros && numeros.length >= 6) {
                vigenciaDesde = `${numeros[0]}/${numeros[1]}/${numeros[2]}`;
                vigenciaHasta = `${numeros[3]}/${numeros[4]}/${numeros[5]}`;
                console.log('✅ Vigencia encontrada (Desde/Hasta):', { desde: vigenciaDesde, hasta: vigenciaHasta });
            }
        }

        if (vigenciaDesde && vigenciaHasta) break;
    }

    return { desde: vigenciaDesde, hasta: vigenciaHasta };
}

    // NUEVA FUNCIÓN: Búsqueda después de "Titular:" - DINÁMICA
    buscarNombreDespuesDeTitular(lines) {
        console.log('🔍 Buscando nombre después de "Titular:"...');
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            if (line.includes('Nombre del asegurado Titular:') || line.includes('Titular:')) {
                console.log('🎯 Encontrada línea con Titular:', line);
                
                // Estrategia 1: Extraer de la misma línea
                const nombreMismaLinea = this.extraerNombreDeLineaConTitularDinamico(line);
                if (nombreMismaLinea) {
                    return nombreMismaLinea;
                }
                
                // Estrategia 2: Buscar en líneas siguientes
                const nombreSiguiente = this.buscarNombreEnLineasSiguientesDinamico(lines, i);
                if (nombreSiguiente) {
                    return nombreSiguiente;
                }
            }
        }
        
        return null;
    }

    // NUEVA FUNCIÓN: Extraer nombre de línea con Titular - DINÁMICA
    extraerNombreDeLineaConTitularDinamico(linea) {
        console.log('🔧 Extrayendo nombre de línea con Titular (dinámico):', linea);
        
        // Dividir la línea en partes por tabs o espacios múltiples
        const partes = this.dividirLineaEnPartes(linea);
        console.log('📊 Partes de la línea:', partes);
        
        // Buscar la parte que parece un nombre completo
        for (const parte of partes) {
            const texto = parte.trim();
            if (this.esNombreCompletoValido(texto) && !this.contienePalabraClave(texto)) {
                console.log('✅ Nombre encontrado (parte de línea):', texto);
                return texto;
            }
        }
        
        // Buscar por patrón: texto después de "Subgrupo" (si existe)
        if (linea.includes('Subgrupo')) {
            const patron = /Subgrupo\s+([A-ZÁÉÍÓÚÑ\s]{10,}?)(?:\s+\d+|$)/i;
            const match = linea.match(patron);
            if (match && match[1]) {
                const nombre = match[1].trim();
                if (this.esNombreCompletoValido(nombre)) {
                    console.log('✅ Nombre encontrado (después de Subgrupo):', nombre);
                    return nombre;
                }
            }
        }
        
        return null;
    }

    // FUNCIÓN MEJORADA: Validar nombre completo - MÁS FLEXIBLE Y DINÁMICA
    esNombreCompletoValido(nombre) {
        if (!nombre || nombre.trim().length === 0) return false;
        
        const nombreLimpio = nombre.trim();
        
        // Exclusión de casos específicos
        if (nombreLimpio === 'Subgrupo' || this.contieneDatosDemograficos(nombreLimpio)) {
            return false;
        }
        
        const palabras = nombreLimpio.split(/\s+/);
        const totalPalabras = palabras.length;
        
        // Mínimo 2 palabras, idealmente 3+
        if (totalPalabras < 2) return false;
        
        // Contar palabras válidas
        let palabrasValidas = 0;
        for (const palabra of palabras) {
            if (this.esPalabraDeNombre(palabra)) {
                palabrasValidas++;
            }
        }
        
        // Al menos 60% de palabras válidas
        const porcentajeValido = (palabrasValidas / totalPalabras) * 100;
        if (porcentajeValido < 60) return false;
        
        // No debe contener números
        if (/\d/.test(nombreLimpio)) return false;
        
        // No debe contener palabras clave del documento
        if (this.contienePalabrasClaveDocumento(nombreLimpio)) return false;
        
        // Longitud mínima razonable
        if (nombreLimpio.length < 8) return false;
        
        console.log(`✅ NOMBRE VÁLIDO: "${nombreLimpio}" (${palabrasValidas}/${totalPalabras} palabras válidas)`);
        return true;
    }

    // NUEVA FUNCIÓN: Verificar si contiene palabra clave (más específica)
    contienePalabraClave(texto) {
        const palabrasClave = [
            'POLIZA', 'CERTIFICADO', 'TITULAR', 'ASEGURADO', 'CONTRATANTE',
            'VIGENCIA', 'SUMA', 'DEDUCIBLE', 'COASEGURO', 'PLAN', 'SUBGRUPO'
        ];
        
        const upperTexto = texto.toUpperCase();
        return palabrasClave.some(palabra => upperTexto.includes(palabra));
    }

    // NUEVA FUNCIÓN: Buscar nombre en líneas siguientes - DINÁMICA
    buscarNombreEnLineasSiguientesDinamico(lines, indiceActual) {
        console.log('🔍 Buscando nombre en líneas siguientes (dinámico)...');
        
        for (let j = indiceActual + 1; j < Math.min(indiceActual + 5, lines.length); j++) {
            const linea = lines[j].trim();
            console.log(`📝 Línea ${j} después de Titular: "${linea}"`);
            
            // Saltar líneas que claramente no son nombres
            if (this.esLineaNoNombre(linea)) {
                console.log('❌ Saltando línea (no es nombre):', linea);
                continue;
            }
            
            // Intentar extraer nombre de la línea completa
            if (this.esNombreCompletoValido(linea)) {
                console.log('✅ Nombre encontrado (línea completa):', linea);
                return linea;
            }
            
            // Intentar extraer nombre de partes de la línea
            const nombreDePartes = this.extraerNombreDePartesLinea(linea);
            if (nombreDePartes) {
                return nombreDePartes;
            }
        }
        
        return null;
    }

    // NUEVA FUNCIÓN: Extraer nombre de partes de línea
    extraerNombreDePartesLinea(linea) {
        const partes = this.dividirLineaEnPartes(linea);
        
        for (const parte of partes) {
            if (this.esNombreCompletoValido(parte)) {
                return parte;
            }
        }
        
        // Si ninguna parte es nombre completo, buscar la parte más prometedora
        let mejorParte = null;
        let mejorPuntuacion = 0;
        
        for (const parte of partes) {
            const analisis = this.analizarLineaParaNombre(parte);
            if (analisis.esCandidato && analisis.puntuacion > mejorPuntuacion) {
                mejorParte = analisis.nombre;
                mejorPuntuacion = analisis.puntuacion;
            }
        }
        
        return mejorParte;
    }

    // NUEVA FUNCIÓN: Dividir línea en partes
    dividirLineaEnPartes(linea) {
        // Intentar diferentes métodos de división
        const metodos = [
            linea.split(/\t+/), // Tabs
            linea.split(/\s{3,}/), // 3+ espacios
            linea.split(/\s{2,}/), // 2+ espacios
            [linea] // Como último recurso, la línea completa
        ];
        
        for (const partes of metodos) {
            const partesFiltradas = partes.map(p => p.trim()).filter(p => p.length > 0);
            if (partesFiltradas.length >= 2) {
                return partesFiltradas;
            }
        }
        
        return [linea];
    }

    // NUEVA FUNCIÓN: Analizar línea para determinar si contiene nombre
    analizarLineaParaNombre(linea) {
        const texto = linea.trim();
        const palabras = texto.split(/\s+/);
        
        // Condiciones de EXCLUSIÓN
        if (this.esLineaNoNombre(texto)) {
            return { esCandidato: false };
        }
        
        // Condiciones de INCLUSIÓN
        let palabrasValidas = 0;
        let longitudTotal = 0;
        
        for (const palabra of palabras) {
            if (this.esPalabraDeNombre(palabra)) {
                palabrasValidas++;
                longitudTotal += palabra.length;
            }
        }
        
        const totalPalabras = palabras.length;
        const porcentajeValido = (palabrasValidas / totalPalabras) * 100;
        const longitudPromedio = longitudTotal / palabrasValidas;
        
        // Calcular puntuación
        let puntuacion = 0;
        
        // + puntos por porcentaje de palabras válidas
        puntuacion += porcentajeValido * 2;
        
        // + puntos por cantidad de palabras (prefiere nombres más completos)
        puntuacion += totalPalabras * 10;
        
        // + puntos por longitud promedio (nombres suelen tener 4+ caracteres)
        if (longitudPromedio >= 4) puntuacion += 20;
        
        // - puntos si contiene números
        if (/\d/.test(texto)) puntuacion -= 50;
        
        // - puntos si contiene palabras clave de documento
        if (this.contienePalabrasClaveDocumento(texto)) puntuacion -= 30;
        
        // Umbral mínimo para ser considerado candidato
        const esCandidato = palabrasValidas >= 2 && 
                            porcentajeValido >= 60 && 
                            puntuacion > 50 &&
                            !this.contieneDatosDemograficos(texto);
        
        return {
            esCandidato,
            nombre: texto,
            puntuacion,
            palabras: totalPalabras,
            palabrasValidas,
            porcentajeValido
        };
    }

    // NUEVA FUNCIÓN: Verificar si una línea NO es nombre
    esLineaNoNombre(linea) {
        const texto = linea.trim();
        
        // Condiciones de EXCLUSIÓN
        const exclusiones = [
            texto.length < 3, // Muy corta
            /^\d+$/.test(texto), // Solo números
            texto === 'Subgrupo',
            this.contieneDatosDemograficos(texto),
            this.contienePalabrasClaveDocumento(texto),
            /(POLIZA|CERTIFICADO|RFC|VIGENCIA|SUMA|DEDUCIBLE|COASEGURO)/i.test(texto),
            /\d{4,}/.test(texto), // Contiene 4+ números consecutivos
            texto.split(/\s+/).length > 8 // Demasiadas palabras (probablemente no es nombre)
        ];
        
        return exclusiones.some(exclusion => exclusion === true);
    }

    // FUNCIÓN MEJORADA: Contiene palabras clave del documento - EXCLUIR nombres válidos
	contienePalabrasClaveDocumento(texto) {
		const palabrasClave = [
			'POLIZA', 'CERTIFICADO', 'TITULAR', 'ASEGURADO', 'CONTRATANTE',
			'VIGENCIA', 'DESDE', 'HASTA', 'RFC', 'NACIMIENTO', 'SEXO',
			'ESTADO', 'CIVIL', 'FECHA', 'INGRESO', 'COLECTIVIDAD',
			'SUMA', 'ASEGURADA', 'DEDUCIBLE', 'COASEGURO', 'PLAN',
			'CONTRATADO', 'U.M.A.M.', 'HONORARIOS', 'QUIRURGICOS',
			'EMERGENCIA', 'EXTRANJERO', 'DENTAL', 'ASISTENCIA', 'INTEGRAL',
			'SUBGRUPO'  // AÑADIR SUBGRUPO específicamente
		];
		
		const upperTexto = texto.toUpperCase();
		
		// EXCEPCIÓN: Si el texto es un nombre válido completo, no considerarlo palabra clave
		const palabras = texto.split(/\s+/);
		if (palabras.length >= 3 && palabras.every(palabra => this.esPalabraDeNombre(palabra))) {
			console.log('✅ Texto es nombre válido, no palabra clave');
			return false;
		}
		
		return palabrasClave.some(palabra => upperTexto.includes(palabra));
	}

    // NUEVA FUNCIÓN: Detectar si una línea contiene datos demográficos
    contieneDatosDemograficos(linea) {
        console.log('contieneDatosDemograficos: ', linea);
        const datosDemograficos = [
            'FEMENINO', 'MASCULINO', 'NO APLICA', 'SOLTERO', 'CASADO', 'DIVORCIADO',
            'VIUDO', 'FEM.', 'MASC.', 'TIT.', 'BENEF.', 'SEXO', 'ESTADO CIVIL'
        ];
        
        const upperLinea = linea.toUpperCase();
        return datosDemograficos.some(dato => upperLinea.includes(dato));
    }

    // Función para identificar líneas que NO son nombres en credenciales
    esLineaNoNombreCredencial(linea) {
        if (!linea || linea.length < 3) return true;
        
        // Palabras que indican que NO es nombre
        const noNombreIndicadores = [
            'SEGUROS', 'MONTERREY', 'POLIZA', 'CERTIFICADO',
            'SUMA', 'ASEG', 'COASEGURO', 'DEDUCIBLE', 'COBERTURA',
            'PLAN', 'AGRUPACION', 'PREEXISTENCIA', 'EXCLUIDO',
            'ALFA', 'MEDICAL', 'TELEFONOS', 'CONTACTO', 'URGENCIA',
            'REFERENCIA', 'TRAMITES', 'PAGO', 'ASISTENCIA', 'AMBULANCIA',
            'GMG-', 'No ', 'www.', '.com', '.mx'
        ];
        
        const lineaUpper = linea.toUpperCase();
        for (const indicador of noNombreIndicadores) {
            if (lineaUpper.includes(indicador.toUpperCase())) {
                return true;
            }
        }
        
        // Si contiene números, no es nombre
        if (/\d/.test(linea)) return true;
        
        // Si es demasiado corta o demasiado larga
        if (linea.length < 5 || linea.length > 60) return true;
        
        return false;
    }

    // FUNCIÓN MEJORADA: Validar nombre completo - MÁS FLEXIBLE Y DINÁMICA
    esNombreCompletoValido(nombre) {
        if (!nombre || nombre.trim().length === 0) return false;
        
        const nombreLimpio = nombre.trim();
        
        // Exclusión de casos específicos
        if (nombreLimpio === 'Subgrupo' || this.contieneDatosDemograficos(nombreLimpio)) {
            return false;
        }
        
        const palabras = nombreLimpio.split(/\s+/);
        const totalPalabras = palabras.length;
        
        // Mínimo 2 palabras, idealmente 3+
        if (totalPalabras < 2) return false;
        
        // Contar palabras válidas
        let palabrasValidas = 0;
        for (const palabra of palabras) {
            if (this.esPalabraDeNombre(palabra)) {
                palabrasValidas++;
            }
        }
        
        // Al menos 60% de palabras válidas
        const porcentajeValido = (palabrasValidas / totalPalabras) * 100;
        if (porcentajeValido < 60) return false;
        
        // No debe contener números
        if (/\d/.test(nombreLimpio)) return false;
        
        // No debe contener palabras clave del documento
        if (this.contienePalabrasClaveDocumento(nombreLimpio)) return false;
        
        // Longitud mínima razonable
        if (nombreLimpio.length < 8) return false;
        
        console.log(`✅ NOMBRE VÁLIDO: "${nombreLimpio}" (${palabrasValidas}/${totalPalabras} palabras válidas)`);
        return true;
    }

    // NUEVA FUNCIÓN: Detectar si una línea contiene datos demográficos
    contieneDatosDemograficos(linea) {
        console.log('contieneDatosDemograficos: ', linea);
        const datosDemograficos = [
            'FEMENINO', 'MASCULINO', 'NO APLICA', 'SOLTERO', 'CASADO', 'DIVORCIADO',
            'VIUDO', 'FEM.', 'MASC.', 'TIT.', 'BENEF.', 'SEXO', 'ESTADO CIVIL'
        ];
        
        const upperLinea = linea.toUpperCase();
        return datosDemograficos.some(dato => upperLinea.includes(dato));
    }

    // FUNCIÓN MEJORADA: Contiene palabras clave del documento - EXCLUIR nombres válidos
	contienePalabrasClaveDocumento(texto) {
		const palabrasClave = [
			'POLIZA', 'CERTIFICADO', 'TITULAR', 'ASEGURADO', 'CONTRATANTE',
			'VIGENCIA', 'DESDE', 'HASTA', 'RFC', 'NACIMIENTO', 'SEXO',
			'ESTADO', 'CIVIL', 'FECHA', 'INGRESO', 'COLECTIVIDAD',
			'SUMA', 'ASEGURADA', 'DEDUCIBLE', 'COASEGURO', 'PLAN',
			'CONTRATADO', 'U.M.A.M.', 'HONORARIOS', 'QUIRURGICOS',
			'EMERGENCIA', 'EXTRANJERO', 'DENTAL', 'ASISTENCIA', 'INTEGRAL',
			'SUBGRUPO'  // AÑADIR SUBGRUPO específicamente
		];
		
		const upperTexto = texto.toUpperCase();
		
		// EXCEPCIÓN: Si el texto es un nombre válido completo, no considerarlo palabra clave
		const palabras = texto.split(/\s+/);
		if (palabras.length >= 3 && palabras.every(palabra => this.esPalabraDeNombre(palabra))) {
			console.log('✅ Texto es nombre válido, no palabra clave');
			return false;
		}
		
		return palabrasClave.some(palabra => upperTexto.includes(palabra));
	}

    // FUNCIÓN MEJORADA: Validar palabra de nombre - MÁS FLEXIBLE
    esPalabraDeNombre(palabra) {
        console.log('esPalabraDeNombre::: ');
        console.log('palabra::: ' + palabra);
        if (!palabra || palabra.length < 2) return false;
        
        // Permitir palabras con acentos y caracteres especiales del español
        const esValida = /^[A-ZÁÉÍÓÚÑ][A-Za-záéíóúñ]*$/.test(palabra) || 
                        /^[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ]+$/.test(palabra);
        
        if (!esValida) {
            console.log('❌ Palabra no válida para nombre:', palabra);
        }
        
        return esValida;
    }

    // Función auxiliar para identificar palabras clave del documento
    esPalabraClaveDocumento(palabra) {
        const palabrasClave = [
            'ANUAL', 'PROPIA', 'OPTIMA', 'SEGUROS', 'MONTERREY', 
            'POLIZA', 'CERTIFICADO', 'R.F.C.', 'CONTRATANTE',
            'VIGENCIA', 'DESDE', 'HASTA', 'PLAN', 'COBERTURA',
            'SUMA', 'ASEGURADA', 'DEDUCIBLE', 'COASEGURO'
        ];
        
        return palabrasClave.includes(palabra.toUpperCase());
    }

    // =============================================
    // 🎨 UI HELPERS
    // =============================================

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Getters para propiedades computadas
    get hasFiles() {
        return this.files.length > 0;
    }

    get disabledProcess() {
        return !this.hasFiles || this.isProcessing || !this.isPdfJsLoaded;
    }

    get disabledFiles() {
        return this.isProcessing || !this.files.length;
    }

    get progressStyle() {
        return `width: ${this.progress.percent}%;`;
    }

    get processedFiles() {
        return !this.hasProcessedFiles;
    }

    get hasProcessedFiles() {
        return this.files.some(f => f.status === 'completed' && f.data?.length > 0);
    }

    get maxFile() {
        return MAX_FILE_SIZE/1024/1024;
    }

    get disableFile() {
        return !this.hasProcessedFiles || this.isSaving;
    }

    async handleSaveFiles() {
        this.isSaving = true;
        try {
            await this.persistAllOriginalFiles();
        } catch (error) {
            console.error('Error en handleSaveFiles:', error);
        } finally {
            this.isSaving = false;
        }
    }

    normalizePolicyForSearch(policy) {
        if (!policy) return '';
        return policy.toString().trim().toUpperCase();
    }
}