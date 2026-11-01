/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Participantes de la póliza (cualquier ramo) con su información relacionada: contratante, asegurados con
 *               sus dependientes, beneficiarios y otros roles. Cada participante se abre para ver su contacto o cuenta
 *               (RFC, correo, teléfonos, domicilio), sus coberturas, su vigencia o baja, su antigüedad y, si es asegurado,
 *               sus beneficiarios. Las columnas se ajustan a lo que trae la póliza (categoría, suma asegurada, prima…).
 *               Solo lectura. Usa ParticipantesPolizaController.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fechaVisible, moneda } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/ParticipantesPolizaController.getDatos';

const POR_PAGINA = 50;
const RAMOS_BIENES = ['auto', 'dano', 'empresarial'];

export default class ParticipantesPoliza extends NavigationMixin(LightningElement) {
    @track datos = null;
    @track abiertos = new Set();
    cargando = false;
    errorMensaje = '';
    vista = 'asegurados';
    estado = 'vigentes';
    busqueda = '';
    pagina = 1;
    _recordId;

    @api
    get recordId() { return this._recordId; }
    set recordId(v) {
        const cambio = v !== this._recordId;
        this._recordId = v;
        if (cambio && v) { this.cargar(); }
    }

    @api
    recargar() { return this.cargar(); }

    async cargar() {
        if (!this._recordId) { return; }
        this.cargando = true;
        try {
            this.datos = await getDatos({ policyId: this._recordId });
            this.errorMensaje = '';
            // Abre la vista que tenga participantes (ej. una póliza con solo beneficiarios u otros roles).
            if (!this.cuenta('asegurados')) {
                const otra = ['beneficiarios', 'otros'].find((v) => this.cuenta(v));
                if (otra) { this.vista = otra; }
            }
        } catch (e) {
            this.errorMensaje = (e && e.body && e.body.message) || (e && e.message) || 'Ocurrió un error inesperado.';
        } finally {
            this.cargando = false;
        }
    }

    // ============================================================
    // Encabezado
    // ============================================================
    get hayDatos() { return !!this.datos; }
    get poliza() { return (this.datos && this.datos.poliza) || {}; }
    get participantes() { return (this.datos && this.datos.participantes) || []; }
    get resumen() { return (this.datos && this.datos.resumen) || {}; }
    get subtitulo() {
        const p = this.poliza;
        const partes = [p.ramo, p.tipo && p.tipo !== p.ramo ? p.tipo : null,
            p.inicio ? `Vigencia ${fechaVisible(p.inicio)} – ${fechaVisible(p.fin)}` : null,
            p.anterior ? `Renueva ${p.anterior}` : null].filter((x) => x);
        return partes.join(' · ');
    }
    get contratante() { return this.poliza.contratante; }
    get hayContratante() { return !!this.contratante; }
    get datosContratante() { return this.lineas(this.contratante); }
    // Flotillas y ubicaciones aseguran bienes: aquí solo están las personas; los bienes van en su propia pestaña.
    get avisoBienes() {
        const r = this.fold(this.poliza.ramo);
        return RAMOS_BIENES.some((x) => r.startsWith(x))
            ? 'Esta póliza asegura bienes: los vehículos o ubicaciones están en la pestaña «Asegurados / Vehículos / Ubicaciones».' : '';
    }
    get textoLimite() { return this.datos && this.datos.limite ? 'Se muestran los primeros 5,000 participantes.' : ''; }

    get stats() {
        const r = this.resumen;
        return [
            { key: 'a', num: r.asegurado || 0, lbl: 'Asegurados' },
            { key: 'd', num: r.dependiente || 0, lbl: 'Dependientes' },
            { key: 'b', num: r.beneficiario || 0, lbl: 'Beneficiarios' },
            { key: 'o', num: r.otro || 0, lbl: 'Otros roles' },
            { key: 'x', num: r.bajas || 0, lbl: 'Dados de baja', clase: 'stat stat-baja' }
        ].map((s) => ({ ...s, clase: s.clase || 'stat' }));
    }

    // ============================================================
    // Vistas y filtros
    // ============================================================
    cuenta(vista) {
        const r = this.resumen;
        if (vista === 'asegurados') { return (r.asegurado || 0) + (r.dependiente || 0); }
        if (vista === 'beneficiarios') { return r.beneficiario || 0; }
        return r.otro || 0;
    }
    get vistas() {
        return [
            { value: 'asegurados', label: `Asegurados (${this.cuenta('asegurados')})` },
            { value: 'beneficiarios', label: `Beneficiarios (${this.cuenta('beneficiarios')})` },
            { value: 'otros', label: `Otros roles (${this.cuenta('otros')})` }
        ].map((v) => ({ ...v, variante: v.value === this.vista ? 'brand' : 'neutral' }));
    }
    cambiarVista(e) { this.vista = e.target.dataset.vista; this.pagina = 1; }
    get enAsegurados() { return this.vista === 'asegurados'; }
    get enBeneficiarios() { return this.vista === 'beneficiarios'; }
    get enOtros() { return this.vista === 'otros'; }

    get opcionesEstado() {
        return [
            { label: `Vigentes (${this.resumen.vigentes || 0})`, value: 'vigentes' },
            { label: `Dados de baja (${this.resumen.bajas || 0})`, value: 'bajas' },
            { label: 'Todos', value: 'todos' }
        ];
    }
    handleEstado(e) { this.estado = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    pasaFiltro(p) {
        if (this.estado === 'vigentes' && !p.activo) { return false; }
        if (this.estado === 'bajas' && p.activo) { return false; }
        const q = this.fold(this.busqueda);
        if (!q) { return true; }
        const c = p.contacto || p.cuenta || {};
        return this.fold(`${p.nombre || ''} ${p.certificado || ''} ${p.categoria || ''} ${p.parentesco || ''} ${c.rfc || ''} ${c.correo || ''}`).includes(q);
    }

    // ============================================================
    // Asegurados (titulares con sus dependientes debajo)
    // ============================================================
    get titulares() { return this.participantes.filter((p) => p.grupo === 'asegurado'); }
    get dependientesPorTitular() {
        const m = new Map();
        this.participantes.filter((p) => p.grupo === 'dependiente').forEach((d) => {
            const k = d.titularId || 'sin';
            if (!m.has(k)) { m.set(k, []); }
            m.get(k).push(d);
        });
        return m;
    }
    get beneficiariosPorAsegurado() {
        const m = new Map();
        this.participantes.filter((p) => p.grupo === 'beneficiario').forEach((b) => {
            const k = b.titularId || 'poliza';
            if (!m.has(k)) { m.set(k, []); }
            m.get(k).push(b);
        });
        return m;
    }
    // Titulares que pasan el filtro (o que tienen un dependiente que lo pasa) y dependientes sin titular en la póliza.
    get gruposAsegurados() {
        const deps = this.dependientesPorTitular;
        const ids = new Set(this.titulares.map((t) => t.id));
        const grupos = [];
        this.titulares.forEach((t) => {
            const suyos = (deps.get(t.id) || []).filter((d) => this.pasaFiltro(d));
            if (this.pasaFiltro(t) || suyos.length) { grupos.push({ titular: t, dependientes: suyos }); }
        });
        [...deps.keys()].filter((k) => !ids.has(k)).forEach((k) => {
            deps.get(k).filter((d) => this.pasaFiltro(d)).forEach((d) => grupos.push({ titular: d, dependientes: [] }));
        });
        return grupos;
    }
    get filasAsegurados() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        const filas = [];
        this.gruposAsegurados.slice(ini, ini + POR_PAGINA).forEach((g) => {
            filas.push(this.fila(g.titular, false));
            g.dependientes.forEach((d) => filas.push(this.fila(d, true)));
        });
        return filas;
    }
    get totalPaginable() {
        if (this.enAsegurados) { return this.gruposAsegurados.length; }
        return this.listaVista.length;
    }

    // ============================================================
    // Beneficiarios y otros roles
    // ============================================================
    get listaVista() {
        const grupo = this.enBeneficiarios ? 'beneficiario' : 'otro';
        return this.participantes.filter((p) => p.grupo === grupo && this.pasaFiltro(p));
    }
    get filasLista() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.listaVista.slice(ini, ini + POR_PAGINA).map((p) => this.fila(p, false));
    }
    get sinFilas() { return this.totalPaginable === 0; }

    // ============================================================
    // Columnas según lo que trae la póliza
    // ============================================================
    get conCategoria() { return this.participantes.some((p) => p.categoria); }
    get conSuma() { return this.participantes.some((p) => p.sumaAsegurada != null); }
    get conPrima() { return this.participantes.some((p) => p.prima != null); }
    get conParentesco() { return this.participantes.some((p) => p.parentesco || p.titularNombre); }
    get columnasAsegurados() {
        return 5 + (this.conCategoria ? 1 : 0) + (this.conSuma ? 1 : 0) + (this.conPrima ? 1 : 0) + (this.conParentesco ? 1 : 0);
    }

    // ============================================================
    // Fila y detalle
    // ============================================================
    fila(p, esDependiente) {
        const c = p.contacto || p.cuenta || {};
        const nacimiento = p.fechaNacimiento || c.fechaNacimiento;
        const abierto = this.abiertos.has(p.id);
        const beneficiarios = (this.beneficiariosPorAsegurado.get(p.id) || []).map((b) => ({
            id: b.id, texto: `${b.nombre}${b.parentesco ? ' · ' + b.parentesco : ''}${b.porcentaje != null ? ' · ' + b.porcentaje + '%' : ''}`
        }));
        return {
            ...p,
            key: p.id,
            keyDetalle: p.id + '-detalle',
            claseFila: [esDependiente ? 'fila-dependiente' : '', p.activo ? '' : 'fila-baja', abierto ? 'fila-abierta' : ''].join(' ').trim(),
            claseNombre: esDependiente ? 'nombre nombre-dependiente' : 'nombre',
            esDependiente,
            abierto,
            iconoAbrir: abierto ? 'utility:chevrondown' : 'utility:chevronright',
            textoAbrir: abierto ? 'Ocultar detalle' : 'Ver detalle',
            nacimientoTxt: nacimiento ? `${fechaVisible(nacimiento)} (${this.edad(nacimiento)} años)` : '',
            parentescoTxt: p.parentesco || (esDependiente ? 'Dependiente' : (p.grupo === 'asegurado' ? 'Titular' : '')),
            deTxt: p.titularNombre ? `de ${p.titularNombre}` : '',
            sumaTxt: moneda(p.sumaAsegurada),
            primaTxt: moneda(p.prima),
            porcentajeTxt: p.porcentaje != null ? `${p.porcentaje}%` : '',
            estado: p.activo ? 'Vigente' : `Baja${p.hasta ? ' ' + fechaVisible(p.hasta) : ''}`,
            claseEstado: p.activo ? 'estado estado-vigente' : 'estado estado-baja',
            contactoTxt: [c.correo, c.celular || c.telefono].filter((x) => x).join(' · '),
            // Detalle
            datosPersona: this.lineas(c, p),
            hayPersona: !!(p.contacto || p.cuenta),
            personaTitulo: p.contacto ? 'Contacto' : (p.cuenta ? (p.cuenta.tipo === 'Persona' ? 'Cuenta (persona)' : 'Cuenta') : 'Contacto'),
            personaId: c.id,
            datosPoliza: [
                ['Roles', p.rolesTexto],
                ['Certificado', p.certificado],
                ['Categoría', p.categoria],
                ['Parentesco', p.parentesco],
                ['Titular', p.titularNombre],
                ['Vigencia', p.desde ? `${fechaVisible(p.desde)}${p.hasta ? ' – ' + fechaVisible(p.hasta) : ''}` : ''],
                ['Asegurado desde', p.aseguradoDesde ? `${fechaVisible(p.aseguradoDesde)}${p.polizaOriginal ? ' (' + p.polizaOriginal + ')' : ''}` : ''],
                ['Vigencia anterior', p.vigenciaAnterior],
                ['Motivo de baja', p.motivoBaja],
                ['Identificación', p.identificacion],
                ['Porcentaje', p.porcentaje != null ? `${p.porcentaje}%` : ''],
                ['Menor de edad', p.menor ? 'Sí' : ''],
                ['Tutor', p.tutor ? p.tutor.nombre : ''],
                ['Contratante', p.contratante ? 'Sí' : '']
            ].filter(([, v]) => v).map(([etiqueta, valor]) => ({ key: etiqueta, etiqueta, valor })),
            coberturasTxt: (p.coberturas || []).map((cob) => ({
                key: cob.id,
                nombre: cob.nombre,
                detalle: [cob.suma != null ? 'Suma ' + moneda(cob.suma) : '', cob.deducible != null ? 'Deducible ' + moneda(cob.deducible) : '',
                    cob.prima != null ? 'Prima ' + moneda(cob.prima) : ''].filter((x) => x).join(' · ')
            })),
            hayCoberturas: (p.coberturas || []).length > 0,
            beneficiarios,
            hayBeneficiarios: beneficiarios.length > 0
        };
    }

    lineas(c, p) {
        if (!c) { return []; }
        const nacimiento = (p && p.fechaNacimiento) || c.fechaNacimiento;
        return [
            ['Nombre', c.nombre],
            ['Tipo', c.tipo],
            ['RFC', c.rfc],
            ['Sexo', c.sexo],
            ['Fecha de nacimiento', nacimiento ? `${fechaVisible(nacimiento)} (${this.edad(nacimiento)} años)` : ''],
            ['Correo', c.correo],
            ['Teléfono', c.telefono],
            ['Celular', c.celular],
            ['Puesto', c.puesto],
            ['Empresa', c.cuentaNombre],
            ['Domicilio', c.domicilio]
        ].filter(([, v]) => v).map(([etiqueta, valor]) => ({ key: etiqueta, etiqueta, valor }));
    }

    toggleDetalle(e) {
        const id = e.currentTarget.dataset.id;
        const s = new Set(this.abiertos);
        if (s.has(id)) { s.delete(id); } else { s.add(id); }
        this.abiertos = s;
    }

    abrirRegistro(e) {
        const id = e.currentTarget.dataset.id;
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    // ============================================================
    // Paginación
    // ============================================================
    get paginas() { return Math.max(1, Math.ceil(this.totalPaginable / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.totalPaginable} ${this.enAsegurados ? 'asegurados' : 'participantes'}`; }
    get sinAnterior() { return this.pagina <= 1; }
    get sinSiguiente() { return this.pagina >= this.paginas; }
    get conPaginas() { return this.paginas > 1; }
    anterior() { if (this.pagina > 1) { this.pagina--; } }
    siguiente() { if (this.pagina < this.paginas) { this.pagina++; } }

    // ============================================================
    // Utilidades
    // ============================================================
    edad(fecha) {
        const [a, m, d] = String(fecha).substring(0, 10).split('-').map(Number);
        const hoy = new Date();
        let edad = hoy.getFullYear() - a;
        if (hoy.getMonth() + 1 < m || (hoy.getMonth() + 1 === m && hoy.getDate() < d)) { edad--; }
        return edad;
    }
    fold(v) {
        return String(v || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
    }
}
