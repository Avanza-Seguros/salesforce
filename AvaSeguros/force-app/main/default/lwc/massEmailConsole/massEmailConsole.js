import { LightningElement, track } from 'lwc';
import getDashboardData from '@salesforce/apex/massEmailConsoleController.getDashboardData';
import runMassEmailFlow from '@salesforce/apex/massEmailConsoleController.runMassEmailFlow';

export default class MassEmailConsole extends LightningElement {

    @track pending = 0;
    @track sentToday = 0;
    @track loading = false;
    @track status = '';

    connectedCallback() {
        console.log('MassEmailConsole connectedCallback');
        this.refreshData();
    }

    refreshData() {
        console.log('MassEmailConsole refreshData');
        this.loading = true;
        this.status = '';

        getDashboardData()
            .then(result => {
                console.log('result::: ' + JSON.stringify(result));
                this.pending = result.pending;
                this.sentToday = result.sentToday;
            })
            .catch(error => {
                console.error(error);
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleRun() {
        console.log('MassEmailConsole handleRun');
        this.loading = true;
        this.status = '';

        runMassEmailFlow()
            .then(result => {
                this.status = 'SUCCESS: ' + JSON.stringify(result);
            })
            .catch(error => {
                this.status = 'ERROR: ' + JSON.stringify(error);
            })
            .finally(() => {
                this.loading = false;
                this.refreshData();
            });
    }
}
