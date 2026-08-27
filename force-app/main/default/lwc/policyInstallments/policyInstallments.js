import { LightningElement, api, wire } from 'lwc';
import getInstallmentsByPolicy from '@salesforce/apex/PolicyInstallmentsController.getInstallmentsByPolicy';

const COLUMNS = [
    {
        label: 'Cuota',
        fieldName: 'installmentUrl',
        type: 'url',
        initialWidth: 110,
        typeAttributes: { label: { fieldName: 'sequenceLabel' }, target: '_self' }
    },
    { label: 'Plan', fieldName: 'planName', type: 'text', initialWidth: 130 },
    { label: 'Vence', fieldName: 'dueDate__c', type: 'date-local', initialWidth: 110 },
    {
        label: 'Esperado',
        fieldName: 'expectedAmount__c',
        type: 'currency',
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Conciliado',
        fieldName: 'matchedAmount__c',
        type: 'currency',
        cellAttributes: { alignment: 'right' }
    },
    {
        label: 'Pendiente',
        fieldName: 'outstandingAmount__c',
        type: 'currency',
        cellAttributes: { alignment: 'right' }
    },
    { label: 'Estado', fieldName: 'installmentStatus__c', type: 'text', initialWidth: 120 },
    {
        label: 'Días mora',
        fieldName: 'daysOverdue__c',
        type: 'number',
        initialWidth: 100,
        cellAttributes: { alignment: 'right' }
    }
];

export default class PolicyInstallments extends LightningElement {
    @api recordId;

    columns = COLUMNS;
    rows = [];
    error;
    loaded = false;

    @wire(getInstallmentsByPolicy, { policyId: '$recordId' })
    wiredInstallments({ data, error }) {
        if (data) {
            this.rows = data.map((row) => ({
                ...row,
                installmentUrl: `/${row.Id}`,
                sequenceLabel: row.sequenceNumber__c
                    ? `#${row.sequenceNumber__c}`
                    : row.Name,
                planName: row.paymentPlan__r ? row.paymentPlan__r.Name : ''
            }));
            this.error = undefined;
            this.loaded = true;
        } else if (error) {
            this.error =
                (error.body && error.body.message) || 'No se pudieron cargar las cuotas.';
            this.rows = [];
            this.loaded = true;
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.error && this.rows.length === 0;
    }

    get cardTitle() {
        return this.hasRows
            ? `Cuotas del plan de pago (${this.rows.length})`
            : 'Cuotas del plan de pago';
    }
}
