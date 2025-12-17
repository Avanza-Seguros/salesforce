import { LightningElement, track, api } from 'lwc';
import processPDF from '@salesforce/apex/IDPController.processPDF';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import { getRecord } from 'lightning/uiRecordApi';

// ContentVersion fields
const CONTENT_VERSION_FIELDS = ['Id', 'Title', 'ContentDocumentId', 'VersionData', 'FileExtension', 'ContentSize'];

export default class IdpProcessor extends LightningElement {
    @api recordId;
    // Propiedades públicas configuradas en App Builder
    @api showHeader = false;
    @api maxFileSize = 10; // en MB
    @api defaultDocumentType = 'constancia';

    // Configuración
    MAX_SIZE_MB = 10;
    MAX_SIZE_BYTES = this.MAX_SIZE_MB * 1024 * 1024;
    
    // Variables de estado
    @track fileContent = null;
    @track fileName = '';
    @track isProcessing = false;
    @track processingMessage = '';
    @track processingTime = 0;
    
    // Configuración
    @track documentType = 'constancia';
    @track customFileName = '';
    @track extractTables = true;
    
    // Respuesta
    @track response = null;
    @track showResults = false;
    
    // Errores
    @track showError = false;
    @track errorTitle = '';
    @track errorMessage = '';
    
    // Opciones para combobox
    documentTypeOptions = [
        { label: 'Factura', value: 'invoice' },
        { label: 'Orden de Compra', value: 'purchase_order' },
        { label: 'Contrato', value: 'contract' },
        { label: 'Identificación', value: 'id' },
        { label: 'Recibo', value: 'receipt' },
        { label: 'Otro', value: 'other' }
    ];

    // Lifecycle hook - cuando el componente se conecta
    connectedCallback() {
        // Establecer el tipo de documento por defecto desde la propiedad
        this.documentType = this.defaultDocumentType;
    }

    // Manejar subida de archivo
    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        
        // Validar tipo de archivo
        if (file.type !== 'application/pdf') {
            this.showErrorToast('Error', 'Por favor, sube solo archivos PDF');
            return;
        }
        
        // Validar tamaño usando la propiedad configurada
        const maxSizeBytes = this.maxFileSize * 1024 * 1024;
        if (file.size > maxSizeBytes) {
            this.showErrorToast(
                'Error', 
                `El archivo es demasiado grande. Máximo permitido: ${this.maxFileSize}MB`
            );
            return;
        }
        
        this.fileName = file.name;
        console.log('Archivo seleccionado:', this.fileName);
        this.customFileName = file.name.replace('.pdf', '');
        console.log('Nombre de archivo personalizado:', this.customFileName);
        // Leer archivo como base64
        const reader = new FileReader();
        reader.onload = () => {
            
            const base64String = reader.result.split(',')[1];
            this.fileContent = base64String;
            this.fileName = this.customFileName + '.pdf';
            console.log('Contenido del archivo en base64:', this.fileContent);
            this.showSuccessToast('Archivo cargado', `${file.name} cargado exitosamente`);
            console.log('Contenido del archivo en base64 cargado');
        };
        
        reader.onerror = (error) => {
            this.showErrorToast('Error', 'No se pudo leer el archivo: ' + error.target.error);
            console.error('Error leyendo el archivo:', error.target.error);
        };
        
        reader.readAsDataURL(file);
    }

    // Limpiar archivo seleccionado
    clearFile() {
        this.fileContent = null;
        this.customFileName = '';
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) fileInput.value = '';
    }

    // Procesar PDF
    async processPDF() {
        console.log('Iniciando procesamiento de PDF...');
        console.log('Nombre de archivo:', this.fileName);
        if (!this.fileContent) {
            this.showErrorToast('Error', 'Primero selecciona un archivo PDF');
            return;
        }
        
        this.isProcessing = true;
        this.processingMessage = 'Enviando PDF al servidor...';
        this.showResults = false;
        this.showError = false;
        
        const startTime = Date.now();
        
        try {            
            this.processingMessage = 'Procesando PDF...';
            console.log('Contenido del archivo en base64:', this.fileContent);
            // Llamar al servicio Apex
            const result = await processPDF({
                pdfBase64: this.fileContent,
                fileName: this.fileName
            });
            console.log('Respuesta del servidor:', JSON.stringify(result));
            this.processingTime = ((Date.now() - startTime) / 1000).toFixed(2);
            
            if (result.success) {
                this.response = result;
                this.showResults = true;
                this.processingMessage = 'Procesamiento completado';
                
                this.showSuccessToast(
                    '¡Éxito!', 
                    `PDF procesado en ${this.processingTime} segundos`
                );
            } else {
                console.error('Error en respuesta del servidor:', result.errorMessage);
            }
        } catch (error) {
            console.error('Error procesando PDF:', error);
            console.error('Error Stack Trace:', error.stack);
            
        } finally {
            this.isProcessing = false;
            this.processingMessage = '';
        }
    }

    // Limpiar todo
    clearAll() {
        this.fileContent = null;
        this.fileName = '';
        this.customFileName = '';
        this.showResults = false;
        this.response = null;
        this.showError = false;
        this.documentType = this.defaultDocumentType;
        
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) fileInput.value = '';
    }

    // Mostrar error
    showErrorResult(title, message) {
        this.errorTitle = title;
        this.errorMessage = message;
        this.showError = true;
        this.showErrorToast(title, message);
    }

    // Limpiar error
    clearError() {
        this.showError = false;
        this.errorTitle = '';
        this.errorMessage = '';
    }

    // Getters computados
    get hasExtractedData() {
        return this.response && 
               this.response.extractedData && 
               Object.keys(this.response.extractedData).length > 0;
    }
    
    get hasMetadata() {
        return this.response && 
               this.response.metadata && 
               Object.keys(this.response.metadata).length > 0;
    }
    
    get formattedExtractedData() {
        return this.hasExtractedData 
            ? JSON.stringify(this.response.extractedData, null, 2)
            : 'No se extrajeron datos';
    }
    
    get formattedMetadata() {
        return this.hasMetadata
            ? JSON.stringify(this.response.metadata, null, 2)
            : 'No hay metadatos disponibles';
    }
    
    get formattedRawResponse() {
        return this.response 
            ? JSON.stringify(this.response.data || this.response, null, 2)
            : '';
    }
    
    // Helpers para Toast Messages
    showSuccessToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'success',
                mode: 'dismissable'
            })
        );
    }
    
    showErrorToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    // Manejar cambio de tipo de documento
    handleDocumentTypeChange(event) {
        this.documentType = event.target.value;
    }

    // Manejar cambio de nombre de archivo
    handleFileNameChange(event) {
        this.customFileName = event.target.value;
    }

    // Manejar cambio de extracción de tablas
    handleExtractTablesChange(event) {
        this.extractTables = event.target.checked;
    }

    get titleProcessButton() {
        return !this.fileContent ? 'Primero sube un archivo PDF' : '';
    }

    get classForStatus() {
        return this.log.Status__c === 'Success' ? 'slds-theme_success' : 'slds-theme_error';
    }

    get processButton() {
        return !this.fileContent || this.isProcessing;
    }
}