// portalContactos/portalContactos.js
// Página «Contactos» del sitio: las personas de la empresa del cliente en tarjetas, con buscador, filtro de activos e
// inactivos, filtro por producto (GMM, Vida, Dental, Adicional) y sus datos de contacto.
import { LightningElement, api, wire } from 'lwc';
import contactos from '@salesforce/apex/PortalSitioController.contactos';

const POR_PAGINA = 24;
const PRODUCTOS = ['GMM', 'Vida', 'Dental', 'Adicional'];
const COLORES = ['#1E63E9', '#0F7A47', '#6D28D9', '#C2410C', '#BE185D', '#0369A1'];

export default class PortalContactos extends LightningElement {
    @api titulo = 'Personas de tu empresa';
    @api subtitulo = 'Consulta a tus colaboradores, su cobertura y cómo contactarlos.';

    datos;
    cargando = true;
    error;
    cuentaVistaPrevia = null;
    busqueda = '';
    estado = 'activos';
    producto = 'todos';
    mostrar = POR_PAGINA;

    @wire(contactos, { cuentaVistaPrevia: '$cuentaVistaPrevia' })
    recibir({ data, error }) {
        if (data) {
            this.datos = data;
            this.error = undefined;
            this.cargando = false;
            // Sin activos se muestran todos para no dejar la página vacía.
            if (!data.personas.some((p) => p.activo)) this.estado = 'todos';
        } else if (error) {
            this.datos = undefined;
            this.error = (error.body && error.body.message) || 'No se pudo cargar la información.';
            this.cargando = false;
        }
    }

    handleVistaPrevia(event) {
        this.cargando = true;
        this.datos = undefined;
        this.mostrar = POR_PAGINA;
        this.cuentaVistaPrevia = event.detail.id || null;
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

    get resumen() {
        const l = this.personas;
        const activos = l.filter((p) => p.activo).length;
        const cuenta = (prod) => l.filter((p) => p.activo && (p.productos || []).includes(prod)).length;
        const cumple = l.filter((p) => p.activo && p.cumpleHoy).length;
        return [
            { clave: 'activos', valor: activos, etiqueta: activos === 1 ? 'Persona activa' : 'Personas activas' },
            { clave: 'inactivos', valor: l.length - activos, etiqueta: 'Inactivas' },
            { clave: 'gmm', valor: cuenta('GMM'), etiqueta: 'Con Gastos Médicos' },
            { clave: 'vida', valor: cuenta('Vida'), etiqueta: 'Con Vida' },
            { clave: 'cumple', valor: cumple, etiqueta: cumple === 1 ? 'Cumple años hoy' : 'Cumplen años hoy' }
        ];
    }

    get filtradas() {
        const texto = this.normalizar(this.busqueda.trim());
        return this.personas.filter((p) => {
            if (this.estado === 'activos' && !p.activo) return false;
            if (this.estado === 'inactivos' && p.activo) return false;
            if (this.producto !== 'todos' && !(p.productos || []).includes(this.producto)) return false;
            if (!texto) return true;
            return this.normalizar([p.nombre, p.puesto, p.area, p.correo, p.certificado].filter(Boolean).join(' ')).includes(texto);
        });
    }

    get tarjetas() {
        return this.filtradas.slice(0, this.mostrar).map((p, i) => {
            const telefono = p.celular || p.telefono;
            return {
                ...p,
                iniciales: this.iniciales(p.nombre),
                estiloAvatar: `background: ${COLORES[this.hash(p.nombre) % COLORES.length]}`,
                linea: [p.puesto, p.area].filter(Boolean).join(' · '),
                productosLista: (p.productos || []).map((x) => ({ clave: `${p.id}-${x}`, texto: x, clase: `chip chip_${x.toLowerCase()}` })),
                hayProductos: (p.productos || []).length > 0,
                urlCorreo: p.correo ? `mailto:${p.correo}` : null,
                telefonoTexto: telefono,
                urlTelefono: telefono ? `tel:${String(telefono).replace(/[^\d+]/g, '')}` : null,
                estadoTexto: p.activo ? 'Activa' : 'Inactiva',
                estadoClase: `estado ${p.activo ? 'estado_activo' : 'estado_inactivo'}`,
                certificadoTexto: p.certificado ? `Certificado ${p.certificado}` : null,
                ingresoTexto: p.ingreso ? `Ingreso ${this.fecha(p.ingreso)}` : null,
                clase: `tarjeta${p.activo ? '' : ' tarjeta_inactiva'}`,
                orden: i
            };
        });
    }
    get hayResultados() {
        return this.filtradas.length > 0;
    }
    get textoResultados() {
        const n = this.filtradas.length;
        return `${n} persona${n === 1 ? '' : 's'}`;
    }
    get hayMas() {
        return this.filtradas.length > this.mostrar;
    }
    get textoMas() {
        return `Ver más (${this.filtradas.length - this.mostrar} restantes)`;
    }

    get opcionesEstado() {
        return [
            { value: 'activos', label: 'Activas' },
            { value: 'inactivos', label: 'Inactivas' },
            { value: 'todos', label: 'Todas' }
        ].map((o) => ({ ...o, clase: `filtro${this.estado === o.value ? ' filtro_activo' : ''}`, presionado: String(this.estado === o.value) }));
    }
    get opcionesProducto() {
        return ['todos', ...PRODUCTOS].map((v) => ({
            value: v,
            label: v === 'todos' ? 'Todos los productos' : v,
            clase: `filtro filtro_chico${this.producto === v ? ' filtro_activo' : ''}`,
            presionado: String(this.producto === v)
        }));
    }

    // ---------- Eventos ----------

    handleBusqueda(event) {
        this.busqueda = event.target.value || '';
        this.mostrar = POR_PAGINA;
    }
    handleEstado(event) {
        this.estado = event.currentTarget.dataset.value;
        this.mostrar = POR_PAGINA;
    }
    handleProducto(event) {
        this.producto = event.currentTarget.dataset.value;
        this.mostrar = POR_PAGINA;
    }
    handleMas() {
        this.mostrar += POR_PAGINA;
    }

    // ---------- Formatos ----------

    normalizar(t) {
        return String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
    }
    iniciales(nombre) {
        const partes = String(nombre || '').trim().split(/\s+/).filter(Boolean);
        if (!partes.length) return '?';
        return ((partes[0][0] || '') + (partes.length > 1 ? partes[partes.length - 1][0] : '')).toUpperCase();
    }
    hash(t) {
        let h = 0;
        for (const c of String(t || '')) h = (h * 31 + c.charCodeAt(0)) % 997;
        return h;
    }
    fecha(valor) {
        const [a, m, d] = String(valor).substring(0, 10).split('-').map(Number);
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(a, m - 1, d));
    }
}
