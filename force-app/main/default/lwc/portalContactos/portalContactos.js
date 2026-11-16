// portalContactos/portalContactos.js
// Página «Mi empresa» del sitio: el listado de las personas aseguradas de la empresa del cliente, tomado del censo
// (titulares, cónyuges y dependientes vigentes), con buscador.
import { LightningElement, api, wire } from 'lwc';
import contactos from '@salesforce/apex/PortalSitioController.contactos';
import puedeVistaPrevia from '@salesforce/apex/PortalPolizasController.puedeVistaPrevia';

const POR_PAGINA = 50;

export default class PortalContactos extends LightningElement {
    @api titulo = 'Personas de tu empresa';
    @api subtitulo = 'Colaboradores y dependientes asegurados en el censo de tu empresa.';

    datos;
    cargando = true;
    error;
    cuentaVistaPrevia = null;
    busqueda = '';
    mostrar = POR_PAGINA;

    puede = false;
    @wire(puedeVistaPrevia)
    recibirPermiso({ data }) {
        this.puede = data === true;
    }

    @wire(contactos, { cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibir({ data, error }) {
        if (data) {
            this.datos = data;
            this.error = undefined;
            this.cargando = false;
        } else if (error) {
            this.datos = undefined;
            this.error = (error.body && error.body.message) || 'No se pudo cargar la información.';
            this.cargando = false;
        }
    }

    handleVistaPrevia(event) {
        this.cargando = true;
        this.datos = undefined;
        this.busqueda = '';
        this.mostrar = POR_PAGINA;
        this.cuentaVistaPrevia = event.detail.id || null;
    }

    handleBusqueda(event) {
        this.busqueda = event.target.value || '';
        this.mostrar = POR_PAGINA;
    }

    handleMas() {
        this.mostrar += POR_PAGINA;
    }

    // ---------- Datos ----------

    get personas() {
        return (this.datos && this.datos.personas) || [];
    }
    get hayPersonas() {
        return !this.cargando && !this.error && this.personas.length > 0;
    }
    get sinPersonas() {
        return !this.cargando && !this.error && this.personas.length === 0;
    }
    get nombreCuenta() {
        return (this.datos && this.datos.cuenta) || '';
    }
    // Sin empresa: el administrador aún no elige cuenta en la vista previa, o el usuario no está ligado a una empresa.
    get mensajeVacio() {
        if (this.datos && !this.datos.cuenta) {
            return this.puede
                ? 'Elige arriba la cuenta del cliente (vista previa de administrador) para ver a las personas de su empresa.'
                : 'Tu usuario no está ligado a ninguna empresa. Contacta a tu ejecutivo para revisarlo.';
        }
        return 'Tu empresa todavía no tiene personas en el censo. Si crees que es un error, contacta a tu ejecutivo.';
    }
    get variosRamos() {
        return new Set(this.personas.map((p) => p.ramo || '')).size > 1;
    }

    get filtradas() {
        const texto = this.normalizar(this.busqueda);
        if (!texto) return this.personas;
        return this.personas.filter((p) =>
            this.normalizar([p.nombre, p.certificado, p.parentesco, p.titularNombre, p.grupo, p.ramo].join(' ')).includes(texto));
    }
    get filas() {
        return this.filtradas.slice(0, this.mostrar).map((p) => ({
            ...p,
            claseFila: p.titular ? 'fila_titular' : 'fila_dependiente',
            claseParentesco: `chip chip_${p.titular ? 'titular' : (p.parentesco === 'Cónyuge' ? 'conyuge' : 'dependiente')}`,
            deTitular: !p.titular && p.titularNombre ? `de ${p.titularNombre}` : '',
            certificadoTexto: p.certificado || '—',
            edadTexto: p.edad == null ? '—' : `${p.edad} año${p.edad === 1 ? '' : 's'}`,
            nacimientoTexto: p.nacimiento ? this.fecha(p.nacimiento) : '',
            generoTexto: p.genero || '—',
            grupoTexto: p.grupo || '—',
            altaTexto: p.alta ? this.fecha(p.alta) : '—',
            primaTexto: p.prima == null ? '—' : this.moneda(p.prima),
            ramoTexto: p.ramo || '—'
        }));
    }
    get hayFilas() {
        return this.filas.length > 0;
    }
    get hayMas() {
        return this.filtradas.length > this.mostrar;
    }
    get conteo() {
        const total = this.personas.length;
        const titulares = this.personas.filter((p) => p.titular).length;
        const filtradas = this.filtradas.length;
        const base = `${total} persona${total === 1 ? '' : 's'} · ${titulares} titular${titulares === 1 ? '' : 'es'} y ${total - titulares} dependiente${total - titulares === 1 ? '' : 's'}`;
        return filtradas === total ? base : `${filtradas} de ${base}`;
    }

    // ---------- Formatos ----------

    normalizar(texto) {
        return String(texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    }
    fecha(valor) {
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(a, m - 1, d));
    }
    moneda(n) {
        return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN', minimumFractionDigits: 2 }).format(n || 0);
    }
}
