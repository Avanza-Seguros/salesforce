// portalSolicitudes/portalSolicitudes.js
// Pestaña Solicitudes del detalle de la póliza en el sitio: el contratante pide altas, bajas y cambios (se crea un
// caso «Solicitud de movimientos» que atiende el ejecutivo) y ve el estado de las que ya envió.
import { LightningElement, api } from 'lwc';
import solicitudes from '@salesforce/apex/PortalPolizasPestanas.solicitudes';
import crearSolicitud from '@salesforce/apex/PortalPolizasPestanas.crearSolicitud';

// Igual que PortalPolizasPestanas.MAX_BYTES_SOLICITUD.
const MAX_BYTES = 4 * 1024 * 1024;

// Datos que se piden en un alta, según lo que asegura la póliza.
const CAMPOS_ALTA = {
    personas: [
        { clave: 'nombre', etiqueta: 'Nombre(s)', requerido: true },
        { clave: 'paterno', etiqueta: 'Apellido paterno', requerido: true },
        { clave: 'materno', etiqueta: 'Apellido materno' },
        { clave: 'nacimiento', etiqueta: 'Fecha de nacimiento', tipo: 'date', requerido: true },
        { clave: 'sexo', etiqueta: 'Sexo', opciones: ['Mujer', 'Hombre'], requerido: true },
        { clave: 'parentesco', etiqueta: 'Parentesco', opciones: ['Titular', 'Cónyuge', 'Hijo(a)', 'Padre/Madre', 'Otro'], requerido: true },
        { clave: 'correo', etiqueta: 'Correo electrónico', tipo: 'email' }
    ],
    vehiculos: [
        { clave: 'vehiculo', etiqueta: 'Vehículo (marca, submarca y versión)', requerido: true },
        { clave: 'modelo', etiqueta: 'Modelo (año)', requerido: true },
        { clave: 'serie', etiqueta: 'Número de serie', requerido: true },
        { clave: 'placas', etiqueta: 'Placas' },
        { clave: 'uso', etiqueta: 'Uso' }
    ],
    ubicaciones: [
        { clave: 'ubicacion', etiqueta: 'Nombre de la ubicación', requerido: true },
        { clave: 'direccion', etiqueta: 'Dirección completa', requerido: true },
        { clave: 'giro', etiqueta: 'Giro o actividad' },
        { clave: 'suma', etiqueta: 'Suma asegurada', tipo: 'number' }
    ]
};
const NOMBRES = { personas: ['asegurado', 'asegurados'], vehiculos: ['vehículo', 'vehículos'], ubicaciones: ['ubicación', 'ubicaciones'] };
const ESTADOS = {
    Recibida: 'estado estado_pendiente',
    'En proceso': 'estado estado_proceso',
    Cerrada: 'estado estado_vigente',
    Rechazada: 'estado estado_rechazada'
};

let siguiente = 1;

export default class PortalSolicitudes extends LightningElement {
    _policyId;
    @api cuentaVistaPrevia;
    @api
    get policyId() { return this._policyId; }
    set policyId(v) {
        const cambio = v !== this._policyId;
        this._policyId = v;
        if (cambio && this.conectado) { this.cargar(); }
    }

    conectado = false;
    cargando = false;
    enviando = false;
    error;
    datos;
    formulario = false;
    movimientos = [];
    comentario = '';
    archivos = [];
    exito;
    abiertas = new Set();

    connectedCallback() {
        this.conectado = true;
        this.cargar();
    }

    async cargar() {
        if (!this._policyId) { return; }
        this.cargando = true;
        this.error = undefined;
        try {
            this.datos = await solicitudes({ policyId: this._policyId, cuentaVistaPrevia: this.cuentaVistaPrevia || null });
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.cargando = false;
        }
    }

    // ===== Lista =====
    get tipo() { return (this.datos && this.datos.tipo) || 'personas'; }
    get nombreRegistro() { return NOMBRES[this.tipo][0]; }
    get puedeSolicitar() { return !!this.datos && this.datos.puedeSolicitar; }
    get avisoSinPermiso() {
        if (!this.datos || this.datos.puedeSolicitar) { return null; }
        if (!this.datos.esContratante) { return 'Las solicitudes de altas, bajas y cambios las envía el contratante de la póliza.'; }
        return null;
    }
    get haySolicitudes() { return !!this.datos && this.datos.solicitudes.length > 0; }
    get lista() {
        if (!this.datos) { return []; }
        return this.datos.solicitudes.map((s) => {
            const abierta = this.abiertas.has(s.folio);
            const asunto = String(s.asunto || '').split(' · ');
            return {
                ...s,
                resumen: asunto.length > 2 ? asunto.slice(2).join(' · ') : '',
                fechaTexto: this.fecha(s.fecha),
                claseEstado: ESTADOS[s.estado] || 'estado',
                abierta,
                textoVer: abierta ? 'Ocultar detalle' : 'Ver detalle',
                detalle: String(s.descripcion || '').split('\n').filter((l) => /^\d+\./.test(l)),
                avance: s.aplicados ? `${s.aplicados} ${s.aplicados === 1 ? 'movimiento aplicado' : 'movimientos aplicados'}${s.abiertos ? ` · ${s.abiertos} en trámite con la aseguradora` : ''}` : '',
                endososTexto: s.endosos && s.endosos.length ? `Endoso ${s.endosos.join(', ')}` : '',
                documentosTexto: s.documentos ? `${s.documentos} ${s.documentos === 1 ? 'archivo' : 'archivos'}` : ''
            };
        });
    }
    handleVer(e) {
        const f = e.currentTarget.dataset.folio;
        const a = new Set(this.abiertas);
        if (a.has(f)) { a.delete(f); } else { a.add(f); }
        this.abiertas = a;
    }

    // ===== Formulario =====
    handleNueva() {
        this.exito = undefined;
        this.error = undefined;
        this.movimientos = [this.nuevoMovimiento('alta')];
        this.comentario = '';
        this.archivos = [];
        this.formulario = true;
    }
    handleCancelar() { this.formulario = false; }
    nuevoMovimiento(tipo) { return { key: 'm' + siguiente++, tipo, registroId: '', fecha: '', detalle: '', datos: {}, titularId: '' }; }
    handleAgregar() { this.movimientos = [...this.movimientos, this.nuevoMovimiento(this.movimientos.length ? this.movimientos[this.movimientos.length - 1].tipo : 'alta')]; }
    handleQuitar(e) {
        const k = e.currentTarget.dataset.key;
        this.movimientos = this.movimientos.filter((m) => m.key !== k);
    }
    cambiar(key, cambios) { this.movimientos = this.movimientos.map((m) => (m.key === key ? { ...m, ...cambios } : m)); }
    handleTipo(e) { this.cambiar(e.target.dataset.key, { tipo: e.detail.value, registroId: '', detalle: '', datos: {} }); }
    handleCampo(e) { this.cambiar(e.target.dataset.key, { [e.target.dataset.campo]: e.detail.value }); }
    handleDato(e) {
        const m = this.movimientos.find((x) => x.key === e.target.dataset.key);
        this.cambiar(m.key, { datos: { ...m.datos, [e.target.dataset.campo]: e.detail.value } });
    }
    handleComentario(e) { this.comentario = e.detail.value; }

    get opcionesTipo() {
        return [
            { label: `Alta de ${this.nombreRegistro}`, value: 'alta' },
            { label: `Baja de ${this.nombreRegistro}`, value: 'baja' },
            { label: 'Cambio de datos', value: 'cambio' }
        ];
    }
    get opcionesRegistro() {
        return ((this.datos && this.datos.registros) || []).map((r) => ({
            label: `${r.clave ? r.clave + ' · ' : ''}${r.nombre}${r.dependiente ? ' (dependiente)' : ''}`, value: r.id
        }));
    }
    get opcionesTitular() {
        return ((this.datos && this.datos.registros) || []).filter((r) => !r.dependiente)
            .map((r) => ({ label: `${r.clave ? r.clave + ' · ' : ''}${r.nombre}`, value: r.id }));
    }
    get sinRegistros() { return !this.opcionesRegistro.length; }
    get filasMovimiento() {
        return this.movimientos.map((m, i) => {
            const esAlta = m.tipo === 'alta';
            const campos = esAlta ? CAMPOS_ALTA[this.tipo].map((c) => ({
                ...c,
                key: m.key + c.clave,
                valor: m.datos[c.clave] || '',
                tipoInput: c.tipo || 'text',
                esLista: !!c.opciones,
                opciones: (c.opciones || []).map((o) => ({ label: o, value: o }))
            })) : [];
            const parentesco = m.datos.parentesco;
            return {
                ...m,
                numero: i + 1,
                esAlta,
                conRegistro: !esAlta,
                campos,
                conTitular: esAlta && this.tipo === 'personas' && !!parentesco && parentesco !== 'Titular',
                etiquetaDetalle: m.tipo === 'baja' ? 'Motivo de la baja' : (m.tipo === 'cambio' ? '¿Qué se cambia?' : 'Nota (opcional)'),
                detalleRequerido: m.tipo === 'cambio',
                etiquetaFecha: m.tipo === 'baja' ? 'Fecha de baja' : (m.tipo === 'alta' ? 'Fecha de alta' : 'Fecha en que aplica'),
                puedeQuitar: this.movimientos.length > 1
            };
        });
    }

    async handleArchivos(e) {
        const nuevos = [...(e.target.files || [])];
        e.target.value = null;
        const leidos = await Promise.all(nuevos.map((f) => new Promise((ok, mal) => {
            const r = new FileReader();
            r.onload = () => ok({ nombre: f.name, tamano: f.size, base64: String(r.result).split(',')[1] });
            r.onerror = () => mal(r.error);
            r.readAsDataURL(f);
        })));
        const todos = [...this.archivos, ...leidos];
        if (todos.reduce((t, a) => t + a.tamano, 0) > MAX_BYTES) {
            this.error = 'Los archivos suman más de 4 MB. Adjunta archivos más ligeros.';
            return;
        }
        this.error = undefined;
        this.archivos = todos;
    }
    get listaArchivos() { return this.archivos.map((a, i) => ({ key: i + a.nombre, i, nombre: a.nombre, tamano: this.tamano(a.tamano) })); }
    get hayArchivos() { return this.archivos.length > 0; }
    handleQuitarArchivo(e) {
        const i = Number(e.currentTarget.dataset.i);
        this.archivos = this.archivos.filter((a, j) => j !== i);
    }

    async handleEnviar() {
        const validos = [...this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea')]
            .reduce((ok, c) => (c.reportValidity ? c.reportValidity() : true) && ok, true);
        if (!validos) { return; }
        const registros = new Map(((this.datos && this.datos.registros) || []).map((r) => [r.id, r]));
        const movimientos = this.movimientos.map((m) => {
            const datos = m.tipo === 'alta' ? CAMPOS_ALTA[this.tipo].map((c) => ({ etiqueta: c.etiqueta, valor: m.datos[c.clave] || '' })) : [];
            if (m.titularId && registros.has(m.titularId)) {
                const t = registros.get(m.titularId);
                datos.push({ etiqueta: 'Titular', valor: `${t.clave ? t.clave + ' · ' : ''}${t.nombre}` });
            }
            return { tipo: m.tipo, registroId: m.registroId || null, fecha: m.fecha || null, detalle: m.detalle || null, datos };
        });
        this.enviando = true;
        this.error = undefined;
        try {
            const r = await crearSolicitud({
                policyId: this._policyId,
                solicitudJson: JSON.stringify({
                    movimientos,
                    comentario: this.comentario,
                    archivos: this.archivos.map((a) => ({ nombre: a.nombre, base64: a.base64 }))
                }),
                cuentaVistaPrevia: this.cuentaVistaPrevia || null
            });
            this.formulario = false;
            this.exito = `Recibimos tu solicitud ${r.folio}. Tu asesor la revisará y verás aquí su avance.`;
            await this.cargar();
        } catch (e) {
            this.error = this.mensaje(e);
        } finally {
            this.enviando = false;
        }
    }

    // ===== Utilidades =====
    fecha(v) {
        if (!v) { return ''; }
        return new Intl.DateTimeFormat('es-MX', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(v));
    }
    tamano(b) { return b >= 1024 * 1024 ? `${(b / 1024 / 1024).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`; }
    mensaje(e) {
        return (e && e.body && (e.body.message || (e.body.pageErrors && e.body.pageErrors[0] && e.body.pageErrors[0].message)))
            || (e && e.message) || 'Ocurrió un error. Intenta de nuevo.';
    }
}
