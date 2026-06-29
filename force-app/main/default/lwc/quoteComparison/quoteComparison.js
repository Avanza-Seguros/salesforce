import { LightningElement, api, wire, track } from 'lwc';
import getQuotes from '@salesforce/apex/QuoteComparisonController.getQuotes';

export default class QuoteComparison extends LightningElement {

    @api recordId; // Opportunity Id

    @track quotes = [];

    @wire(getQuotes, { opportunityId: '$recordId' })
    wiredQuotes({ data, error }) {
        if (data) {
            this.quotes = data;
        } else if (error) {
            console.error(error);
        }
    }

    get hasQuotes() {
        return this.quotes.length > 0;
    }

    handleSelect(event) {
        const selectedId = event.target.dataset.id;

        // aquí puedes:
        // - marcar quote como ganador
        // - llamar Apex
        console.log('Seleccionado:', selectedId);
    }
}