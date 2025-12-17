import { LightningElement, track } from 'lwc';
import uploadPDF from '@salesforce/apex/PdfProcessor.uploadPDF';

export default class PdfProcessor extends LightningElement {

    @track uploadMessages = [];
    isUploading = false;

    handleFileChange(event) {
        const files = event.target.files;
        if (!files || files.length === 0) return;

        [...files].forEach(file => {
            if (file.type !== "application/pdf") {
                this.uploadMessages.push({
                    id: Date.now(),
                    text: `❌ ${file.name} no es un PDF válido`
                });
                return;
            }
            this.readAndUpload(file);
        });
    }

    readAndUpload(file) {
        this.isUploading = true;

        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1]; // quitar encabezado data:application/pdf...

            uploadPDF({ fileName: file.name, base64File: base64 })
                .then(result => {
                    this.uploadMessages.push({
                        id: Date.now(),
                        text: `✔️ ${file.name} cargado correctamente. ContentVersionId: ${result}`
                    });
                })
                .catch(error => {
                    console.error(error);
                    this.uploadMessages.push({
                        id: Date.now(),
                        text: `❌ Error al cargar ${file.name}: ${error.body ? error.body.message : error}`
                    });
                })
                .finally(() => {
                    this.isUploading = false;
                });
        };

        reader.readAsDataURL(file);
    }
}
