import { LightningElement } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import PDFJS_LEGACY from '@salesforce/resourceUrl/pdfjs_legacy';

export default class MinimalPdf extends LightningElement {
    async connectedCallback() {
        try {
            await loadScript(this, PDFJS_LEGACY + '/pdf.js');
            console.log('PDF.js cargado:', window.PDFJS);
        } catch (error) {
            console.error('Error final:', error);
        }
    }
}