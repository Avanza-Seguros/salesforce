/**
 * @creation date: 01/11/2026
 * @author: Sergio Uribe Toledo - Volestra
 * @description: Participantes de la póliza (cualquier ramo) con su información relacionada: contratante, asegurados con
 *               sus dependientes y, si los hay (Vida), beneficiarios. Cada participante se abre para ver su contacto o cuenta
 *               (RFC, correo, teléfonos, domicilio), su vigencia o baja, el envío de su correo, sus archivos adjuntos y, si
 *               es titular, sus dependientes. Las columnas se ajustan a lo que trae la póliza (categoría, suma asegurada, prima…).
 *               Solo lectura. Usa ParticipantesPolizaController.
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { fechaVisible, moneda } from 'c/lectorArchivos';
import getDatos from '@salesforce/apex/ParticipantesPolizaController.getDatos';
import { descargarDocumento, fijarPortal } from 'c/portalContexto';
import datosComponente from '@salesforce/apex/PortalPolizasPestanas.datosComponente';

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
    // Sitio de empresas (portalPolizas): igual que en Salesforce en solo lectura, con los datos de PortalPolizasPestanas;
    // sin enlaces a registros de Salesforce (no existen en el sitio); los archivos se descargan.
    @api portal = false;
    @api cuentaVistaPrevia;
    get interno() { return !this.portal; }
    // En el sitio de empresas se agrega «part-portal» para tomar el estilo de Oportunidades.
    get claseRaiz() { return this.portal ? 'part part-portal' : 'part'; }

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
        // Espera a que lleguen todas las propiedades (portal, cuentaVistaPrevia) antes de la primera carga.
        await Promise.resolve();
        if (this.portal) { fijarPortal(this._recordId, this.cuentaVistaPrevia); }
        this.cargando = true;
        try {
            this.datos = await (this.portal
                ? datosComponente({ policyId: this._recordId, cuentaVistaPrevia: this.cuentaVistaPrevia || null, tipo: 'participantes' })
                : getDatos({ policyId: this._recordId }));
            this.errorMensaje = '';
            // Abre la vista que tenga participantes (ej. una póliza con solo beneficiarios u otros roles).
            if (!this.cuenta(this.vista)) {
                const otra = ['asegurados', 'dependientes', 'beneficiarios'].find((v) => this.cuenta(v));
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
        if (!RAMOS_BIENES.some((x) => r.startsWith(x))) { return ''; }
        return r.startsWith('auto')
            ? 'Esta póliza asegura vehículos: están en la pestaña «Vehículos».'
            : 'Esta póliza asegura bienes: las ubicaciones están en la pestaña «Ubicaciones».';
    }
    get textoLimite() { return this.datos && this.datos.limite ? 'Se muestran los primeros 5,000 participantes.' : ''; }

    get stats() {
        const r = this.resumen;
        return [
            { key: 'a', num: this.cuenta('asegurados'), lbl: 'Titulares' },
            { key: 'd', num: r.dependiente || 0, lbl: 'Dependientes' },
            // Beneficiarios: solo las pólizas que los tienen (Vida).
            ...(r.beneficiario ? [{ key: 'b', num: r.beneficiario, lbl: 'Beneficiarios' }] : []),
            { key: 'x', num: r.bajas || 0, lbl: 'Dados de baja', clase: 'stat stat-baja' }
        ].map((s) => ({ ...s, clase: s.clase || 'stat' }));
    }

    // ============================================================
    // Vistas y filtros
    // ============================================================
    cuenta(vista) {
        const r = this.resumen;
        // En Titulares también van las personas con otro papel (p. ej. el conductor en autos).
        if (vista === 'asegurados') { return (r.asegurado || 0) + (r.otro || 0); }
        if (vista === 'dependientes') { return r.dependiente || 0; }
        return r.beneficiario || 0;
    }
    get vistas() {
        return [
            { value: 'asegurados', label: `Titulares (${this.cuenta('asegurados')})` },
            { value: 'dependientes', label: `Dependientes (${this.cuenta('dependientes')})` },
            ...(this.cuenta('beneficiarios') ? [{ value: 'beneficiarios', label: `Beneficiarios (${this.cuenta('beneficiarios')})` }] : [])
        ].map((v) => ({ ...v, variante: v.value === this.vista ? 'brand' : 'neutral' }));
    }
    cambiarVista(e) { this.vista = e.target.dataset.vista; this.pagina = 1; }
    get enAsegurados() { return this.vista === 'asegurados'; }
    get enBeneficiarios() { return this.vista === 'beneficiarios'; }

    get opcionesEstado() {
        return [
            { label: `Vigentes (${this.resumen.vigentes || 0})`, value: 'vigentes' },
            { label: `Dados de baja (${this.resumen.bajas || 0})`, value: 'bajas' },
            { label: `Cambios (${this.participantes.filter((p) => p.tipoMovimiento === 'Cambio').length})`, value: 'cambios' },
            { label: `Correo sin enviar (${this.participantes.filter((p) => p.activo && !p.correoEnviado).length})`, value: 'sincorreo' },
            { label: `Correo enviado (${this.participantes.filter((p) => p.correoEnviado).length})`, value: 'concorreo' },
            { label: 'Todos', value: 'todos' }
        ];
    }
    handleEstado(e) { this.estado = e.detail.value; this.pagina = 1; }
    handleBusqueda(e) { this.busqueda = e.target.value || ''; this.pagina = 1; }

    pasaFiltro(p) {
        if (this.estado === 'vigentes' && !p.activo) { return false; }
        if (this.estado === 'bajas' && p.activo) { return false; }
        if (this.estado === 'cambios' && p.tipoMovimiento !== 'Cambio') { return false; }
        if (this.estado === 'sincorreo' && (!p.activo || p.correoEnviado)) { return false; }
        if (this.estado === 'concorreo' && !p.correoEnviado) { return false; }
        const q = this.fold(this.busqueda);
        if (!q) { return true; }
        const c = p.contacto || p.cuenta || {};
        return this.fold(`${p.nombre || ''} ${p.certificado || ''} ${p.categoria || ''} ${p.parentesco || ''} ${c.rfc || ''} ${c.correo || ''}`).includes(q);
    }

    // ============================================================
    // Asegurados (titulares; sus dependientes van en su detalle y en la pestaña Dependientes)
    // ============================================================
    get titulares() { return this.participantes.filter((p) => p.grupo === 'asegurado' || p.grupo === 'otro'); }
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
    // Titulares que pasan el filtro.
    get gruposAsegurados() {
        const lista = this.titulares.filter((t) => this.pasaFiltro(t)).map((titular) => ({ titular }));
        return this.orden.campo ? lista.sort((a, b) => this.comparar(a.titular, b.titular)) : lista;
    }

    // ============================================================
    // Orden por columna (clic en el encabezado; otro clic invierte)
    // ============================================================
    orden = { campo: '', asc: true };
    ordenar(e) {
        const campo = e.currentTarget.dataset.campo;
        this.orden = { campo, asc: this.orden.campo === campo ? !this.orden.asc : true };
        this.pagina = 1;
    }
    get flechas() {
        const f = {};
        if (this.orden.campo) { f[this.orden.campo] = this.orden.asc ? '▲' : '▼'; }
        return f;
    }
    valorOrden(p, campo) {
        const c = p.contacto || p.cuenta || {};
        switch (campo) {
            case 'nacimiento': return p.fechaNacimiento || c.fechaNacimiento || '';
            case 'prima': return p.prima;
            case 'porcentaje': return p.porcentaje;
            case 'estado': return p.tipoMovimiento || (p.activo ? 'Alta' : 'Baja');
            case 'envio': return p.correoEnviado ? 'Enviado' : (c.correo ? 'Pendiente' : 'Sin correo');
            case 'correo': return c.correo || '';
            default: return p[campo];
        }
    }
    comparar(a, b) {
        const x = this.valorOrden(a, this.orden.campo);
        const y = this.valorOrden(b, this.orden.campo);
        const vacioX = x === null || x === undefined || x === '';
        const vacioY = y === null || y === undefined || y === '';
        // Los vacíos siempre al final.
        if (vacioX || vacioY) { return vacioX === vacioY ? 0 : (vacioX ? 1 : -1); }
        const r = typeof x === 'number' && typeof y === 'number'
            ? x - y
            : String(x).localeCompare(String(y), 'es', { numeric: true, sensitivity: 'base' });
        return this.orden.asc ? r : -r;
    }
    ordenarLista(lista) {
        return this.orden.campo ? [...lista].sort((a, b) => this.comparar(a, b)) : lista;
    }
    get filasAsegurados() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.gruposAsegurados.slice(ini, ini + POR_PAGINA).map((g) => this.fila(g.titular, false));
    }
    get totalPaginable() {
        if (this.enAsegurados) { return this.gruposAsegurados.length; }
        return this.listaVista.length;
    }

    // ============================================================
    // Dependientes y beneficiarios
    // ============================================================
    get listaVista() {
        const grupo = this.enBeneficiarios ? 'beneficiario' : 'dependiente';
        return this.ordenarLista(this.participantes.filter((p) => p.grupo === grupo && this.pasaFiltro(p)));
    }
    get filasLista() {
        const ini = (this.pagina - 1) * POR_PAGINA;
        return this.listaVista.slice(ini, ini + POR_PAGINA).map((p) => this.fila(p, false));
    }
    get sinFilas() { return this.totalPaginable === 0; }

    // ============================================================
    // Columnas según lo que trae la póliza
    // ============================================================
    // «POR ASIGNAR»: pólizas empresariales de personas (en las individuales no hay certificado).
    get conCertificado() { return !this.avisoBienes && (this.resumen.asegurado || 0) > 1; }
    get conCategoria() { return this.participantes.some((p) => p.categoria); }
    get conPrima() { return this.participantes.some((p) => p.prima != null); }
    get conParentesco() { return this.participantes.some((p) => p.parentesco || p.titularNombre); }
    get columnasAsegurados() {
        return 8 + (this.conCategoria ? 1 : 0) +(this.conPrima ? 1 : 0) + (this.conParentesco ? 1 : 0);
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
        const dependientes = (this.dependientesPorTitular.get(p.id) || []).map((d) => ({
            id: d.id, texto: `${d.nombre}${d.parentesco ? ' · ' + d.parentesco : ''}${d.activo ? '' : ' · baja'}`
        }));
        return {
            ...p,
            certificadoTxt: p.certificado || (this.conCertificado ? 'POR ASIGNAR' : ''),
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
            primaTxt: moneda(p.prima),
            porcentajeTxt: p.porcentaje != null ? `${p.porcentaje}%` : '',
            // Estado = último movimiento: Alta, Baja o Cambio.
            estado: p.tipoMovimiento || (p.activo ? 'Alta' : 'Baja'),
            claseEstado: `estado estado-${String(p.tipoMovimiento || (p.activo ? 'Alta' : 'Baja')).toLowerCase()}`,
            fechaMovimientoTxt: p.fechaMovimiento ? fechaVisible(p.fechaMovimiento) : '',
            contactoTxt: [c.correo, c.celular || c.telefono].filter((x) => x).join(' · '),
            // Correo: enviado (con fecha), pendiente o sin correo.
            correoDir: c.correo || '',
            correoTxt: p.correoEnviado ? 'Enviado' : (c.correo ? 'Pendiente' : 'Sin correo'),
            claseCorreo: `estado ${p.correoEnviado ? 'correo-enviado' : (c.correo ? 'correo-pendiente' : 'correo-sin')}`,
            fechaCorreoTxt: p.correoEnviado && p.fechaCorreo ? this.fechaHora(p.fechaCorreo) : '',
            tituloCorreo: p.correoEnviado
                ? `Enviado el ${this.fechaHora(p.fechaCorreo)}`
                : (c.correo ? `Aún no se envía el correo a ${c.correo}` : 'El participante no tiene correo'),
            // Detalle
            datosPersona: this.lineas(c, p),
            hayPersona: !!(p.contacto || p.cuenta),
            personaTitulo: p.contacto ? 'Contacto' : (p.cuenta ? (p.cuenta.tipo === 'Persona' ? 'Cuenta (persona)' : 'Cuenta') : 'Contacto'),
            personaId: c.id,
            datosPoliza: [
                ['Certificado', p.certificado || (this.conCertificado ? 'POR ASIGNAR' : '')],
                ['Categoría', p.categoria],
                ['Parentesco', p.parentesco],
                ['Titular', p.titularNombre],
                ['Vigencia', p.desde ? `${fechaVisible(p.desde)}${p.hasta ? ' – ' + fechaVisible(p.hasta) : ''}` : ''],
                ['Motivo de baja', p.motivoBaja],
                ['Identificación', p.identificacion],
                ['Porcentaje', p.porcentaje != null ? `${p.porcentaje}%` : ''],
                ['Menor de edad', p.menor ? 'Sí' : ''],
                ['Tutor', p.tutor ? p.tutor.nombre : ''],
                ['Contratante', p.contratante ? 'Sí' : ''],
                ['Correo enviado', p.correoEnviado ? this.fechaHora(p.fechaCorreo) : '']
            ].filter(([, v]) => v).map(([etiqueta, valor]) => ({ key: etiqueta, etiqueta, valor })),
            coberturasTxt: (p.coberturas || []).map((cob) => ({
                key: cob.id,
                nombre: cob.nombre,
                detalle: [cob.suma != null ? 'Suma ' + moneda(cob.suma) : '', cob.deducible != null ? 'Deducible ' + moneda(cob.deducible) : '',
                    cob.prima != null ? 'Prima ' + moneda(cob.prima) : ''].filter((x) => x).join(' · ')
            })),
            hayCoberturas: (p.coberturas || []).length > 0,
            archivosTxt: (p.archivos || []).map((a) => ({
                key: a.id,
                id: a.id,
                participanteId: p.id,
                titulo: a.titulo + (a.tipo ? '.' + a.tipo : ''),
                tipo: a.tipo || 'archivo',
                icono: this.iconoArchivo(a.tipo),
                detalle: [a.tipo ? a.tipo.toUpperCase() : '', this.tamanoTxt(a.tamano), a.fecha ? fechaVisible(a.fecha) : '']
                    .filter((x) => x).join(' · ')
            })),
            hayArchivos: (p.archivos || []).length > 0,
            beneficiarios,
            hayBeneficiarios: beneficiarios.length > 0,
            dependientes,
            hayDependientes: dependientes.length > 0
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

    // Vista previa del archivo (Salesforce Files).
    async verArchivo(e) {
        e.preventDefault();
        const id = e.currentTarget.dataset.id;
        const participanteId = e.currentTarget.dataset.participante;
        if (!id) { return; }
        if (this.portal) {
            // En el sitio el archivo se descarga (el usuario del sitio no tiene acceso directo a él).
            const contenedor = this.template.querySelector('.part');
            try {
                try {
                    await descargarDocumento(id, contenedor, participanteId);
                } catch (sinPersona) {
                    // Archivo de la póliza (el del contratante).
                    await descargarDocumento(id, contenedor);
                }
            } catch (err) {
                this.errorMensaje = (err && err.body && err.body.message) || 'No se pudo descargar el archivo.';
            }
            return;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__namedPage', attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: id } });
    }
    iconoArchivo(tipo) {
        const t = String(tipo || '').toLowerCase();
        if (t === 'pdf') { return 'doctype:pdf'; }
        if (['xls', 'xlsx', 'csv'].includes(t)) { return t === 'csv' ? 'doctype:csv' : 'doctype:excel'; }
        if (['doc', 'docx'].includes(t)) { return 'doctype:word'; }
        if (['png', 'jpg', 'jpeg', 'gif', 'webp'].includes(t)) { return 'doctype:image'; }
        if (t === 'zip') { return 'doctype:zip'; }
        if (t === 'txt') { return 'doctype:txt'; }
        return 'doctype:unknown';
    }
    tamanoTxt(b) {
        if (b == null) { return ''; }
        if (b < 1024) { return `${b} B`; }
        if (b < 1024 * 1024) { return `${Math.round(b / 1024)} KB`; }
        return `${(b / 1024 / 1024).toFixed(1)} MB`;
    }

    abrirRegistro(e) {
        const id = e.currentTarget.dataset.id;
        if (!id) { return; }
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: id, actionName: 'view' } });
    }

    // Fecha y hora del envío de correo (el envío se hace desde Asegurados de la póliza).
    fechaHora(v) {
        if (!v) { return ''; }
        const d = new Date(v);
        return isNaN(d) ? '' : d.toLocaleString('es-MX', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
    }

    // ============================================================
    // Paginación
    // ============================================================
    get paginas() { return Math.max(1, Math.ceil(this.totalPaginable / POR_PAGINA)); }
    get textoPagina() { return `Página ${this.pagina} de ${this.paginas} · ${this.totalPaginable} ${this.enAsegurados ? 'titulares' : 'participantes'}`; }
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
