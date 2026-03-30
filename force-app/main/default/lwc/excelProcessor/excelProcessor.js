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

        try {
            // Leer el archivo como ArrayBuffer para tener control de codificación
            const arrayBuffer = await this.readFileAsArrayBuffer(file);
            
            // Intentar decodificar con diferentes codificaciones
            let content = this.decodeWithMultipleEncodings(arrayBuffer);
            
            console.log('Archivo leído, contenido:', content.substring(0, 200));
            
            const processedData = this.processFileContent(content, fileExtension);
            this.excelData = processedData;
            this.processResult = this.prepareSimpleData(this.excelData);
            console.log('Registros procesados:', JSON.stringify(this.processResult));
            this.showResults = true;
            this.isLoading = false;
            
            if (this.processResult && this.processResult.length > 0) {
                this.showToast('Éxito', 'Archivo procesado correctamente. ' + this.processResult.length + ' registros encontrados.', 'success');
            } else {
                this.showToast('Advertencia', 'El archivo se procesó pero no se encontraron datos válidos.', 'warning');
            }
            
        } catch (error) {
            this.isLoading = false;
            console.error('Error procesando archivo:', error);
            this.showToast('Error', 'Error procesando archivo: ' + error.message, 'error');
        }
    }

    // Leer archivo como ArrayBuffer
    readFileAsArrayBuffer(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = reject;
            reader.readAsArrayBuffer(file);
        });
    }

    // Decodificar con múltiples codificaciones
    decodeWithMultipleEncodings(arrayBuffer) {
        // Lista de codificaciones a intentar en orden
        const encodings = ['UTF-8', 'ISO-8859-1', 'Windows-1252', 'Latin1'];
        
        for (const encoding of encodings) {
            try {
                const decoder = new TextDecoder(encoding, { fatal: false });
                const decoded = decoder.decode(arrayBuffer);
                
                // Verificar si la decodificación parece correcta (sin caracteres de reemplazo)
                if (!decoded.includes('�') && this.hasSpanishCharacters(decoded)) {
                    console.log(`✅ Decodificado correctamente con ${encoding}`);
                    return decoded;
                }
            } catch (e) {
                console.log(`❌ Error decodificando con ${encoding}:`, e);
            }
        }
        
        // Si ninguna funciona, intentar con UTF-8 por defecto
        console.log('⚠️ Usando UTF-8 por defecto');
        return new TextDecoder('UTF-8').decode(arrayBuffer);
    }

    // Verificar si el texto tiene caracteres españoles
    hasSpanishCharacters(text) {
        const spanishPattern = /[ñÑáéíóúÁÉÍÓÚüÜ¡¿]/;
        return spanishPattern.test(text);
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

    // ✅ MÉTODO CORREGIDO: Validación de email que acepta caracteres internacionales (incluyendo ñ)
    validarEmail(email) {
        if (!email || typeof email !== 'string') return false;
        
        console.log('🔍 Validando email:', email);
        
        // 1. Eliminar espacios al inicio y final
        email = email.trim();
        
        // 2. Verificar que no tenga espacios internos (excepto si está entre comillas, pero eso es raro)
        if (email.includes(' ') && !email.includes('"')) {
            console.log('❌ Email contiene espacios sin estar entre comillas:', email);
            return false;
        }
        
        // 3. Verificar estructura básica
        const partes = email.split('@');
        if (partes.length !== 2) {
            console.log('❌ Email no tiene exactamente un @:', email);
            return false;
        }
        
        const [local, dominio] = partes;
        
        // 4. Verificar que local y dominio no estén vacíos
        if (!local || local.length === 0) {
            console.log('❌ Parte local del email vacía:', email);
            return false;
        }
        
        if (!dominio || dominio.length === 0) {
            console.log('❌ Dominio del email vacío:', email);
            return false;
        }
        
        // 5. Verificar que el dominio tenga al menos un punto
        if (!dominio.includes('.')) {
            console.log('❌ Dominio no contiene punto:', email);
            return false;
        }
        
        // 6. Verificar que la extensión del dominio sea válida (al menos 2 caracteres)
        const partesDominio = dominio.split('.');
        const extension = partesDominio[partesDominio.length - 1];
        if (extension.length < 2) {
            console.log('❌ Extensión del dominio muy corta:', email);
            return false;
        }
        
        // 7. ✅ CORRECCIÓN: Validación que acepta caracteres internacionales (incluyendo ñ, á, é, etc.)
        // Regex mejorada que acepta caracteres Unicode (incluyendo ñ)
        const emailRegex = /^[a-zA-Z0-9À-ÿ._%+-]+@[a-zA-Z0-9À-ÿ.-]+\.[a-zA-Z]{2,}$/;
        
        // Versión alternativa más permisiva:
        // const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        
        if (!emailRegex.test(email)) {
            console.log('❌ Email no pasa validación regex:', email);
            return false;
        }
        
        console.log('✅ Email válido (acepta ñ):', email);
        return true;
    }

    // ✅ NUEVO MÉTODO: Limpiar y normalizar email
    limpiarEmail(email) {
        if (!email || typeof email !== 'string') return '';
        
        // 1. Eliminar espacios al inicio y final
        let limpio = email.trim();
        
        // 2. Convertir a minúsculas (opcional)
        limpio = limpio.toLowerCase();
        
        // 3. Eliminar espacios internos
        limpio = limpio.replace(/\s+/g, '');
        
        // 4. Eliminar caracteres especiales problemáticos al inicio/final
        limpio = limpio.replace(/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$/g, '');
        
        // 5. Verificar estructura básica
        const partes = limpio.split('@');
        if (partes.length !== 2) {
            return 'XxxCorreoXx@correo.com'; // Correo por defecto si no es válido
        }
        
        return limpio;
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

    // ✅ MÉTODO MODIFICADO: Preparar datos con validación mejorada de email
    prepareSimpleData(data) {
        return data.map((row, index) => {
            let emailOriginal = String(row.INT_EMAIL || '');
            let email = '';
            
            console.log(`\n--- Procesando registro ${index + 1} ---`);
            console.log('Email original:', emailOriginal);
            
            // Si el email está vacío o es undefined/null
            if (!emailOriginal || emailOriginal.trim() === '' || 
                emailOriginal.toLowerCase() === 'null' || 
                emailOriginal.toLowerCase() === 'undefined' ||
                emailOriginal.toLowerCase() === 'sin email' ||
                emailOriginal.toLowerCase() === 'no tiene') {
                console.log('📭 Email vacío o inválido, usando correo por defecto');
                email = 'XxxCorreoXx@correo.com';
            } 
            // Si tiene contenido
            else {
                // Limpiar el email primero (preserva ñ)
                email = this.limpiarEmail(emailOriginal);
                
                // Validar el email limpio
                const esValido = this.validarEmail(email);
                
                if (!esValido) {
                    console.log(`❌ Email inválido: "${emailOriginal}" → Reemplazando por XxxCorreoXx@correo.com`);
                    email = 'XxxCorreoXx@correo.com';
                } else {
                    console.log(`✅ Email válido y preservado: "${email}"`);
                }
            }
            
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
                beneficiary: String(row.INT_BENEFI || ''),
                parently: String(row.PARENTESCO || row.INT_PARENT || ''),
                entryDate: String(row.INT_FINGPO || ''),
                email: email,
                emailOriginal: emailOriginal // ✅ Opcional: para debugging
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