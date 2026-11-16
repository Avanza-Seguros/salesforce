// portalVistaPrevia/portalVistaPrevia.js
// Vista previa de administrador para las páginas del sitio: solo usuarios internos con el permiso pueden elegir una
// cuenta y ver la página como uno de sus usuarios. Avisa con el evento «cambio» ({ id, nombre }; id null al quitarla).
import { LightningElement, api, wire } from 'lwc';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';
import buscarCuentas from '@salesforce/apex/PortalPolizasController.buscarCuentas';

export default class PortalVistaPrevia extends LightningElement {
    @api pagina = 'la página';

    puede = false;
    cuentaId = null;
    nombre;
    texto = '';
    cuentas = [];
    buscando = false;
    error;
    temporizador;

    @wire(puedeVistaPrevia)
    recibirPermiso({ data }) {
        this.puede = data === true;
    }

    get textoActual() {
        return `Viendo ${this.pagina} como un usuario de`;
    }
    get hayCuentas() {
        return this.cuentas.length > 0;
    }
    get sinCuentas() {
        return !this.buscando && !this.error && this.texto.trim().length >= 2 && this.cuentas.length === 0;
    }

    handleTexto(event) {
        this.texto = event.target.value || '';
        clearTimeout(this.temporizador);
        const texto = this.texto.trim();
        if (texto.length < 2) {
            this.cuentas = [];
            this.buscando = false;
            return;
        }
        this.buscando = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.temporizador = setTimeout(() => this.buscar(texto), 300);
    }

    async buscar(texto) {
        try {
            const cuentas = await buscarCuentas({ texto });
            if (texto !== this.texto.trim()) return;
            this.cuentas = cuentas.map((c) => ({
                ...c,
                detalle: `${c.polizas} póliza${c.polizas === 1 ? '' : 's'} como titular`
            }));
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'No se pudieron buscar las cuentas.';
        } finally {
            this.buscando = false;
        }
    }

    handleElegir(event) {
        const { id, nombre } = event.currentTarget.dataset;
        this.cuentaId = id;
        this.nombre = nombre;
        this.dispatchEvent(new CustomEvent('cambio', { detail: { id, nombre } }));
    }

    handleQuitar() {
        this.cuentaId = null;
        this.nombre = undefined;
        this.texto = '';
        this.cuentas = [];
        this.dispatchEvent(new CustomEvent('cambio', { detail: { id: null, nombre: null } }));
    }
}
