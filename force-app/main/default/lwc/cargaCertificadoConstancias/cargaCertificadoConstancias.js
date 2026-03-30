import { LightningElement } from 'lwc';

export default class CargaCertificadoConstancias extends LightningElement {
    
    switchTab(event) {
        const tabElement = event.currentTarget;
        const tabName = tabElement.dataset.tab;
        
        // Desactivar todos los tabs
        const allTabs = this.template.querySelectorAll('.slds-tabs_default__item');
        const allContents = this.template.querySelectorAll('[data-tab-content]');
        
        allTabs.forEach(tab => tab.classList.remove('slds-is-active'));
        allContents.forEach(content => {
            content.classList.add('slds-hide');
            content.classList.remove('slds-show');
        });
        
        // Activar tab seleccionado
        tabElement.classList.add('slds-is-active');
        
        // Mostrar contenido correspondiente
        const activeContent = this.template.querySelector(`[data-tab-content="${tabName}"]`);
        if (activeContent) {
            activeContent.classList.remove('slds-hide');
            activeContent.classList.add('slds-show');
        }
    }

    connectedCallback() {
        // Verificar que los paneles existen
        setTimeout(() => {
            const panels = this.template.querySelectorAll('.slds-tabs_default__content');
            console.log('Paneles en DOM:', panels.length);
            panels.forEach(panel => {
                console.log('Panel ID:', panel.id, 'Clases:', panel.className);
            });
        }, 100);
    }
}