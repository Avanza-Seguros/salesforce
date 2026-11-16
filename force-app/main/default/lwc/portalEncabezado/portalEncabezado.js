// portalEncabezado/portalEncabezado.js
// Encabezado del sitio Avanza Seguro (sustituye al del tema): logo, menú tipo píldora con el «Default Navigation»
// publicado (con submenús), buscador de pólizas, avisos (pagos vencidos y renovaciones próximas) y menú del usuario.
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import encabezado from '@salesforce/apex/PortalSitioController.encabezado';
import dashboard from '@salesforce/apex/PortalPolizasController.dashboard';

const DIAS_AVISO = 30;

export default class PortalEncabezado extends NavigationMixin(LightningElement) {
    @api textoInicio = 'Inicio';
    @api placeholderBusqueda = 'Busca tu póliza por número, ramo o aseguradora';

    datos;
    alertas = 0;
    detalleAlertas = '';
    abierto = null; // clave del submenú o 'usuario'
    menuMovil = false;
    busqueda = '';
    ruta = '';

    @wire(encabezado)
    recibirEncabezado({ data }) {
        if (data) this.datos = data;
    }

    @wire(dashboard, { cuentaVistaPrevia: null })
    recibirDashboard({ data }) {
        if (!data) return;
        const hoy = new Date();
        hoy.setHours(0, 0, 0, 0);
        const renovar = (data.polizas || []).filter((p) => {
            if (!p.vigente || !p.finVigencia) return false;
            const [a, m, d] = String(p.finVigencia).substring(0, 10).split('-').map(Number);
            const dias = Math.round((new Date(a, m - 1, d) - hoy) / 86400000);
            return dias >= 0 && dias <= DIAS_AVISO;
        }).length;
        const vencidas = data.cuotasVencidas || 0;
        this.alertas = vencidas + renovar;
        const partes = [];
        if (vencidas) partes.push(`${vencidas} pago${vencidas === 1 ? '' : 's'} vencido${vencidas === 1 ? '' : 's'}`);
        if (renovar) partes.push(`${renovar} póliza${renovar === 1 ? '' : 's'} por renovar`);
        this.detalleAlertas = partes.join(' y ');
    }

    @wire(CurrentPageReference)
    recibirPagina() {
        this.ruta = this.rutaActual();
        this.abierto = null;
        this.menuMovil = false;
    }

    connectedCallback() {
        this.ruta = this.rutaActual();
        this.cerrarFuera = (e) => {
            if (this.abierto && !this.template.host.contains(e.target)) this.abierto = null;
        };
        document.addEventListener('click', this.cerrarFuera);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this.cerrarFuera);
    }

    // ---------- Rutas ----------

    get base() {
        return basePath || '';
    }
    rutaActual() {
        if (typeof window === 'undefined') return '/';
        let r = window.location.pathname || '/';
        if (this.base && r.startsWith(this.base)) r = r.substring(this.base.length);
        return r || '/';
    }
    esActual(valor) {
        if (!valor) return false;
        const limpio = valor.split('?')[0];
        if (limpio === '/' || limpio === '') return this.ruta === '/' || this.ruta === '';
        return this.ruta === limpio || this.ruta.startsWith(limpio + '/');
    }
    url(valor, tipo) {
        if (tipo === 'ExternalLink') return valor;
        return `${this.base}${valor && valor.startsWith('/') ? '' : '/'}${valor || ''}`;
    }

    // Navegación dentro del sitio: el sitio ya antepone su base (/s) a las rutas relativas, así que se pasa la ruta sin
    // ella (con la base quedaba /s/s/... y salía «Invalid Page»). Los href sí llevan la base completa.
    ir(valor) {
        const ruta = `${valor && valor.startsWith('/') ? '' : '/'}${valor || ''}`;
        this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url: ruta } });
    }

    // ---------- Menú ----------

    get menu() {
        const inicio = { etiqueta: this.textoInicio, valor: '/', tipo: 'InternalLink', hijos: [] };
        const lista = [inicio, ...((this.datos && this.datos.menu) || [])];
        return lista.map((e, i) => {
            const clave = `m${i}`;
            const hijos = (e.hijos || []).map((h, j) => ({
                ...h,
                clave: `${clave}-${j}`,
                href: this.url(h.valor, h.tipo),
                destino: h.nuevaVentana || h.tipo === 'ExternalLink' ? '_blank' : null,
                actual: this.esActual(h.valor) ? 'page' : null,
                clase: `submenu_enlace${this.esActual(h.valor) ? ' submenu_enlace_actual' : ''}`
            }));
            const actual = this.esActual(e.valor) || hijos.some((h) => h.actual);
            const abierto = this.abierto === clave;
            return {
                ...e,
                clave,
                hijos,
                tieneHijos: hijos.length > 0,
                href: e.valor ? this.url(e.valor, e.tipo) : null,
                destino: e.nuevaVentana || e.tipo === 'ExternalLink' ? '_blank' : null,
                actual: actual ? 'page' : null,
                abierto,
                expandido: abierto ? 'true' : 'false',
                clase: `nav_enlace${actual ? ' nav_enlace_actual' : ''}`,
                claseIcono: `nav_flecha${abierto ? ' nav_flecha_abierta' : ''}`
            };
        });
    }

    get claseNav() {
        return `nav${this.menuMovil ? ' nav_abierta' : ''}`;
    }
    get expandidoMovil() {
        return this.menuMovil ? 'true' : 'false';
    }
    get iconoMovil() {
        return this.menuMovil ? 'utility:close' : 'utility:rows';
    }

    handleMovil() {
        this.menuMovil = !this.menuMovil;
    }

    handleSubmenu(event) {
        event.stopPropagation();
        const clave = event.currentTarget.dataset.clave;
        this.abierto = this.abierto === clave ? null : clave;
    }

    handleEnlace(event) {
        const { valor, tipo, destino } = event.currentTarget.dataset;
        if (tipo === 'ExternalLink' || destino === '_blank' || !valor) return;
        event.preventDefault();
        this.abierto = null;
        this.menuMovil = false;
        this.ir(valor);
    }

    handleTeclaMenu(event) {
        if (event.key === 'Escape') {
            this.abierto = null;
        }
    }

    // ---------- Búsqueda ----------

    handleBusqueda(event) {
        this.busqueda = event.target.value || '';
    }

    handleBuscar(event) {
        if (event.key && event.key !== 'Enter') return;
        event.preventDefault();
        const texto = this.busqueda.trim();
        const destino = `/mis-polizas${texto ? `?buscar=${encodeURIComponent(texto)}` : ''}`;
        this.ir(destino);
    }

    // ---------- Avisos y usuario ----------

    get hayAlertas() {
        return this.alertas > 0;
    }
    get etiquetaAlertas() {
        return this.alertas ? `Avisos: ${this.detalleAlertas}` : 'Avisos: no tienes pendientes';
    }
    get urlAvisos() {
        return this.url('/mi-dashboard');
    }
    get textoAlertas() {
        return this.alertas > 9 ? '9+' : String(this.alertas);
    }

    get nombre() {
        return (this.datos && this.datos.nombre) || '';
    }
    get cuenta() {
        return (this.datos && this.datos.cuenta) || '';
    }
    get iniciales() {
        return (this.datos && this.datos.iniciales) || '';
    }
    get foto() {
        return this.datos && this.datos.foto;
    }
    get usuarioAbierto() {
        return this.abierto === 'usuario';
    }
    get expandidoUsuario() {
        return this.usuarioAbierto ? 'true' : 'false';
    }
    get urlPerfil() {
        return this.datos ? this.url(`/profile/${this.datos.usuarioId}`) : '#';
    }
    get urlAjustes() {
        return this.datos ? this.url(`/settings/${this.datos.usuarioId}`) : '#';
    }
    get urlSalir() {
        return `${this.base.replace(/\/s$/, '')}/secur/logout.jsp`;
    }
    get urlInicio() {
        return this.url('/');
    }

    handleUsuario(event) {
        event.stopPropagation();
        this.abierto = this.abierto === 'usuario' ? null : 'usuario';
    }
}
