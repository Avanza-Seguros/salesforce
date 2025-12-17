import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processExcelData from '@salesforce/apex/ExcelProcessorController.processExcelData';

export default class ExcelProcessor extends LightningElement {
    @track isLoading = false;
    @track fileName = '';
    @track excelData = [];
    @track showResults = false;
    @track processResult = [];

    async handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        const validTypes = ['.csv', '.txt'];
        const fileExtension = file.name.toLowerCase().substring(file.name.lastIndexOf('.'));
        
        if (!validTypes.includes(fileExtension)) {
            this.showToast('Error', 'Por favor selecciona un archivo CSV o TXT', 'error');
            return;
        }

        this.fileName = file.name;
        this.isLoading = true;

        const reader = new FileReader();
        
        reader.onload = (e) => {
            try {
                const content = e.target.result;
                console.log('Archivo leído, contenido:', content.substring(0, 200));
                
                const processedData = this.processFileContent(content, fileExtension);
                this.excelData = processedData;
                this.processResult = this.prepareSimpleData(this.excelData);
                console.log('Registros procesados:', JSON.stringify(this.processResult)); // ✅ CORRECTO
                this.showResults = true;
                this.isLoading = false;
                
                if (this.processResult && this.processResult.length > 0) { // ✅ CORRECTO
                    this.showToast('Éxito', 'Archivo procesado correctamente. ' + this.processResult.length + 'registros encontrados.', 'success'); // ✅ CORRECTO
                } else {
                    this.showToast('Advertencia', 'El archivo se procesó pero no se encontraron datos válidos.', 'warning');
                }
                
            } catch (error) {
                this.isLoading = false;
                console.error('Error procesando archivo:', error);
                this.showToast('Error', 'Error procesando archivo: ' + error.message, 'error');
            }
        };

        reader.onerror = (error) => {
            this.isLoading = false;
            console.error('Error leyendo archivo:', error);
            this.showToast('Error', 'Error leyendo el archivo', 'error');
        };

        reader.readAsText(file, 'UTF-8');
    }

    processFileContent(content, fileExtension) {
        if (!content) return [];
        
        const lines = content.split('\n').filter(line => line.trim() !== '');
        console.log('Líneas encontradas:', lines.length); // ✅ CORRECTO
        
        if (lines.length < 2) { // ✅ CORRECTO
            throw new Error('El archivo debe contener al menos una línea de encabezados y una línea de datos');
        }

        const firstLine = lines[0];
        const separator = firstLine.includes('\t') ? '\t' : ',';
        console.log('Separador detectado:', separator === '\t' ? 'TAB' : 'COMA');

        const headers = this.parseLine(firstLine, separator);
        console.log('Número de encabezados:', headers.length); // ✅ CORRECTO

        const result = [];
        for (let i = 1; i < lines.length; i++) {
            const values = this.parseLine(lines[i], separator);
            
            if (values.length === headers.length) { // ✅ CORRECTO
                const rowData = {};
                for (let j = 0; j < headers.length; j++) { // ✅ CORRECTO
                    rowData[headers[j]] = String(values[j] || '').trim();
                }
                result.push(rowData);
            } else {
                console.warn(`Línea ${i} ignorada: ${values.length} valores vs ${headers.length} encabezados`); // ✅ CORRECTO
            }
        }

        return result;
    }

    parseLine(line, separator) {
        return line.split(separator)
            .map(cell => cell.trim()
                .replace(/^"(.*)"$/, '$1')
                .replace(/^'(.*)'$/, '$1')
                .replace(/\r/g, '')
            );
    }

    // Procesar todos los datos
    async processAllData() {
        console.log('DEBUG - excelData:', this.excelData);
        console.log('DEBUG - typeof excelData:', typeof this.excelData);
        
        // Verificar si es array
        if (Array.isArray(this.excelData)) {
            console.log('DEBUG - excelData.length:', this.excelData.length); // ✅ CORRECTO
        } else {
            console.error('DEBUG - excelData no es un array!');
        }

        if (!this.excelData || this.excelData.length === 0) { // ✅ CORRECTO
            this.showToast('Error', 'No hay datos para procesar', 'error');
            return;
        }

        this.isLoading = true;
        console.log('Total de registros a procesar:', this.excelData.length); // ✅ CORRECTO
        
        try {
            // Validar datos antes de enviar
            const validationResult = this.prepareSimpleData(this.excelData);
            
            const result = await processExcelData({ excelData: validationResult });
            console.log('Resultado del proceso:', JSON.stringify(result));
            
            this.showToast(
                'Proceso Completado', 
                `Se procesaron ${result.totalRecords} registros. ` +
                `Pólizas: ${result.policiesProcessed}, ` +
                `Casos: ${result.casesCreated}, ` +
                `Items: ${result.itemsCreated}`,
                'success'
            );
        } catch (error) {
            console.error('Error en processAllData:', error);
            this.handleError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // ✅ NUEVO MÉTODO: Validar datos antes de enviar a Apex
    validateExcelData(data) {
        const validatedData = [];
        const invalidRecords = [];
        
        data.forEach((record, index) => {
            // Verificar campos mínimos requeridos
            if (!record.INT_POLIZA || record.INT_POLIZA.trim() === '') {
                console.warn(`Registro ${index + 1} ignorado: sin número de póliza`);
                invalidRecords.push(index + 1);
                return;
            }
            
            // Verificar que el registro tenga al menos algún dato
            const hasData = Object.values(record).some(value => 
                value && value.toString().trim() !== ''
            );
            
            if (!hasData) {
                console.warn(`Registro ${index + 1} ignorado: todos los campos vacíos`);
                invalidRecords.push(index + 1);
                return;
            }
            
            // Limpiar el registro
            const cleanedRecord = {};
            Object.keys(record).forEach(key => {
                let value = record[key];
                
                // Convertir a string y limpiar
                if (value !== null && value !== undefined) {
                    value = value.toString().trim();
                    
                    // Convertir vacíos a null
                    if (value === '' || value === 'null' || value === 'undefined') {
                        value = null;
                    }
                } else {
                    value = null;
                }
                
                cleanedRecord[key] = value;
            });
            
            validatedData.push(cleanedRecord);
        });
        
        console.log(`Validación: ${validatedData.length} válidos, ${invalidRecords.length} inválidos`);
        
        return {
            validatedData,
            invalidRecords,
            totalRecords: data.length
        };
    }

    // Preparar datos en formato simple para evitar problemas de tipo
    prepareSimpleData(data) {
        return data.map(row => {
            return {
                policy: String(row.INT_POLIZA || ''),
                certificate: String(row.INT_CERTIF || ''),
                category: String(row.INT_CATEGO || ''),
                fatherLastName: String(row.INT_PATERN || ''),
                motherLastName: String(row.INT_MATERN || ''),
                firstName: String(row.INT_NOMBRE || ''),
                birthDate: String(row.INT_FNACIM || ''),
                certificateDate: String(row.INT_FINGEM || ''),
                gender: String(row.INT_SEXO || ''),
                beneficiary: String (row.INT_BENEFI || ''),
                parently: String(row.PARENTESCO || row.INT_PARENT || ''),
                entryDate: String(row.INT_FINGPO || ''),
                email: String(row.INT_EMAIL || 'XxxCorreoXx@correo.com')
            };
        });
    }

    // Obtener resumen de pólizas
    getPolicyCount(data) {
        const policyMap = {};
        data.forEach(row => {
            const policyNumber = row.INT_POLIZA;
            if (policyNumber) {
                policyMap[policyNumber] = (policyMap[policyNumber] || 0) + 1;
            }
        });
        return policyMap;
    }

    resetForm() {
        this.excelData = [];
        this.fileName = '';
        this.showResults = false;
        this.processResult = null;
        
        const fileInput = this.template.querySelector('input[type="file"]');
        if (fileInput) fileInput.value = '';
    }

    handleError(error) {
        console.error('Error:', error);
        const errorMessage = error.body?.message || error.message || 'Error procesando la solicitud';
        this.showToast('Error', errorMessage, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get policySummary() {
        if (!this.excelData || this.excelData.length === 0) return []; // ✅ CORRECTO
        
        const policyCount = this.getPolicyCount(this.excelData);
        return Object.keys(policyCount).map(policyNumber => ({
            policyNumber: policyNumber,
            recordCount: this.excelData.length
        }));
    }

    get hasProcessResult() {
        return this.showResults = true;
    }

    // ✅ NUEVO GETTER: Para verificar si hay datos de Excel
    get hasExcelData() {
        return this.excelData && this.excelData.length > 0; // ✅ CORRECTO
    }
    
    // ✅ NUEVO GETTER: Para mostrar estadísticas
    get statistics() {
        if (!this.hasExcelData) return null;
        
        return {
            totalRecords: this.excelData.length, // ✅ CORRECTO
            uniquePolicies: Object.keys(this.getPolicyCount(this.excelData)).length,
            sampleData: this.excelData.slice(0, 3) // Primeros 3 registros
        };
    }

    get registrosTotales() {
        return this.result.totalRecords;
    }

    get polizasEncontradas() {
        return this.result.policiesProcessed;
    }

    get casosEncontradss() {
        return this.result.casesCreated;
    }
}